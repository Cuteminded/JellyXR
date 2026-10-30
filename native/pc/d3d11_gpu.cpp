#include "d3d11_gpu.h"
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_d3d11va.h>
#include <libavutil/time.h>
}
#include <d3dcompiler.h>
#include <cstring>
#include <stdexcept>

using namespace jellyxr_d3d11;

D3D11Frame::~D3D11Frame() {
    if (!ready || submitted)
        return;
    for (auto &mutex : planes->mutexes) {
        if (mutex->AcquireSync(1, 5000) == S_OK)
            mutex->ReleaseSync(0);
    }
}

bool D3D11Gpu::initialize(VkInstance instance, VkPhysicalDevice p_physical, VkDevice p_device, uint32_t p_family) {
    try {
        physical = p_physical;
        device = p_device;
        family = p_family;
        api->initialize(instance, device);
        create_device();
        create_shaders();
        enabled = true;
        return true;
    } catch (const std::exception &error) {
        disable(error.what());
        return false;
    }
}

void D3D11Gpu::disable(const std::string &message) {
    enabled = false;
    std::lock_guard<std::mutex> lock(reason_mutex);
    reason = message;
}

void D3D11Gpu::create_device() {
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
        throw std::runtime_error("Cannot match D3D11 and Vulkan adapters");
    check_hr(D3D11CreateDevice(adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr, D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
                               nullptr, 0, D3D11_SDK_VERSION, &d3d, nullptr, &immediate),
             "create video decoder device");
    AVBufferRef *reference = av_hwdevice_ctx_alloc(AV_HWDEVICE_TYPE_D3D11VA);
    if (!reference)
        throw std::bad_alloc();
    hardware = std::shared_ptr<AVBufferRef>(reference, [](AVBufferRef *value) { av_buffer_unref(&value); });
    auto *context = reinterpret_cast<AVHWDeviceContext *>(reference->data);
    auto *windows = static_cast<AVD3D11VADeviceContext *>(context->hwctx);
    windows->device = d3d.Get();
    windows->device->AddRef();
    if (av_hwdevice_ctx_init(reference) < 0)
        throw std::runtime_error("Cannot initialize D3D11VA decoder device");
}

void D3D11Gpu::create_shaders() {
    const char *source = "float4 vs(uint id:SV_VertexID):SV_Position { return float4(id==2?3:-1,id==1?3:-1,0,1); }"
                         "Texture2D<float2> plane:register(t0);"
                         "float2 ps(float4 p:SV_Position):SV_Target { return plane.Load(int3(p.xy,0)); }";
    ComPtr<ID3DBlob> code, errors;
    check_hr(D3DCompile(source, std::strlen(source), nullptr, nullptr, nullptr, "vs", "vs_5_0",
                        D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &code, &errors),
             "compile video vertex shader");
    check_hr(d3d->CreateVertexShader(code->GetBufferPointer(), code->GetBufferSize(), nullptr, &vertex),
             "create video vertex shader");
    code.Reset();
    check_hr(D3DCompile(source, std::strlen(source), nullptr, nullptr, nullptr, "ps", "ps_5_0",
                        D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &code, &errors),
             "compile video plane shader");
    check_hr(d3d->CreatePixelShader(code->GetBufferPointer(), code->GetBufferSize(), nullptr, &pixel),
             "create video plane shader");
    D3D11_RASTERIZER_DESC description{};
    description.FillMode = D3D11_FILL_SOLID;
    description.CullMode = D3D11_CULL_NONE;
    description.DepthClipEnable = TRUE;
    check_hr(d3d->CreateRasterizerState(&description, &rasterizer), "create video rasterizer");
}

void D3D11Gpu::create_source(ID3D11Texture2D *texture) {
    D3D11_TEXTURE2D_DESC description{}, current{};
    texture->GetDesc(&description);
    if (intermediate)
        intermediate->GetDesc(&current);
    if (description.Width == current.Width && description.Height == current.Height &&
        description.Format == current.Format)
        return;
    intermediate.Reset();
    for (auto &view : source_views)
        view.Reset();
    description.ArraySize = description.MipLevels = 1;
    description.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    description.MiscFlags = description.CPUAccessFlags = 0;
    description.Usage = D3D11_USAGE_DEFAULT;
    check_hr(d3d->CreateTexture2D(&description, nullptr, &intermediate), "create readable decoder texture");
    for (unsigned i = 0; i < 2; ++i) {
        D3D11_SHADER_RESOURCE_VIEW_DESC view{};
        view.Format = description.Format == DXGI_FORMAT_P010 ? (i ? DXGI_FORMAT_R16G16_UNORM : DXGI_FORMAT_R16_UNORM)
                                                             : (i ? DXGI_FORMAT_R8G8_UNORM : DXGI_FORMAT_R8_UNORM);
        view.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
        view.Texture2D.MipLevels = 1;
        check_hr(d3d->CreateShaderResourceView(intermediate.Get(), &view, &source_views[i]),
                 "create decoder plane view");
    }
}

std::shared_ptr<SharedPlanes> D3D11Gpu::acquire_planes(unsigned width, unsigned height, unsigned bytes) {
    for (auto &slot : pool) {
        if (slot.use_count() == 1 && slot->matches(width, height, bytes))
            return slot;
    }
    for (auto entry = pool.begin(); entry != pool.end();) {
        if (entry->use_count() == 1 && !(*entry)->matches(width, height, bytes))
            entry = pool.erase(entry);
        else
            ++entry;
    }
    if (pool.size() >= 8)
        throw std::runtime_error("D3D11 shared frame limit reached");
    auto slot = std::make_shared<SharedPlanes>();
    slot->initialize(api, physical, device, d3d.Get(), width, height, bytes);
    pool.push_back(slot);
    return slot;
}

std::shared_ptr<D3D11Frame> D3D11Gpu::prepare(AVFrame *frame) {
    if (!enabled || frame->format != AV_PIX_FMT_D3D11)
        return {};
    int64_t started = av_gettime_relative();
    try {
        auto *source = reinterpret_cast<ID3D11Texture2D *>(frame->data[0]);
        D3D11_TEXTURE2D_DESC description{};
        source->GetDesc(&description);
        if (description.Format != DXGI_FORMAT_NV12 && description.Format != DXGI_FORMAT_P010)
            throw std::runtime_error("D3D11 GPU frames require NV12 or P010");
        auto result = std::make_shared<D3D11Frame>();
        result->source = std::shared_ptr<AVFrame>(av_frame_clone(frame), [](AVFrame *value) { av_frame_free(&value); });
        if (!result->source)
            throw std::bad_alloc();
        result->planes =
            acquire_planes(description.Width, description.Height, description.Format == DXGI_FORMAT_P010 ? 2 : 1);
        extract(frame, *result->planes);
        result->ready = true;
        preparation_us += av_gettime_relative() - started;
        ++prepared_count;
        return result;
    } catch (const std::exception &error) {
        disable(error.what());
        return {};
    }
}
