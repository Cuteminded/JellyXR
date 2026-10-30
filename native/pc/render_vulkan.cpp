#include "render_vulkan.h"
#include <godot_cpp/classes/rd_texture_format.hpp>
#include <godot_cpp/classes/rd_texture_view.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <mpv/client.h>
#include <chrono>

using namespace godot;

void RenderVulkan::run_sync(void (RenderVulkan::*operation)()) {
    auto *server = RenderingServer::get_singleton();
    if (server->is_on_render_thread()) { (this->*operation)(); return; }
    {
        std::lock_guard<std::mutex> lock(sync_mutex);
        sync_operation = operation;
        sync_complete = false;
    }
    server->call_on_render_thread(callable_mp(this, &RenderVulkan::dispatch_sync));
    std::unique_lock<std::mutex> lock(sync_mutex);
    sync_condition.wait(lock, [this] { return sync_complete; });
}

void RenderVulkan::dispatch_sync() {
    (this->*sync_operation)();
    { std::lock_guard<std::mutex> lock(sync_mutex); sync_complete = true; }
    sync_condition.notify_one();
}

void RenderVulkan::initialize_on_render_thread() {
    device = RenderingServer::get_singleton()->get_rendering_device();
    if (!device) { render_error = MPV_ERROR_UNSUPPORTED; return; }
#ifdef _WIN32
    if (d3d12.initialize(device)) decoder.set_d3d12_bridge(d3d12.decoder_bridge());
    if (d3d11.initialize(device)) decoder.set_d3d11_bridge(d3d11.decoder_bridge());
#endif
#ifdef __linux__
    vaapi_available = vaapi.initialize(device);
    decoder.enable_vaapi_frames(vaapi_available);
    decoder.set_vaapi_device(vaapi_available ? vaapi.render_node() : "");
#endif
}

int RenderVulkan::start(String url, String authorization, int64_t start_ms) {
    run_sync(&RenderVulkan::initialize_on_render_thread);
    if (render_error < 0) return render_error;
    decoder.set_frame_callback(wakeup, this);
    int result = decoder.start(url.utf8().get_data(), authorization.utf8().get_data(), start_ms);
    return result < 0 ? MPV_ERROR_LOADING_FAILED : 0;
}

void RenderVulkan::destroy_textures() {
    for (auto &texture : textures) {
        if (texture.is_valid()) texture->set_texture_rd_rid(RID());
        texture.unref();
    }
    for (auto &plane : planes) {
        if (plane.is_valid()) device->free_rid(plane);
        plane = RID();
    }
    target_width = target_height = 0;
}

bool RenderVulkan::create_textures() {
    destroy_textures();
    Ref<RDTextureFormat> format;
    format.instantiate();
    format->set_texture_type(RenderingDevice::TEXTURE_TYPE_2D);
    format->set_usage_bits(RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice::TEXTURE_USAGE_CAN_UPDATE_BIT |
        RenderingDevice::TEXTURE_USAGE_CAN_COPY_TO_BIT);
    Ref<RDTextureView> view;
    view.instantiate();
    for (int index = 0; index < frame.plane_count; ++index) {
        format->set_format(frame.sample_bytes == 1 ?
            (index && frame.interleaved ? RenderingDevice::DATA_FORMAT_R8G8_UNORM : RenderingDevice::DATA_FORMAT_R8_UNORM) :
            (index && frame.interleaved ? RenderingDevice::DATA_FORMAT_R16G16_UNORM : RenderingDevice::DATA_FORMAT_R16_UNORM));
        format->set_width(index ? (frame.storage_width + 1) / 2 : frame.storage_width);
        format->set_height(index ? (frame.storage_height + 1) / 2 : frame.storage_height);
        planes[index] = device->texture_create(format, view);
        if (!planes[index].is_valid()) return false;
        textures[index].instantiate();
        textures[index]->set_texture_rd_rid(planes[index]);
    }
    source_width = frame.width;
    source_height = frame.height;
    storage_width = frame.storage_width;
    storage_height = frame.storage_height;
    target_width = frame.display_width;
    target_height = frame.display_height;
    sample_bytes = frame.sample_bytes;
    interleaved = frame.interleaved;
    return true;
}

void RenderVulkan::present_on_render_thread() {
    if (!stopping && decoder.take_frame(frame) && frame.generation == decoder.current_generation()) {
        present_frame();
        presentation_us += std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - presentation_started).count();
        if (render_error >= 0 && frame.generation == decoder.current_generation()) {
            const Dictionary parameters = frame_parameters();
            std::lock_guard<std::mutex> lock(texture_mutex);
            ready_parameters = parameters;
            ready_size = Vector2i(frame.display_width, frame.display_height);
            ready_generation = frame.generation;
            ready_timestamp = frame.timestamp;
            ++presented_frames;
            frame_ready = true;
        }
    }
    queued = false;
}

void RenderVulkan::wakeup(void *owner) { static_cast<RenderVulkan *>(owner)->queue_frame(); }

void RenderVulkan::queue_frame() {
    if (stopping || queued.exchange(true)) return;
    presentation_started = std::chrono::steady_clock::now();
    RenderingServer::get_singleton()->call_on_render_thread(callable_mp(this, &RenderVulkan::present_on_render_thread));
}

