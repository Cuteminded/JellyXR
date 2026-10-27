package nu.lizzy.jellyxr.video;

public final class PlaybackWatchdogTest {
    public static void main(String[] args) {
        PlaybackWatchdog watchdog = new PlaybackWatchdog();
        watchdog.reset(1000);
        check(!watchdog.stalled(20999, 0, false), "Allow decoder startup time");
        check(watchdog.stalled(21000, 0, false), "Recover when the decoder never delivers frames");
        watchdog.reset(1000);
        check(!watchdog.stalled(21000, 20000, false), "Frames keep playback healthy");
        check(watchdog.stalled(40000, 20000, false), "Recover when frames stop despite an advancing audio clock");
        watchdog.reset(1000);
        check(!watchdog.stalled(60999, 0, true), "Allow extra time for buffering and seeking");
        check(watchdog.stalled(61000, 0, true), "Buffering cannot hang indefinitely");
        watchdog.setPaused(true, 61000);
        check(!watchdog.stalled(200000, 0, false), "Paused video must not trigger recovery");
        watchdog.setPaused(false, 200000);
        check(!watchdog.stalled(219999, 0, false), "Resume gives the decoder time to deliver frames");
        watchdog.reset(300000);
        check(!watchdog.stalled(300000, 20000, false), "Old frames cannot shorten the new stream startup window");
        System.out.println("Playback watchdog checks: PASS");
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
