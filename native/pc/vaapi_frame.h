#pragma once

struct AVFrame;
struct AVDRMFrameDescriptor;

class VaapiFrame {
public:
    VaapiFrame() = default;
    ~VaapiFrame();
    VaapiFrame(const VaapiFrame &) = delete;
    VaapiFrame &operator=(const VaapiFrame &) = delete;
    int export_from(const AVFrame *source);
    void reset();
    const AVDRMFrameDescriptor *descriptor() const;

private:
    AVFrame *mapped = nullptr;
    AVFrame *retained = nullptr;
};
