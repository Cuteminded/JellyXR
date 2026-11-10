package nu.lizzy.jellyxr.video;

import android.content.Context;
import android.graphics.SurfaceTexture;
import android.media.AudioManager;
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
    private BufferedPlayback player;
    private volatile int position;
    private volatile int duration;
    private volatile int bufferedPosition = -1;
    private volatile boolean buffering;
    private volatile float volume = 1.0f;
    private final AtomicInteger generation = new AtomicInteger();
    private volatile int readyGeneration = -1;
    private int textureGeneration = -1;
    private final HardwareDecoders decoders = new HardwareDecoders();
    private final AtomicBoolean scanStarted = new AtomicBoolean();
    private volatile String activeDecoder = "";

    @UsedByGodot public void scan_decoders() {
        if (scanStarted.compareAndSet(false, true)) new Thread(decoders::scan, "JellyXR codecs").start();
    }

    @UsedByGodot public int decode_support(String codec, String profile, int depth, int width, int height, double fps) {
        return decoders.supports(codec, profile, depth, width, height, fps);
    }

    @UsedByGodot public int active_decode_support() {
        return has_video_frame() ? decoders.active(activeDecoder) : HardwareDecoders.UNKNOWN;
    }

    @UsedByGodot public String decoder_summary() { return decoders.summary(); }

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
            activeDecoder = "";
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

    private void prepare(Surface output, String url, String authorization, int startMs, int opening) {
        try {
            buffering = true;
            watchdog.reset(SystemClock.elapsedRealtime());
            player = new BufferedPlayback(getContext(), output, url, authorization, startMs, volume,
                new BufferedPlayback.Listener() {
                    private boolean current() { return opening == generation.get(); }

                    @Override public void ready() {
                        if (!current()) return;
                        watchdog.setPaused(player.paused(), SystemClock.elapsedRealtime());
                        emitSignal("prepared");
                    }

                    @Override public void completed() {
                        if (!current()) return;
                        main.removeCallbacks(pollPlayback);
                        emitSignal("completed");
                    }

                    @Override public void failed(String message) {
                        if (!current()) return;
                        buffering = false;
                        main.removeCallbacks(pollPlayback);
                        emitSignal("failed", message);
                    }

                    @Override public void sizeChanged(int width, int height) {
                        if (current()) emitSignal("video_size", width, height);
                    }

                    @Override public void decoderChanged(String name) {
                        if (current()) activeDecoder = name;
                    }
                });
            main.post(pollPlayback);
        } catch (RuntimeException exception) {
            Log.e("JellyXRVideo", "Cannot prepare playback", exception);
            releasePlayer();
            emitSignal("failed", "Cannot open the video stream. Check network and format support.");
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
        if (player == null || player.ended()) return;
        try {
            position = player.position();
            duration = player.duration();
            bufferedPosition = player.bufferedPosition();
            buffering = player.buffering();
            if (watchdog.stalled(SystemClock.elapsedRealtime(), lastFrame, buffering)) {
                Log.w("JellyXRVideo", "No video frames at " + position + " ms, buffering=" + buffering);
                emitSignal("failed", "Video playback stalled.");
                return;
            }
        } catch (IllegalStateException exception) {
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
        return bufferedPosition;
    }
    @UsedByGodot public boolean has_video_frame() { return readyGeneration >= 0 && readyGeneration == generation.get(); }
    @UsedByGodot public boolean is_buffering() { return buffering; }

    @UsedByGodot public void set_paused(boolean paused) {
        main.post(() -> {
            if (player == null) return;
            player.setPaused(paused);
            watchdog.setPaused(paused, SystemClock.elapsedRealtime());
        });
    }

    @UsedByGodot public void set_volume(double level) {
        volume = (float) Math.max(0.0, Math.min(1.0, level));
        main.post(() -> {
            if (player != null) player.setVolume(volume);
        });
    }

    @UsedByGodot public double get_system_volume() {
        AudioManager audio = (AudioManager) getContext().getSystemService(Context.AUDIO_SERVICE);
        int maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        return maximum > 0 ? (double) audio.getStreamVolume(AudioManager.STREAM_MUSIC) / maximum : 0.0;
    }

    @UsedByGodot public double set_system_volume(double level) {
        AudioManager audio = (AudioManager) getContext().getSystemService(Context.AUDIO_SERVICE);
        int maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        int index = (int) Math.round(Math.max(0.0, Math.min(1.0, level)) * maximum);
        try {
            audio.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0);
        } catch (SecurityException exception) {
            Log.w("JellyXRVideo", "Android denied the media volume change", exception);
        }
        return get_system_volume();
    }

    @UsedByGodot public void seek_to(int milliseconds) {
        main.post(() -> {
            if (player == null) return;
            bufferedPosition = -1;
            watchdog.setPaused(player.paused(), SystemClock.elapsedRealtime());
            player.seek(milliseconds);
        });
    }

    @UsedByGodot public void stop_video() {
        generation.incrementAndGet();
        main.post(this::releasePlayer);
    }

    private void releasePlayer() {
        main.removeCallbacks(pollPlayback);
        buffering = false;
        position = 0;
        duration = 0;
        bufferedPosition = -1;
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
