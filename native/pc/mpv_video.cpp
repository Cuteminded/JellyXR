#include "mpv_video.h"
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cstring>

using namespace godot;

void JellyframeMpv::_bind_methods() {
    ClassDB::bind_method(D_METHOD("open_video", "url", "authorization", "start_ms"), &JellyframeMpv::open_video);
    ClassDB::bind_method(D_METHOD("set_paused", "paused"), &JellyframeMpv::set_paused);
    ClassDB::bind_method(D_METHOD("seek_to", "milliseconds"), &JellyframeMpv::seek_to);
    ClassDB::bind_method(D_METHOD("position_ms"), &JellyframeMpv::position_ms);
    ClassDB::bind_method(D_METHOD("duration_ms"), &JellyframeMpv::duration_ms);
    ClassDB::bind_method(D_METHOD("is_buffering"), &JellyframeMpv::is_buffering);
    ClassDB::bind_method(D_METHOD("stop_video"), &JellyframeMpv::stop_video);
    ADD_SIGNAL(MethodInfo("prepared"));
    ADD_SIGNAL(MethodInfo("ended"));
    ADD_SIGNAL(MethodInfo("failed", PropertyInfo(Variant::STRING, "message")));
    ADD_SIGNAL(MethodInfo("size_changed", PropertyInfo(Variant::INT, "width"), PropertyInfo(Variant::INT, "height")));
    ADD_SIGNAL(MethodInfo("texture_changed", PropertyInfo(Variant::OBJECT, "texture", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D")));
}

JellyframeMpv::~JellyframeMpv() {
    shutdown();
}

String JellyframeMpv::initialize() {
    player = mpv_create();
    if (!player) return "Could not create the PC video decoder.";
    const char *options[][2] = {
        {"config", "no"}, {"terminal", "no"}, {"load-scripts", "no"},
        {"ytdl", "no"}, {"input-default-bindings", "no"}, {"input-vo-keyboard", "no"},
        {"vo", "libmpv"}, {"hwdec", "auto-copy"}, {"osd-level", "0"},
        {"sub-auto", "no"}, {"audio-file-auto", "no"}, {"keep-open", "no"},
        {"idle", "yes"}, {"tls-verify", "yes"}
    };
    for (const auto &option : options) {
        int error = mpv_set_option_string(player, option[0], option[1]);
        if (error < 0) return String("PC decoder option failed: ") + option[0] + ".";
    }
    int error = mpv_initialize(player);
    if (error >= 0) error = renderer.start(player);
    if (error < 0) return String("PC decoder initialization failed: ") + mpv_error_string(error);
    mpv_observe_property(player, 1, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(player, 2, "duration", MPV_FORMAT_DOUBLE);
    return "";
}

String JellyframeMpv::open_video(String url, String authorization, int64_t start_ms) {
    shutdown();
    String error = initialize();
    if (!error.is_empty()) {
        shutdown();
        return error;
    }
    auto header = (String("Authorization: ") + authorization).utf8();
    mpv_node entry{};
    entry.format = MPV_FORMAT_STRING;
    entry.u.string = const_cast<char *>(header.get_data());
    mpv_node_list list{};
    list.num = authorization.is_empty() ? 0 : 1;
    list.values = &entry;
    mpv_node headers{};
    headers.format = MPV_FORMAT_NODE_ARRAY;
    headers.u.list = &list;
    int result = mpv_set_property(player, "http-header-fields", MPV_FORMAT_NODE, &headers);
    auto start = String::num(double(std::max<int64_t>(0, start_ms)) / 1000.0, 3).utf8();
    if (result >= 0) result = mpv_set_option_string(player, "start", start.get_data());
    auto address = url.utf8();
    const char *command[] = {"loadfile", address.get_data(), "replace", nullptr};
    if (result >= 0) result = mpv_command_async(player, 1, command);
    if (result < 0) {
        shutdown();
        return String("Could not open the video: ") + mpv_error_string(result);
    }
    position = std::max<int64_t>(0, start_ms);
    duration = 0;
    active = true;
    set_process(true);
    return "";
}

void JellyframeMpv::set_paused(bool paused) {
    if (!player || !active) return;
    int flag = paused;
    mpv_set_property_async(player, 0, "pause", MPV_FORMAT_FLAG, &flag);
}

void JellyframeMpv::seek_to(int64_t milliseconds) {
    if (!player || !active) return;
    auto target = String::num(double(std::max<int64_t>(0, milliseconds)) / 1000.0, 3).utf8();
    const char *command[] = {"seek", target.get_data(), "absolute+exact", nullptr};
    mpv_command_async(player, 0, command);
}

int64_t JellyframeMpv::position_ms() const { return position; }
int64_t JellyframeMpv::duration_ms() const { return duration; }

bool JellyframeMpv::is_buffering() const {
    if (!player || !active) return false;
    int buffering = 0;
    int seeking = 0;
    mpv_get_property(player, "paused-for-cache", MPV_FORMAT_FLAG, &buffering);
    mpv_get_property(player, "seeking", MPV_FORMAT_FLAG, &seeking);
    return buffering || seeking;
}

void JellyframeMpv::stop_video() {
    shutdown();
}

void JellyframeMpv::shutdown() {
    active = false;
    renderer.stop();
    if (player) mpv_terminate_destroy(player);
    player = nullptr;
    texture.unref();
    frame = VideoFrame();
}

bool JellyframeMpv::update_size() {
    int64_t width = 0;
    int64_t height = 0;
    mpv_get_property(player, "dwidth", MPV_FORMAT_INT64, &width);
    mpv_get_property(player, "dheight", MPV_FORMAT_INT64, &height);
    if (width <= 0 || height <= 0) {
        mpv_get_property(player, "width", MPV_FORMAT_INT64, &width);
        mpv_get_property(player, "height", MPV_FORMAT_INT64, &height);
    }
    if (width <= 0 || height <= 0) return false;
    if (width > 8192 || height > 8192 || width * height > 33554432) return false;
    renderer.resize(int(width), int(height));
    emit_signal("size_changed", width, height);
    return true;
}

void JellyframeMpv::upload_frame() {
    if (!renderer.take_frame(frame)) return;
    PackedByteArray pixels;
    pixels.resize(int64_t(frame.pixels.size()));
    std::memcpy(pixels.ptrw(), frame.pixels.data(), frame.pixels.size());
    auto image = Image::create_from_data(frame.width, frame.height, false, Image::FORMAT_RGBA8, pixels);
    if (texture.is_null() || texture->get_width() != frame.width || texture->get_height() != frame.height) {
        texture = ImageTexture::create_from_image(image);
        emit_signal("texture_changed", texture);
    } else {
        texture->update(image);
    }
}

void JellyframeMpv::_process(double) {
    if (!player || !active) return;
    if (renderer.error() < 0) {
        active = false;
        emit_signal("failed", String("PC video rendering failed: ") + mpv_error_string(renderer.error()));
        return;
    }
    for (int count = 0; count < 64; ++count) {
        auto *event = mpv_wait_event(player, 0);
        if (event->event_id == MPV_EVENT_NONE) break;
        if (event->event_id == MPV_EVENT_PROPERTY_CHANGE) {
            auto *property = static_cast<mpv_event_property *>(event->data);
            if (property->format != MPV_FORMAT_DOUBLE || !property->data) continue;
            int64_t milliseconds = int64_t(*static_cast<double *>(property->data) * 1000.0);
            if (event->reply_userdata == 1) position = std::max<int64_t>(0, milliseconds);
            if (event->reply_userdata == 2) duration = std::max<int64_t>(0, milliseconds);
        } else if (event->event_id == MPV_EVENT_FILE_LOADED) {
            if (!update_size()) {
                active = false;
                emit_signal("failed", "The stream has no supported video track.");
                return;
            }
            emit_signal("prepared");
            return;
        } else if (event->event_id == MPV_EVENT_VIDEO_RECONFIG) {
            update_size();
        } else if (event->event_id == MPV_EVENT_END_FILE) {
            auto end = *static_cast<mpv_event_end_file *>(event->data);
            if (end.reason == MPV_END_FILE_REASON_ERROR) {
                active = false;
                emit_signal("failed", String("PC video playback failed: ") + mpv_error_string(end.error));
                return;
            }
            if (end.reason == MPV_END_FILE_REASON_EOF) {
                active = false;
                emit_signal("ended");
                return;
            }
        } else if (event->event_id == MPV_EVENT_COMMAND_REPLY && event->reply_userdata == 1 && event->error < 0) {
            String error = String("Could not load the video: ") + mpv_error_string(event->error);
            active = false;
            emit_signal("failed", error);
            return;
        }
    }
    upload_frame();
}
