#pragma once

#include <memory>

#ifdef _WIN32
#define JELLYFRAME_GL_CALL __stdcall
#else
#define JELLYFRAME_GL_CALL
#endif

class SharedGlContext {
public:
    SharedGlContext();
    ~SharedGlContext();
    bool create();
    bool activate();
    void release();
    void destroy();
    void *resolve(const char *name) const;

private:
    struct Native;
    std::unique_ptr<Native> native;
};
