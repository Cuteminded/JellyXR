#include "video_decoder.h"
#include <godot_cpp/variant/variant.hpp>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/hwcontext.h>
#include <libavutil/time.h>
#include <libavutil/pixfmt.h>
#include <libswscale/swscale.h>
}
#include <algorithm>
#include <cstring>

bool VideoDecoder::publish(AVFrame *frame, uint64_t frame_generation) {
    VideoPlanes &output = staging;
    {
        std::lock_guard<std::mutex> lock(mutex);
        if (generation != frame_generation) { ++dropped_frames; return true; }
    }
    int64_t timestamp = frame->best_effort_timestamp;
    output.timestamp = timestamp == AV_NOPTS_VALUE ? 0 :
        (av_rescale_q(timestamp, input->streams[stream_index]->time_base, AV_TIME_BASE_Q) - origin_us) / 1000;
    decoded_timestamp = output.timestamp;
    {
        std::lock_guard<std::mutex> lock(mutex);
        if (output.timestamp < discard_before ||
                (output.timestamp < clock - 100 && av_gettime_relative() - last_publish_us < 100000)) {
            ++dropped_frames;
            return true;
        }
        discard_before = -1;
    }
    int64_t started = av_gettime_relative();
    hardware_active = frame->hw_frames_ctx != nullptr;
    bool converted;
    if (frame->hw_frames_ctx) {
        converted = download_planes(frame, output);
        download_us += av_gettime_relative() - started;
    } else {
        pinned_download = false;
        converted = convert(frame, output);
        conversion_us += av_gettime_relative() - started;
    }
    ++converted_frames;
    if (!converted) { decode_error = AVERROR_INVALIDDATA; return false; }
    output.generation = frame_generation;
    std::unique_lock<std::mutex> lock(mutex);
    wake.wait(lock, [this, &output, frame_generation] {
        return stopping || generation != frame_generation ||
            (!frame_ready && (awaiting_first_frame || output.timestamp <= clock + 30));
    });
    if (stopping) return false;
    if (generation != frame_generation) { ++dropped_frames; return true; }
    std::swap(pending, output);
    frame_ready = true;
    last_publish_us = av_gettime_relative();
    lock.unlock();
    if (frame_callback) frame_callback(frame_owner);
    return true;
}

godot::Dictionary VideoDecoder::diagnostics() const {
    godot::Dictionary values;
    values["codec"] = godot::String(codec_name.c_str());
    values["hardware_device"] = hardware_active ? godot::String(hardware_device.c_str()) : godot::String("none");
    values["hardware_decoding"] = hardware_active.load();
    values["pinned_download"] = pinned_download.load();
    values["transfer"] = active_transfer.load() == 1 ? "pq" : active_transfer.load() == 2 ? "hlg" : "sdr";
    values["decoded_frames"] = int64_t(decoded_frames.load());
    values["dropped_frames"] = int64_t(dropped_frames.load());
    values["corrupt_packets"] = int64_t(corrupt_packets.load());
    values["decode_error"] = decode_error.load();
    values["decoded_timestamp_ms"] = decoded_timestamp.load();
    values["read_ahead_ms"] = buffered_ms.load();
    values["read_ahead_mb"] = double(buffered_bytes.load()) / 1048576.0;
    values["read_mb"] = double(read_bytes.load()) / 1048576.0;
    values["read_seconds"] = double(read_us.load()) / 1000000.0;
    values["decode_ms"] = decoded_frames ? double(decode_us.load()) / decoded_frames.load() / 1000.0 : 0;
    uint64_t count = converted_frames.load();
    values["download_ms"] = count ? double(download_us.load()) / count / 1000.0 : 0;
    values["conversion_ms"] = count ? double(conversion_us.load()) / count / 1000.0 : 0;
    return values;
}
