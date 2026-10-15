#include "shared_gl_context.h"
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/glx.h>
#include <GL/glxext.h>
#include <dlfcn.h>
#include <cstring>

struct SharedGlContext::Native {
    void *library = nullptr;
    void *x11 = nullptr;
    bool egl = false;
    EGLDisplay egl_display = EGL_NO_DISPLAY;
    EGLContext egl_context = EGL_NO_CONTEXT;
    EGLSurface egl_surface = EGL_NO_SURFACE;
    Display *glx_display = nullptr;
    GLXContext glx_context = nullptr;
    GLXPbuffer glx_surface = 0;
    decltype(&eglGetProcAddress) egl_proc = nullptr;
    decltype(&eglMakeCurrent) egl_make_current = nullptr;
    decltype(&eglDestroyContext) egl_destroy_context = nullptr;
    decltype(&eglDestroySurface) egl_destroy_surface = nullptr;
    decltype(&glXGetProcAddressARB) glx_proc = nullptr;
    decltype(&glXMakeContextCurrent) glx_make_current = nullptr;
    decltype(&glXDestroyContext) glx_destroy_context = nullptr;
    decltype(&glXDestroyPbuffer) glx_destroy_surface = nullptr;

    template<class T> T symbol(const char *name) const { return reinterpret_cast<T>(dlsym(library, name)); }

    void *resolve(const char *name) const {
        void *address = nullptr;
        if (egl_proc) address = reinterpret_cast<void *>(egl_proc(name));
        if (glx_proc) address = reinterpret_cast<void *>(glx_proc(reinterpret_cast<const GLubyte *>(name)));
        return address ? address : dlsym(library, name);
    }

