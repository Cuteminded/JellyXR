#pragma once

#include "render_worker.h"
#include "render_gl.h"
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
    godot::Dictionary playback_diagnostics() const;
    godot::String rendering_backend() const;
    void stop_video();
    void _process(double delta) override;

protected:
    static void _bind_methods();

private:
    godot::String initialize();
    bool update_size();
    bool upload_frame();
    void report_diagnostics();
    void fallback_to_software();
    void update_property(const mpv_event &event);
    void shutdown();
    mpv_handle *player = nullptr;
    RenderWorker renderer;
    godot::Ref<RenderGl> gl_renderer;
    VideoFrame frame;
    godot::Ref<godot::ImageTexture> texture;
    int64_t position = 0;
    int64_t duration = 0;
    bool active = false;
    bool prepared = false;
    bool paused = false;
    bool buffering = false;
    bool seeking = false;
    bool diagnostics_enabled = false;
    uint64_t uploaded_frames = 0;
    uint64_t diagnostic_frames = 0;
    uint64_t diagnostic_time_ms = 0;
    double upload_cpu_ms = 0;
    bool software_only = false;
    godot::String current_url;
    godot::String current_authorization;
    PlaybackWatchdog watchdog;
};
