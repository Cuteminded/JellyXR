#include "../native/pc/playback_watchdog.h"
#include <cstdlib>
#include <iostream>

static void check(bool condition, const char *message) {
    if (!condition) {
        std::cerr << message << '\n';
        std::exit(1);
    }
}

int main() {
    PlaybackWatchdog watchdog;
    watchdog.reset(1000);
    check(!watchdog.stalled(20999, false, false, false), "Allow decoder startup time");
    check(watchdog.stalled(21000, false, false, false), "Recover when video frames stop");
    check(!watchdog.stalled(22000, true, false, false), "A new frame clears the stall timer");
    check(!watchdog.stalled(41999, false, false, false), "Advancing playback gets a fresh timeout");
    check(watchdog.stalled(42000, false, false, false), "An advancing audio clock cannot hide missing video frames");
    watchdog.reset(1000);
    check(!watchdog.stalled(60999, false, false, true), "Allow buffering and seeking extra time");
    check(watchdog.stalled(61000, false, false, true), "Buffering cannot hang indefinitely");
    watchdog.reset(61000);
    check(!watchdog.stalled(61001, false, false, false), "Finishing buffering gives the decoder time to produce its first frame");
    check(!watchdog.stalled(200000, false, true, false), "Paused playback must not trigger recovery");
    check(!watchdog.stalled(219999, false, false, false), "Resume allows time for new frames");
    check(watchdog.stalled(220000, false, false, false), "Resume still detects a stalled decoder");
    watchdog.reset(300000);
    check(!watchdog.stalled(300000, false, false, false), "Reopening clears the previous timeout");
    std::cout << "PC playback watchdog checks: PASS\n";
}
