#include "vaapi_frame.h"
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_drm.h>
}

VaapiFrame::~VaapiFrame() { reset(); }

void VaapiFrame::reset() {
    av_frame_free(&mapped);
    av_frame_free(&retained);
}

int VaapiFrame::export_from(const AVFrame *source) {
    reset();
    if (!source || source->format != AV_PIX_FMT_VAAPI || !source->hw_frames_ctx) return AVERROR(EINVAL);
    retained = av_frame_clone(source);
    mapped = av_frame_alloc();
    if (!retained || !mapped) {
        reset();
        return AVERROR(ENOMEM);
    }
    mapped->format = AV_PIX_FMT_DRM_PRIME;
    int result = av_hwframe_map(mapped, retained, AV_HWFRAME_MAP_READ | AV_HWFRAME_MAP_DIRECT);
    if (result < 0) reset();
    return result;
}

const AVDRMFrameDescriptor *VaapiFrame::descriptor() const {
    return mapped ? reinterpret_cast<const AVDRMFrameDescriptor *>(mapped->data[0]) : nullptr;
}
