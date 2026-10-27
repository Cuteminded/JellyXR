#include "video_decoder.h"
#include "stream_identity.h"
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/hwcontext.h>
#include <libavutil/display.h>
#include <libavutil/pixdesc.h>
#include <libavutil/time.h>
#include <libswscale/swscale.h>
}
#include <algorithm>
#include <chrono>
#include <cstring>
#include <cmath>
#include <future>

VideoDecoder::~VideoDecoder() { stop(); }

void VideoDecoder::configure_hardware(const AVCodec *decoder) {
#ifdef _WIN32
    const AVHWDeviceType devices[] = {AV_HWDEVICE_TYPE_CUDA, AV_HWDEVICE_TYPE_D3D11VA};
#else
    const AVHWDeviceType devices[] = {AV_HWDEVICE_TYPE_VAAPI, AV_HWDEVICE_TYPE_CUDA};
#endif
    for (auto device_type : devices) {
        for (int index = 0; ; ++index) {
            const AVCodecHWConfig *config = avcodec_get_hw_config(decoder, index);
            if (!config) break;
            if (config->device_type != device_type || !(config->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX)) continue;
            if (av_hwdevice_ctx_create(&codec->hw_device_ctx, device_type, nullptr, nullptr, 0) < 0) continue;
            hardware_device = av_hwdevice_get_type_name(device_type);
            hardware_format = config->pix_fmt;
            hardware_attempted = false;
            codec->opaque = this;
            codec->get_format = [](AVCodecContext *context, const AVPixelFormat *formats) {
                auto *self = static_cast<VideoDecoder *>(context->opaque);
                if (!self->hardware_attempted) {
                    self->hardware_attempted = true;
                    for (auto *format = formats; *format != AV_PIX_FMT_NONE; ++format) {
                        if (*format == self->hardware_format) return *format;
                    }
                }
                for (auto *format = formats; *format != AV_PIX_FMT_NONE; ++format) {
                    const AVPixFmtDescriptor *description = av_pix_fmt_desc_get(*format);
                    if (description && !(description->flags & AV_PIX_FMT_FLAG_HWACCEL)) return *format;
                }
                return AV_PIX_FMT_NONE;
            };
            return;
        }
    }
}

int VideoDecoder::interrupt(void *owner) {
    auto *self = static_cast<VideoDecoder *>(owner);
    int64_t deadline = self->io_deadline.load();
    return self->stopping || self->seek_interrupt || (deadline && av_gettime_relative() > deadline);
}

int VideoDecoder::open(const std::string &url, const std::string &authorization) {
    input = avformat_alloc_context();
    if (!input) return AVERROR(ENOMEM);
    input->interrupt_callback = {interrupt, this};
    AVDictionary *options = nullptr;
    if (!authorization.empty()) {
        if (authorization.find_first_of("\r\n") != std::string::npos) return AVERROR(EINVAL);
        std::string header = "Authorization: " + authorization + "\r\n";
        av_dict_set(&options, "headers", header.c_str(), 0);
    }
    av_dict_set(&options, "tls_verify", "1", 0);
    av_dict_set(&options, "user_agent", JELLYXR_STREAM_USER_AGENT, 0);
    av_dict_set(&options, "rw_timeout", "15000000", 0);
    io_deadline = av_gettime_relative() + 15000000;
    int result = avformat_open_input(&input, url.c_str(), nullptr, &options);
    av_dict_free(&options);
    if (result < 0) return result;
    result = avformat_find_stream_info(input, nullptr);
    if (result < 0) return result;
    const AVCodec *decoder = nullptr;
    stream_index = av_find_best_stream(input, AVMEDIA_TYPE_VIDEO, -1, -1, &decoder, 0);
    if (stream_index < 0) return stream_index;
    audio = av_find_best_stream(input, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0) >= 0;
    codec = avcodec_alloc_context3(nullptr);
    if (!codec) return AVERROR(ENOMEM);
    result = avcodec_parameters_to_context(codec, input->streams[stream_index]->codecpar);
    if (result < 0) return result;
    codec->thread_count = std::min(8u, std::max(1u, std::thread::hardware_concurrency()));
    const AVCodec *software_decoder = decoder;
    if (codec->codec_id == AV_CODEC_ID_AV1) {
        const AVCodec *native_decoder = avcodec_find_decoder_by_name("av1");
        if (native_decoder) decoder = native_decoder;
    }
    configure_hardware(decoder);
    if (!codec->hw_device_ctx) decoder = software_decoder;
    else codec->thread_count = 1;
    result = avcodec_open2(codec, decoder, nullptr);
    if (result < 0) return result;
    codec_name = decoder->name;
    return read_geometry();
}

