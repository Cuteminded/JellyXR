#include "../native/pc/playback_clock.h"
#include <cassert>
#include <iostream>

int main() {
    PlaybackClock clock;
    clock.reset(1000, 5000);
    assert(clock.position(5016) == 1016);
    assert(clock.position(5033) == 1033);
    clock.synchronize(1040, 5050);
    assert(clock.position(5050) == 1048);
    assert(clock.position(5066) == 1064);
    clock.synchronize(1110, 5100);
    assert(clock.position(5100) == 1100);
    // A missing audio update must not let video run indefinitely ahead.
    assert(clock.position(6000) == 1350);
    clock.synchronize(1400, 6000);
    assert(clock.position(6016) == 1368);
    // Pause, buffering, and seeking discard the previous extrapolation.
    clock.reset(1400, 7000);
    clock.reset(1400, 8000);
    assert(clock.position(8000) == 1400);
    assert(clock.position(8016) == 1416);
    clock.reset(3000, 9000);
    assert(clock.position(9016) == 3016);
    clock.synchronize(10000, 9100);
    assert(clock.position(9100) == 10000);
    std::cout << "PC playback clock checks: PASS\n";
}
