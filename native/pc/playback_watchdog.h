#pragma once

#include <cstdint>

class PlaybackWatchdog {
public:
    void reset(uint64_t now) { last_progress = now; }

    bool stalled(uint64_t now, bool received_frame, bool paused, bool waiting) {
        if (received_frame || paused) {
            reset(now);
            return false;
        }
        return now - last_progress >= (waiting ? 60000 : 20000);
    }

private:
    uint64_t last_progress = 0;
};
