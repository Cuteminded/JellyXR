#include "video_decoder.h"
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/hwcontext.h>
#include <libavutil/mastering_display_metadata.h>
#include <libswscale/swscale.h>
}
#include <algorithm>
#include <cstring>

static bool native_format(int format) {
    return format == AV_PIX_FMT_NV12 || format == AV_PIX_FMT_P010LE || format == AV_PIX_FMT_YUV420P ||
        format == AV_PIX_FMT_YUVJ420P || format == AV_PIX_FMT_YUV420P10LE;
}

static bool supported_size(int width, int height) {
    return width > 0 && height > 0 && width <= 8192 && height <= 8192 && int64_t(width) * height <= 33554432;
}

bool VideoDecoder::prepare_planes(AVFrame *frame, VideoPlanes &output, int storage_width, int storage_height) {
    output.width = frame->width;
    output.height = frame->height;
    output.storage_width = storage_width;
    output.storage_height = storage_height;
    output.rotation = rotation;
    AVRational aspect = av_guess_sample_aspect_ratio(input, input->streams[stream_index], frame);
    output.display_width = aspect.num > 0 && aspect.den > 0 ? int(av_rescale(frame->width, aspect.num, aspect.den)) : frame->width;
    output.display_height = frame->height;
    if (rotation % 2) std::swap(output.display_width, output.display_height);
    if (!supported_size(output.width, output.height) || !supported_size(storage_width, storage_height) ||
            !supported_size(output.display_width, output.display_height)) return false;
    output.interleaved = frame->format == AV_PIX_FMT_NV12 || frame->format == AV_PIX_FMT_P010LE;
    output.sample_bytes = frame->format == AV_PIX_FMT_NV12 || frame->format == AV_PIX_FMT_YUV420P || frame->format == AV_PIX_FMT_YUVJ420P ? 1 : 2;
    output.plane_count = output.interleaved ? 2 : 3;
    output.sample_scale = output.sample_bytes == 1 ? 1020.f : frame->format == AV_PIX_FMT_P010LE ? 65535.f / 64.f : 65535.f;
    output.code_max = output.sample_bytes == 1 ? 1020.f : 1023.f;
    for (int index = 0; index < 3; ++index) {
        int width = index ? (storage_width + 1) / 2 : storage_width;
        int height = index ? (storage_height + 1) / 2 : storage_height;
        int64_t bytes = int64_t(width) * height * output.sample_bytes * (index && output.interleaved ? 2 : 1);
        if (output.planes[index].resize(index < output.plane_count ? bytes : 0) != 0) return false;
    }
    auto range = frame->color_range != AVCOL_RANGE_UNSPECIFIED ? frame->color_range : codec->color_range;
    auto colorspace = frame->colorspace != AVCOL_SPC_UNSPECIFIED ? frame->colorspace : codec->colorspace;
    auto transfer = frame->color_trc != AVCOL_TRC_UNSPECIFIED ? frame->color_trc : codec->color_trc;
    output.full_range = range == AVCOL_RANGE_JPEG ? 1.f : 0.f;
    output.kr = .2126f;
    output.kb = .0722f;
    if (colorspace == AVCOL_SPC_BT2020_NCL) { output.kr = .2627f; output.kb = .0593f; }
    else if (colorspace == AVCOL_SPC_BT470BG || colorspace == AVCOL_SPC_SMPTE170M ||
            (colorspace == AVCOL_SPC_UNSPECIFIED && frame->height < 720)) { output.kr = .299f; output.kb = .114f; }
    output.transfer = transfer == AVCOL_TRC_SMPTE2084 ? 1.f : transfer == AVCOL_TRC_ARIB_STD_B67 ? 2.f : 0.f;
    active_transfer = int(output.transfer);
    float peak_nits = 1000;
    auto *mastering = av_frame_get_side_data(frame, AV_FRAME_DATA_MASTERING_DISPLAY_METADATA);
    if (mastering && mastering->size >= sizeof(AVMasteringDisplayMetadata)) {
        auto *metadata = reinterpret_cast<AVMasteringDisplayMetadata *>(mastering->data);
        if (metadata->has_luminance) peak_nits = float(av_q2d(metadata->max_luminance));
    }
    auto *light = av_frame_get_side_data(frame, AV_FRAME_DATA_CONTENT_LIGHT_LEVEL);
    if (light && light->size >= sizeof(AVContentLightMetadata)) {
        auto *metadata = reinterpret_cast<AVContentLightMetadata *>(light->data);
        if (metadata->MaxCLL) peak_nits = float(metadata->MaxCLL);
    }
    output.source_peak = std::clamp(peak_nits, 203.f, 10000.f) / 203.f;
    return true;
}

