#include "render_worker.h"
#include <chrono>
#include <future>

RenderWorker::~RenderWorker() {
    stop();
}

int RenderWorker::start(mpv_handle *player) {
    std::promise<int> initialized;
    auto result = initialized.get_future();
    stopping = false;
    dirty = false;
    render_error = 0;
    dimensions = (uint64_t(1920) << 32) | 1080;
    worker = std::thread([this, player, ready = std::move(initialized)]() mutable {
        mpv_render_context *renderer = nullptr;
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_SW)},
            {MPV_RENDER_PARAM_INVALID, nullptr}
        };
        int error = mpv_render_context_create(&renderer, player, params);
        if (error >= 0) mpv_render_context_set_update_callback(renderer, wakeup, this);
        ready.set_value(error);
        if (error < 0) return;
        render_loop(renderer);
        mpv_render_context_set_update_callback(renderer, nullptr, nullptr);
        mpv_render_context_free(renderer);
    });
    return result.get();
}

void RenderWorker::wakeup(void *context) {
    auto *self = static_cast<RenderWorker *>(context);
    self->dirty = true;
    self->wake.notify_one();
}

void RenderWorker::resize(int width, int height) {
    dimensions = (uint64_t(width) << 32) | uint32_t(height);
    wakeup(this);
}

void RenderWorker::render_loop(mpv_render_context *renderer) {
    VideoFrame frame;
    while (!stopping) {
        {
            std::unique_lock<std::mutex> lock(wake_mutex);
            wake.wait_for(lock, std::chrono::milliseconds(20), [this] { return stopping || dirty; });
        }
        if (stopping) break;
        if (!dirty.exchange(false)) continue;
        if (!(mpv_render_context_update(renderer) & MPV_RENDER_UPDATE_FRAME)) continue;
        auto size = dimensions.load();
        frame.width = int(size >> 32);
        frame.height = int(size & 0xffffffff);
        if (frame.pixels.resize(int64_t(frame.width) * frame.height * 4) != 0) {
            render_error = MPV_ERROR_NOMEM;
            break;
        }
        int extent[] = {frame.width, frame.height};
        size_t stride = size_t(frame.width) * 4;
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_SW_SIZE, extent},
            {MPV_RENDER_PARAM_SW_FORMAT, const_cast<char *>("rgba")},
            {MPV_RENDER_PARAM_SW_STRIDE, &stride},
            {MPV_RENDER_PARAM_SW_POINTER, frame.pixels.ptrw()},
            {MPV_RENDER_PARAM_INVALID, nullptr}
        };
        int result = mpv_render_context_render(renderer, params);
        if (result < 0) {
            render_error = result;
            break;
        }
        {
            std::lock_guard<std::mutex> lock(frame_mutex);
            std::swap(pending, frame);
            frame_ready = true;
        }
    }
}

bool RenderWorker::take_frame(VideoFrame &frame) {
    std::lock_guard<std::mutex> lock(frame_mutex);
    if (!frame_ready) return false;
    std::swap(frame, pending);
    frame_ready = false;
    return true;
}

int RenderWorker::error() const {
    return render_error.load();
}

void RenderWorker::stop() {
    stopping = true;
    wake.notify_one();
    if (worker.joinable()) worker.join();
    std::lock_guard<std::mutex> lock(frame_mutex);
    pending = VideoFrame();
    frame_ready = false;
}
