#pragma once
#include "video_decoder.h"
#include "vaapi_vulkan_import.h"
#include <godot_cpp/classes/rendering_device.hpp>
#include <memory>

class VaapiGodot {
public:
    bool initialize(godot::RenderingDevice *device);
    bool copy(const VideoPlanes &frame, const std::array<godot::RID, 3> &planes);
    const std::string &render_node() const { return node; }
    std::string failure() const { std::lock_guard<std::mutex> lock(reason_mutex); return reason; }
    uint64_t copies() const { return copied; }
    uint64_t outstanding() const { return inflight->load(); }
private:
    struct Job;
    static void record(uint64_t command, void *userdata);
    static void release(void *userdata);
    godot::RenderingDevice *rd = nullptr;
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    uint32_t queue_family = 0;
    std::string node, reason;
    mutable std::mutex reason_mutex;
    std::shared_ptr<std::atomic<uint64_t>> inflight = std::make_shared<std::atomic<uint64_t>>(0);
    std::atomic<uint64_t> copied{0};
};
