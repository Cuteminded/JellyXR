#include "d3d12_gpu.h"
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_d3d12va.h>
#include <libavutil/time.h>
}
#include <cstring>
#include <stdexcept>
using namespace jellyxr_d3d11;

D3D12Frame::~D3D12Frame() {
    if (!submitted && planes)
        planes->wait_copy();
}

bool D3D12Gpu::initialize(VkInstance instance, VkPhysicalDevice p_physical, VkDevice p_device, uint32_t p_family) {
    try {
        physical = p_physical;
        device = p_device;
        family = p_family;
        api->initialize(instance, device);
        create_device();
        enabled = true;
        return true;
    } catch (const std::exception &error) {
        disable(error.what());
        return false;
    }
}

void D3D12Gpu::disable(const std::string &message) {
    enabled = false;
    std::lock_guard<std::mutex> lock(reason_mutex);
    reason = message;
}

void D3D12Gpu::create_device() {
    VkPhysicalDeviceIDProperties id{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES};
    VkPhysicalDeviceProperties2 properties{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2};
    properties.pNext = &id;
    api->properties(physical, &properties);
    if (!id.deviceLUIDValid)
        throw std::runtime_error("Vulkan GPU has no Windows adapter LUID");
    ComPtr<IDXGIFactory1> factory;
    check_hr(CreateDXGIFactory1(IID_PPV_ARGS(&factory)), "create DXGI factory");
    ComPtr<IDXGIAdapter1> adapter;
    for (UINT i = 0; factory->EnumAdapters1(i, &adapter) == S_OK; ++i) {
        DXGI_ADAPTER_DESC1 description{};
        check_hr(adapter->GetDesc1(&description), "read DXGI adapter");
        if (std::memcmp(&description.AdapterLuid, id.deviceLUID, VK_LUID_SIZE) == 0)
            break;
        adapter.Reset();
    }
    if (!adapter)
        throw std::runtime_error("Cannot match D3D12 and Vulkan adapters");
    check_hr(D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_12_0, IID_PPV_ARGS(&d3d)), "create D3D12 video device");
    D3D12_COMMAND_QUEUE_DESC description{};
    description.Type = D3D12_COMMAND_LIST_TYPE_COPY;
    check_hr(d3d->CreateCommandQueue(&description, IID_PPV_ARGS(&queue)), "create D3D12 transfer queue");
    AVBufferRef *reference = av_hwdevice_ctx_alloc(AV_HWDEVICE_TYPE_D3D12VA);
    if (!reference)
        throw std::bad_alloc();
    hardware = std::shared_ptr<AVBufferRef>(reference, [](AVBufferRef *value) { av_buffer_unref(&value); });
    auto *context = reinterpret_cast<AVHWDeviceContext *>(reference->data);
    auto *windows = static_cast<AVD3D12VADeviceContext *>(context->hwctx);
    windows->device = d3d.Get();
    windows->device->AddRef();
    windows->resource_flags = D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS;
    if (av_hwdevice_ctx_init(reference) < 0)
        throw std::runtime_error("Cannot initialize D3D12VA decoder device");
}

std::shared_ptr<D3D12Planes> D3D12Gpu::acquire_planes(unsigned width, unsigned height, unsigned bytes) {
    for (auto &slot : pool)
        if (slot.use_count() == 1 && slot->matches(width, height, bytes))
            return slot;
    for (auto entry = pool.begin(); entry != pool.end();) {
        if (entry->use_count() == 1 && !(*entry)->matches(width, height, bytes))
            entry = pool.erase(entry);
        else
            ++entry;
    }
    if (pool.size() >= 8)
        throw std::runtime_error("D3D12 shared frame limit reached");
    auto slot = std::make_shared<D3D12Planes>();
    slot->initialize(api, physical, device, d3d.Get(), width, height, bytes);
    pool.push_back(slot);
    return slot;
}

std::shared_ptr<D3D12Frame> D3D12Gpu::prepare(AVFrame *frame) {
    if (!enabled || frame->format != AV_PIX_FMT_D3D12)
        return {};
    int64_t started = av_gettime_relative();
    try {
        auto *source = reinterpret_cast<AVD3D12VAFrame *>(frame->data[0]);
        auto description = source->texture->GetDesc();
        if (description.Format != DXGI_FORMAT_NV12 && description.Format != DXGI_FORMAT_P010)
            throw std::runtime_error("D3D12 GPU frames require NV12 or P010");
        if (!(description.Flags & D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS))
            throw std::runtime_error("D3D12 decoder surface does not permit asynchronous sharing");
        auto result = std::make_shared<D3D12Frame>();
        result->source = std::shared_ptr<AVFrame>(av_frame_clone(frame), [](AVFrame *value) { av_frame_free(&value); });
        if (!result->source)
            throw std::bad_alloc();
        result->planes = acquire_planes(unsigned(description.Width), description.Height,
                                        description.Format == DXGI_FORMAT_P010 ? 2 : 1);
        extract(frame, *result->planes);
        result->fence_value = result->planes->value;
        preparation_us += av_gettime_relative() - started;
        ++prepared_count;
        return result;
    } catch (const std::exception &error) {
        disable(error.what());
        return {};
    }
}
