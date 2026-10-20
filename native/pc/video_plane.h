#pragma once

#include <godot_cpp/variant/packed_byte_array.hpp>
#include <memory>

struct AVBufferRef;
class CudaHostPin;

class VideoPlane {
public:
    VideoPlane();
    ~VideoPlane();
    VideoPlane(VideoPlane &&other) noexcept;
    VideoPlane &operator=(VideoPlane &&other) noexcept;
    godot::Error resize(int64_t size);
    int64_t size() const { return bytes.size(); }
    uint8_t *ptrw();
    const godot::PackedByteArray &data() const { return bytes; }
    bool pin(AVBufferRef *device);
private:
    godot::PackedByteArray bytes;
    std::unique_ptr<CudaHostPin> registration;
};
