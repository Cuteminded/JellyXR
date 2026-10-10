#pragma once

#include "render_worker.h"
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
    void stop_video();
    void _process(double delta) override;

protected:
    static void _bind_methods();

private:
    godot::String initialize();
    bool update_size();
    void upload_frame();
    void shutdown();
    mpv_handle *player = nullptr;
    RenderWorker renderer;
    VideoFrame frame;
    godot::Ref<godot::ImageTexture> texture;
    int64_t position = 0;
    int64_t duration = 0;
    bool active = false;
};
