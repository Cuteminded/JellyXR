#pragma once

#include <algorithm>
#include <cstdint>
#include <cstdlib>

class PlaybackClock {
public:
    void reset(int64_t position, uint64_t now) {
        anchor = position;
        sampled_at = now;
    }

    int64_t position(uint64_t now) const {
        return anchor + int64_t(std::min<uint64_t>(now - sampled_at, 250));
    }

    void synchronize(int64_t audio_position, uint64_t now) {
        int64_t predicted = position(now);
        int64_t error = audio_position - predicted;
        anchor = std::abs(error) > 250 ? audio_position : predicted + std::clamp<int64_t>(error, -2, 2);
        sampled_at = now;
    }

private:
    int64_t anchor = 0;
    uint64_t sampled_at = 0;
};
