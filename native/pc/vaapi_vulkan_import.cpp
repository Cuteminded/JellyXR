#include "vaapi_vulkan_import.h"
extern "C" {
#include <libavutil/hwcontext_drm.h>
#include <libavutil/pixfmt.h>
}
#include <drm_fourcc.h>
#include <unistd.h>
#include <stdexcept>
#include <string>
#include <vector>
namespace jellyxr_vaapi {
static void vk_check(VkResult result, const char *operation) {
    if (result != VK_SUCCESS) throw std::runtime_error(std::string(operation) + ": VkResult=" + std::to_string(result));
}
GpuImage::~GpuImage() { reset(); }
void GpuImage::reset() {
    if (image) vkDestroyImage(device, image, nullptr);
    if (memory) vkFreeMemory(device, memory, nullptr);
    image = VK_NULL_HANDLE;
    memory = VK_NULL_HANDLE;
}
void Importer::initialize(VkPhysicalDevice p_physical, VkDevice p_device) {
    physical = p_physical;
    device = p_device;
    get_fd_properties = reinterpret_cast<PFN_vkGetMemoryFdPropertiesKHR>(vkGetDeviceProcAddr(device, "vkGetMemoryFdPropertiesKHR"));
    if (!get_fd_properties) throw std::runtime_error("Missing DMA-BUF memory import function");
}
uint32_t Importer::memory_type(uint32_t bits, VkMemoryPropertyFlags flags) const {
    VkPhysicalDeviceMemoryProperties properties;
    vkGetPhysicalDeviceMemoryProperties(physical, &properties);
    for (uint32_t i = 0; i < properties.memoryTypeCount; ++i)
        if ((bits & (1u << i)) && (properties.memoryTypes[i].propertyFlags & flags) == flags) return i;
    throw std::runtime_error("No compatible imported memory type");
}
std::array<PlaneLayout, 2> video_layout(const AVDRMFrameDescriptor &descriptor,
        int format, int width, int height, int storage_width, int storage_height) {
    if (format != AV_PIX_FMT_NV12 && format != AV_PIX_FMT_P010LE)
        throw std::runtime_error("Vulkan probe supports NV12 and P010 only");
    if (width <= 0 || height <= 0 || storage_width < width || storage_height < height ||
            storage_width > 16384 || storage_height > 16384)
        throw std::runtime_error("Invalid frame dimensions");
    if (descriptor.nb_layers != 2 || descriptor.nb_objects < 1 || descriptor.nb_objects > AV_DRM_MAX_PLANES)
        throw std::runtime_error("Expected two separately exported Y/UV layers");
    bool ten_bit = format == AV_PIX_FMT_P010LE;
    std::array<PlaneLayout, 2> result{};
    for (int i = 0; i < 2; ++i) {
        const auto &layer = descriptor.layers[i];
        uint32_t expected = ten_bit ? (i ? DRM_FORMAT_GR1616 : DRM_FORMAT_R16) : (i ? DRM_FORMAT_GR88 : DRM_FORMAT_R8);
        if (layer.format != expected || layer.nb_planes < 1 || layer.nb_planes > AV_DRM_MAX_PLANES)
            throw std::runtime_error("Unsupported DRM layer format or plane count");
        int object_index = layer.planes[0].object_index;
        if (object_index < 0 || object_index >= descriptor.nb_objects)
            throw std::runtime_error("Invalid DRM object index");
        const auto &object = descriptor.objects[object_index];
        if (object.fd < 0 || object.size == 0 || object.format_modifier == DRM_FORMAT_MOD_INVALID)
            throw std::runtime_error("Invalid DMA-BUF object or missing modifier");
        for (int p = 0; p < layer.nb_planes; ++p) {
            const auto &plane = layer.planes[p];
            if (plane.object_index != object_index || plane.offset < 0 ||
                    uint64_t(plane.offset) >= object.size || plane.pitch <= 0)
                throw std::runtime_error("Unsupported DRM memory-plane layout");
        }
        result[i] = {ten_bit ? (i ? VK_FORMAT_R16G16_UNORM : VK_FORMAT_R16_UNORM) :
            (i ? VK_FORMAT_R8G8_UNORM : VK_FORMAT_R8_UNORM),
            uint32_t(i ? (width + 1) / 2 : width), uint32_t(i ? (height + 1) / 2 : height),
            uint32_t(i ? (storage_width + 1) / 2 : storage_width),
            uint32_t(i ? (storage_height + 1) / 2 : storage_height), uint32_t((ten_bit ? 2 : 1) * (i ? 2 : 1))};
    }
    return result;
}

static VkImageCreateInfo image_info(VkFormat format, uint32_t width, uint32_t height) {
    VkImageCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    info.imageType = VK_IMAGE_TYPE_2D;
    info.format = format;
    info.extent = {width, height, 1};
    info.mipLevels = info.arrayLayers = 1;
    info.samples = VK_SAMPLE_COUNT_1_BIT;
    info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    return info;
}

void Importer::import_image(GpuImage &image, const AVDRMFrameDescriptor &descriptor,
        int plane, const PlaneLayout &layout) {
    const auto &layer = descriptor.layers[plane];
    const auto &object = descriptor.objects[layer.planes[0].object_index];
    VkDrmFormatModifierPropertiesListEXT modifiers{};
    modifiers.sType = VK_STRUCTURE_TYPE_DRM_FORMAT_MODIFIER_PROPERTIES_LIST_EXT;
    VkFormatProperties2 properties{};
    properties.sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2;
    properties.pNext = &modifiers;
    vkGetPhysicalDeviceFormatProperties2(physical, layout.format, &properties);
    std::vector<VkDrmFormatModifierPropertiesEXT> entries(modifiers.drmFormatModifierCount);
    modifiers.pDrmFormatModifierProperties = entries.data();
    vkGetPhysicalDeviceFormatProperties2(physical, layout.format, &properties);
    bool supported = false;
    for (const auto &entry : entries)
        if (entry.drmFormatModifier == object.format_modifier && entry.drmFormatModifierPlaneCount == uint32_t(layer.nb_planes) &&
                (entry.drmFormatModifierTilingFeatures & VK_FORMAT_FEATURE_TRANSFER_SRC_BIT)) supported = true;
    if (!supported) throw std::runtime_error("DRM modifier/plane count does not support Vulkan transfer source");

    VkPhysicalDeviceExternalImageFormatInfo external_query{};
    external_query.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO;
    external_query.handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;
    VkPhysicalDeviceImageDrmFormatModifierInfoEXT modifier_query{};
    modifier_query.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_DRM_FORMAT_MODIFIER_INFO_EXT;
    modifier_query.pNext = &external_query;
    modifier_query.drmFormatModifier = object.format_modifier;
    modifier_query.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    VkPhysicalDeviceImageFormatInfo2 query{};
    query.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2;
    query.pNext = &modifier_query;
    query.format = layout.format;
    query.type = VK_IMAGE_TYPE_2D;
    query.tiling = VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT;
    query.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    VkExternalImageFormatProperties external_properties{};
    external_properties.sType = VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES;
    VkImageFormatProperties2 limits{};
    limits.sType = VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2;
    limits.pNext = &external_properties;
    vk_check(vkGetPhysicalDeviceImageFormatProperties2(physical, &query, &limits), "query DMA-BUF image support");
    if (!(external_properties.externalMemoryProperties.externalMemoryFeatures & VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT) ||
            layout.storage_width > limits.imageFormatProperties.maxExtent.width ||
            layout.storage_height > limits.imageFormatProperties.maxExtent.height)
        throw std::runtime_error("DMA-BUF image is not importable at this size");

    std::vector<VkSubresourceLayout> layouts(layer.nb_planes);
    for (int i = 0; i < layer.nb_planes; ++i) {
        layouts[i].offset = layer.planes[i].offset;
        layouts[i].rowPitch = layer.planes[i].pitch;
    }
    VkImageDrmFormatModifierExplicitCreateInfoEXT modifier{};
    modifier.sType = VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_EXPLICIT_CREATE_INFO_EXT;
    modifier.drmFormatModifier = object.format_modifier;
    modifier.drmFormatModifierPlaneCount = uint32_t(layouts.size());
    modifier.pPlaneLayouts = layouts.data();
    VkExternalMemoryImageCreateInfo external{};
    external.sType = VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO;
    external.pNext = &modifier;
    external.handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;
    auto info = image_info(layout.format, layout.storage_width, layout.storage_height);
    info.pNext = &external;
    info.tiling = VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT;
    info.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    image.device = device;
    vk_check(vkCreateImage(device, &info, nullptr, &image.image), "create imported image");
    VkMemoryRequirements requirements;
    vkGetImageMemoryRequirements(device, image.image, &requirements);
    if (requirements.size > object.size) throw std::runtime_error("DMA-BUF is smaller than Vulkan image memory requirements");
    VkMemoryFdPropertiesKHR fd_properties{};
    fd_properties.sType = VK_STRUCTURE_TYPE_MEMORY_FD_PROPERTIES_KHR;
    vk_check(get_fd_properties(device, VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT, object.fd, &fd_properties), "query DMA-BUF memory types");
    VkMemoryDedicatedAllocateInfo dedicated{};
    dedicated.sType = VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO;
    dedicated.image = image.image;
    VkImportMemoryFdInfoKHR import{};
    import.sType = VK_STRUCTURE_TYPE_IMPORT_MEMORY_FD_INFO_KHR;
    import.pNext = &dedicated;
    import.handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT;
    VkMemoryAllocateInfo allocation{};
    allocation.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocation.pNext = &import;
    allocation.allocationSize = object.size;
    allocation.memoryTypeIndex = memory_type(requirements.memoryTypeBits & fd_properties.memoryTypeBits, 0);
    import.fd = dup(object.fd);
    if (import.fd < 0) throw std::runtime_error("Cannot duplicate DMA-BUF descriptor");
    VkResult result = vkAllocateMemory(device, &allocation, nullptr, &image.memory);
    if (result != VK_SUCCESS) close(import.fd);
    vk_check(result, "import DMA-BUF memory");
    vk_check(vkBindImageMemory(device, image.image, image.memory, 0), "bind imported image");
}


}

