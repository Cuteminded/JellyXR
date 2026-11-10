#pragma once

#include <future>
#include <memory>
#include <godot_cpp/variant/string.hpp>

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
    };
    void update();
    std::future<ScanResult> scan;
    ScanResult result{nullptr, "Checking hardware decoders..."};
};
