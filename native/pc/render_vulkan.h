#pragma once

#include "video_decoder.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/rendering_device.hpp>
#include <godot_cpp/classes/texture2drd.hpp>
#include <chrono>
#ifdef _WIN32
#include "d3d11_godot.h"
#include "d3d12_godot.h"
#endif
#ifdef __linux__
#include "vaapi_godot.h"
#endif

class RenderVulkan : public godot::RefCounted {
    GDCLASS(RenderVulkan, godot::RefCounted)
public:
    int start(godot::String url, godot::String authorization, int64_t start_ms);
    void stop();
    void set_clock(int64_t milliseconds) { decoder.set_clock(milliseconds); }
    void seek(int64_t milliseconds) { decoder.seek(milliseconds); frame_ready = false; presented_timestamp = -1; }
    int64_t timestamp_ms() const { return presented_timestamp; }
    bool take_frame();
    int error() const;
    bool has_audio() const { return decoder.has_audio(); }
    int width() const { return presented_size.x > 0 ? presented_size.x : decoder.width(); }
    int height() const { return presented_size.y > 0 ? presented_size.y : decoder.height(); }
    int64_t duration_ms() const { return decoder.duration_ms(); }
    bool ended() const { return decoder.ended(); }
    bool read_ahead_ready() const { return decoder.read_ahead_ready(); }
    godot::Dictionary diagnostics() const;
    godot::Dictionary shader_parameters() const { return presented_parameters; }
protected:
    static void _bind_methods() {}
private:
#ifdef _WIN32
    D3D11Godot d3d11;
    D3D12Godot d3d12;
#endif
    void run_sync(void (RenderVulkan::*operation)());
    void dispatch_sync();
    void initialize_on_render_thread();
    void present_on_render_thread();
    void present_frame();
    void queue_frame();
    static void wakeup(void *owner);
    void destroy_on_render_thread();
    void destroy_textures();
    bool create_textures();
#ifdef __linux__
    VaapiGodot vaapi;
    std::atomic<bool> vaapi_available{false};
#endif
    VideoDecoder decoder;
    VideoPlanes frame;
    godot::RenderingDevice *device = nullptr;
    std::array<godot::Ref<godot::Texture2DRD>, 3> textures;
    godot::Dictionary ready_parameters;
    godot::Dictionary presented_parameters;
    godot::Dictionary frame_parameters() const;
    godot::Vector2i ready_size;
    godot::Vector2i presented_size;
    std::mutex texture_mutex;
    uint64_t ready_generation = 0;
    int64_t ready_timestamp = -1;
    int64_t presented_timestamp = -1;
    std::array<godot::RID, 3> planes;
    int target_width = 0;
    int target_height = 0;
    int source_width = 0;
    int source_height = 0;
    int storage_width = 0;
    int storage_height = 0;
    int sample_bytes = 0;
    bool interleaved = false;
    std::atomic<int> render_error{0};
    std::atomic<uint64_t> presented_frames{0}, presentation_us{0};
    std::atomic<bool> queued{false}, frame_ready{false};
    std::atomic<bool> stopping{false};
    std::chrono::steady_clock::time_point presentation_started;
    std::mutex sync_mutex;
    std::condition_variable sync_condition;
    bool sync_complete = false;
    void (RenderVulkan::*sync_operation)() = nullptr;
};
