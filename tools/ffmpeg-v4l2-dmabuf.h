/* Included by FFmpeg's v4l2_buffers.c after its internal declarations. */
#include <stdlib.h>
#include <string.h>
#include <libavutil/common.h>
#include <libavutil/mem.h>
#include "jellyxr_v4l2_dmabuf_data.h"

static void jellyxr_free_capture(void *opaque, uint8_t *data)
{
    JellyXRV4L2DmaBuf *capture = (void *)data;
    AVDRMFrameDescriptor *desc = &capture->descriptor;
    (void)opaque;
    for (int i = 0; i < desc->nb_objects; i++)
        close(desc->objects[i].fd);
    av_free(capture);
}

static void jellyxr_export_capture(AVFrame *frame, V4L2Buffer *buffer)
{
    const char *copy = getenv("JELLYXR_V4L2_GPU_COPY");
    if ((copy && !strcmp(copy, "0")) || logger(buffer)->codec_id != AV_CODEC_ID_H264 ||
        frame->opaque_ref || buffer->context->jellyxr_capture_export_failed)
        return;
    const struct v4l2_format *fmt = &buffer->context->format;
    const int multi = V4L2_TYPE_IS_MULTIPLANAR(fmt->type);
    const uint32_t fourcc = multi ? fmt->fmt.pix_mp.pixelformat : fmt->fmt.pix.pixelformat;
    const unsigned width = multi ? fmt->fmt.pix_mp.width : fmt->fmt.pix.width;
    const unsigned height = multi ? fmt->fmt.pix_mp.height : fmt->fmt.pix.height;

    JellyXRV4L2DmaBuf *capture = av_mallocz(sizeof(*capture));
    if (!capture)
        return;
    capture->signature = JELLYXR_V4L2_DMABUF_SIGNATURE;
    capture->width = width;
    capture->height = height;
    AVDRMFrameDescriptor *desc = &capture->descriptor;
    for (int i = 0; i < buffer->num_planes && i < AV_DRM_MAX_PLANES; i++) {
        struct v4l2_exportbuffer request = {
            .type = buffer->buf.type, .index = buffer->buf.index, .plane = i, .flags = O_CLOEXEC,
        };
        if (ioctl(buf_to_m2mctx(buffer)->fd, VIDIOC_EXPBUF, &request) < 0) {
            av_log(logger(buffer), AV_LOG_WARNING,
                   "JellyXR V4L2 DMA-BUF export failed on plane %d: %s\n", i, strerror(errno));
            goto fail;
        }
        desc->objects[i].fd = request.fd;
        desc->objects[i].size = buffer->plane_info[i].length;
        desc->nb_objects++;
    }
    if ((fourcc != V4L2_PIX_FMT_NV12 && fourcc != V4L2_PIX_FMT_NV12M) ||
        frame->format != AV_PIX_FMT_NV12 || desc->nb_objects != (fourcc == V4L2_PIX_FMT_NV12M ? 2 : 1)) {
        av_log(logger(buffer), AV_LOG_WARNING, "JellyXR V4L2 DMA-BUF GPU copy requires linear NV12/NV12M\n");
        goto fail;
    }
    desc->nb_layers = 2;
    for (int i = 0; i < 2; i++) {
        int object = desc->nb_objects == 2 ? i : 0;
        uintptr_t address = (uintptr_t)frame->data[i];
        uintptr_t base = (uintptr_t)buffer->plane_info[object].mm_addr;
        if (address < base || address - base >= desc->objects[object].size || frame->linesize[i] <= 0) {
            av_log(logger(buffer), AV_LOG_WARNING, "JellyXR V4L2 DMA-BUF invalid plane layout\n");
            goto fail;
        }
        /* DRM_FORMAT_R8 and DRM_FORMAT_GR88 with DRM_FORMAT_MOD_LINEAR. */
        desc->layers[i].format = i ? MKTAG('G', 'R', '8', '8') : MKTAG('R', '8', ' ', ' ');
        desc->layers[i].nb_planes = 1;
        desc->layers[i].planes[0] = (AVDRMPlaneDescriptor){
            .object_index = object, .offset = address - base, .pitch = frame->linesize[i],
        };
    }
    frame->opaque_ref = av_buffer_create((uint8_t *)capture, sizeof(*capture), jellyxr_free_capture, NULL, 0);
    if (frame->opaque_ref)
        return;
fail:
    buffer->context->jellyxr_capture_export_failed = 1;
    jellyxr_free_capture(NULL, (uint8_t *)capture);
}
