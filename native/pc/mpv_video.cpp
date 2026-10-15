#include "mpv_video.h"
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

void JellyframeMpv::_bind_methods() {
    ClassDB::bind_method(D_METHOD("open_video", "url", "authorization", "start_ms"), &JellyframeMpv::open_video);
    ClassDB::bind_method(D_METHOD("set_paused", "paused"), &JellyframeMpv::set_paused);
    ClassDB::bind_method(D_METHOD("seek_to", "milliseconds"), &JellyframeMpv::seek_to);
    ClassDB::bind_method(D_METHOD("position_ms"), &JellyframeMpv::position_ms);
    ClassDB::bind_method(D_METHOD("duration_ms"), &JellyframeMpv::duration_ms);
    ClassDB::bind_method(D_METHOD("is_buffering"), &JellyframeMpv::is_buffering);
    ClassDB::bind_method(D_METHOD("playback_diagnostics"), &JellyframeMpv::playback_diagnostics);
    ClassDB::bind_method(D_METHOD("rendering_backend"), &JellyframeMpv::rendering_backend);
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
    const bool use_opengl = !software_only &&
        OS::get_singleton()->get_environment("JELLYFRAME_PC_RENDERER") != "software" && hardware_opengl_available();
    const char *options[][2] = {
        {"config", "no"}, {"terminal", "no"}, {"load-scripts", "no"},
        {"ytdl", "no"}, {"input-default-bindings", "no"}, {"input-vo-keyboard", "no"},
        {"vo", "libmpv"}, {"hwdec", use_opengl ? "auto" : "auto-copy"}, {"osd-level", "0"},
        {"sub-auto", "no"}, {"audio-file-auto", "no"}, {"keep-open", "no"},
        {"idle", "yes"}, {"tls-verify", "yes"}
    };
    for (const auto &option : options) {
        int error = mpv_set_option_string(player, option[0], option[1]);
        if (error < 0) return String("PC decoder option failed: ") + option[0] + ".";
    }
    int error = mpv_initialize(player);
    if (error >= 0 && use_opengl) {
        gl_renderer.instantiate();
        if (gl_renderer->start(player) < 0) {
            gl_renderer->stop();
            gl_renderer.unref();
        }
    }
    if (error >= 0 && gl_renderer.is_null()) {
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

String JellyframeMpv::open_video(String url, String authorization, int64_t start_ms) {
    shutdown();
    current_url = url;
    current_authorization = authorization;
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
    diagnostics_enabled = OS::get_singleton()->get_environment("JELLYFRAME_PC_DIAGNOSTICS") == "1";
    diagnostic_time_ms = playback_time_ms();
    set_process(true);
    return "";
}

void JellyframeMpv::set_paused(bool value) {
    if (!player || !active) return;
    paused = value;
    watchdog.reset(playback_time_ms());
    int flag = value;
    mpv_set_property_async(player, 0, "pause", MPV_FORMAT_FLAG, &flag);
}

void JellyframeMpv::seek_to(int64_t milliseconds) {
    if (!player || !active) return;
    seeking = true;
    watchdog.reset(playback_time_ms());
    auto target = String::num(double(std::max<int64_t>(0, milliseconds)) / 1000.0, 3).utf8();
    const char *command[] = {"seek", target.get_data(), "absolute+exact", nullptr};
    mpv_command_async(player, 0, command);
}

int64_t JellyframeMpv::position_ms() const { return position; }
int64_t JellyframeMpv::duration_ms() const { return duration; }

bool JellyframeMpv::is_buffering() const {
    return active && (buffering || seeking);
}

Dictionary JellyframeMpv::playback_diagnostics() const {
    Dictionary result;
    if (!player) return result;
    for (const char *name : {"video-codec", "hwdec-current"}) {
        char *value = mpv_get_property_string(player, name);
        result[name] = value ? String::utf8(value) : String("unavailable");
        mpv_free(value);
    }
    for (const char *name : {"container-fps", "decoder-frame-drop-count", "frame-drop-count"}) {
        double value = 0;
        result[name] = mpv_get_property(player, name, MPV_FORMAT_DOUBLE, &value) >= 0 ? Variant(value) : Variant();
    }
    result["render_backend"] = rendering_backend();
    result["width"] = texture.is_valid() ? texture->get_width() : frame.width;
    result["height"] = texture.is_valid() ? texture->get_height() : frame.height;
    result["cpu_rgba_bytes"] = frame.pixels.size();
    result["render_call_ms"] = gl_renderer.is_valid() ? gl_renderer->render_call_ms() : double(frame.render_time_us) / 1000.0;
    result["present_cpu_ms"] = gl_renderer.is_valid() ? gl_renderer->present_cpu_ms() : 0.0;
    result["upload_cpu_ms"] = upload_cpu_ms;
    result["uploaded_frames"] = int64_t(uploaded_frames);
    result["paused"] = paused;
    result["buffering"] = buffering;
    result["seeking"] = seeking;
    return result;
}

String JellyframeMpv::rendering_backend() const {
    if (!player) return "none";
    return gl_renderer.is_valid() ? "opengl" : "software";
}

void JellyframeMpv::fallback_to_software() {
    String url = current_url;
    String authorization = current_authorization;
    int64_t resume_at = position;
    bool was_paused = paused;
    software_only = true;
    String error = open_video(url, authorization, resume_at);
    if (!error.is_empty()) { emit_signal("failed", error); return; }
    if (was_paused) set_paused(true);
}

void JellyframeMpv::report_diagnostics() {
    if (!diagnostics_enabled || !prepared) return;
    uint64_t now = playback_time_ms();
    uint64_t elapsed = now - diagnostic_time_ms;
    if (elapsed < 5000) return;
    Dictionary result = playback_diagnostics();
    result["uploaded_fps"] = double(uploaded_frames - diagnostic_frames) * 1000.0 / double(elapsed);
    UtilityFunctions::print("Jellyframe PC playback: ", result);
    diagnostic_time_ms = now;
    diagnostic_frames = uploaded_frames;
}

void JellyframeMpv::stop_video() {
    shutdown();
}

void JellyframeMpv::shutdown() {
    active = false;
    prepared = false;
    paused = false;
    buffering = false;
    seeking = false;
    set_process(false);
    if (gl_renderer.is_valid()) {
        gl_renderer->stop();
        gl_renderer.unref();
    }
    renderer.stop();
    if (player) mpv_terminate_destroy(player);
    player = nullptr;
    texture.unref();
    frame = VideoFrame();
    uploaded_frames = 0;
    diagnostic_frames = 0;
    diagnostic_time_ms = 0;
    upload_cpu_ms = 0;
    current_url = "";
    current_authorization = "";
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
    if (gl_renderer.is_valid()) gl_renderer->resize(int(width), int(height));
    else renderer.resize(int(width), int(height));
    emit_signal("size_changed", width, height);
    return true;
}

bool JellyframeMpv::upload_frame() {
    if (gl_renderer.is_valid()) {
        bool received = gl_renderer->take_frame();
        if (received) {
            if (texture != gl_renderer->get_texture()) {
                texture = gl_renderer->get_texture();
                emit_signal("texture_changed", texture);
            }
            ++uploaded_frames;
        }
        return received;
    }
    if (!renderer.take_frame(frame)) return false;
    auto upload_started = std::chrono::steady_clock::now();
    auto image = Image::create_from_data(frame.width, frame.height, false, Image::FORMAT_RGBA8, frame.pixels);
    if (texture.is_null() || texture->get_width() != frame.width || texture->get_height() != frame.height) {
        texture = ImageTexture::create_from_image(image);
        emit_signal("texture_changed", texture);
    } else {
        texture->update(image);
    }
    upload_cpu_ms = double(std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now() - upload_started).count()) / 1000.0;
    ++uploaded_frames;
    return true;
}

void JellyframeMpv::update_property(const mpv_event &event) {
    auto *property = static_cast<mpv_event_property *>(event.data);
    if (!property->data) return;
    if (property->format == MPV_FORMAT_DOUBLE) {
        int64_t milliseconds = int64_t(*static_cast<double *>(property->data) * 1000.0);
        if (event.reply_userdata == 1) position = std::max<int64_t>(0, milliseconds);
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
        if (event.reply_userdata == 5) {
            paused = value;
            watchdog.reset(playback_time_ms());
        }
    }
}

void JellyframeMpv::_process(double) {
    if (!player || !active) return;
    if (gl_renderer.is_valid() && gl_renderer->error() < 0) { fallback_to_software(); return; }
    if (gl_renderer.is_null() && renderer.error() < 0) {
        active = false;
        emit_signal("failed", String("PC video rendering failed: ") + mpv_error_string(renderer.error()));
        return;
    }
    for (int count = 0; count < 64; ++count) {
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
    report_diagnostics();
    if (prepared && watchdog.stalled(playback_time_ms(), received_frame, paused, buffering || seeking)) {
        if (gl_renderer.is_valid()) { fallback_to_software(); return; }
        active = false;
        emit_signal("failed", "Video playback stalled.");
    }
}
