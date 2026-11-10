#pragma once

#include <future>
#include <memory>
#include <godot_cpp/variant/string.hpp>
#ifdef __linux__
#include "v4l2_decoder.h"
#endif

struct AVBufferRef;

class DecoderProbe {
public:
    void start();
    int supports(const godot::String &codec, const godot::String &profile,
                 int depth, int width, int height);
    godot::String summary();

private:
    struct ScanResult {
        std::shared_ptr<AVBufferRef> device;
        godot::String description;
#ifdef __linux__
        std::vector<V4L2DecodeFormat> v4l2_formats;
#endif
    };
    void update();
    std::future<ScanResult> scan;
    ScanResult result{nullptr, "Checking hardware decoders..."};
};
