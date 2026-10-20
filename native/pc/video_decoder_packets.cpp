#include "video_decoder.h"
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/time.h>
}
#include <algorithm>

void VideoDecoder::clear_packets() {
    for (auto &entry : packets) av_packet_free(&entry.packet);
    packets.clear();
    buffered_bytes = buffered_ms = 0;
    buffered_packets = 0;
}

void VideoDecoder::update_buffer_size() {
    buffered_packets = packets.size();
    int64_t first = AV_NOPTS_VALUE;
    int64_t last = AV_NOPTS_VALUE;
    for (const auto &entry : packets) {
        if (!entry.packet) continue;
        int64_t timestamp = entry.packet->dts == AV_NOPTS_VALUE ? entry.packet->pts : entry.packet->dts;
        if (timestamp == AV_NOPTS_VALUE) continue;
        if (first == AV_NOPTS_VALUE) first = timestamp;
        last = timestamp;
    }
    buffered_ms = first == AV_NOPTS_VALUE ? 0 : std::max<int64_t>(0,
        av_rescale_q(last - first, input->streams[stream_index]->time_base, AVRational{1, 1000}));
}

bool VideoDecoder::read_packet(AVPacket *packet, uint64_t &packet_generation, bool &flush, int &error) {
    std::unique_lock<std::mutex> lock(mutex);
    wake.wait(lock, [this] { return stopping || !packets.empty(); });
    if (stopping) return false;
    auto entry = packets.front();
    packets.pop_front();
    packet_generation = entry.generation;
    flush = entry.flush;
    error = entry.error;
    if (entry.packet) {
        buffered_bytes -= entry.packet->size;
        av_packet_move_ref(packet, entry.packet);
        av_packet_free(&entry.packet);
    }
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
                    packets.size() < 512 && buffered_bytes < 128 * 1048576 && buffered_ms < 4000);
            });
            if (stopping) break;
            target = seek_target;
            seek_target = -1;
            seek_interrupt = false;
            read_generation = generation;
        }
        if (target >= 0) {
            io_deadline = av_gettime_relative() + 15000000;
            int error = avformat_seek_file(input, -1, INT64_MIN, origin_us + target * 1000, INT64_MAX, 0);
            io_deadline = 0;
            std::lock_guard<std::mutex> lock(mutex);
            if (generation != read_generation) continue;
            consecutive_errors = 0;
            packets.push_back({nullptr, read_generation, true, error});
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
        if (generation != read_generation || stopping) { av_packet_free(&packet); continue; }
        if (result == AVERROR_INVALIDDATA && ++consecutive_errors <= 8) {
            ++corrupt_packets;
            av_packet_free(&packet);
            continue;
        }
        if (result < 0) {
            av_packet_free(&packet);
            packets.push_back({nullptr, read_generation, false, result});
            reader_ended = true;
        } else {
            consecutive_errors = 0;
            read_bytes += packet->size;
            if (packet->stream_index != stream_index) { av_packet_free(&packet); continue; }
            buffered_bytes += packet->size;
            packets.push_back({packet, read_generation, false, 0});
            update_buffer_size();
        }
        wake.notify_all();
    }
}
