#include "d3d12_gpu.h"
#include <stdexcept>
using namespace jellyxr_d3d11;

D3D12Planes::~D3D12Planes() {
    wait_copy();
    if (semaphore) {
        auto destroy = reinterpret_cast<PFN_vkDestroySemaphore>(api->device_function(device, "vkDestroySemaphore"));
        destroy(device, semaphore, nullptr);
    }
    for (unsigned i = 0; i < 2; ++i) {
        if (images[i])
            api->destroy_image(device, images[i], nullptr);
        if (memories[i])
            api->free(device, memories[i], nullptr);
    }
    if (event)
        CloseHandle(event);
}

bool D3D12Planes::wait_copy() const {
    if (!fence || !value)
        return true;
    uint64_t completed = fence->GetCompletedValue();
    if (completed == UINT64_MAX)
        return false;
    if (completed >= value)
        return true;
    return event && SUCCEEDED(fence->SetEventOnCompletion(value, event)) &&
           WaitForSingleObject(event, 5000) == WAIT_OBJECT_0;
}

bool D3D12Planes::matches(unsigned w, unsigned h, unsigned bytes) const {
    return width == w && height == h && sample_bytes == bytes;
}

void D3D12Planes::initialize(std::shared_ptr<VulkanApi> functions, VkPhysicalDevice physical, VkDevice logical,
                             ID3D12Device *d3d, unsigned w, unsigned h, unsigned bytes) {
    api = functions;
    device = logical;
    width = w;
    height = h;
    sample_bytes = bytes;
    for (unsigned i = 0; i < 2; ++i) {
        D3D12_HEAP_PROPERTIES heap{};
        heap.Type = D3D12_HEAP_TYPE_DEFAULT;
        D3D12_RESOURCE_DESC description{};
        description.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
        description.Width = i ? w / 2 : w;
        description.Height = i ? h / 2 : h;
        description.DepthOrArraySize = description.MipLevels = description.SampleDesc.Count = 1;
        description.Format = bytes == 2 ? (i ? DXGI_FORMAT_R16G16_UNORM : DXGI_FORMAT_R16_UNORM)
                                        : (i ? DXGI_FORMAT_R8G8_UNORM : DXGI_FORMAT_R8_UNORM);
        description.Flags = D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS;
        check_hr(d3d->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_SHARED, &description, D3D12_RESOURCE_STATE_COMMON,
                                              nullptr, IID_PPV_ARGS(&textures[i])),
                 "create shared D3D12 video plane");
        import_plane(physical, d3d, i);
    }
    check_hr(d3d->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_COPY, IID_PPV_ARGS(&allocator)),
             "create D3D12 video allocator");
    check_hr(d3d->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_COPY, allocator.Get(), nullptr, IID_PPV_ARGS(&commands)),
             "create D3D12 video commands");
    check_hr(commands->Close(), "close initial D3D12 video commands");
    create_fence(d3d);
}

