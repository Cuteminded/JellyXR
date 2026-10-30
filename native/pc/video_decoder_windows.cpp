#include "video_decoder.h"
#include "d3d11_gpu.h"
#include "d3d12_gpu.h"
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixdesc.h>
}

bool VideoDecoder::configure_windows_hardware(const AVCodec *decoder) {
    struct Candidate {
        AVHWDeviceType type;
        AVBufferRef *device;
        int version;
    };
    Candidate candidates[] = {
        {AV_HWDEVICE_TYPE_D3D12VA, d3d12 && d3d12->available() ? d3d12->decoder_device() : nullptr, 12},
        {AV_HWDEVICE_TYPE_D3D11VA, d3d11 && d3d11->available() ? d3d11->decoder_device() : nullptr, 11}};
    for (const auto &candidate : candidates) {
        if (!candidate.device)
            continue;
        for (int index = 0; const AVCodecHWConfig *config = avcodec_get_hw_config(decoder, index); ++index) {
            if (config->device_type != candidate.type || !(config->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX))
                continue;
            codec->hw_device_ctx = av_buffer_ref(candidate.device);
            if (!codec->hw_device_ctx)
                break;
            hardware_device = candidate.version == 12 ? "d3d12va" : "d3d11va";
            windows_device_type = candidate.version;
            hardware_format = config->pix_fmt;
            codec->opaque = this;
            codec->get_format = [](AVCodecContext *context, const AVPixelFormat *formats) {
                auto *self = static_cast<VideoDecoder *>(context->opaque);
                for (auto *format = formats; *format != AV_PIX_FMT_NONE; ++format)
                    if (*format == self->hardware_format)
                        return *format;
                if (self->hardware_format == AV_PIX_FMT_D3D12 && self->d3d11 && self->d3d11->available()) {
                    for (auto *format = formats; *format != AV_PIX_FMT_NONE; ++format) {
                        if (*format != AV_PIX_FMT_D3D11)
                            continue;
                        AVBufferRef *fallback = av_buffer_ref(self->d3d11->decoder_device());
                        if (!fallback)
                            break;
                        av_buffer_unref(&context->hw_device_ctx);
                        context->hw_device_ctx = fallback;
                        self->hardware_format = AV_PIX_FMT_D3D11;
                        self->windows_device_type = 11;
                        self->d3d12->disable("D3D12 format negotiation failed; using D3D11");
                        return *format;
                    }
                }
                if (self->hardware_format == AV_PIX_FMT_D3D12)
                    self->d3d12->disable("D3D12 format negotiation failed; using software decoding");
                for (auto *format = formats; *format != AV_PIX_FMT_NONE; ++format) {
                    const auto *description = av_pix_fmt_desc_get(*format);
                    if (description && !(description->flags & AV_PIX_FMT_FLAG_HWACCEL))
                        return *format;
                }
                return AV_PIX_FMT_NONE;
            };
            return true;
        }
        if (candidate.version == 12)
            d3d12->disable("Codec has no D3D12VA hardware configuration");
    }
    return false;
}