// VideoPlane owns the allocation until the transfer completes.
static void retain_plane_storage(void *, uint8_t *) {}

bool VideoDecoder::download_planes(AVFrame *frame, VideoPlanes &output) {
    auto *context = reinterpret_cast<AVHWFramesContext *>(frame->hw_frames_ctx->data);
    if (!native_format(context->sw_format)) return false;
    AVFrame description = *frame;
    description.format = context->sw_format;
    if (!prepare_planes(&description, output, context->width, context->height)) return false;
    AVFrame *target = av_frame_alloc();
    if (!target) return false;
    target->format = context->sw_format;
    target->width = context->width;
    target->height = context->height;
    bool ready = true;
    bool pinned = context->format == AV_PIX_FMT_CUDA;
    for (int index = 0; index < output.plane_count; ++index) {
        if (context->format == AV_PIX_FMT_CUDA) pinned = output.planes[index].pin(context->device_ref) && pinned;
        int width = index ? (context->width + 1) / 2 : context->width;
        target->data[index] = output.planes[index].ptrw();
        target->linesize[index] = width * output.sample_bytes * (index && output.interleaved ? 2 : 1);
        target->buf[index] = av_buffer_create(target->data[index], output.planes[index].size(), retain_plane_storage, nullptr, 0);
        ready = ready && target->buf[index];
    }
    pinned_download = pinned;
    int result = ready ? av_hwframe_transfer_data(target, frame, 0) : AVERROR(ENOMEM);
    av_frame_free(&target);
    return result >= 0;
}

bool VideoDecoder::convert(AVFrame *frame, VideoPlanes &output) {
    bool native = native_format(frame->format);
    AVFrame description = *frame;
    if (!native) description.format = AV_PIX_FMT_YUV420P10LE;
    if (!prepare_planes(&description, output, frame->width, frame->height)) return false;
    uint8_t *data[4] = {};
    int strides[4] = {};
    for (int index = 0; index < output.plane_count; ++index) {
        int width = index ? (frame->width + 1) / 2 : frame->width;
        int height = index ? (frame->height + 1) / 2 : frame->height;
        strides[index] = width * output.sample_bytes * (index && output.interleaved ? 2 : 1);
        data[index] = output.planes[index].ptrw();
        if (native) {
            for (int row = 0; row < height; ++row) {
                std::memcpy(data[index] + row * strides[index], frame->data[index] + row * frame->linesize[index], strides[index]);
            }
        }
    }
    if (native) return true;
    scaler = sws_getCachedContext(scaler, frame->width, frame->height, AVPixelFormat(frame->format),
        frame->width, frame->height, AV_PIX_FMT_YUV420P10LE, SWS_POINT, nullptr, nullptr, nullptr);
    if (!scaler) return false;
    int range = int(output.full_range);
    const int *coefficients = sws_getCoefficients(SWS_CS_DEFAULT);
    if (sws_setColorspaceDetails(scaler, coefficients, range, coefficients, range, 0, 1 << 16, 1 << 16) < 0) return false;
    return sws_scale(scaler, frame->data, frame->linesize, 0, frame->height, data, strides) == frame->height;
}
