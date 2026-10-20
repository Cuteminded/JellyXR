#include "render_gl.h"
#include <chrono>

int RenderGl::acquire_slot() {
    std::lock_guard<std::mutex> lock(slots_mutex);
    for (size_t index = 0; index < slots.size(); ++index) {
        auto &slot = slots[index];
        if (slot.state == SlotState::Retired && fence_complete(slot.released)) {
            api.delete_fence(slot.released);
            slot.released = nullptr;
            slot.state = SlotState::Free;
        }
        if (slot.state == SlotState::Free) {
            slot.state = SlotState::Rendering;
            return int(index);
        }
    }
    return -1;
}

bool RenderGl::prepare_slot(Slot &slot) {
    uint64_t size = dimensions.load();
    int width = int(size >> 32);
    int height = int(size & 0xffffffff);
    if (slot.texture && slot.width == width && slot.height == height) return true;
    if (slot.framebuffer) api.delete_framebuffers(1, &slot.framebuffer);
    if (slot.texture) api.delete_textures(1, &slot.texture);
    slot.width = width;
    slot.height = height;
    api.gen_textures(1, &slot.texture);
    api.bind_texture(gl::texture_2d, slot.texture);
    api.texture_parameter(gl::texture_2d, gl::texture_min_filter, gl::nearest);
    api.texture_parameter(gl::texture_2d, gl::texture_mag_filter, gl::nearest);
    api.texture_image(gl::texture_2d, 0, gl::rgba8, width, height, 0, gl::rgba, gl::unsigned_byte, nullptr);
    api.bind_texture(gl::texture_2d, 0);
    api.gen_framebuffers(1, &slot.framebuffer);
    api.bind_framebuffer(gl::framebuffer, slot.framebuffer);
    api.attach_texture(gl::framebuffer, gl::color_attachment, gl::texture_2d, slot.texture, 0);
    bool complete = api.check_framebuffer(gl::framebuffer) == gl::framebuffer_complete;
    api.bind_framebuffer(gl::framebuffer, 0);
    if (!complete) render_error = MPV_ERROR_UNSUPPORTED;
    return complete;
}

bool RenderGl::render_slot(mpv_render_context *renderer, Slot &slot) {
    if (!prepare_slot(slot)) return false;
    mpv_opengl_fbo target{int(slot.framebuffer), slot.width, slot.height, int(gl::rgba8)};
    int flip = 0;
    int block = 1;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &target},
        {MPV_RENDER_PARAM_FLIP_Y, &flip},
        {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &block},
        {MPV_RENDER_PARAM_INVALID, nullptr}
    };
    int error = mpv_render_context_render(renderer, params);
    if (error < 0) { render_error = error; return false; }
    void *ready = api.fence(gl::sync_complete, 0);
    api.flush();
    if (!ready) { render_error = MPV_ERROR_GENERIC; return false; }
    {
        std::lock_guard<std::mutex> lock(slots_mutex);
        slot.ready = ready;
        slot.sequence = ++next_sequence;
        slot.state = SlotState::Ready;
    }
    return true;
}

void RenderGl::render_loop(mpv_render_context *renderer) {
    bool pending = false;
    while (!stopping && render_error >= 0) {
        if (dirty.exchange(false)) {
            if (mpv_render_context_update(renderer) & MPV_RENDER_UPDATE_FRAME) pending = true;
        }
        int selected = pending && dimensions.load() ? acquire_slot() : -1;
        if (selected >= 0) {
            if (!render_slot(renderer, slots[selected])) break;
            pending = false;
            continue;
        }
        std::unique_lock<std::mutex> lock(wake_mutex);
        wake.wait_for(lock, std::chrono::milliseconds(pending ? 2 : 20), [this] { return stopping || dirty; });
    }
}

void RenderGl::destroy_slots() {
    std::lock_guard<std::mutex> lock(slots_mutex);
    for (auto &slot : slots) {
        if (slot.ready) api.delete_fence(slot.ready);
        if (slot.released) api.delete_fence(slot.released);
        if (slot.framebuffer) api.delete_framebuffers(1, &slot.framebuffer);
        if (slot.texture) api.delete_textures(1, &slot.texture);
        slot = Slot();
    }
}
