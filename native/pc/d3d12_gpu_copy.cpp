#include "d3d12_gpu.h"
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext_d3d12va.h>
}
#include <stdexcept>
using namespace jellyxr_d3d11;

void D3D12Gpu::extract(AVFrame *frame, D3D12Planes &planes) {
    if (!planes.wait_copy())
        throw std::runtime_error("D3D12 transfer did not finish before surface reuse");
    auto *source = reinterpret_cast<AVD3D12VAFrame *>(frame->data[0]);
    auto description = source->texture->GetDesc();
    check_hr(planes.allocator->Reset(), "reset D3D12 video allocator");
    check_hr(planes.commands->Reset(planes.allocator.Get(), nullptr), "reset D3D12 video commands");
    for (unsigned i = 0; i < 2; ++i) {
        D3D12_RESOURCE_BARRIER barrier{};
        barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        barrier.Transition.pResource = planes.textures[i].Get();
        barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
        barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_DEST;
        planes.commands->ResourceBarrier(1, &barrier);
        D3D12_TEXTURE_COPY_LOCATION from{}, to{};
        from.pResource = source->texture;
        from.Type = to.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        from.SubresourceIndex = source->subresource_index * description.MipLevels +
                                i * description.MipLevels * description.DepthOrArraySize;
        to.pResource = planes.textures[i].Get();
        planes.commands->CopyTextureRegion(&to, 0, 0, 0, &from, nullptr);
        std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
        planes.commands->ResourceBarrier(1, &barrier);
    }
    check_hr(planes.commands->Close(), "close D3D12 video commands");
    check_hr(queue->Wait(source->sync_ctx.fence, source->sync_ctx.fence_value), "wait for D3D12 decode");
    ID3D12CommandList *commands[] = {planes.commands.Get()};
    queue->ExecuteCommandLists(1, commands);
    check_hr(queue->Signal(planes.fence.Get(), ++planes.value), "signal D3D12 video transfer");
}

void D3D12Gpu::record(VkCommandBuffer command, const D3D12Frame &frame, const std::array<VkImage, 2> &destinations) {
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
