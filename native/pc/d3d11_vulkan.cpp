#include "d3d11_vulkan.h"
#include <stdexcept>

namespace jellyxr_d3d11 {
void check_hr(HRESULT result, const char *operation) {
    if (result != S_OK)
        throw std::runtime_error(std::string(operation) + ": HRESULT " + std::to_string(uint32_t(result)));
}
void check_vk(VkResult result, const char *operation) {
    if (result != VK_SUCCESS)
        throw std::runtime_error(std::string(operation) + ": Vulkan " + std::to_string(result));
}

void VulkanApi::initialize(VkInstance instance, VkDevice device) {
    static HMODULE loader = LoadLibraryExW(L"vulkan-1.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!loader)
        throw std::runtime_error("Vulkan loader unavailable");
    auto get = reinterpret_cast<PFN_vkGetInstanceProcAddr>(GetProcAddress(loader, "vkGetInstanceProcAddr"));
    if (!get)
        throw std::runtime_error("Vulkan entry point unavailable");
#define LOAD_INSTANCE(member, function)                                                                                \
    member = reinterpret_cast<PFN_##function>(get(instance, #function));                                               \
    if (!member)                                                                                                       \
        throw std::runtime_error("Missing " #function);
    LOAD_INSTANCE(properties, vkGetPhysicalDeviceProperties2)
    LOAD_INSTANCE(image_properties, vkGetPhysicalDeviceImageFormatProperties2)
    LOAD_INSTANCE(memory_properties, vkGetPhysicalDeviceMemoryProperties)
    LOAD_INSTANCE(device_function, vkGetDeviceProcAddr)
#undef LOAD_INSTANCE
#define LOAD_DEVICE(member, function)                                                                                  \
    member = reinterpret_cast<PFN_##function>(device_function(device, #function));                                     \
    if (!member)                                                                                                       \
        throw std::runtime_error("Missing " #function);
    LOAD_DEVICE(create_image, vkCreateImage)
    LOAD_DEVICE(destroy_image, vkDestroyImage)
    LOAD_DEVICE(requirements, vkGetImageMemoryRequirements)
    LOAD_DEVICE(handle_properties, vkGetMemoryWin32HandlePropertiesKHR)
    LOAD_DEVICE(allocate, vkAllocateMemory)
    LOAD_DEVICE(free, vkFreeMemory)
    LOAD_DEVICE(bind, vkBindImageMemory)
    LOAD_DEVICE(barrier, vkCmdPipelineBarrier)
    LOAD_DEVICE(copy, vkCmdCopyImage)
#undef LOAD_DEVICE
}

uint32_t VulkanApi::memory_type(VkPhysicalDevice physical, uint32_t bits) const {
    VkPhysicalDeviceMemoryProperties properties{};
    memory_properties(physical, &properties);
    for (uint32_t i = 0; i < properties.memoryTypeCount; ++i)
        if (bits & (1u << i))
            return i;
    throw std::runtime_error("No compatible D3D11 shared memory type");
}

SharedPlanes::~SharedPlanes() {
    for (unsigned i = 0; i < 2; ++i) {
        if (images[i])
            api->destroy_image(device, images[i], nullptr);
        if (memories[i])
            api->free(device, memories[i], nullptr);
    }
}

bool SharedPlanes::matches(unsigned w, unsigned h, unsigned bytes) const {
    return width == w && height == h && sample_bytes == bytes;
}

static void require_format(const VulkanApi &api, VkPhysicalDevice physical, VkFormat format, unsigned w, unsigned h) {
    VkPhysicalDeviceExternalImageFormatInfo external{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO};
    external.handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_TEXTURE_BIT;
    VkPhysicalDeviceImageFormatInfo2 query{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2};
    query.pNext = &external;
    query.format = format;
    query.type = VK_IMAGE_TYPE_2D;
    query.tiling = VK_IMAGE_TILING_OPTIMAL;
    query.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    VkExternalImageFormatProperties imported{VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES};
    VkImageFormatProperties2 properties{VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2};
    properties.pNext = &imported;
    check_vk(api.image_properties(physical, &query, &properties), "query shared video plane support");
    if (!(imported.externalMemoryProperties.externalMemoryFeatures & VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT) ||
        !(imported.externalMemoryProperties.compatibleHandleTypes & external.handleType) ||
        w > properties.imageFormatProperties.maxExtent.width || h > properties.imageFormatProperties.maxExtent.height)
        throw std::runtime_error("D3D11 video plane is not importable at this size");
}

static void import_plane(SharedPlanes &planes, VkPhysicalDevice physical, unsigned index, VkFormat format) {
    auto &api = *planes.api;
    unsigned width = index ? planes.width / 2 : planes.width;
    unsigned height = index ? planes.height / 2 : planes.height;
    require_format(api, physical, format, width, height);
    VkExternalMemoryImageCreateInfo external{VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO};
    external.handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_TEXTURE_BIT;
    VkImageCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    info.pNext = &external;
    info.imageType = VK_IMAGE_TYPE_2D;
    info.format = format;
    info.extent = {width, height, 1};
    info.mipLevels = info.arrayLayers = 1;
    info.samples = VK_SAMPLE_COUNT_1_BIT;
    info.tiling = VK_IMAGE_TILING_OPTIMAL;
    info.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    check_vk(api.create_image(planes.device, &info, nullptr, &planes.images[index]), "create imported video plane");
    ComPtr<IDXGIResource1> resource;
    check_hr(planes.textures[index].As(&resource), "get shared video resource");
    HANDLE handle = nullptr;
    check_hr(
        resource->CreateSharedHandle(nullptr, DXGI_SHARED_RESOURCE_READ | DXGI_SHARED_RESOURCE_WRITE, nullptr, &handle),
        "export shared video handle");
    try {
        VkMemoryWin32HandlePropertiesKHR properties{VK_STRUCTURE_TYPE_MEMORY_WIN32_HANDLE_PROPERTIES_KHR};
        check_vk(
            api.handle_properties(planes.device, VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_TEXTURE_BIT, handle, &properties),
            "query shared video memory");
        VkMemoryRequirements requirements{};
        api.requirements(planes.device, planes.images[index], &requirements);
        VkMemoryDedicatedAllocateInfo dedicated{VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO};
        dedicated.image = planes.images[index];
        VkImportMemoryWin32HandleInfoKHR import{VK_STRUCTURE_TYPE_IMPORT_MEMORY_WIN32_HANDLE_INFO_KHR};
        import.pNext = &dedicated;
        import.handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D11_TEXTURE_BIT;
        import.handle = handle;
        VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
        allocation.pNext = &import;
        allocation.allocationSize = requirements.size;
        allocation.memoryTypeIndex = api.memory_type(physical, requirements.memoryTypeBits & properties.memoryTypeBits);
        check_vk(api.allocate(planes.device, &allocation, nullptr, &planes.memories[index]),
                 "import shared video memory");
        check_vk(api.bind(planes.device, planes.images[index], planes.memories[index], 0), "bind shared video memory");
    } catch (...) {
        CloseHandle(handle);
        throw;
    }
    CloseHandle(handle);
}

void SharedPlanes::initialize(std::shared_ptr<VulkanApi> functions, VkPhysicalDevice physical, VkDevice logical,
                              ID3D11Device *d3d, unsigned w, unsigned h, unsigned bytes) {
    api = functions;
    device = logical;
    width = w;
    height = h;
    sample_bytes = bytes;
    for (unsigned i = 0; i < 2; ++i) {
        D3D11_TEXTURE2D_DESC description{};
        description.Width = i ? w / 2 : w;
        description.Height = i ? h / 2 : h;
        description.ArraySize = description.MipLevels = description.SampleDesc.Count = 1;
        description.Format = bytes == 2 ? (i ? DXGI_FORMAT_R16G16_UNORM : DXGI_FORMAT_R16_UNORM)
                                        : (i ? DXGI_FORMAT_R8G8_UNORM : DXGI_FORMAT_R8_UNORM);
        description.Usage = D3D11_USAGE_DEFAULT;
        description.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
        description.MiscFlags = D3D11_RESOURCE_MISC_SHARED_NTHANDLE | D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX;
        check_hr(d3d->CreateTexture2D(&description, nullptr, &textures[i]), "create shared video plane");
        check_hr(textures[i].As(&mutexes[i]), "get shared video mutex");
        check_hr(d3d->CreateRenderTargetView(textures[i].Get(), nullptr, &targets[i]), "create video plane target");
        import_plane(*this, physical, i,
                     bytes == 2 ? (i ? VK_FORMAT_R16G16_UNORM : VK_FORMAT_R16_UNORM)
                                : (i ? VK_FORMAT_R8G8_UNORM : VK_FORMAT_R8_UNORM));
    }
}
} // namespace jellyxr_d3d11
