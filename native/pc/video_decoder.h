#pragma once

#include "video_plane.h"

#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <array>
#include <atomic>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <memory>
#include <string>
#include <thread>

struct AVFormatContext;
struct AVCodecContext;
struct AVFrame;
struct AVPacket;
struct SwsContext;
class VaapiFrame;

struct VideoPlanes {
    int width = 0;
    int height = 0;
    int storage_width = 0;
    int storage_height = 0;
    int display_width = 0;
    int display_height = 0;
    int rotation = 0;
    int plane_count = 3;
    int sample_bytes = 2;
    bool interleaved = false;
    float sample_scale = 65535;
    float code_max = 1023;
    int64_t timestamp = 0;
    uint64_t generation = 0;
    float kr = 0.2126f;
    float kb = 0.0722f;
    float full_range = 0;
    float transfer = 0;
    float source_peak = 1000.f / 203.f;
    std::array<VideoPlane, 3> planes;
    std::shared_ptr<AVFrame> hardware_frame;
    std::shared_ptr<VaapiFrame> exported_frame;
};

class VideoDecoder {
public:
    ~VideoDecoder();
    int start(const std::string &url, const std::string &authorization, int64_t start_ms);
    void stop();
    void set_clock(int64_t milliseconds);
    void seek(int64_t milliseconds);
    bool take_frame(VideoPlanes &frame);
    int error() const { return decode_error; }
    bool has_audio() const { return audio; }
    int width() const { return source_width; }
    int height() const { return source_height; }
    int64_t duration_ms() const { return duration; }
    bool ended() const { return end_of_stream; }
    bool read_ahead_ready() const {
        return reader_ended || buffered_ms >= 1000 || buffered_bytes >= max_buffer_bytes || buffered_packets >= max_buffer_packets;
    }
    godot::Dictionary diagnostics() const;
    void set_frame_callback(void (*callback)(void *), void *owner) { frame_callback = callback; frame_owner = owner; }
    bool has_frame();
    void enable_vaapi_frames(bool enabled) { vaapi_frames = enabled; }
    void set_vaapi_device(const std::string &device) { vaapi_device = device; }
    bool download_frame(VideoPlanes &frame);
    uint64_t current_generation() const { return generation; }

private:
    static constexpr int64_t max_buffer_ms = 30000;
    static constexpr uint64_t max_buffer_bytes = 256 * 1048576;
    static constexpr size_t max_buffer_packets = 4096;
    static int interrupt(void *owner);
    void configure_hardware(const struct AVCodec *decoder);
    int open(const std::string &url, const std::string &authorization);
    int read_geometry();
    void decode_loop();
    void read_loop();
    bool read_packet(AVPacket *packet, uint64_t &packet_generation, bool &flush, int &error);
    void clear_packets();
    void update_buffer_size();
    bool publish(AVFrame *frame, uint64_t frame_generation);
    bool convert(AVFrame *frame, VideoPlanes &output);
    bool prepare_planes(AVFrame *frame, VideoPlanes &output, int storage_width, int storage_height, bool allocate = true);
    bool download_planes(AVFrame *frame, VideoPlanes &output, bool prepare = true);
    void close();
    AVFormatContext *input = nullptr;
    AVCodecContext *codec = nullptr;
    SwsContext *scaler = nullptr;
    int stream_index = -1;
    int hardware_format = -1;
    bool hardware_attempted = false;
    int source_width = 0;
    int source_height = 0;
    int rotation = 0;
    bool audio = false;
    std::string codec_name;
    std::string hardware_device;
    std::string vaapi_device;
    std::atomic<uint64_t> corrupt_packets{0};
    std::atomic<bool> hardware_active{false};
    std::atomic<bool> pinned_download{false};
    std::atomic<bool> vaapi_frames{false};
    std::atomic<int> active_transfer{0};
    std::atomic<uint64_t> decoded_frames{0}, dropped_frames{0}, converted_frames{0};
    std::atomic<uint64_t> download_us{0}, conversion_us{0};
    std::atomic<uint64_t> vaapi_export_us{0}, vaapi_export_frames{0};
    std::atomic<uint64_t> read_us{0}, decode_us{0}, read_bytes{0};
    std::atomic<int64_t> buffered_ms{0};
    std::atomic<uint64_t> buffered_bytes{0};
    std::atomic<size_t> buffered_packets{0};
    std::atomic<bool> reader_ended{false}, seek_interrupt{false};
    int64_t origin_us = 0;
    int64_t duration = 0;
    std::atomic<bool> end_of_stream{false};
    std::thread worker;
    std::thread reader;
    std::atomic<bool> stopping{false};
    std::atomic<int> decode_error{0};
    std::atomic<int64_t> io_deadline{0};
    std::mutex mutex;
    std::condition_variable wake;
    struct QueuedPacket {
        AVPacket *packet = nullptr;
        uint64_t generation = 0;
        bool flush = false;
        int error = 0;
    };
    std::deque<QueuedPacket> packets;
    VideoPlanes pending;
    VideoPlanes staging;
    bool frame_ready = false;
    bool awaiting_first_frame = true;
    int64_t clock = 0;
    int64_t seek_target = -1;
    int64_t discard_before = -1;
    int64_t last_publish_us = 0;
    std::atomic<int64_t> decoded_timestamp{0};
    std::atomic<uint64_t> generation{0};
    void (*frame_callback)(void *) = nullptr;
    void *frame_owner = nullptr;
};
