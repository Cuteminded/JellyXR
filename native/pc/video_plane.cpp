#include "video_plane.h"
extern "C" {
#include <libavutil/buffer.h>
#include <libavutil/hwcontext.h>
}
#include <cstring>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define CUDA_CALL __stdcall
#else
#include <dlfcn.h>
#define CUDA_CALL
#endif

struct CudaApi {
    int (CUDA_CALL *push)(void *) = nullptr;
    int (CUDA_CALL *pop)(void **) = nullptr;
    int (CUDA_CALL *host_register)(void *, size_t, unsigned) = nullptr;
    int (CUDA_CALL *host_unregister)(void *) = nullptr;

    CudaApi() {
#ifdef _WIN32
        HMODULE library = LoadLibraryExW(L"nvcuda.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
        auto symbol = [library](const char *name) -> void * { return library ? reinterpret_cast<void *>(GetProcAddress(library, name)) : nullptr; };
#else
        void *library = dlopen("libcuda.so.1", RTLD_NOW | RTLD_LOCAL);
        auto symbol = [library](const char *name) -> void * { return library ? dlsym(library, name) : nullptr; };
#endif
        push = reinterpret_cast<decltype(push)>(symbol("cuCtxPushCurrent_v2"));
        pop = reinterpret_cast<decltype(pop)>(symbol("cuCtxPopCurrent_v2"));
        host_register = reinterpret_cast<decltype(host_register)>(symbol("cuMemHostRegister_v2"));
        host_unregister = reinterpret_cast<decltype(host_unregister)>(symbol("cuMemHostUnregister"));
    }
};

static const CudaApi &cuda_api() {
    static const CudaApi api;
    return api;
}


class CudaHostPin {
public:
    CudaHostPin(AVBufferRef *owner, void *address, size_t size) : address(address) {
        auto *device = reinterpret_cast<AVHWDeviceContext *>(owner->data);
        if (device->type != AV_HWDEVICE_TYPE_CUDA) return;
        const auto &api = cuda_api();
        if (!api.push || !api.pop || !api.host_register || !api.host_unregister) return;
        // CUcontext is the first member of FFmpeg's public AVCUDADeviceContext.
        std::memcpy(&context, device->hwctx, sizeof(context));
        reference = av_buffer_ref(owner);
        if (!reference || api.push(context) != 0) return;
        registered = api.host_register(address, size, 1) == 0;
        void *previous = nullptr;
        api.pop(&previous);
    }

    ~CudaHostPin() {
        const auto &api = cuda_api();
        if (registered && api.push(context) == 0) {
            api.host_unregister(address);
            void *previous = nullptr;
            api.pop(&previous);
        }
        av_buffer_unref(&reference);
    }

    bool valid() const { return registered; }
    void *get_address() const { return address; }
private:
    AVBufferRef *reference = nullptr;
    void *context = nullptr;
    void *address = nullptr;
    bool registered = false;
};

VideoPlane::VideoPlane() = default;
VideoPlane::~VideoPlane() = default;
VideoPlane::VideoPlane(VideoPlane &&other) noexcept = default;

VideoPlane &VideoPlane::operator=(VideoPlane &&other) noexcept {
    if (this == &other) return *this;
    registration.reset();
    bytes = std::move(other.bytes);
    registration = std::move(other.registration);
    return *this;
}

godot::Error VideoPlane::resize(int64_t size) {
    if (bytes.size() == size) return godot::OK;
    registration.reset();
    return godot::Error(bytes.resize(size));
}

bool VideoPlane::pin(AVBufferRef *device) {
    uint8_t *address = ptrw();
    if (registration) return registration->valid();
    registration = std::make_unique<CudaHostPin>(device, address, bytes.size());
    return registration->valid();
}

uint8_t *VideoPlane::ptrw() {
    uint8_t *address = bytes.ptrw();
    if (registration && registration->get_address() != address) registration.reset();
    return address;
}
