#pragma once

#include <cstdint>
#include <string_view>
#include <vector>

struct AVCodec;

struct V4L2FrameSize {
    uint32_t min_width, max_width;
    uint32_t min_height, max_height;
};

struct V4L2DecodeFormat {
    const char *codec;
    const char *label;
    const AVCodec *decoder;
    std::vector<V4L2FrameSize> sizes;
    std::vector<int> profiles;

    bool supports_size(int width, int height) const;
    bool supports_profile(int profile, int bit_depth) const;
};

std::vector<V4L2DecodeFormat> scan_v4l2_decoders();
int v4l2_profile(std::string_view codec, std::string_view profile);
