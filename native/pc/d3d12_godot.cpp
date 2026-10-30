#include "d3d12_godot.h"
#include <godot_cpp/classes/os.hpp>
#include <stdexcept>
using namespace godot;

struct D3D12Godot::Job {
    std::shared_ptr<D3D12Gpu> gpu;
    std::shared_ptr<D3D12Frame> frame;
    std::array<VkImage, 2> destinations;
    std::shared_ptr<std::atomic<uint64_t>> inflight;
};

bool D3D12Godot::initialize(RenderingDevice *device) {
    rd = device;
    if (OS::get_singleton()->get_environment("JELLYXR_DISABLE_D3D12_GPU") == "1" ||
        OS::get_singleton()->get_environment("JELLYXR_WINDOWS_VIDEO_API") == "d3d11") {
        gpu->disable("D3D12 GPU frames disabled by environment");
        return false;
    }
    if (!rd->has_method("jellyxr_d3d12_available") || !rd->has_method("jellyxr_vulkan_queue_copy") ||
        !rd->has_method("jellyxr_vulkan_drain") || !bool(rd->call("jellyxr_d3d12_available"))) {
        gpu->disable("Godot D3D12 render-graph adapter unavailable");
        return false;
    }
    return gpu->initialize(
        reinterpret_cast<VkInstance>(
            rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_VULKAN_INSTANCE, RID(), 0)),
        reinterpret_cast<VkPhysicalDevice>(
            rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_PHYSICAL_DEVICE, RID(), 0)),
        reinterpret_cast<VkDevice>(rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_LOGICAL_DEVICE, RID(), 0)),
        uint32_t(rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_QUEUE_FAMILY, RID(), 0)));
}

bool D3D12Godot::copy(const VideoPlanes &frame, const std::array<RID, 3> &targets) {
    if (!frame.d3d12_frame || !gpu->available())
        return false;
    auto job = std::make_unique<Job>();
    job->gpu = gpu;
    job->frame = frame.d3d12_frame;
    job->inflight = inflight;
    Array textures, memories;
    for (unsigned i = 0; i < 2; ++i) {
        job->destinations[i] =
            (VkImage)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_TEXTURE, targets[i], 0);
        if (!job->destinations[i]) {
            gpu->disable("Missing Vulkan video destination");
            return false;
        }
        textures.push_back(targets[i]);
    }
    memories.push_back(uint64_t(job->frame->planes->semaphore));
    memories.push_back(job->frame->fence_value);
    memories.push_back(12);
    ++*inflight;
    Error result = Error(int64_t(rd->call("jellyxr_vulkan_queue_copy", uint64_t(&record), uint64_t(&release),
                                          uint64_t(job.get()), textures, memories)));
    if (result != OK) {
        --*inflight;
        gpu->disable("Godot rejected D3D12 GPU copy");
        return false;
    }
    job->frame->submitted = true;
    job.release();
    ++copied;
    return true;
}

void D3D12Godot::record(uint64_t command, void *userdata) {
    auto *job = static_cast<Job *>(userdata);
    job->gpu->record(reinterpret_cast<VkCommandBuffer>(command), *job->frame, job->destinations);
}

void D3D12Godot::release(void *userdata) {
    auto *job = static_cast<Job *>(userdata);
    auto counter = job->inflight;
    delete job;
    --*counter;
}
