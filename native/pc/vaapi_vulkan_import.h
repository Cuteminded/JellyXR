#pragma once
#include <vulkan/vulkan.h>
#include <array>
struct AVDRMFrameDescriptor;
namespace jellyxr_vaapi {
struct PlaneLayout {
    VkFormat format = VK_FORMAT_UNDEFINED;
    uint32_t width = 0, height = 0, storage_width = 0, storage_height = 0;
    uint32_t bytes_per_pixel = 0;
};
struct GpuImage {
    VkDevice device = VK_NULL_HANDLE;
    VkImage image = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    ~GpuImage();
    GpuImage() = default;
    GpuImage(const GpuImage &) = delete;
    GpuImage &operator=(const GpuImage &) = delete;
    void reset();
};
std::array<PlaneLayout, 2> video_layout(const AVDRMFrameDescriptor &, int, int, int, int, int);
class Importer {
public:
    void initialize(VkPhysicalDevice p_physical, VkDevice p_device);
    void import_image(GpuImage &, const AVDRMFrameDescriptor &, int, const PlaneLayout &);
private:
    uint32_t memory_type(uint32_t bits, VkMemoryPropertyFlags flags) const;
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    PFN_vkGetMemoryFdPropertiesKHR get_fd_properties = nullptr;
};
}
