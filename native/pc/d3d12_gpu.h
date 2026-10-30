#pragma once
#include "d3d11_vulkan.h"
#include <d3d12.h>
#include <atomic>
#include <mutex>
#include <vector>
struct AVBufferRef;
struct AVFrame;

struct D3D12Planes {
    std::shared_ptr<jellyxr_d3d11::VulkanApi> api;
    VkDevice device = VK_NULL_HANDLE;
    std::array<jellyxr_d3d11::ComPtr<ID3D12Resource>, 2> textures;
    std::array<VkImage, 2> images{};
    std::array<VkDeviceMemory, 2> memories{};
    jellyxr_d3d11::ComPtr<ID3D12CommandAllocator> allocator;
    jellyxr_d3d11::ComPtr<ID3D12GraphicsCommandList> commands;
    jellyxr_d3d11::ComPtr<ID3D12Fence> fence;
    VkSemaphore semaphore = VK_NULL_HANDLE;
    HANDLE event = nullptr;
    uint64_t value = 0;
    unsigned width = 0, height = 0, sample_bytes = 0;
    ~D3D12Planes();
    bool wait_copy() const;
    bool matches(unsigned w, unsigned h, unsigned bytes) const;
    void initialize(std::shared_ptr<jellyxr_d3d11::VulkanApi> functions, VkPhysicalDevice physical, VkDevice logical,
                    ID3D12Device *d3d, unsigned w, unsigned h, unsigned bytes);

private:
    void import_plane(VkPhysicalDevice physical, ID3D12Device *d3d, unsigned plane);
    void create_fence(ID3D12Device *d3d);
};

struct D3D12Frame {
    std::shared_ptr<D3D12Planes> planes;
    std::shared_ptr<AVFrame> source;
    uint64_t fence_value = 0;
    bool submitted = false;
    ~D3D12Frame();
};

class D3D12Gpu {
public:
    bool initialize(VkInstance instance, VkPhysicalDevice physical, VkDevice device, uint32_t family);
    std::shared_ptr<D3D12Frame> prepare(AVFrame *frame);
    AVBufferRef *decoder_device() const { return hardware.get(); }
    bool available() const { return enabled; }
    std::string failure() const {
        std::lock_guard<std::mutex> lock(reason_mutex);
        return reason;
    }
    void disable(const std::string &message);
    uint64_t prepared() const { return prepared_count; }
    double preparation_ms() const {
        return prepared_count ? double(preparation_us.load()) / prepared_count.load() / 1000 : 0;
    }
    void record(VkCommandBuffer command, const D3D12Frame &frame, const std::array<VkImage, 2> &destinations);

private:
    void create_device();
    std::shared_ptr<D3D12Planes> acquire_planes(unsigned width, unsigned height, unsigned bytes);
    void extract(AVFrame *frame, D3D12Planes &planes);
    std::shared_ptr<jellyxr_d3d11::VulkanApi> api = std::make_shared<jellyxr_d3d11::VulkanApi>();
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    uint32_t family = 0;
    jellyxr_d3d11::ComPtr<ID3D12Device> d3d;
    jellyxr_d3d11::ComPtr<ID3D12CommandQueue> queue;
    std::shared_ptr<AVBufferRef> hardware;
    std::vector<std::shared_ptr<D3D12Planes>> pool;
    std::atomic<bool> enabled{false};
    std::atomic<uint64_t> prepared_count{0}, preparation_us{0};
    mutable std::mutex reason_mutex;
    std::string reason;
};
