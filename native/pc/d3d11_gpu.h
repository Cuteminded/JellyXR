#pragma once
#include "d3d11_vulkan.h"
#include <atomic>
#include <mutex>
#include <vector>
struct AVBufferRef;
struct AVFrame;

struct D3D11Frame {
    std::shared_ptr<jellyxr_d3d11::SharedPlanes> planes;
    std::shared_ptr<AVFrame> source;
    bool ready = false, submitted = false;
    ~D3D11Frame();
};

class D3D11Gpu {
public:
    bool initialize(VkInstance instance, VkPhysicalDevice physical, VkDevice device, uint32_t family);
    std::shared_ptr<D3D11Frame> prepare(AVFrame *frame);
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
    void record(VkCommandBuffer command, const D3D11Frame &frame, const std::array<VkImage, 2> &destinations);

private:
    void create_device();
    void create_shaders();
    void create_source(ID3D11Texture2D *texture);
    std::shared_ptr<jellyxr_d3d11::SharedPlanes> acquire_planes(unsigned width, unsigned height, unsigned bytes);
    void extract(AVFrame *frame, jellyxr_d3d11::SharedPlanes &planes);
    std::shared_ptr<jellyxr_d3d11::VulkanApi> api = std::make_shared<jellyxr_d3d11::VulkanApi>();
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    uint32_t family = 0;
    jellyxr_d3d11::ComPtr<ID3D11Device> d3d;
    jellyxr_d3d11::ComPtr<ID3D11DeviceContext> immediate;
    jellyxr_d3d11::ComPtr<ID3D11Texture2D> intermediate;
    std::array<jellyxr_d3d11::ComPtr<ID3D11ShaderResourceView>, 2> source_views;
    jellyxr_d3d11::ComPtr<ID3D11VertexShader> vertex;
    jellyxr_d3d11::ComPtr<ID3D11PixelShader> pixel;
    jellyxr_d3d11::ComPtr<ID3D11RasterizerState> rasterizer;
    std::shared_ptr<AVBufferRef> hardware;
    std::vector<std::shared_ptr<jellyxr_d3d11::SharedPlanes>> pool;
    std::atomic<bool> enabled{false};
    std::atomic<uint64_t> prepared_count{0}, preparation_us{0};
    mutable std::mutex reason_mutex;
    std::string reason;
};
