package nu.lizzy.jellyxr.video;

import android.graphics.SurfaceTexture;
import android.media.MediaPlayer;
import android.net.Uri;
import android.opengl.Matrix;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.Surface;
import android.util.Log;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import javax.microedition.khronos.opengles.GL10;

public final class JellyXRVideo extends GodotPlugin {
    private final Handler main = new Handler(Looper.getMainLooper());
    private final AtomicBoolean frameAvailable = new AtomicBoolean();
    private final float[] transform = new float[16];
    private final PlaybackWatchdog watchdog = new PlaybackWatchdog();
    private volatile long lastFrame;
    private final Runnable pollPlayback = this::pollPlayback;
    private SurfaceTexture texture;
    private Surface surface;
    private MediaPlayer player;
    private volatile int position;
    private volatile int duration;
    private volatile int bufferedPercent = -1;
    private volatile boolean prepared;
    private volatile boolean buffering;
    private volatile boolean seeking;
    private final AtomicInteger generation = new AtomicInteger();
    private volatile int readyGeneration = -1;
    private int textureGeneration = -1;

    public JellyXRVideo(Godot godot) {
        super(godot);
        Matrix.setIdentityM(transform, 0);
    }

    @Override public String getPluginName() { return "JellyXRVideo"; }

    @Override public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> result = new HashSet<>();
        result.add(new SignalInfo("prepared"));
        result.add(new SignalInfo("completed"));
        result.add(new SignalInfo("failed", String.class));
        result.add(new SignalInfo("video_size", Integer.class, Integer.class));
        return result;
    }

    @UsedByGodot public void open_video(int textureId, String url, String authorization, int startMs) {
        int opening = generation.incrementAndGet();
        main.post(() -> {
            if (opening != generation.get()) return;
            releasePlayer();
            runOnRenderThread(() -> {
                if (opening != generation.get()) return;
                releaseSurface();
                texture = new SurfaceTexture(textureId);
                textureGeneration = opening;
                texture.setOnFrameAvailableListener(ignored -> {
                    if (ignored != texture || opening != generation.get()) return;
                    lastFrame = SystemClock.elapsedRealtime();
                    frameAvailable.set(true);
                });
                surface = new Surface(texture);
                Surface output = surface;
                main.post(() -> {
                    if (opening == generation.get()) prepare(output, url, authorization, startMs, opening);
                });
            });
        });
    }

    private boolean isCurrent(MediaPlayer current, int opening) {
        return current == player && opening == generation.get();
    }

    private void prepare(Surface output, String url, String authorization, int startMs, int opening) {
        try {
            player = new MediaPlayer();
            player.setSurface(output);
            HashMap<String, String> headers = new HashMap<>();
            headers.put("Authorization", authorization);
            headers.put("android-allow-cross-domain-redirect", "0");
            player.setDataSource(getContext(), Uri.parse(url), headers);
            player.setOnPreparedListener(current -> {
                if (!isCurrent(current, opening)) return;
                prepared = true;
                watchdog.reset(SystemClock.elapsedRealtime());
                duration = Math.max(0, current.getDuration());
                if (startMs > 0) current.seekTo(startMs, MediaPlayer.SEEK_CLOSEST);
                current.start();
                main.post(pollPlayback);
                emitSignal("prepared");
            });
            player.setOnVideoSizeChangedListener((current, width, height) -> {
                if (isCurrent(current, opening)) emitSignal("video_size", width, height);
            });
            player.setOnBufferingUpdateListener((current, percent) -> {
                if (isCurrent(current, opening)) bufferedPercent = Math.max(0, Math.min(100, percent));
            });
            player.setOnInfoListener((current, what, extra) -> {
                if (!isCurrent(current, opening)) return true;
                if (what == MediaPlayer.MEDIA_INFO_BUFFERING_START) {
                    buffering = true;
                }
                if (what == MediaPlayer.MEDIA_INFO_BUFFERING_END) {
                    buffering = false;
                }
                if (what == MediaPlayer.MEDIA_INFO_VIDEO_TRACK_LAGGING) Log.w("JellyXRVideo", "Video decoder is falling behind");
                return false;
            });
            player.setOnSeekCompleteListener(current -> {
                if (!isCurrent(current, opening)) return;
                seeking = false;
                watchdog.setPaused(!current.isPlaying(), SystemClock.elapsedRealtime());
            });
            player.setOnCompletionListener(current -> {
                if (!isCurrent(current, opening)) return;
                main.removeCallbacks(pollPlayback);
                emitSignal("completed");
            });
            player.setOnErrorListener((current, what, extra) -> {
                if (!isCurrent(current, opening)) return true;
                prepared = false;
                main.removeCallbacks(pollPlayback);
                emitSignal("failed", "Android could not decode this stream (" + what + ", " + extra + ").");
                return true;
            });
            player.prepareAsync();
        } catch (Exception exception) {
            emitSignal("failed", "Cannot open the video stream. Check network and format support.");
            releasePlayer();
        }
    }

    @Override public void onGLDrawFrame(GL10 gl) {
        if (texture != null && frameAvailable.compareAndSet(true, false)) {
            texture.updateTexImage();
            synchronized (transform) { texture.getTransformMatrix(transform); }
            if (textureGeneration == generation.get()) readyGeneration = textureGeneration;
        }
    }

    private void pollPlayback() {
        if (player == null || !prepared) return;
        try {
            position = player.getCurrentPosition();
            if (watchdog.stalled(SystemClock.elapsedRealtime(), lastFrame, buffering || seeking)) {
                prepared = false;
                Log.w("JellyXRVideo", "No video frames at " + position + " ms, buffering=" + buffering + ", seeking=" + seeking);
                emitSignal("failed", "Video playback stalled.");
                return;
            }
        } catch (IllegalStateException exception) {
            prepared = false;
            emitSignal("failed", "The video player stopped unexpectedly.");
            return;
        }
        main.postDelayed(pollPlayback, 250);
    }

    @UsedByGodot public float[] texture_transform() {
        synchronized (transform) { return transform.clone(); }
    }

    @UsedByGodot public int position_ms() { return position; }
    @UsedByGodot public int duration_ms() { return duration; }
    @UsedByGodot public int buffered_position_ms() {
        return prepared && !seeking && bufferedPercent >= 0 && duration > 0
            ? (int) ((long) duration * bufferedPercent / 100) : -1;
    }
    @UsedByGodot public boolean has_video_frame() { return readyGeneration >= 0 && readyGeneration == generation.get(); }
    @UsedByGodot public boolean is_buffering() { return prepared && (buffering || seeking); }

    @UsedByGodot public void set_paused(boolean paused) {
        main.post(() -> {
            if (player == null || !prepared) return;
            if (paused) player.pause(); else player.start();
            watchdog.setPaused(paused, SystemClock.elapsedRealtime());
        });
    }

    @UsedByGodot public void seek_to(int milliseconds) {
        main.post(() -> {
            if (player != null && prepared) {
                seeking = true;
                bufferedPercent = -1;
                watchdog.setPaused(!player.isPlaying(), SystemClock.elapsedRealtime());
                player.seekTo(Math.max(0, Math.min(milliseconds, player.getDuration())), MediaPlayer.SEEK_CLOSEST);
            }
        });
    }

    @UsedByGodot public void stop_video() {
        generation.incrementAndGet();
        main.post(this::releasePlayer);
    }

    private void releasePlayer() {
        main.removeCallbacks(pollPlayback);
        prepared = false;
        buffering = false;
        seeking = false;
        position = 0;
        duration = 0;
        bufferedPercent = -1;
        if (player != null) { player.release(); player = null; }
    }

    private void releaseSurface() {
        readyGeneration = -1;
        lastFrame = 0;
        frameAvailable.set(false);
        if (surface != null) { surface.release(); surface = null; }
        if (texture != null) { texture.release(); texture = null; }
    }

    @Override public void onMainPause() { set_paused(true); }

    @Override public void onMainDestroy() {
        generation.incrementAndGet();
        releasePlayer();
        runOnRenderThread(this::releaseSurface);
    }

    @UsedByGodot public void save_session(String value) {
        try { new SessionStore(getContext()).save(value); }
        catch (Exception exception) { emitSignal("failed", "Could not save the sign-in securely."); }
    }

    @UsedByGodot public String load_session() {
        try { return new SessionStore(getContext()).load(); }
        catch (Exception exception) { return ""; }
    }
}
