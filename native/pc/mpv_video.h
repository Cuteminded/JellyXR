#pragma once

#include "render_worker.h"
#include "render_gl.h"
#include "render_vulkan.h"
#include "playback_watchdog.h"
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/node.hpp>

class JellyframeMpv : public godot::Node {
    GDCLASS(JellyframeMpv, godot::Node)

public:
    ~JellyframeMpv();
    godot::String open_video(godot::String url, godot::String authorization, int64_t start_ms);
    void set_paused(bool paused);
    void seek_to(int64_t milliseconds);
    int64_t position_ms() const;
    int64_t duration_ms() const;
    bool is_buffering() const;
    godot::String rendering_backend() const;
    godot::Dictionary playback_diagnostics() const;
    // Vulkan exposes YUV planes; texture_changed carries the luma texture.
    godot::Dictionary video_shader_parameters() const;
    void stop_video();
    void _process(double delta) override;

protected:
    static void _bind_methods();

private:
    godot::String initialize(int64_t start_ms);
    bool update_size();
    bool upload_frame();
    void fallback_to_software();
    void update_property(const mpv_event &event);
    void shutdown();
    bool uses_video_clock() const;
    void update_video_buffering();
    void apply_audio_pause();
    bool video_buffering = false;
    uint64_t video_buffer_count = 0;
    uint64_t video_clock_origin = 0;
    bool video_clock_started = false;
    bool log_video_stats = false;
    uint64_t last_diagnostics_time = 0;
    mpv_handle *player = nullptr;
    RenderWorker renderer;
    godot::Ref<RenderGl> gl_renderer;
    godot::Ref<RenderVulkan> vulkan_renderer;
    VideoFrame frame;
    godot::Ref<godot::Texture2D> texture;
    int64_t position = 0;
    int64_t duration = 0;
    bool active = false;
    bool prepared = false;
    bool paused = false;
    bool buffering = false;
    bool seeking = false;
    bool software_only = false;
    godot::String current_url;
    godot::String current_authorization;
    PlaybackWatchdog watchdog;
};
