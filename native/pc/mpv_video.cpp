#include "mpv_video.h"
#include "stream_identity.h"
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <algorithm>
#include <chrono>

using namespace godot;

static uint64_t playback_time_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

static bool hardware_opengl_available() {
    auto *server = RenderingServer::get_singleton();
    if (DisplayServer::get_singleton()->get_name() == "headless" ||
            server->get_current_rendering_method() != "gl_compatibility") return false;
    String adapter = server->get_video_adapter_name().to_lower();
    return !adapter.contains("llvmpipe") && !adapter.contains("softpipe") &&
        !adapter.contains("software rasterizer") && !adapter.contains("swiftshader");
}

void JellyXRMpv::_bind_methods() {
    ClassDB::bind_method(D_METHOD("open_video", "url", "authorization", "start_ms"), &JellyXRMpv::open_video);
    ClassDB::bind_method(D_METHOD("set_paused", "paused"), &JellyXRMpv::set_paused);
    ClassDB::bind_method(D_METHOD("seek_to", "milliseconds"), &JellyXRMpv::seek_to);
    ClassDB::bind_method(D_METHOD("position_ms"), &JellyXRMpv::position_ms);
    ClassDB::bind_method(D_METHOD("duration_ms"), &JellyXRMpv::duration_ms);
    ClassDB::bind_method(D_METHOD("is_buffering"), &JellyXRMpv::is_buffering);
    ClassDB::bind_method(D_METHOD("rendering_backend"), &JellyXRMpv::rendering_backend);
    ClassDB::bind_method(D_METHOD("video_shader_parameters"), &JellyXRMpv::video_shader_parameters);
    ClassDB::bind_method(D_METHOD("playback_diagnostics"), &JellyXRMpv::playback_diagnostics);
    ClassDB::bind_method(D_METHOD("stop_video"), &JellyXRMpv::stop_video);
    ADD_SIGNAL(MethodInfo("prepared"));
    ADD_SIGNAL(MethodInfo("ended"));
    ADD_SIGNAL(MethodInfo("failed", PropertyInfo(Variant::STRING, "message")));
    ADD_SIGNAL(MethodInfo("size_changed", PropertyInfo(Variant::INT, "width"), PropertyInfo(Variant::INT, "height")));
    ADD_SIGNAL(MethodInfo("texture_changed", PropertyInfo(Variant::OBJECT, "texture", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D")));
}

JellyXRMpv::~JellyXRMpv() {
    shutdown();
}

String JellyXRMpv::initialize(int64_t start_ms) {
    log_video_stats = OS::get_singleton()->get_environment("JELLYXR_VIDEO_STATS") == "1";
    last_diagnostics_time = playback_time_ms();
    player = mpv_create();
    if (!player) return "Could not create the PC video decoder.";
    const bool use_opengl = !software_only &&
        OS::get_singleton()->get_environment("JELLYXR_PC_RENDERER") != "software" && hardware_opengl_available();
    if (!software_only && OS::get_singleton()->get_environment("JELLYXR_PC_RENDERER") != "software" &&
            DisplayServer::get_singleton()->get_name() != "headless" &&
            RenderingServer::get_singleton()->get_current_rendering_driver_name() == "vulkan") {
        vulkan_renderer.instantiate();
        if (vulkan_renderer->start(current_url, current_authorization, start_ms) < 0) {
            vulkan_renderer->stop();
            vulkan_renderer.unref();
        }
    }
    const char *options[][2] = {
        {"config", "no"}, {"terminal", "no"}, {"load-scripts", "no"},
        {"ytdl", "no"}, {"input-default-bindings", "no"}, {"input-vo-keyboard", "no"},
        {"vo", vulkan_renderer.is_valid() ? "null" : "libmpv"},
        {"hwdec", use_opengl ? "auto" : "auto-copy"}, {"osd-level", "0"},
        {"sub-auto", "no"}, {"audio-file-auto", "no"}, {"keep-open", "no"},
        {"idle", "yes"}, {"tls-verify", "yes"},
        {"cache", "yes"}, {"cache-secs", "30"}, {"demuxer-max-bytes", "256MiB"},
        {"user-agent", JELLYXR_STREAM_USER_AGENT}
    };
    for (const auto &option : options) {
        int error = mpv_set_option_string(player, option[0], option[1]);
        if (error < 0) return String("PC decoder option failed: ") + option[0] + ".";
    }
    if (vulkan_renderer.is_valid() && vulkan_renderer->has_audio()) {
        int error = mpv_set_option_string(player, "vid", "no");
        if (error < 0) return "Could not configure the Vulkan playback clock.";
    }
    int error = mpv_initialize(player);
    if (error >= 0 && use_opengl) {
        gl_renderer.instantiate();
        if (gl_renderer->start(player) < 0) {
            gl_renderer->stop();
            gl_renderer.unref();
        }
    }
    if (error >= 0 && gl_renderer.is_null() && vulkan_renderer.is_null()) {
        error = mpv_set_property_string(player, "hwdec", "auto-copy");
        if (error >= 0) error = renderer.start(player);
    }
    if (error < 0) return String("PC decoder initialization failed: ") + mpv_error_string(error);
    mpv_observe_property(player, 1, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(player, 2, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(player, 3, "paused-for-cache", MPV_FORMAT_FLAG);
    mpv_observe_property(player, 4, "seeking", MPV_FORMAT_FLAG);
    mpv_observe_property(player, 5, "pause", MPV_FORMAT_FLAG);
    return "";
}

String JellyXRMpv::open_video(String url, String authorization, int64_t start_ms) {
    shutdown();
    current_url = url;
    current_authorization = authorization;
    String error = initialize(start_ms);
    if (!error.is_empty()) {
        shutdown();
        return error;
    }
    if (uses_video_clock()) {
        position = std::max<int64_t>(0, start_ms);
        duration = vulkan_renderer->duration_ms();
        video_clock_origin = playback_time_ms() - position;
        active = true;
        set_process(true);
        return "";
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
    audio_clock.reset(position, playback_time_ms());
    duration = 0;
    active = true;
    set_process(true);
    return "";
}

void JellyXRMpv::set_paused(bool value) {
    if (!player || !active) return;
    if (uses_video_clock()) {
        if (!paused && video_clock_started && !seeking) position = int64_t(playback_time_ms() - video_clock_origin);
        video_clock_origin = playback_time_ms() - position;
        paused = value;
        watchdog.reset(playback_time_ms());
        return;
    }
    paused = value;
    audio_clock.reset(position, playback_time_ms());
    watchdog.reset(playback_time_ms());
    apply_audio_pause();
}

void JellyXRMpv::seek_to(int64_t milliseconds) {
    if (!player || !active) return;
    seeking = true;
    audio_clock.reset(std::max<int64_t>(0, milliseconds), playback_time_ms());
    if (vulkan_renderer.is_valid()) vulkan_renderer->seek(milliseconds);
    watchdog.reset(playback_time_ms());
    if (uses_video_clock()) {
        position = std::max<int64_t>(0, milliseconds);
        video_clock_origin = playback_time_ms() - position;
        return;
    }
    auto target = String::num(double(std::max<int64_t>(0, milliseconds)) / 1000.0, 3).utf8();
    const char *command[] = {"seek", target.get_data(), "absolute+exact", nullptr};
    mpv_command_async(player, 0, command);
}

int64_t JellyXRMpv::position_ms() const { return position; }
int64_t JellyXRMpv::duration_ms() const { return duration; }

bool JellyXRMpv::is_buffering() const {
    return active && (buffering || video_buffering || seeking);
}

bool JellyXRMpv::uses_video_clock() const {
    return vulkan_renderer.is_valid() && !vulkan_renderer->has_audio();
}

String JellyXRMpv::rendering_backend() const {
    if (!player) return "none";
    if (vulkan_renderer.is_valid()) return "vulkan";
    return gl_renderer.is_valid() ? "opengl" : "software";
}

Dictionary JellyXRMpv::playback_diagnostics() const {
    Dictionary values = vulkan_renderer.is_valid() ? vulkan_renderer->diagnostics() : Dictionary();
    values["renderer"] = rendering_backend();
    values["version"] = "vulkan-paced-yuv-2";
    values["audio_position_ms"] = position;
    if (vulkan_renderer.is_valid()) {
        values["video_position_ms"] = vulkan_renderer->timestamp_ms();
        values["video_buffering"] = video_buffering;
        values["video_buffer_count"] = int64_t(video_buffer_count);
    }
    return values;
}

void JellyXRMpv::fallback_to_software() {
    UtilityFunctions::print("PC video: falling back to software. ", playback_diagnostics());
    String url = current_url;
    String authorization = current_authorization;
    int64_t resume_at = position;
    bool was_paused = paused;
    software_only = true;
    String error = open_video(url, authorization, resume_at);
    if (!error.is_empty()) { emit_signal("failed", error); return; }
    if (was_paused) set_paused(true);
}

void JellyXRMpv::stop_video() {
    shutdown();
}

void JellyXRMpv::shutdown() {
    active = false;
    prepared = false;
    paused = false;
    buffering = false;
    video_buffering = false;
    video_buffer_count = 0;
    seeking = false;
    video_clock_started = false;
    set_process(false);
    if (vulkan_renderer.is_valid()) {
        vulkan_renderer->stop();
        vulkan_renderer.unref();
    }
    if (gl_renderer.is_valid()) {
        gl_renderer->stop();
        gl_renderer.unref();
    }
    renderer.stop();
    if (player) mpv_terminate_destroy(player);
    player = nullptr;
    texture.unref();
    frame = VideoFrame();
    current_url = "";
    current_authorization = "";
}

bool JellyXRMpv::update_size() {
    if (vulkan_renderer.is_valid()) {
        emit_signal("size_changed", vulkan_renderer->width(), vulkan_renderer->height());
        return vulkan_renderer->width() > 0 && vulkan_renderer->height() > 0;
    }
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
    if (gl_renderer.is_valid()) gl_renderer->resize(int(width), int(height));
    else renderer.resize(int(width), int(height));
    emit_signal("size_changed", width, height);
    return true;
}

bool JellyXRMpv::upload_frame() {
    if (vulkan_renderer.is_valid()) {
        uint64_t now = playback_time_ms();
        if (paused || buffering || video_buffering || seeking || !prepared) audio_clock.reset(position, now);
        vulkan_renderer->set_clock(uses_video_clock() ? position : audio_clock.position(now));
        Dictionary previous_parameters = vulkan_renderer->shader_parameters();
        if (!vulkan_renderer->take_frame()) return false;
        if (uses_video_clock()) {
            if (!video_clock_started || seeking) video_clock_origin = playback_time_ms() - position;
            video_clock_started = true;
            seeking = false;
        }
        Ref<Texture2D> next = vulkan_renderer->shader_parameters()["y_plane"];
        if (texture != next) {
            texture = next;
            emit_signal("size_changed", vulkan_renderer->width(), vulkan_renderer->height());
            UtilityFunctions::print("PC video: ", playback_diagnostics());
        }
        if (!vulkan_renderer->shader_parameters().recursive_equal(previous_parameters, 0)) {
            emit_signal("texture_changed", texture);
        }
        return true;
    }
    if (gl_renderer.is_valid()) {
        bool received = gl_renderer->take_frame();
        if (received) {
            if (texture != gl_renderer->get_texture()) {
                texture = gl_renderer->get_texture();
                emit_signal("texture_changed", texture);
            }
        }
        return received;
    }
    if (!renderer.take_frame(frame)) return false;
    auto image = Image::create_from_data(frame.width, frame.height, false, Image::FORMAT_RGBA8, frame.pixels);
    if (texture.is_null() || texture->get_width() != frame.width || texture->get_height() != frame.height) {
        texture = ImageTexture::create_from_image(image);
        emit_signal("texture_changed", texture);
    } else {
        Ref<ImageTexture> image_texture = texture;
        image_texture->update(image);
    }
    return true;
}

void JellyXRMpv::update_property(const mpv_event &event) {
    auto *property = static_cast<mpv_event_property *>(event.data);
    if (!property->data) return;
    if (property->format == MPV_FORMAT_DOUBLE) {
        int64_t milliseconds = int64_t(*static_cast<double *>(property->data) * 1000.0);
        if (event.reply_userdata == 1) {
            position = std::max<int64_t>(0, milliseconds);
            uint64_t now = playback_time_ms();
            if (paused || buffering || video_buffering || seeking || !prepared) audio_clock.reset(position, now);
            else audio_clock.synchronize(position, now);
        }
        if (event.reply_userdata == 2) duration = std::max<int64_t>(0, milliseconds);
    } else if (property->format == MPV_FORMAT_FLAG) {
        bool value = *static_cast<int *>(property->data) != 0;
        if (event.reply_userdata == 3) {
            if (buffering && !value) watchdog.reset(playback_time_ms());
            buffering = value;
        }
        if (event.reply_userdata == 4) {
            if (seeking && !value) watchdog.reset(playback_time_ms());
            seeking = value;
        }
        if (event.reply_userdata == 5 && vulkan_renderer.is_null()) {
            paused = value;
            watchdog.reset(playback_time_ms());
        }
    }
}

void JellyXRMpv::_process(double) {
    if (!player || !active) return;
    if (vulkan_renderer.is_valid() && vulkan_renderer->error() < 0) { fallback_to_software(); return; }
    if (gl_renderer.is_valid() && gl_renderer->error() < 0) { fallback_to_software(); return; }
    if (gl_renderer.is_null() && vulkan_renderer.is_null() && renderer.error() < 0) {
        active = false;
        emit_signal("failed", String("PC video rendering failed: ") + mpv_error_string(renderer.error()));
        return;
    }
    if (uses_video_clock()) {
        if (!prepared) {
            if (!update_size()) { fallback_to_software(); return; }
            prepared = true;
            video_clock_origin = playback_time_ms() - position;
            watchdog.reset(playback_time_ms());
            emit_signal("prepared");
            return;
        }
        if (!paused && video_clock_started && !seeking) position = int64_t(playback_time_ms() - video_clock_origin);
        if (!paused && video_clock_started && ((duration > 0 && position >= duration) || (duration == 0 && vulkan_renderer->ended()))) {
            active = false;
            emit_signal("ended");
            return;
        }
    }
    for (int count = 0; !uses_video_clock() && count < 64; ++count) {
        auto *event = mpv_wait_event(player, 0);
        if (event->event_id == MPV_EVENT_NONE) break;
        if (event->event_id == MPV_EVENT_PROPERTY_CHANGE) {
            update_property(*event);
        } else if (event->event_id == MPV_EVENT_FILE_LOADED) {
            if (!update_size()) {
                active = false;
                emit_signal("failed", "The stream has no supported video track.");
                return;
            }
            prepared = true;
            watchdog.reset(playback_time_ms());
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
    bool received_frame = upload_frame();
    update_video_buffering();
    if (log_video_stats && playback_time_ms() - last_diagnostics_time >= 5000) {
        last_diagnostics_time = playback_time_ms();
        UtilityFunctions::print("PC video statistics: ", playback_diagnostics());
    }
    if (prepared && watchdog.stalled(playback_time_ms(), received_frame, paused, buffering || video_buffering || seeking)) {
        if (gl_renderer.is_valid() || vulkan_renderer.is_valid()) { fallback_to_software(); return; }
        active = false;
        emit_signal("failed", "Video playback stalled.");
    }
}

Dictionary JellyXRMpv::video_shader_parameters() const {
    return vulkan_renderer.is_valid() ? vulkan_renderer->shader_parameters() : Dictionary();
}
