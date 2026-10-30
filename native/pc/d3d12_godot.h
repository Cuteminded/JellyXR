#pragma once
#include "d3d12_gpu.h"
#include "video_decoder.h"
#include <godot_cpp/classes/rendering_device.hpp>

class D3D12Godot {
public:
    bool initialize(godot::RenderingDevice *device);
    bool copy(const VideoPlanes &frame, const std::array<godot::RID, 3> &targets);
    std::shared_ptr<D3D12Gpu> decoder_bridge() const { return gpu; }
    bool available() const { return gpu->available(); }
    std::string failure() const { return gpu->failure(); }
    uint64_t copies() const { return copied; }
    uint64_t outstanding() const { return inflight->load(); }
    uint64_t prepared() const { return gpu->prepared(); }
    double preparation_ms() const { return gpu->preparation_ms(); }

private:
    struct Job;
    static void record(uint64_t command, void *userdata);
    static void release(void *userdata);
    godot::RenderingDevice *rd = nullptr;
    std::shared_ptr<D3D12Gpu> gpu = std::make_shared<D3D12Gpu>();
    std::shared_ptr<std::atomic<uint64_t>> inflight = std::make_shared<std::atomic<uint64_t>>(0);
    std::atomic<uint64_t> copied{0};
};
