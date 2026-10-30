#include "d3d11_gpu.h"
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_d3d11va.h>
}
#include <stdexcept>
using namespace jellyxr_d3d11;

void D3D11Gpu::extract(AVFrame *frame, SharedPlanes &planes) {
    auto *device_context = reinterpret_cast<AVHWDeviceContext *>(hardware->data);
    auto *windows = static_cast<AVD3D11VADeviceContext *>(device_context->hwctx);
    struct DeviceLock {
        AVD3D11VADeviceContext *device;
        explicit DeviceLock(AVD3D11VADeviceContext *value) : device(value) { device->lock(device->lock_ctx); }
        ~DeviceLock() { device->unlock(device->lock_ctx); }
    } lock(windows);
    auto *texture = reinterpret_cast<ID3D11Texture2D *>(frame->data[0]);
    create_source(texture);
    for (auto &mutex : planes.mutexes)
        check_hr(mutex->AcquireSync(0, 5000), "acquire shared video plane");
    D3D11_TEXTURE2D_DESC description{};
    texture->GetDesc(&description);
    immediate->CopySubresourceRegion(
        intermediate.Get(), 0, 0, 0, 0, texture,
        D3D11CalcSubresource(0, UINT(reinterpret_cast<uintptr_t>(frame->data[1])), description.MipLevels), nullptr);
    immediate->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    immediate->VSSetShader(vertex.Get(), nullptr, 0);
    immediate->PSSetShader(pixel.Get(), nullptr, 0);
    immediate->RSSetState(rasterizer.Get());
    for (unsigned i = 0; i < 2; ++i) {
        D3D11_VIEWPORT viewport{
            0, 0, float(i ? planes.width / 2 : planes.width), float(i ? planes.height / 2 : planes.height), 0, 1};
        auto *target = planes.targets[i].Get();
        auto *source = source_views[i].Get();
        immediate->RSSetViewports(1, &viewport);
        immediate->OMSetRenderTargets(1, &target, nullptr);
        immediate->PSSetShaderResources(0, 1, &source);
        immediate->Draw(3, 0);
    }
    immediate->ClearState();
    for (auto &mutex : planes.mutexes)
        check_hr(mutex->ReleaseSync(1), "release shared plane to Vulkan");
    immediate->Flush();
}

void D3D11Gpu::record(VkCommandBuffer command, const D3D11Frame &frame, const std::array<VkImage, 2> &destinations) {
    auto &planes = *frame.planes;
    for (unsigned i = 0; i < 2; ++i) {
        VkImageMemoryBarrier acquire{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
        acquire.oldLayout = acquire.newLayout = VK_IMAGE_LAYOUT_GENERAL;
        acquire.srcQueueFamilyIndex = VK_QUEUE_FAMILY_EXTERNAL;
        acquire.dstQueueFamilyIndex = family;
        acquire.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        acquire.image = planes.images[i];
        acquire.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        api->barrier(command, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0,
                     nullptr, 1, &acquire);
        VkImageCopy copy{};
        copy.srcSubresource = copy.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        copy.extent = {i ? planes.width / 2 : planes.width, i ? planes.height / 2 : planes.height, 1};
        api->copy(command, planes.images[i], VK_IMAGE_LAYOUT_GENERAL, destinations[i],
                  VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);
        std::swap(acquire.srcQueueFamilyIndex, acquire.dstQueueFamilyIndex);
        acquire.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        acquire.dstAccessMask = 0;
        api->barrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, nullptr, 0,
                     nullptr, 1, &acquire);
    }
}
