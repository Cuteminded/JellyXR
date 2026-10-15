#include "render_gl.h"
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <chrono>
#include <future>

using namespace godot;

void RenderGl::run_sync(void (RenderGl::*operation)()) {
    auto *server = RenderingServer::get_singleton();
    if (server->is_on_render_thread()) { (this->*operation)(); return; }
    {
        std::lock_guard<std::mutex> lock(sync_mutex);
        sync_operation = operation;
        sync_complete = false;
    }
    server->call_on_render_thread(callable_mp(this, &RenderGl::dispatch_sync));
    std::unique_lock<std::mutex> lock(sync_mutex);
    sync_condition.wait(lock, [this] { return sync_complete; });
}

void RenderGl::dispatch_sync() {
    (this->*sync_operation)();
    {
        std::lock_guard<std::mutex> lock(sync_mutex);
        sync_complete = true;
    }
    sync_condition.notify_one();
}

void RenderGl::initialize_on_render_thread() {
    if (!context.create() || !api.load(context)) render_error = MPV_ERROR_UNSUPPORTED;
}

int RenderGl::start(mpv_handle *handle) {
    player = handle;
    run_sync(&RenderGl::initialize_on_render_thread);
    if (render_error < 0) return render_error;
    std::promise<int> initialized;
    auto result = initialized.get_future();
    worker = std::thread([this, ready = std::move(initialized)]() mutable {
        if (!context.activate()) { ready.set_value(MPV_ERROR_UNSUPPORTED); return; }
        mpv_render_context *renderer = nullptr;
        mpv_opengl_init_params gl_init{resolve, this};
        int advanced = 1;
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
            {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_init},
            {MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced},
            {MPV_RENDER_PARAM_INVALID, nullptr}
        };
        int error = mpv_render_context_create(&renderer, player, params);
        if (error >= 0) mpv_render_context_set_update_callback(renderer, wakeup, this);
        ready.set_value(error);
        if (error >= 0) {
            render_loop(renderer);
            mpv_render_context_set_update_callback(renderer, nullptr, nullptr);
            mpv_render_context_free(renderer);
        }
        destroy_slots();
        context.release();
    });
    int initialization_error = result.get();
    if (initialization_error < 0) render_error = initialization_error;
    return render_error;
}

void *RenderGl::resolve(void *owner, const char *name) {
    return static_cast<RenderGl *>(owner)->context.resolve(name);
}

void RenderGl::wakeup(void *owner) {
    auto *self = static_cast<RenderGl *>(owner);
    self->dirty = true;
    self->wake.notify_one();
}

void RenderGl::resize(int width, int height) {
    if (texture.is_valid() && target_width == width && target_height == height) return;
    run_sync(&RenderGl::detach_on_render_thread);
    target_width = width;
    target_height = height;
    texture = ImageTexture::create_from_image(Image::create_empty(width, height, false, Image::FORMAT_RGBA8));
    run_sync(&RenderGl::attach_on_render_thread);
    dimensions = (uint64_t(width) << 32) | uint32_t(height);
    wake.notify_one();
}

void RenderGl::attach_on_render_thread() {
    display_texture = unsigned(RenderingServer::get_singleton()->texture_get_native_handle(texture->get_rid()));
    if (!display_texture) { render_error = MPV_ERROR_UNSUPPORTED; return; }
    GlFramebufferState state(api);
    api.gen_framebuffers(1, &read_framebuffer);
    api.gen_framebuffers(1, &draw_framebuffer);
    api.bind_framebuffer(gl::draw_framebuffer, draw_framebuffer);
    api.attach_texture(gl::draw_framebuffer, gl::color_attachment, gl::texture_2d, display_texture, 0);
    if (api.check_framebuffer(gl::draw_framebuffer) != gl::framebuffer_complete) render_error = MPV_ERROR_UNSUPPORTED;
}

bool RenderGl::fence_complete(void *fence) {
    unsigned status = api.poll_fence(fence, 0, 0);
    if (status == gl::wait_failed) render_error = MPV_ERROR_GENERIC;
    return status == gl::already_signaled || status == gl::condition_satisfied;
}

int RenderGl::select_ready_slot() {
    int selected = -1;
    for (size_t index = 0; index < slots.size(); ++index) {
        auto &slot = slots[index];
        if (slot.state != SlotState::Ready || !fence_complete(slot.ready)) continue;
        if (slot.width != target_width || slot.height != target_height) {
            api.delete_fence(slot.ready);
            slot.ready = nullptr;
            slot.state = SlotState::Free;
        } else if (selected < 0 || slot.sequence > slots[selected].sequence) {
            selected = int(index);
        }
    }
    return selected;
}

void RenderGl::present_on_render_thread() {
    auto started = std::chrono::steady_clock::now();
    std::unique_lock<std::mutex> lock(slots_mutex, std::try_to_lock);
    if (lock.owns_lock() && display_texture) {
        int selected = select_ready_slot();
        if (selected >= 0) {
            auto &slot = slots[selected];
            GlFramebufferState state(api);
            api.bind_framebuffer(gl::read_framebuffer, read_framebuffer);
            api.attach_texture(gl::read_framebuffer, gl::color_attachment, gl::texture_2d, slot.texture, 0);
            api.bind_framebuffer(gl::draw_framebuffer, draw_framebuffer);
            api.blit(0, 0, slot.width, slot.height, 0, 0, target_width, target_height, gl::color_buffer, gl::nearest);
            api.delete_fence(slot.ready);
            slot.ready = nullptr;
            slot.released = api.fence(gl::sync_complete, 0);
            api.flush();
            slot.state = SlotState::Retired;
            if (!slot.released) render_error = MPV_ERROR_GENERIC;
            else frame_ready = true;
            for (auto &older : slots) {
                if (older.state == SlotState::Ready && older.sequence < slot.sequence && fence_complete(older.ready)) {
                    api.delete_fence(older.ready);
                    older.ready = nullptr;
                    older.state = SlotState::Free;
                }
            }
            wake.notify_one();
        }
    }
    present_time_us = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    queued = false;
}

bool RenderGl::take_frame() {
    bool received = frame_ready.exchange(false);
    if (!queued.exchange(true)) {
        RenderingServer::get_singleton()->call_on_render_thread(callable_mp(this, &RenderGl::present_on_render_thread));
    }
    return received;
}

void RenderGl::detach_on_render_thread() {
    if (read_framebuffer) api.delete_framebuffers(1, &read_framebuffer);
    if (draw_framebuffer) api.delete_framebuffers(1, &draw_framebuffer);
    read_framebuffer = 0;
    draw_framebuffer = 0;
    display_texture = 0;
    frame_ready = false;
}

void RenderGl::destroy_on_render_thread() { context.destroy(); }

void RenderGl::stop() {
    run_sync(&RenderGl::detach_on_render_thread);
    stopping = true;
    wake.notify_one();
    if (worker.joinable()) worker.join();
    run_sync(&RenderGl::destroy_on_render_thread);
    texture.unref();
    player = nullptr;
}

int RenderGl::error() const { return render_error; }
double RenderGl::render_call_ms() const { return double(render_time_us.load()) / 1000.0; }
double RenderGl::present_cpu_ms() const { return double(present_time_us.load()) / 1000.0; }
Ref<ImageTexture> RenderGl::get_texture() const { return texture; }
