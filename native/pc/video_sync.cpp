#include "mpv_video.h"

void JellyframeMpv::apply_audio_pause() {
    int flag = paused || video_buffering;
    mpv_set_property_async(player, 0, "pause", MPV_FORMAT_FLAG, &flag);
}

void JellyframeMpv::update_video_buffering() {
    if (vulkan_renderer.is_null() || uses_video_clock() || !prepared || seeking) return;
    int64_t timestamp = vulkan_renderer->timestamp_ms();
    bool waiting = video_buffering;
    if (timestamp < 0 || position - timestamp > 250) waiting = true;
    else if (position - timestamp <= 80 && vulkan_renderer->read_ahead_ready()) waiting = false;
    if (waiting == video_buffering) return;
    video_buffering = waiting;
    if (waiting) ++video_buffer_count;
    apply_audio_pause();
}
