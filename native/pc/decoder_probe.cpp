#include "decoder_probe.h"
#ifdef _WIN32
#include <d3d11.h>
#include <wrl/client.h>
#else
#include <va/va.h>
#endif
extern "C" {
#include <libavutil/hwcontext.h>
#ifdef _WIN32
#include <libavutil/hwcontext_d3d11va.h>
#else
#include <libavutil/hwcontext_vaapi.h>
#endif
}
#include <chrono>

using godot::String;

#ifdef _WIN32
static const GUID *decode_profile(const String &codec, const String &profile, int depth) {
    if (codec == "h264" && depth == 8 && (profile == "high" || profile == "main" || profile == "baseline" || profile == "constrained baseline")) return &D3D11_DECODER_PROFILE_H264_VLD_NOFGT;
    if (codec == "hevc" && profile == "main" && depth == 8) return &D3D11_DECODER_PROFILE_HEVC_VLD_MAIN;
    if (codec == "hevc" && profile == "main 10" && depth == 10) return &D3D11_DECODER_PROFILE_HEVC_VLD_MAIN10;
    if (codec == "vp9" && profile == "profile 0" && depth == 8) return &D3D11_DECODER_PROFILE_VP9_VLD_PROFILE0;
    if (codec == "vp9" && profile == "profile 2" && depth == 10) return &D3D11_DECODER_PROFILE_VP9_VLD_10BIT_PROFILE2;
    return nullptr;
}

static bool supports_format(void *context, const String &codec, const String &profile,
                            int depth, int width, int height) {
    const GUID *guid = decode_profile(codec, profile, depth);
    if (!guid) return false;
    auto *windows = static_cast<AVD3D11VADeviceContext *>(context);
    Microsoft::WRL::ComPtr<ID3D11VideoDevice> video;
    if (FAILED(windows->device->QueryInterface(IID_PPV_ARGS(&video)))) return false;
    const auto format = depth == 10 ? DXGI_FORMAT_P010 : DXGI_FORMAT_NV12;
    BOOL supported = FALSE;
    if (FAILED(video->CheckVideoDecoderFormat(guid, format, &supported)) || !supported) return false;
    const D3D11_VIDEO_DECODER_DESC desc{*guid, UINT(width), UINT(height), format};
    UINT count = 0;
    return SUCCEEDED(video->GetVideoDecoderConfigCount(&desc, &count)) && count > 0;
}
#else
static VAProfile decode_profile(const String &codec, const String &profile, int depth) {
    if (codec == "h264" && depth == 8) {
        if (profile == "high") return VAProfileH264High;
        if (profile == "main") return VAProfileH264Main;
        if (profile == "constrained baseline") return VAProfileH264ConstrainedBaseline;
    }
    if (codec == "hevc" && profile == "main" && depth == 8) return VAProfileHEVCMain;
    if (codec == "hevc" && profile == "main 10" && depth == 10) return VAProfileHEVCMain10;
    if (codec == "vp9" && profile == "profile 0" && depth == 8) return VAProfileVP9Profile0;
    if (codec == "vp9" && profile == "profile 2" && depth == 10) return VAProfileVP9Profile2;
    if (codec == "av1" && profile == "main" && (depth == 8 || depth == 10)) return VAProfileAV1Profile0;
    return VAProfileNone;
}

static bool supports_format(void *context, const String &codec, const String &profile,
                            int depth, int width, int height) {
    const auto requested = decode_profile(codec, profile, depth);
    if (requested == VAProfileNone) return false;
    auto display = static_cast<AVVAAPIDeviceContext *>(context)->display;
    VAConfigAttrib attributes[] = {{VAConfigAttribRTFormat, 0},
        {VAConfigAttribMaxPictureWidth, 0}, {VAConfigAttribMaxPictureHeight, 0}};
    if (vaGetConfigAttributes(display, requested, VAEntrypointVLD, attributes, 3) != VA_STATUS_SUCCESS)
        return false;
    for (const auto &attribute : attributes)
        if (attribute.value == VA_ATTRIB_NOT_SUPPORTED) return false;
    const unsigned int format = depth == 10 ? VA_RT_FORMAT_YUV420_10 : VA_RT_FORMAT_YUV420;
    return (attributes[0].value & format) && attributes[1].value >= unsigned(width) &&
        attributes[2].value >= unsigned(height);
}
#endif

static String describe_device(AVHWDeviceContext *context) {
    struct Format { const char *name; const char *codec; const char *profile; int depth; };
    const Format formats[] = {{"H.264 High", "h264", "high", 8}, {"HEVC Main", "hevc", "main", 8},
        {"HEVC Main 10", "hevc", "main 10", 10}, {"VP9 Profile 0", "vp9", "profile 0", 8},
        {"VP9 Profile 2", "vp9", "profile 2", 10}, {"AV1 Main", "av1", "main", 8}};
    String supported;
    for (const auto &format : formats) {
        if (!supports_format(context->hwctx, format.codec, format.profile, format.depth, 1920, 1080)) continue;
        if (!supported.is_empty()) supported += ", ";
        supported += format.name;
    }
    const String backend = av_hwdevice_get_type_name(context->type);
    return supported.is_empty() ? backend + " opened. Format support will be checked during playback."
        : backend + " reports support at 1920 x 1080 for " + supported + ".";
}

void DecoderProbe::start() {
    if (scan.valid() || result.device) return;
    scan = std::async(std::launch::async, [] {
        AVBufferRef *reference = nullptr;
#ifdef _WIN32
        const auto type = AV_HWDEVICE_TYPE_D3D11VA;
#else
        const auto type = AV_HWDEVICE_TYPE_VAAPI;
#endif
        if (av_hwdevice_ctx_create(&reference, type, nullptr, nullptr, 0) < 0)
            return ScanResult{nullptr, "No decoder device was found by the startup check. JellyXR checks the player during playback."};
        std::shared_ptr<AVBufferRef> device(reference, [](AVBufferRef *value) { av_buffer_unref(&value); });
        return ScanResult{device, describe_device(reinterpret_cast<AVHWDeviceContext *>(reference->data))};
    });
}

void DecoderProbe::update() {
    if (scan.valid() && scan.wait_for(std::chrono::seconds(0)) == std::future_status::ready) result = scan.get();
}

String DecoderProbe::summary() {
    update();
    return result.description;
}

int DecoderProbe::supports(const String &codec, const String &profile, int depth, int width, int height) {
    update();
    if (!result.device || width <= 0 || height <= 0) return 0;
    auto *context = reinterpret_cast<AVHWDeviceContext *>(result.device->data);
    // This device has no frame-rate query and the player may select a different device.
    // Its answer is advisory. Only playback can confirm hardware decoding.
    return supports_format(context->hwctx, codec, profile.to_lower(), depth, width, height) ? 1 : 0;
}