void D3D12Planes::import_plane(VkPhysicalDevice physical, ID3D12Device *d3d, unsigned plane) {
    VkFormat format = sample_bytes == 2 ? (plane ? VK_FORMAT_R16G16_UNORM : VK_FORMAT_R16_UNORM)
                                        : (plane ? VK_FORMAT_R8G8_UNORM : VK_FORMAT_R8_UNORM);
    VkPhysicalDeviceExternalImageFormatInfo external_query{
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO};
    external_query.handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D12_RESOURCE_BIT;
    VkPhysicalDeviceImageFormatInfo2 query{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2};
    query.pNext = &external_query;
    query.format = format;
    query.type = VK_IMAGE_TYPE_2D;
    query.tiling = VK_IMAGE_TILING_OPTIMAL;
    query.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    VkExternalImageFormatProperties imported{VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES};
    VkImageFormatProperties2 properties{VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2};
    properties.pNext = &imported;
    check_vk(api->image_properties(physical, &query, &properties), "query D3D12 video plane support");
    auto description = textures[plane]->GetDesc();
    if (!(imported.externalMemoryProperties.externalMemoryFeatures & VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT) ||
        !(imported.externalMemoryProperties.compatibleHandleTypes & external_query.handleType) ||
        description.Width > properties.imageFormatProperties.maxExtent.width ||
        description.Height > properties.imageFormatProperties.maxExtent.height)
        throw std::runtime_error("D3D12 video plane is not importable at this size");
    VkExternalMemoryImageCreateInfo external{VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO};
    external.handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D12_RESOURCE_BIT;
    VkImageCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    info.pNext = &external;
    info.imageType = VK_IMAGE_TYPE_2D;
    info.format = format;
    info.extent = {unsigned(description.Width), description.Height, 1};
    info.mipLevels = info.arrayLayers = 1;
    info.samples = VK_SAMPLE_COUNT_1_BIT;
    info.tiling = VK_IMAGE_TILING_OPTIMAL;
    info.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    check_vk(api->create_image(device, &info, nullptr, &images[plane]), "create imported D3D12 video plane");
    HANDLE handle = nullptr;
    check_hr(d3d->CreateSharedHandle(textures[plane].Get(), nullptr, GENERIC_ALL, nullptr, &handle),
             "export D3D12 video handle");
    try {
        VkMemoryWin32HandlePropertiesKHR memory{VK_STRUCTURE_TYPE_MEMORY_WIN32_HANDLE_PROPERTIES_KHR};
        check_vk(api->handle_properties(device, VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D12_RESOURCE_BIT, handle, &memory),
                 "query D3D12 video memory");
        VkMemoryRequirements requirements{};
        api->requirements(device, images[plane], &requirements);
        VkMemoryDedicatedAllocateInfo dedicated{VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO};
        dedicated.image = images[plane];
        VkImportMemoryWin32HandleInfoKHR import{VK_STRUCTURE_TYPE_IMPORT_MEMORY_WIN32_HANDLE_INFO_KHR};
        import.pNext = &dedicated;
        import.handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_D3D12_RESOURCE_BIT;
        import.handle = handle;
        VkMemoryAllocateInfo allocation{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
        allocation.pNext = &import;
        allocation.allocationSize = requirements.size;
        allocation.memoryTypeIndex = api->memory_type(physical, requirements.memoryTypeBits & memory.memoryTypeBits);
        check_vk(api->allocate(device, &allocation, nullptr, &memories[plane]), "import D3D12 video memory");
        check_vk(api->bind(device, images[plane], memories[plane], 0), "bind D3D12 video memory");
    } catch (...) {
        CloseHandle(handle);
        throw;
    }
    CloseHandle(handle);
}

void D3D12Planes::create_fence(ID3D12Device *d3d) {
    check_hr(d3d->CreateFence(0, D3D12_FENCE_FLAG_SHARED, IID_PPV_ARGS(&fence)), "create shared D3D12 fence");
    event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!event)
        throw std::runtime_error("Cannot create D3D12 transfer event");
    auto create = reinterpret_cast<PFN_vkCreateSemaphore>(api->device_function(device, "vkCreateSemaphore"));
    auto import = reinterpret_cast<PFN_vkImportSemaphoreWin32HandleKHR>(
        api->device_function(device, "vkImportSemaphoreWin32HandleKHR"));
    if (!create || !import)
        throw std::runtime_error("Vulkan D3D12 fence import unavailable");
    HANDLE handle = nullptr;
    check_hr(d3d->CreateSharedHandle(fence.Get(), nullptr, GENERIC_ALL, nullptr, &handle), "export D3D12 video fence");
    try {
        VkSemaphoreCreateInfo info{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
        check_vk(create(device, &info, nullptr, &semaphore), "create Vulkan video fence");
        VkImportSemaphoreWin32HandleInfoKHR external{VK_STRUCTURE_TYPE_IMPORT_SEMAPHORE_WIN32_HANDLE_INFO_KHR};
        external.semaphore = semaphore;
        external.handleType = VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_D3D12_FENCE_BIT;
        external.handle = handle;
        check_vk(import(device, &external), "import D3D12 video fence");
    } catch (...) {
        CloseHandle(handle);
        throw;
    }
    CloseHandle(handle);
}