    bool create_egl(EGLContext parent) {
        auto get_display = symbol<decltype(&eglGetCurrentDisplay)>("eglGetCurrentDisplay");
        auto query = symbol<decltype(&eglQueryContext)>("eglQueryContext");
        auto choose = symbol<decltype(&eglChooseConfig)>("eglChooseConfig");
        auto create_context = symbol<decltype(&eglCreateContext)>("eglCreateContext");
        auto create_surface = symbol<decltype(&eglCreatePbufferSurface)>("eglCreatePbufferSurface");
        auto query_string = symbol<decltype(&eglQueryString)>("eglQueryString");
        egl_proc = symbol<decltype(egl_proc)>("eglGetProcAddress");
        egl_make_current = symbol<decltype(egl_make_current)>("eglMakeCurrent");
        egl_destroy_context = symbol<decltype(egl_destroy_context)>("eglDestroyContext");
        egl_destroy_surface = symbol<decltype(egl_destroy_surface)>("eglDestroySurface");
        if (!get_display || !query || !choose || !create_context || !create_surface || !query_string ||
                !egl_proc || !egl_make_current || !egl_destroy_context || !egl_destroy_surface) return false;
        egl = true;
        egl_display = get_display();
        EGLint config_id = 0;
        EGLint api = 0;
        if (!query(egl_display, parent, EGL_CONFIG_ID, &config_id) ||
                !query(egl_display, parent, EGL_CONTEXT_CLIENT_TYPE, &api) || api != EGL_OPENGL_API) return false;
        const EGLint config_attributes[] = {EGL_CONFIG_ID, config_id, EGL_SURFACE_TYPE, 0,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_NONE};
        EGLConfig config = nullptr;
        EGLint count = 0;
        if (!choose(egl_display, config_attributes, &config, 1, &count) || count != 1) return false;
        const EGLint attributes[] = {EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 3,
            EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT, EGL_NONE};
        egl_context = create_context(egl_display, config, parent, attributes);
        if (egl_context == EGL_NO_CONTEXT) return false;
        const EGLint surface_attributes[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
        egl_surface = create_surface(egl_display, config, surface_attributes);
        const char *extensions = query_string(egl_display, EGL_EXTENSIONS);
        return egl_surface != EGL_NO_SURFACE || (extensions && std::strstr(extensions, "EGL_KHR_surfaceless_context"));
    }

    bool create_glx() {
        library = dlopen("libGL.so.1", RTLD_NOW | RTLD_LOCAL);
        if (!library) return false;
        auto get_context = symbol<decltype(&glXGetCurrentContext)>("glXGetCurrentContext");
        auto get_display = symbol<decltype(&glXGetCurrentDisplay)>("glXGetCurrentDisplay");
        auto query = symbol<decltype(&glXQueryContext)>("glXQueryContext");
        auto choose = symbol<decltype(&glXChooseFBConfig)>("glXChooseFBConfig");
        auto config_attribute = symbol<decltype(&glXGetFBConfigAttrib)>("glXGetFBConfigAttrib");
        auto create_surface = symbol<decltype(&glXCreatePbuffer)>("glXCreatePbuffer");
        glx_proc = symbol<decltype(glx_proc)>("glXGetProcAddressARB");
        glx_make_current = symbol<decltype(glx_make_current)>("glXMakeContextCurrent");
        glx_destroy_context = symbol<decltype(glx_destroy_context)>("glXDestroyContext");
        glx_destroy_surface = symbol<decltype(glx_destroy_surface)>("glXDestroyPbuffer");
        if (!get_context || !get_display || !query || !choose || !config_attribute || !create_surface ||
                !glx_proc || !glx_make_current || !glx_destroy_context || !glx_destroy_surface) return false;
        GLXContext parent = get_context();
        if (!parent) return false;
        glx_display = get_display();
        int config_id = 0;
        int screen = 0;
        if (query(glx_display, parent, GLX_FBCONFIG_ID, &config_id) || query(glx_display, parent, GLX_SCREEN, &screen)) return false;
        x11 = dlopen("libX11.so.6", RTLD_NOW | RTLD_LOCAL);
        auto free_configs = x11 ? reinterpret_cast<int (*)(void *)>(dlsym(x11, "XFree")) : nullptr;
        if (!free_configs) return false;
        const int config_attributes[] = {GLX_FBCONFIG_ID, config_id, None};
        int count = 0;
        GLXFBConfig *configs = choose(glx_display, screen, config_attributes, &count);
        if (!configs || count < 1) { if (configs) free_configs(configs); return false; }
        int drawable_types = 0;
        config_attribute(glx_display, configs[0], GLX_DRAWABLE_TYPE, &drawable_types);
        auto create_context = reinterpret_cast<PFNGLXCREATECONTEXTATTRIBSARBPROC>(resolve("glXCreateContextAttribsARB"));
        if (create_context && (drawable_types & GLX_PBUFFER_BIT)) {
            const int attributes[] = {GLX_CONTEXT_MAJOR_VERSION_ARB, 3, GLX_CONTEXT_MINOR_VERSION_ARB, 3,
                GLX_CONTEXT_PROFILE_MASK_ARB, GLX_CONTEXT_CORE_PROFILE_BIT_ARB, None};
            glx_context = create_context(glx_display, configs[0], parent, True, attributes);
            const int surface_attributes[] = {GLX_PBUFFER_WIDTH, 1, GLX_PBUFFER_HEIGHT, 1, None};
            if (glx_context) glx_surface = create_surface(glx_display, configs[0], surface_attributes);
        }
        free_configs(configs);
        return glx_context && glx_surface;
    }

    bool create() {
        library = dlopen("libEGL.so.1", RTLD_NOW | RTLD_LOCAL);
        if (library) {
            auto current = symbol<decltype(&eglGetCurrentContext)>("eglGetCurrentContext");
            EGLContext parent = current ? current() : EGL_NO_CONTEXT;
            if (parent != EGL_NO_CONTEXT) return create_egl(parent);
            dlclose(library);
            library = nullptr;
        }
        return create_glx();
    }

    bool activate() {
        if (egl) {
            auto bind_api = symbol<decltype(&eglBindAPI)>("eglBindAPI");
            return bind_api && bind_api(EGL_OPENGL_API) && egl_make_current(egl_display, egl_surface, egl_surface, egl_context);
        }
        return glx_make_current(glx_display, glx_surface, glx_surface, glx_context);
    }

    void release() {
        if (egl) egl_make_current(egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        else glx_make_current(glx_display, None, None, nullptr);
    }

    ~Native() {
        if (egl_context != EGL_NO_CONTEXT) egl_destroy_context(egl_display, egl_context);
        if (egl_surface != EGL_NO_SURFACE) egl_destroy_surface(egl_display, egl_surface);
        if (glx_context) glx_destroy_context(glx_display, glx_context);
        if (glx_surface) glx_destroy_surface(glx_display, glx_surface);
        if (x11) dlclose(x11);
        if (library) dlclose(library);
    }
};

SharedGlContext::SharedGlContext() = default;
SharedGlContext::~SharedGlContext() = default;
bool SharedGlContext::create() {
    native = std::make_unique<Native>();
    if (native->create()) return true;
    destroy();
    return false;
}
bool SharedGlContext::activate() { return native && native->activate(); }
void SharedGlContext::release() { native->release(); }
void SharedGlContext::destroy() { native.reset(); }
void *SharedGlContext::resolve(const char *name) const { return native ? native->resolve(name) : nullptr; }
