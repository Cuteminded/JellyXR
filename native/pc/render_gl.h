#pragma once

#include "gl_functions.h"
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <mpv/render_gl.h>
#include <array>
#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>

class RenderGl : public godot::RefCounted {
    GDCLASS(RenderGl, godot::RefCounted)

public:
    int start(mpv_handle *player);
    void resize(int width, int height);
    bool take_frame();
    void stop();
    int error() const;
    godot::Ref<godot::ImageTexture> get_texture() const;

protected:
    static void _bind_methods() {}

private:
    enum class SlotState { Free, Rendering, Ready, Retired };
    struct Slot {
        SlotState state = SlotState::Free;
        unsigned texture = 0;
        unsigned framebuffer = 0;
        int width = 0;
        int height = 0;
        uint64_t sequence = 0;
        void *ready = nullptr;
        void *released = nullptr;
    };

    void run_sync(void (RenderGl::*operation)());
    void dispatch_sync();
    void initialize_on_render_thread();
    void attach_on_render_thread();
    void detach_on_render_thread();
    void destroy_on_render_thread();
    void present_on_render_thread();
    int select_ready_slot();
    bool fence_complete(void *fence);
    void render_loop(mpv_render_context *renderer);
    int acquire_slot();
    bool prepare_slot(Slot &slot);
    bool render_slot(mpv_render_context *renderer, Slot &slot);
    void destroy_slots();
    static void wakeup(void *owner);
    static void *resolve(void *owner, const char *name);
    SharedGlContext context;
    GlFunctions api;
    mpv_handle *player = nullptr;
    std::thread worker;
    std::mutex wake_mutex;
    std::condition_variable wake;
    std::atomic<bool> stopping{false};
    std::atomic<bool> dirty{false};
    std::atomic<int> render_error{0};
    std::atomic<uint64_t> dimensions{(uint64_t(1920) << 32) | 1080};
    std::array<Slot, 2> slots;
    std::mutex slots_mutex;
    uint64_t next_sequence = 0;
    godot::Ref<godot::ImageTexture> texture;
    unsigned display_texture = 0;
    unsigned read_framebuffer = 0;
    unsigned draw_framebuffer = 0;
    int target_width = 0;
    int target_height = 0;
    std::atomic<bool> queued{false};
    std::atomic<bool> frame_ready{false};
    std::mutex sync_mutex;
    std::condition_variable sync_condition;
    bool sync_complete = false;
    void (RenderGl::*sync_operation)() = nullptr;
};