void RenderVulkan::present_frame() {
    if ((frame.display_width != target_width || frame.display_height != target_height ||
            frame.width != source_width || frame.height != source_height || frame.storage_width != storage_width || frame.storage_height != storage_height ||
            frame.sample_bytes != sample_bytes || frame.interleaved != interleaved) && !create_textures()) {
        render_error = MPV_ERROR_NOMEM;
        return;
    }
#ifdef _WIN32
    if (frame.d3d12_frame && d3d12.copy(frame, planes)) {
        frame.d3d12_frame.reset();
        return;
    }
    if (frame.d3d11_frame && d3d11.copy(frame, planes)) {
        frame.d3d11_frame.reset();
        return;
    }
#endif
#ifdef __linux__
    if (frame.hardware_frame && vaapi_available) {
        if (vaapi.copy(frame, planes)) {
            frame.hardware_frame.reset();
            frame.exported_frame.reset();
            return;
        }
        vaapi_available = false;
        decoder.enable_vaapi_frames(false);
    }
#endif
    if (!decoder.download_frame(frame)) {
        render_error = MPV_ERROR_GENERIC;
        return;
    }
    for (int index = 0; index < frame.plane_count; ++index) {
        if (device->texture_update(planes[index], 0, frame.planes[index].data()) != OK) {
            render_error = MPV_ERROR_GENERIC;
            return;
        }
    }
}

bool RenderVulkan::take_frame() {
    if (!stopping && render_error >= 0 && !queued && decoder.has_frame()) queue_frame();
    std::lock_guard<std::mutex> lock(texture_mutex);
    if (!frame_ready.exchange(false) || ready_generation != decoder.current_generation()) return false;
    presented_parameters = ready_parameters;
    presented_size = ready_size;
    presented_timestamp = ready_timestamp;
    return true;
}

Dictionary RenderVulkan::diagnostics() const {
    Dictionary values = decoder.diagnostics();
    uint64_t count = presented_frames.load();
    values["direct_yuv"] = true;
#ifdef _WIN32
    values["d3d12_gpu_available"] = d3d12.available();
    values["d3d12_gpu_copy"] = d3d12.available() && d3d12.copies() > 0;
    values["d3d12_gpu_frames"] = int64_t(d3d12.copies());
    values["d3d12_inflight_frames"] = int64_t(d3d12.outstanding());
    values["d3d12_prepared_frames"] = int64_t(d3d12.prepared());
    values["d3d12_prepare_ms"] = d3d12.preparation_ms();
    values["d3d12_fallback_reason"] = String(d3d12.failure().c_str());
    values["d3d11_gpu_available"] = d3d11.available();
    values["d3d11_gpu_copy"] = d3d11.available() && d3d11.copies() > 0;
    values["d3d11_gpu_frames"] = int64_t(d3d11.copies());
    values["d3d11_inflight_frames"] = int64_t(d3d11.outstanding());
    values["d3d11_prepared_frames"] = int64_t(d3d11.prepared());
    values["d3d11_prepare_ms"] = d3d11.preparation_ms();
    values["d3d11_fallback_reason"] = String(d3d11.failure().c_str());
#endif
#ifdef __linux__
    values["vaapi_gpu_available"] = vaapi_available.load();
    values["vaapi_gpu_copy"] = vaapi_available.load() && vaapi.copies() > 0;
    values["vaapi_gpu_frames"] = int64_t(vaapi.copies());
    values["vaapi_inflight_frames"] = int64_t(vaapi.outstanding());
    values["vaapi_fallback_reason"] = String(vaapi.failure().c_str());
    values["vaapi_render_node"] = String(vaapi.render_node().c_str());
#endif
    values["presented_frames"] = int64_t(count);
    values["presentation_ms"] = count ? double(presentation_us.load()) / count / 1000.0 : 0;
    return values;
}

int RenderVulkan::error() const {
    return render_error < 0 ? render_error.load() : decoder.error() < 0 ? MPV_ERROR_GENERIC : 0;
}

void RenderVulkan::destroy_on_render_thread() {
    if (!device) return;
#ifdef _WIN32
    if (d3d11.outstanding() > 0 || d3d12.outstanding() > 0) device->call("jellyxr_vulkan_drain");
#endif
#ifdef __linux__
    if (vaapi.outstanding() > 0) device->call("jellyxr_vulkan_drain");
#endif
    destroy_textures();
    device = nullptr;
}

void RenderVulkan::stop() {
    stopping = true;
    decoder.stop();
    run_sync(&RenderVulkan::destroy_on_render_thread);
    presented_parameters.clear();
    ready_parameters.clear();
    frame = VideoPlanes();
}

Dictionary RenderVulkan::frame_parameters() const {
    Dictionary values;
    values["direct_yuv"] = true;
    values["y_plane"] = textures[0];
    values["u_plane"] = textures[1];
    values["v_plane"] = frame.interleaved ? textures[1] : textures[2];
    values["source_size"] = Vector2(frame.width, frame.height);
    values["video_rotation"] = frame.rotation;
    values["interleaved_chroma"] = frame.interleaved;
    values["chroma_in_alpha"] = frame.interleaved && frame.sample_bytes == 1;
    values["color_coefficients"] = Vector2(frame.kr, frame.kb);
    values["full_range"] = frame.full_range;
    values["transfer"] = frame.transfer;
    values["sample_scale"] = frame.sample_scale;
    values["code_max"] = frame.code_max;
    values["source_peak"] = frame.source_peak;
    return values;
}
