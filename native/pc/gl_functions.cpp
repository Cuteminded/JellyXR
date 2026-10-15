#include "gl_functions.h"

bool GlFunctions::load(const SharedGlContext &context) {
#define LOAD_GL(member, name) member = reinterpret_cast<decltype(member)>(context.resolve(name)); if (!member) return false
    LOAD_GL(gen_textures, "glGenTextures");
    LOAD_GL(delete_textures, "glDeleteTextures");
    LOAD_GL(bind_texture, "glBindTexture");
    LOAD_GL(texture_parameter, "glTexParameteri");
    LOAD_GL(texture_image, "glTexImage2D");
    LOAD_GL(gen_framebuffers, "glGenFramebuffers");
    LOAD_GL(delete_framebuffers, "glDeleteFramebuffers");
    LOAD_GL(bind_framebuffer, "glBindFramebuffer");
    LOAD_GL(attach_texture, "glFramebufferTexture2D");
    LOAD_GL(check_framebuffer, "glCheckFramebufferStatus");
    LOAD_GL(blit, "glBlitFramebuffer");
    LOAD_GL(fence, "glFenceSync");
    LOAD_GL(poll_fence, "glClientWaitSync");
    LOAD_GL(delete_fence, "glDeleteSync");
    LOAD_GL(flush, "glFlush");
    LOAD_GL(get_integer, "glGetIntegerv");
    LOAD_GL(is_enabled, "glIsEnabled");
    LOAD_GL(enable, "glEnable");
    LOAD_GL(disable, "glDisable");
#undef LOAD_GL
    return true;
}

GlFramebufferState::GlFramebufferState(const GlFunctions &functions) : api(functions) {
    api.get_integer(gl::read_binding, &read);
    api.get_integer(gl::draw_binding, &draw);
    scissor = api.is_enabled(gl::scissor_test);
    api.disable(gl::scissor_test);
}

GlFramebufferState::~GlFramebufferState() {
    api.bind_framebuffer(gl::read_framebuffer, unsigned(read));
    api.bind_framebuffer(gl::draw_framebuffer, unsigned(draw));
    if (scissor) api.enable(gl::scissor_test);
}
