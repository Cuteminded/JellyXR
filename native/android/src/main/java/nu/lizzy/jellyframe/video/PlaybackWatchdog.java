package nu.lizzy.jellyframe.video;

final class PlaybackWatchdog {
    private static final long FRAME_TIMEOUT_MS = 20000;
    private static final long BUFFER_TIMEOUT_MS = 60000;
    private long lastProgress;
    private boolean paused;

    void reset(long now) {
        lastProgress = now;
        paused = false;
    }

    void setPaused(boolean value, long now) {
        paused = value;
        lastProgress = now;
    }

    boolean stalled(long now, long lastFrame, boolean waiting) {
        if (paused) {
            lastProgress = now;
            return false;
        }
        lastProgress = Math.max(lastProgress, lastFrame);
        return now - lastProgress >= (waiting ? BUFFER_TIMEOUT_MS : FRAME_TIMEOUT_MS);
    }
}