int VideoDecoder::read_geometry() {
    source_width = codec->width;
    source_height = codec->height;
    auto *stream = input->streams[stream_index];
#if LIBAVFORMAT_VERSION_MAJOR >= 61
    const AVPacketSideData *display = av_packet_side_data_get(stream->codecpar->coded_side_data,
        stream->codecpar->nb_coded_side_data, AV_PKT_DATA_DISPLAYMATRIX);
    const uint8_t *matrix = display ? display->data : nullptr;
    size_t matrix_size = display ? display->size : 0;
#else
    size_t matrix_size = 0;
    const uint8_t *matrix = av_stream_get_side_data(stream, AV_PKT_DATA_DISPLAYMATRIX, &matrix_size);
#endif
    if (matrix && matrix_size >= 9 * sizeof(int32_t)) {
        double angle = -av_display_rotation_get(reinterpret_cast<const int32_t *>(matrix));
        if (!std::isfinite(angle) || std::abs(angle / 90.0 - std::round(angle / 90.0)) > 0.001) return AVERROR(ENOSYS);
        rotation = (int(std::round(angle / 90.0)) % 4 + 4) % 4;
    }
    AVRational aspect = av_guess_sample_aspect_ratio(input, stream, nullptr);
    if (aspect.num > 0 && aspect.den > 0) source_width = int(av_rescale(source_width, aspect.num, aspect.den));
    if (rotation % 2) std::swap(source_width, source_height);
    if (source_width <= 0 || source_height <= 0 || source_width > 8192 || source_height > 8192 ||
            int64_t(source_width) * source_height > 33554432) return AVERROR(ENOSYS);
    origin_us = input->start_time == AV_NOPTS_VALUE ? 0 : input->start_time;
    duration = input->duration == AV_NOPTS_VALUE ? 0 : input->duration / 1000;
    io_deadline = 0;
    return 0;
}

int VideoDecoder::start(const std::string &url, const std::string &authorization, int64_t start_ms) {
    stop();
    stopping = false;
    decode_error = 0;
    hardware_active = false;
    pinned_download = false;
    hardware_device.clear();
    corrupt_packets = 0;
    decoded_frames = dropped_frames = converted_frames = 0;
    download_us = conversion_us = 0;
    read_us = decode_us = read_bytes = 0;
    buffered_ms = buffered_bytes = 0;
    reader_ended = seek_interrupt = false;
    end_of_stream = false;
    clock = std::max<int64_t>(0, start_ms);
    seek_target = clock > 0 ? clock : -1;
    discard_before = clock - 100;
    last_publish_us = 0;
    decoded_timestamp = 0;
    generation = 0;
    awaiting_first_frame = true;
    rotation = 0;
    std::promise<int> initialized;
    auto result = initialized.get_future();
    worker = std::thread([this, url, authorization, ready = std::move(initialized)]() mutable {
        int error = open(url, authorization);
        ready.set_value(error);
        if (error >= 0) {
            reader = std::thread(&VideoDecoder::read_loop, this);
            decode_loop();
            stopping = true;
            wake.notify_all();
            reader.join();
        }
        close();
    });
    return result.get();
}

void VideoDecoder::close() {
    sws_freeContext(scaler);
    scaler = nullptr;
    avcodec_free_context(&codec);
    avformat_close_input(&input);
}

void VideoDecoder::stop() {
    stopping = true;
    wake.notify_all();
    if (worker.joinable()) worker.join();
    std::lock_guard<std::mutex> lock(mutex);
    clear_packets();
    pending = VideoPlanes();
    staging = VideoPlanes();
    frame_ready = false;
}

void VideoDecoder::set_clock(int64_t milliseconds) {
    { std::lock_guard<std::mutex> lock(mutex); clock = milliseconds; }
    wake.notify_all();
}

void VideoDecoder::seek(int64_t milliseconds) {
    {
        std::lock_guard<std::mutex> lock(mutex);
        seek_target = std::max<int64_t>(0, milliseconds);
        clock = seek_target;
        discard_before = seek_target - 100;
        last_publish_us = 0;
        ++generation;
        seek_interrupt = true;
        clear_packets();
        reader_ended = false;
        end_of_stream = false;
        frame_ready = false;
        awaiting_first_frame = true;
    }
    wake.notify_all();
}

bool VideoDecoder::take_frame(VideoPlanes &frame) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!frame_ready || (!awaiting_first_frame && pending.timestamp > clock)) return false;
    awaiting_first_frame = false;
    std::swap(frame, pending);
    frame_ready = false;
    wake.notify_all();
    return true;
}

bool VideoDecoder::has_frame() {
    std::lock_guard<std::mutex> lock(mutex);
    return frame_ready && (awaiting_first_frame || pending.timestamp <= clock);
}

void VideoDecoder::decode_loop() {
    AVPacket *packet = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    if (!packet || !frame) decode_error = AVERROR(ENOMEM);
    uint64_t codec_generation = 0;
    int consecutive_errors = 0;
    while (!stopping && decode_error >= 0) {
        int64_t started = av_gettime_relative();
        int result = avcodec_receive_frame(codec, frame);
        decode_us += av_gettime_relative() - started;
        if (result >= 0) {
            consecutive_errors = 0;
            ++decoded_frames;
            bool keep_going = publish(frame, codec_generation);
            av_frame_unref(frame);
            if (!keep_going) break;
            continue;
        }
        if (result == AVERROR_EOF) {
            end_of_stream = true;
        } else if (result == AVERROR_INVALIDDATA) {
            ++corrupt_packets;
            if (++consecutive_errors > 8) { decode_error = result; break; }
        } else if (result != AVERROR(EAGAIN)) { decode_error = result; break; }
        bool flush = false;
        if (!read_packet(packet, codec_generation, flush, result)) break;
        if (result < 0 && (flush || result != AVERROR_EOF)) { decode_error = result; break; }
        if (flush) {
            avcodec_flush_buffers(codec);
            end_of_stream = false;
            consecutive_errors = 0;
            continue;
        }
        started = av_gettime_relative();
        bool draining = result == AVERROR_EOF;
        result = avcodec_send_packet(codec, draining ? nullptr : packet);
        decode_us += av_gettime_relative() - started;
        av_packet_unref(packet);
        if (result == AVERROR_INVALIDDATA && ++consecutive_errors <= 8) {
            ++corrupt_packets;
            continue;
        }
        if (result < 0) { decode_error = result; break; }
    }
    av_frame_free(&frame);
    av_packet_free(&packet);
}
