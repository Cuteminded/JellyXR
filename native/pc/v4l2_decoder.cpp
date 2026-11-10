#include "v4l2_decoder.h"
#include <algorithm>
#include <cerrno>
#include <dirent.h>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <string>
#include <sys/ioctl.h>
#include <unistd.h>
extern "C" {
#include <libavcodec/avcodec.h>
}

namespace {
struct CodecFormat {
    uint32_t fourcc;
    const char *codec, *label, *decoder;
};

constexpr CodecFormat codecs[] = {
    {V4L2_PIX_FMT_H264, "h264", "H.264", "h264_v4l2m2m"},
    {V4L2_PIX_FMT_HEVC, "hevc", "HEVC", "hevc_v4l2m2m"},
    {V4L2_PIX_FMT_VP8, "vp8", "VP8", "vp8_v4l2m2m"},
    {V4L2_PIX_FMT_VP9, "vp9", "VP9", "vp9_v4l2m2m"},
    {V4L2_PIX_FMT_MPEG2, "mpeg2video", "MPEG-2", "mpeg2_v4l2m2m"},
    {V4L2_PIX_FMT_MPEG4, "mpeg4", "MPEG-4", "mpeg4_v4l2m2m"},
};

int query(int fd, unsigned long request, void *value) {
    int result;
    do { result = ioctl(fd, request, value); } while (result < 0 && errno == EINTR);
    return result;
}

std::vector<V4L2FrameSize> frame_sizes(int fd, uint32_t fourcc) {
    std::vector<V4L2FrameSize> sizes;
    v4l2_frmsizeenum size{};
    size.pixel_format = fourcc;
    for (; query(fd, VIDIOC_ENUM_FRAMESIZES, &size) == 0; ++size.index) {
        if (size.type == V4L2_FRMSIZE_TYPE_DISCRETE) {
            const auto &s = size.discrete;
            sizes.push_back({s.width, s.width, s.height, s.height});
        } else if (size.type == V4L2_FRMSIZE_TYPE_CONTINUOUS || size.type == V4L2_FRMSIZE_TYPE_STEPWISE) {
            const auto &s = size.stepwise;
            sizes.push_back({s.min_width, s.max_width, s.min_height, s.max_height});
        }
    }
    return sizes;
}

std::vector<int> profiles(int fd, uint32_t fourcc) {
    struct Profile { uint32_t control, index; int ffmpeg; };
    const Profile h264[] = {
        {V4L2_CID_MPEG_VIDEO_H264_PROFILE, V4L2_MPEG_VIDEO_H264_PROFILE_BASELINE, AV_PROFILE_H264_BASELINE},
        {V4L2_CID_MPEG_VIDEO_H264_PROFILE, V4L2_MPEG_VIDEO_H264_PROFILE_CONSTRAINED_BASELINE, AV_PROFILE_H264_CONSTRAINED_BASELINE},
        {V4L2_CID_MPEG_VIDEO_H264_PROFILE, V4L2_MPEG_VIDEO_H264_PROFILE_MAIN, AV_PROFILE_H264_MAIN},
        {V4L2_CID_MPEG_VIDEO_H264_PROFILE, V4L2_MPEG_VIDEO_H264_PROFILE_HIGH, AV_PROFILE_H264_HIGH}
    };
    const Profile hevc[] = {{V4L2_CID_MPEG_VIDEO_HEVC_PROFILE, V4L2_MPEG_VIDEO_HEVC_PROFILE_MAIN, AV_PROFILE_HEVC_MAIN}};
    const Profile vp9[] = {{V4L2_CID_MPEG_VIDEO_VP9_PROFILE, V4L2_MPEG_VIDEO_VP9_PROFILE_0, AV_PROFILE_VP9_0}};
    std::vector<int> result;
    const auto read = [fd, &result](const auto &candidates) {
        for (const auto &profile : candidates) {
            v4l2_querymenu menu{};
            menu.id = profile.control;
            menu.index = profile.index;
            if (query(fd, VIDIOC_QUERYMENU, &menu) == 0) result.push_back(profile.ffmpeg);
        }
    };
    if (fourcc == V4L2_PIX_FMT_H264) read(h264);
    if (fourcc == V4L2_PIX_FMT_HEVC) read(hevc);
    if (fourcc == V4L2_PIX_FMT_VP9) read(vp9);
    return result;
}

bool has_linear_output(int fd, v4l2_buf_type output, uint32_t fourcc) {
    const bool multiplanar = output == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
    v4l2_format input{};
    input.type = output;
    if (multiplanar) {
        input.fmt.pix_mp.pixelformat = fourcc;
        input.fmt.pix_mp.width = 1920;
        input.fmt.pix_mp.height = 1080;
    } else {
        input.fmt.pix.pixelformat = fourcc;
        input.fmt.pix.width = 1920;
        input.fmt.pix.height = 1080;
    }
    if (query(fd, VIDIOC_S_FMT, &input) < 0) return false;
    if ((multiplanar ? input.fmt.pix_mp.pixelformat : input.fmt.pix.pixelformat) != fourcc) return false;
    v4l2_fmtdesc capture{};
    capture.type = multiplanar ? V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE : V4L2_BUF_TYPE_VIDEO_CAPTURE;
    for (; query(fd, VIDIOC_ENUM_FMT, &capture) == 0; ++capture.index) {
        if (capture.pixelformat == V4L2_PIX_FMT_NV12 || capture.pixelformat == V4L2_PIX_FMT_NV12M ||
            capture.pixelformat == V4L2_PIX_FMT_YUV420 || capture.pixelformat == V4L2_PIX_FMT_YUV420M)
            return true;
    }
    return false;
}

void scan_device(int fd, std::vector<V4L2DecodeFormat> &formats) {
    v4l2_capability caps{};
    if (query(fd, VIDIOC_QUERYCAP, &caps) < 0) return;
    const uint32_t flags = caps.capabilities & V4L2_CAP_DEVICE_CAPS ? caps.device_caps : caps.capabilities;
    if (!(flags & V4L2_CAP_STREAMING) || !(flags & (V4L2_CAP_VIDEO_M2M | V4L2_CAP_VIDEO_M2M_MPLANE))) return;
    v4l2_fmtdesc format{};
    const auto output = flags & V4L2_CAP_VIDEO_M2M_MPLANE ? V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE : V4L2_BUF_TYPE_VIDEO_OUTPUT;
    format.type = output;
    for (; query(fd, VIDIOC_ENUM_FMT, &format) == 0; ++format.index) {
        for (const auto &codec : codecs) {
            if (codec.fourcc != format.pixelformat) continue;
            const AVCodec *decoder = avcodec_find_decoder_by_name(codec.decoder);
            if (decoder && has_linear_output(fd, output, codec.fourcc))
                formats.push_back({codec.codec, codec.label, decoder, frame_sizes(fd, codec.fourcc), profiles(fd, codec.fourcc)});
        }
    }
}
}

