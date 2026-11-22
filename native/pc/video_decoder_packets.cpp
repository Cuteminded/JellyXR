#include "video_decoder.h"
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/time.h>
}
#include <algorithm>

static int64_t packet_decode_timestamp(const AVPacket *packet) {
    if (!packet) return AV_NOPTS_VALUE;
    return packet->dts == AV_NOPTS_VALUE ? packet->pts : packet->dts;
}

void VideoDecoder::clear_packets() {
    for (auto &entry : packets) av_packet_free(&entry.packet);
    packets.clear();
    next_packet = 0;
    history_bytes = 0;
    buffered_seek_pending = false;
    buffered_bytes = buffered_ms = 0;
    buffered_packets = 0;
}

void VideoDecoder::trim_packet_history() {
    if (!next_packet) return;
    const int64_t end = packet_decode_timestamp(packets[next_packet - 1].packet);
    size_t trim_count = 0;
    if (end != AV_NOPTS_VALUE) {
        const int64_t cutoff = end - av_rescale_q(back_buffer_ms, AVRational{1, 1000}, stream_time_base);
        for (size_t index = 0; index < next_packet; ++index) {
            const auto *packet = packets[index].packet;
            const int64_t timestamp = packet_decode_timestamp(packet);
            if (timestamp == AV_NOPTS_VALUE) continue;
            if (timestamp > cutoff) break;
            if (packet->flags & AV_PKT_FLAG_KEY) trim_count = index;
        }
    }
    while (next_packet && (trim_count || history_bytes > max_history_bytes || next_packet > max_buffer_packets)) {
        auto &entry = packets.front();
        if (entry.packet) history_bytes -= entry.packet->size;
        av_packet_free(&entry.packet);
        packets.pop_front();
        --next_packet;
        if (trim_count) --trim_count;
    }
}

bool VideoDecoder::seek_buffered(int64_t milliseconds) {
    if (packets.empty()) return false;
    const int64_t target = av_rescale_q(origin_us + milliseconds * 1000, AV_TIME_BASE_Q, stream_time_base);
    size_t keyframe = packets.size();
    bool reaches_target = false;
    for (size_t index = 0; index < packets.size(); ++index) {
        const auto *packet = packets[index].packet;
        if (!packet) continue;
        const int64_t timestamp = packet->pts == AV_NOPTS_VALUE ? packet->dts : packet->pts;
        if (timestamp == AV_NOPTS_VALUE) continue;
        if (timestamp >= target) reaches_target = true;
        if (timestamp <= target && (packet->flags & AV_PKT_FLAG_KEY)) keyframe = index;
    }
    if (!reaches_target || keyframe == packets.size()) return false;

    next_packet = keyframe;
    history_bytes = 0;
    uint64_t ahead_bytes = 0;
    for (size_t index = 0; index < packets.size(); ++index) {
        const auto *packet = packets[index].packet;
        if (!packet) continue;
        if (index < next_packet) history_bytes += packet->size;
        else ahead_bytes += packet->size;
    }
    buffered_bytes = ahead_bytes;
    buffered_seek_pending = true;
    trim_packet_history();
    update_buffer_size();
    ++buffered_seeks;
    return true;
}

void VideoDecoder::update_buffer_size() {
    buffered_packets = packets.size() - next_packet;
    int64_t first = AV_NOPTS_VALUE;
    int64_t last = AV_NOPTS_VALUE;
    for (size_t index = next_packet; index < packets.size() && first == AV_NOPTS_VALUE; ++index) {
        first = packet_decode_timestamp(packets[index].packet);
    }
    for (size_t index = packets.size(); index > next_packet && last == AV_NOPTS_VALUE; --index) {
        last = packet_decode_timestamp(packets[index - 1].packet);
    }
    buffered_ms = first == AV_NOPTS_VALUE ? 0 : std::max<int64_t>(0,
        av_rescale_q(last - first, stream_time_base, AVRational{1, 1000}));
}

bool VideoDecoder::read_packet(AVPacket *packet, uint64_t &packet_generation, bool &flush, int &error) {
    std::unique_lock<std::mutex> lock(mutex);
    wake.wait(lock, [this] { return stopping || buffered_seek_pending || next_packet < packets.size(); });
    if (stopping) return false;
    packet_generation = generation;
    if (buffered_seek_pending) {
        buffered_seek_pending = false;
        flush = true;
        error = 0;
        return true;
    }
    const auto &entry = packets[next_packet++];
    flush = entry.flush;
    error = entry.error;
    if (entry.packet) {
        buffered_bytes -= entry.packet->size;
        history_bytes += entry.packet->size;
        error = av_packet_ref(packet, entry.packet);
    }
    trim_packet_history();
    update_buffer_size();
    wake.notify_all();
    return true;
}

void VideoDecoder::read_loop() {
    int consecutive_errors = 0;
    while (!stopping) {
        int64_t target;
        uint64_t read_generation;
        {
            std::unique_lock<std::mutex> lock(mutex);
            wake.wait(lock, [this] {
                return stopping || seek_target >= 0 || (!reader_ended &&
                    buffered_packets < max_buffer_packets && buffered_bytes < max_buffer_bytes && buffered_ms < max_buffer_ms);
            });
            if (stopping) break;
            target = seek_target;
            seek_target = -1;
            seek_interrupt = false;
            read_generation = demux_generation;
        }
        if (target >= 0) {
            io_deadline = av_gettime_relative() + 15000000;
            int error = avformat_seek_file(input, -1, INT64_MIN, origin_us + target * 1000, INT64_MAX, 0);
            io_deadline = 0;
            std::lock_guard<std::mutex> lock(mutex);
            if (demux_generation != read_generation) continue;
            consecutive_errors = 0;
            packets.push_back({nullptr, true, error});
            update_buffer_size();
            if (error < 0) reader_ended = true;
            wake.notify_all();
            if (error < 0) continue;
        }
        AVPacket *packet = av_packet_alloc();
        int64_t started = av_gettime_relative();
        io_deadline = started + 15000000;
        int result = packet ? av_read_frame(input, packet) : AVERROR(ENOMEM);
        io_deadline = 0;
        read_us += av_gettime_relative() - started;
        std::lock_guard<std::mutex> lock(mutex);
        if (demux_generation != read_generation || stopping) { av_packet_free(&packet); continue; }
        if (result == AVERROR_INVALIDDATA && ++consecutive_errors <= 8) {
            ++corrupt_packets;
            av_packet_free(&packet);
            continue;
        }
        if (result < 0) {
            av_packet_free(&packet);
            packets.push_back({nullptr, false, result});
            reader_ended = true;
        } else {
            consecutive_errors = 0;
            read_bytes += packet->size;
            if (packet->stream_index != stream_index) { av_packet_free(&packet); continue; }
            buffered_bytes += packet->size;
            packets.push_back({packet, false, 0});
        }
        update_buffer_size();
        wake.notify_all();
    }
}
