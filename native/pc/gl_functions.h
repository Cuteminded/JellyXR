#pragma once

#include "shared_gl_context.h"

namespace gl {
constexpr unsigned texture_2d = 0x0DE1, rgba = 0x1908, rgba8 = 0x8058, unsigned_byte = 0x1401;
constexpr unsigned framebuffer = 0x8D40, read_framebuffer = 0x8CA8, draw_framebuffer = 0x8CA9;
constexpr unsigned read_binding = 0x8CAA, draw_binding = 0x8CA6, color_attachment = 0x8CE0;
constexpr unsigned framebuffer_complete = 0x8CD5, color_buffer = 0x4000, nearest = 0x2600;
constexpr unsigned scissor_test = 0x0C11, texture_min_filter = 0x2801, texture_mag_filter = 0x2800;
constexpr unsigned sync_complete = 0x9117, already_signaled = 0x911A, condition_satisfied = 0x911C, wait_failed = 0x911D;
}

struct GlFunctions {
    void (JELLYFRAME_GL_CALL *gen_textures)(int, unsigned *) = nullptr;
    void (JELLYFRAME_GL_CALL *delete_textures)(int, const unsigned *) = nullptr;
    void (JELLYFRAME_GL_CALL *bind_texture)(unsigned, unsigned) = nullptr;
    void (JELLYFRAME_GL_CALL *texture_parameter)(unsigned, unsigned, int) = nullptr;
    void (JELLYFRAME_GL_CALL *texture_image)(unsigned, int, int, int, int, int, unsigned, unsigned, const void *) = nullptr;
    void (JELLYFRAME_GL_CALL *gen_framebuffers)(int, unsigned *) = nullptr;
    void (JELLYFRAME_GL_CALL *delete_framebuffers)(int, const unsigned *) = nullptr;
    void (JELLYFRAME_GL_CALL *bind_framebuffer)(unsigned, unsigned) = nullptr;
    void (JELLYFRAME_GL_CALL *attach_texture)(unsigned, unsigned, unsigned, unsigned, int) = nullptr;
    unsigned (JELLYFRAME_GL_CALL *check_framebuffer)(unsigned) = nullptr;
    void (JELLYFRAME_GL_CALL *blit)(int, int, int, int, int, int, int, int, unsigned, unsigned) = nullptr;
    void *(JELLYFRAME_GL_CALL *fence)(unsigned, unsigned) = nullptr;
    unsigned (JELLYFRAME_GL_CALL *poll_fence)(void *, unsigned, unsigned long long) = nullptr;
    void (JELLYFRAME_GL_CALL *delete_fence)(void *) = nullptr;
    void (JELLYFRAME_GL_CALL *flush)() = nullptr;
    void (JELLYFRAME_GL_CALL *get_integer)(unsigned, int *) = nullptr;
    unsigned char (JELLYFRAME_GL_CALL *is_enabled)(unsigned) = nullptr;
    void (JELLYFRAME_GL_CALL *enable)(unsigned) = nullptr;
    void (JELLYFRAME_GL_CALL *disable)(unsigned) = nullptr;

    bool load(const SharedGlContext &context);
};

class GlFramebufferState {
public:
    explicit GlFramebufferState(const GlFunctions &functions);
    ~GlFramebufferState();
private:
    const GlFunctions &api;
    int read = 0;
    int draw = 0;
    bool scissor = false;
};
