#include "shared_gl_context.h"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <GL/gl.h>
#include <cstdint>

struct SharedGlContext::Native {
    using CreatePbuffer = HANDLE (WINAPI *)(HDC, int, int, int, const int *);
    using GetPbufferDC = HDC (WINAPI *)(HANDLE);
    using ReleasePbufferDC = int (WINAPI *)(HANDLE, HDC);
    using DestroyPbuffer = BOOL (WINAPI *)(HANDLE);
    using CreateContext = HGLRC (WINAPI *)(HDC, HGLRC, const int *);
    HANDLE surface = nullptr;
    HDC display = nullptr;
    HGLRC context = nullptr;
    ReleasePbufferDC release_dc = nullptr;
    DestroyPbuffer destroy_surface = nullptr;

    void *resolve(const char *name) const {
        PROC address = wglGetProcAddress(name);
        intptr_t value = reinterpret_cast<intptr_t>(address);
        if (value == 0 || value == 1 || value == 2 || value == 3 || value == -1) {
            address = reinterpret_cast<PROC>(GetProcAddress(GetModuleHandleW(L"opengl32.dll"), name));
        }
        return reinterpret_cast<void *>(address);
    }

    bool create() {
        HDC parent_display = wglGetCurrentDC();
        HGLRC parent_context = wglGetCurrentContext();
        if (!parent_display || !parent_context) return false;
        auto create_surface = reinterpret_cast<CreatePbuffer>(resolve("wglCreatePbufferARB"));
        auto get_dc = reinterpret_cast<GetPbufferDC>(resolve("wglGetPbufferDCARB"));
        release_dc = reinterpret_cast<ReleasePbufferDC>(resolve("wglReleasePbufferDCARB"));
        destroy_surface = reinterpret_cast<DestroyPbuffer>(resolve("wglDestroyPbufferARB"));
        auto create_context = reinterpret_cast<CreateContext>(resolve("wglCreateContextAttribsARB"));
        if (!create_surface || !get_dc || !release_dc || !destroy_surface || !create_context) return false;
        const int surface_attributes[] = {0};
        surface = create_surface(parent_display, GetPixelFormat(parent_display), 1, 1, surface_attributes);
        if (!surface) return false;
        display = get_dc(surface);
        if (!display) return false;
        constexpr int major_version = 0x2091;
        constexpr int minor_version = 0x2092;
        constexpr int profile_mask = 0x9126;
        constexpr int core_profile = 1;
        const int attributes[] = {major_version, 3, minor_version, 3, profile_mask, core_profile, 0};
        context = create_context(display, parent_context, attributes);
        return context != nullptr;
    }

    ~Native() {
        if (context) wglDeleteContext(context);
        if (display) release_dc(surface, display);
        if (surface) destroy_surface(surface);
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
bool SharedGlContext::activate() { return native && wglMakeCurrent(native->display, native->context); }
void SharedGlContext::release() { wglMakeCurrent(nullptr, nullptr); }
void SharedGlContext::destroy() { native.reset(); }
void *SharedGlContext::resolve(const char *name) const { return native ? native->resolve(name) : nullptr; }
