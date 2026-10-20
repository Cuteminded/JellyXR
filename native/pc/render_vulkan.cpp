#include "render_vulkan.h"
#include "video_conversion_shader.h"
#include <godot_cpp/classes/rd_sampler_state.hpp>
#include <godot_cpp/classes/rd_shader_source.hpp>
#include <godot_cpp/classes/rd_shader_spirv.hpp>
#include <godot_cpp/classes/rd_texture_format.hpp>
#include <godot_cpp/classes/rd_texture_view.hpp>
#include <godot_cpp/classes/rd_uniform.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <mpv/client.h>
#include <cstring>
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
    Ref<RDShaderSource> source;
    source.instantiate();
    source->set_stage_source(RenderingDevice::SHADER_STAGE_COMPUTE, video_conversion_shader);
    Ref<RDShaderSPIRV> spirv = device->shader_compile_spirv_from_source(source);
    if (spirv.is_null() || !spirv->get_stage_compile_error(RenderingDevice::SHADER_STAGE_COMPUTE).is_empty()) {
        render_error = MPV_ERROR_UNSUPPORTED;
        return;
    }
    shader = device->shader_create_from_spirv(spirv);
    if (shader.is_valid()) pipeline = device->compute_pipeline_create(shader);
    Ref<RDSamplerState> state;
    state.instantiate();
    sampler = device->sampler_create(state);
    if (!pipeline.is_valid() || !sampler.is_valid()) render_error = MPV_ERROR_UNSUPPORTED;
}

int RenderVulkan::start(String url, String authorization, int64_t start_ms) {
    run_sync(&RenderVulkan::initialize_on_render_thread);
    if (render_error < 0) return render_error;
    decoder.set_frame_callback(wakeup, this);
    int result = decoder.start(url.utf8().get_data(), authorization.utf8().get_data(), start_ms);
    return result < 0 ? MPV_ERROR_LOADING_FAILED : 0;
}

void RenderVulkan::destroy_textures() {
    if (texture.is_valid()) texture->set_texture_rd_rid(RID());
    texture.unref();
    if (uniforms.is_valid()) device->free_rid(uniforms);
    uniforms = RID();
    if (output.is_valid()) device->free_rid(output);
    output = RID();
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
    format->set_usage_bits(RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice::TEXTURE_USAGE_CAN_UPDATE_BIT);
    Ref<RDTextureView> view;
    view.instantiate();
    TypedArray<RDUniform> bindings;
    for (int index = 0; index < 3; ++index) {
        RID plane;
        if (index < frame.plane_count) {
            format->set_format(frame.sample_bytes == 1 ?
                (index && frame.interleaved ? RenderingDevice::DATA_FORMAT_R8G8_UNORM : RenderingDevice::DATA_FORMAT_R8_UNORM) :
                (index && frame.interleaved ? RenderingDevice::DATA_FORMAT_R16G16_UNORM : RenderingDevice::DATA_FORMAT_R16_UNORM));
            format->set_width(index ? (frame.storage_width + 1) / 2 : frame.storage_width);
            format->set_height(index ? (frame.storage_height + 1) / 2 : frame.storage_height);
            planes[index] = device->texture_create(format, view);
            if (!planes[index].is_valid()) return false;
            plane = planes[index];
        } else plane = planes[0];
        Ref<RDUniform> uniform;
        uniform.instantiate();
        uniform->set_uniform_type(RenderingDevice::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE);
        uniform->set_binding(index);
        uniform->add_id(sampler);
        uniform->add_id(plane);
        bindings.append(uniform);
    }
    format->set_width(frame.display_width);
    format->set_height(frame.display_height);
    format->set_format(RenderingDevice::DATA_FORMAT_R8G8B8A8_UNORM);
    format->add_shareable_format(RenderingDevice::DATA_FORMAT_R8G8B8A8_UNORM);
    format->add_shareable_format(RenderingDevice::DATA_FORMAT_R8G8B8A8_SRGB);
    format->set_usage_bits(RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice::TEXTURE_USAGE_STORAGE_BIT | RenderingDevice::TEXTURE_USAGE_CAN_COPY_FROM_BIT);
    output = device->texture_create(format, view);
    if (!output.is_valid()) return false;
    Ref<RDUniform> destination;
    destination.instantiate();
    destination->set_uniform_type(RenderingDevice::UNIFORM_TYPE_IMAGE);
    destination->set_binding(3);
    destination->add_id(output);
    bindings.append(destination);
    uniforms = device->uniform_set_create(bindings, shader, 0);
    if (!uniforms.is_valid()) return false;
    texture.instantiate();
    texture->set_texture_rd_rid(output);
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
            std::lock_guard<std::mutex> lock(texture_mutex);
            ready_texture = texture;
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
    for (int index = 0; index < frame.plane_count; ++index) {
        if (device->texture_update(planes[index], 0, frame.planes[index].data()) != OK) {
            render_error = MPV_ERROR_GENERIC;
            return;
        }
    }
    struct Parameters {
        int32_t width, height, source_width, source_height;
        float kr, kb, full_range, transfer;
        int32_t rotation, interleaved;
        float sample_scale, code_max;
        float source_peak, padding[3];
    } parameters{frame.display_width, frame.display_height, frame.width, frame.height,
        frame.kr, frame.kb, frame.full_range, frame.transfer, frame.rotation, frame.interleaved ? 1 : 0, frame.sample_scale, frame.code_max,
        frame.source_peak, {0, 0, 0}};
    PackedByteArray constants;
    constants.resize(sizeof(parameters));
    std::memcpy(constants.ptrw(), &parameters, sizeof(parameters));
    int64_t list = device->compute_list_begin();
    device->compute_list_bind_compute_pipeline(list, pipeline);
    device->compute_list_bind_uniform_set(list, uniforms, 0);
    device->compute_list_set_push_constant(list, constants, constants.size());
    device->compute_list_dispatch(list, (frame.display_width + 15) / 16, (frame.display_height + 15) / 16, 1);
    device->compute_list_end();
}

bool RenderVulkan::take_frame() {
    if (!stopping && render_error >= 0 && !queued && decoder.has_frame()) queue_frame();
    std::lock_guard<std::mutex> lock(texture_mutex);
    if (!frame_ready.exchange(false) || ready_generation != decoder.current_generation()) return false;
    presented_texture = ready_texture;
    presented_timestamp = ready_timestamp;
    return true;
}

Dictionary RenderVulkan::diagnostics() const {
    Dictionary values = decoder.diagnostics();
    uint64_t count = presented_frames.load();
    values["presented_frames"] = int64_t(count);
    values["presentation_ms"] = count ? double(presentation_us.load()) / count / 1000.0 : 0;
    return values;
}

int RenderVulkan::error() const {
    return render_error < 0 ? render_error.load() : decoder.error() < 0 ? MPV_ERROR_GENERIC : 0;
}

void RenderVulkan::destroy_on_render_thread() {
    if (!device) return;
    destroy_textures();
    if (pipeline.is_valid()) device->free_rid(pipeline);
    if (shader.is_valid()) device->free_rid(shader);
    if (sampler.is_valid()) device->free_rid(sampler);
    pipeline = shader = sampler = RID();
    device = nullptr;
}

void RenderVulkan::stop() {
    stopping = true;
    decoder.stop();
    run_sync(&RenderVulkan::destroy_on_render_thread);
    presented_texture.unref();
    ready_texture.unref();
    frame = VideoPlanes();
}
