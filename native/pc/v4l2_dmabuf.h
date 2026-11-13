#pragma once
#ifdef __cplusplus
extern "C" {
#endif
#include <libavutil/hwcontext_drm.h>
#ifdef __cplusplus
}
#endif

typedef struct JellyXRV4L2DmaBuf {
    uint64_t signature;
    AVDRMFrameDescriptor descriptor;
    int width, height;
} JellyXRV4L2DmaBuf;

#define JELLYXR_V4L2_DMABUF_SIGNATURE UINT64_C(0x4A585256344C3201)
