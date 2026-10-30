#include "vaapi_godot.h"
#include "vaapi_frame.h"
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
}
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <stdexcept>

using namespace godot;
using namespace jellyxr_vaapi;

struct VaapiGodot::Job {
    std::shared_ptr<VaapiFrame> exported;
    std::array<GpuImage, 2> imported;
    std::array<PlaneLayout, 2> layout;
    std::array<VkImage, 2> destination;
    uint32_t queue_family;
    std::shared_ptr<std::atomic<uint64_t>> inflight;
};

bool VaapiGodot::initialize(RenderingDevice *p_device) {
    rd = p_device;
    if (!rd->has_method("jellyxr_vaapi_available") || !rd->has_method("jellyxr_vulkan_queue_copy") ||
            !rd->has_method("jellyxr_vulkan_drain") || !bool(rd->call("jellyxr_vaapi_available"))) {
        reason = "Godot VAAPI render-graph adapter unavailable";
        return false;
    }
    physical = reinterpret_cast<VkPhysicalDevice>(rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_PHYSICAL_DEVICE, RID(), 0));
    device = reinterpret_cast<VkDevice>(rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_LOGICAL_DEVICE, RID(), 0));
    queue_family = uint32_t(rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_QUEUE_FAMILY, RID(), 0));
    VkPhysicalDeviceDrmPropertiesEXT drm{};
    drm.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRM_PROPERTIES_EXT;
    VkPhysicalDeviceProperties2 properties{};
    properties.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
    properties.pNext = &drm;
    vkGetPhysicalDeviceProperties2(physical, &properties);
    if (properties.properties.apiVersion < VK_API_VERSION_1_2) {
        reason = "VAAPI GPU import requires Vulkan 1.2";
        return false;
    }
    if (!drm.hasRender) { reason = "Vulkan GPU has no DRM render node"; return false; }
    node = "/dev/dri/renderD" + std::to_string(drm.renderMinor);
    struct stat status{};
    if (stat(node.c_str(), &status) != 0 || !S_ISCHR(status.st_mode) ||
            major(status.st_rdev) != drm.renderMajor || minor(status.st_rdev) != drm.renderMinor) {
        reason = "Vulkan render node is inaccessible";
        node.clear();
        return false;
    }
    return true;
}

bool VaapiGodot::copy(const VideoPlanes &frame, const std::array<RID, 3> &planes) {
    if (!frame.hardware_frame || inflight->load() >= 8) {
        std::lock_guard<std::mutex> lock(reason_mutex);
        reason = "VAAPI frame limit reached";
        return false;
    }
    try {
        std::unique_ptr<Job> job = std::make_unique<Job>();
        auto *source = frame.hardware_frame.get();
        job->exported = frame.exported_frame;
        if (!job->exported) throw std::runtime_error("VAAPI DMA-BUF export failed in decoder worker");
        auto *frames = reinterpret_cast<AVHWFramesContext *>(source->hw_frames_ctx->data);
        job->layout = video_layout(*job->exported->descriptor(), frames->sw_format, source->width,
            source->height, frames->width, frames->height);
        Importer importer;
        importer.initialize(physical, device);
        for (int i = 0; i < 2; ++i) {
            importer.import_image(job->imported[i], *job->exported->descriptor(), i, job->layout[i]);
            job->destination[i] = (VkImage)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_TEXTURE, planes[i], 0);
        }
        job->queue_family = queue_family;
        job->inflight = inflight;
        Array targets;
        targets.push_back(planes[0]);
        targets.push_back(planes[1]);
        ++*inflight;
        Error result = Error(int64_t(rd->call("jellyxr_vulkan_queue_copy", uint64_t(&record),
            uint64_t(&release), uint64_t(job.get()), targets)));
        if (result != OK) {
            --*inflight;
            throw std::runtime_error("Godot rejected VAAPI GPU copy");
        }
        job.release();
        ++copied;
        return true;
    } catch (const std::exception &error) {
        std::lock_guard<std::mutex> lock(reason_mutex);
        reason = error.what();
        return false;
    }
}

void VaapiGodot::record(uint64_t p_command, void *userdata) {
    auto *job = static_cast<Job *>(userdata);
    auto command = reinterpret_cast<VkCommandBuffer>(p_command);
    for (int i = 0; i < 2; ++i) {
        VkImageMemoryBarrier acquire{};
        acquire.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        acquire.oldLayout = acquire.newLayout = VK_IMAGE_LAYOUT_GENERAL;
        acquire.srcQueueFamilyIndex = VK_QUEUE_FAMILY_FOREIGN_EXT;
        acquire.dstQueueFamilyIndex = job->queue_family;
        acquire.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        acquire.image = job->imported[i].image;
        acquire.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, nullptr, 0, nullptr, 1, &acquire);
        VkImageCopy region{};
        region.srcSubresource = region.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        region.extent = {job->layout[i].width, job->layout[i].height, 1};
        vkCmdCopyImage(command, job->imported[i].image, VK_IMAGE_LAYOUT_GENERAL,
            job->destination[i], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        std::swap(acquire.srcQueueFamilyIndex, acquire.dstQueueFamilyIndex);
        acquire.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        acquire.dstAccessMask = 0;
        vkCmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
            0, 0, nullptr, 0, nullptr, 1, &acquire);
    }
}

void VaapiGodot::release(void *userdata) {
    auto *job = static_cast<Job *>(userdata);
    auto inflight = job->inflight;
    delete job;
    --*inflight;
}
