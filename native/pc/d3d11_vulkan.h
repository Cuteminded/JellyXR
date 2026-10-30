#pragma once
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#define VK_USE_PLATFORM_WIN32_KHR
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <wrl/client.h>
#include <array>
#include <memory>
#include <string>

namespace jellyxr_d3d11 {
using Microsoft::WRL::ComPtr;

struct VulkanApi {
    PFN_vkGetPhysicalDeviceProperties2 properties = nullptr;
    PFN_vkGetPhysicalDeviceImageFormatProperties2 image_properties = nullptr;
    PFN_vkGetPhysicalDeviceMemoryProperties memory_properties = nullptr;
    PFN_vkGetDeviceProcAddr device_function = nullptr;
    PFN_vkCreateImage create_image = nullptr;
    PFN_vkDestroyImage destroy_image = nullptr;
    PFN_vkGetImageMemoryRequirements requirements = nullptr;
    PFN_vkGetMemoryWin32HandlePropertiesKHR handle_properties = nullptr;
    PFN_vkAllocateMemory allocate = nullptr;
    PFN_vkFreeMemory free = nullptr;
    PFN_vkBindImageMemory bind = nullptr;
    PFN_vkCmdPipelineBarrier barrier = nullptr;
    PFN_vkCmdCopyImage copy = nullptr;
    void initialize(VkInstance instance, VkDevice device);
    uint32_t memory_type(VkPhysicalDevice physical, uint32_t bits) const;
};

struct SharedPlanes {
    std::shared_ptr<VulkanApi> api;
    VkDevice device = VK_NULL_HANDLE;
    std::array<ComPtr<ID3D11Texture2D>, 2> textures;
    std::array<ComPtr<ID3D11RenderTargetView>, 2> targets;
    std::array<ComPtr<IDXGIKeyedMutex>, 2> mutexes;
    std::array<VkImage, 2> images{};
    std::array<VkDeviceMemory, 2> memories{};
    unsigned width = 0, height = 0, sample_bytes = 0;
    ~SharedPlanes();
    bool matches(unsigned w, unsigned h, unsigned bytes) const;
    void initialize(std::shared_ptr<VulkanApi> functions, VkPhysicalDevice physical, VkDevice logical,
                    ID3D11Device *d3d, unsigned w, unsigned h, unsigned bytes);
};

void check_hr(HRESULT result, const char *operation);
void check_vk(VkResult result, const char *operation);
} // namespace jellyxr_d3d11
