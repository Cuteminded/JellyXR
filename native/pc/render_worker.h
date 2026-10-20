#pragma once

#include <mpv/client.h>
#include <mpv/render.h>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <thread>

struct VideoFrame {
    int width = 0;
    int height = 0;
    godot::PackedByteArray pixels;
};

class RenderWorker {
public:
    ~RenderWorker();
    int start(mpv_handle *player);
    void resize(int width, int height);
    bool take_frame(VideoFrame &frame);
    int error() const;
    void stop();

private:
    static void wakeup(void *context);
    void render_loop(mpv_render_context *renderer);
    std::thread worker;
    std::atomic<bool> stopping{false};
    std::atomic<bool> dirty{false};
    std::atomic<int> render_error{0};
    std::atomic<uint64_t> dimensions{(uint64_t(1920) << 32) | 1080};
    std::mutex wake_mutex;
    std::condition_variable wake;
    std::mutex frame_mutex;
    VideoFrame pending;
    bool frame_ready = false;
};