bool V4L2DecodeFormat::supports_size(int width, int height) const {
    if (width <= 0 || height <= 0) return false;
    const auto w = uint32_t(width), h = uint32_t(height);
    for (const auto &size : sizes) {
        // Container metadata can omit the padding a decoder adds to align coded frames.
        if (w >= size.min_width && w <= size.max_width && h >= size.min_height && h <= size.max_height)
            return true;
    }
    return false;
}

std::vector<V4L2DecodeFormat> scan_v4l2_decoders() {
    std::vector<V4L2DecodeFormat> formats;
    DIR *devices = opendir("/dev");
    if (!devices) return formats;
    while (auto *entry = readdir(devices)) {
        const std::string_view name(entry->d_name);
        if (name.size() <= 5 || name.substr(0, 5) != "video" || name.find_first_not_of("0123456789", 5) != name.npos)
            continue;
        const std::string path = "/dev/" + std::string(name);
        const int fd = open(path.c_str(), O_RDWR | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) continue;
        scan_device(fd, formats);
        close(fd);
    }
    closedir(devices);
    return formats;
}

bool V4L2DecodeFormat::supports_profile(int profile, int bit_depth) const {
    if (bit_depth > 8) return false;
    if (!profiles.empty()) return std::find(profiles.begin(), profiles.end(), profile) != profiles.end();
    const std::string_view name(codec);
    if (name == "h264") return profile == AV_PROFILE_H264_BASELINE ||
        profile == AV_PROFILE_H264_CONSTRAINED_BASELINE || profile == AV_PROFILE_H264_MAIN ||
        profile == AV_PROFILE_H264_HIGH;
    if (name == "hevc") return profile == AV_PROFILE_HEVC_MAIN;
    if (name == "vp9") return profile == AV_PROFILE_VP9_0;
    return true;
}

int v4l2_profile(std::string_view codec, std::string_view profile) {
    if (codec == "h264") {
        if (profile == "baseline") return AV_PROFILE_H264_BASELINE;
        if (profile == "constrained baseline") return AV_PROFILE_H264_CONSTRAINED_BASELINE;
        if (profile == "main") return AV_PROFILE_H264_MAIN;
        if (profile == "high") return AV_PROFILE_H264_HIGH;
    }
    if (codec == "hevc" && profile == "main") return AV_PROFILE_HEVC_MAIN;
    if (codec == "vp9" && profile == "profile 0") return AV_PROFILE_VP9_0;
    return AV_PROFILE_UNKNOWN;
}
