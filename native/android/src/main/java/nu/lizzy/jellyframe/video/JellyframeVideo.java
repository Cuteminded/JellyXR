package nu.lizzy.jellyframe.video;

import android.graphics.SurfaceTexture;
import android.media.MediaPlayer;
import android.net.Uri;
import android.opengl.Matrix;
import android.os.Handler;
import android.os.Looper;
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
import javax.microedition.khronos.opengles.GL10;

public final class JellyframeVideo extends GodotPlugin {
    private final Handler main = new Handler(Looper.getMainLooper());
    private final AtomicBoolean frameAvailable = new AtomicBoolean();
    private final float[] transform = new float[16];
    private SurfaceTexture texture;
    private Surface surface;
    private MediaPlayer player;
    private volatile int position;
    private volatile int duration;
    private volatile boolean prepared;
    private volatile boolean buffering;
    private volatile boolean seeking;
    private int generation;

    public JellyframeVideo(Godot godot) {
        super(godot);
        Matrix.setIdentityM(transform, 0);
    }

    @Override public String getPluginName() { return "JellyframeVideo"; }

    @Override public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> result = new HashSet<>();
        result.add(new SignalInfo("prepared"));
        result.add(new SignalInfo("completed"));
        result.add(new SignalInfo("failed", String.class));
        result.add(new SignalInfo("video_size", Integer.class, Integer.class));
        return result;
    }

    @UsedByGodot public void open_video(int textureId, String url, String authorization, int startMs) {
        Log.i("JellyframeVideo", "Opening video texture " + textureId);
        main.post(() -> {
            releasePlayer();
            int opening = generation;
            runOnRenderThread(() -> {
                releaseSurface();
                texture = new SurfaceTexture(textureId);
                Log.i("JellyframeVideo", "SurfaceTexture created");
                texture.setOnFrameAvailableListener(ignored -> frameAvailable.set(true));
                surface = new Surface(texture);
                Surface output = surface;
                main.post(() -> {
                    if (opening == generation) prepare(output, url, authorization, startMs);
                });
            });
        });
    }

    private void prepare(Surface output, String url, String authorization, int startMs) {
        try {
            player = new MediaPlayer();
            player.setSurface(output);
            HashMap<String, String> headers = new HashMap<>();
            headers.put("Authorization", authorization);
            headers.put("android-allow-cross-domain-redirect", "0");
            player.setDataSource(getContext(), Uri.parse(url), headers);
            player.setOnPreparedListener(current -> {
                Log.i("JellyframeVideo", "Decoder prepared: " + current.getVideoWidth() + "x" + current.getVideoHeight());
                prepared = true;
                duration = Math.max(0, current.getDuration());
                if (startMs > 0) current.seekTo(startMs, MediaPlayer.SEEK_CLOSEST);
                current.start();
                emitSignal("prepared");
            });
            player.setOnVideoSizeChangedListener((current, width, height) -> emitSignal("video_size", width, height));
            player.setOnInfoListener((current, what, extra) -> {
                if (what == MediaPlayer.MEDIA_INFO_BUFFERING_START) buffering = true;
                if (what == MediaPlayer.MEDIA_INFO_BUFFERING_END) buffering = false;
                return false;
            });
            player.setOnSeekCompleteListener(current -> seeking = false);
            player.setOnCompletionListener(current -> emitSignal("completed"));
            player.setOnErrorListener((current, what, extra) -> {
                prepared = false;
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
        }
        main.post(() -> {
            if (player != null && prepared) {
                try { position = player.getCurrentPosition(); }
                catch (IllegalStateException ignored) { prepared = false; }
            }
        });
    }

    @UsedByGodot public float[] texture_transform() {
        synchronized (transform) { return transform.clone(); }
    }

    @UsedByGodot public int position_ms() { return position; }
    @UsedByGodot public int duration_ms() { return duration; }
    @UsedByGodot public boolean is_buffering() { return prepared && (buffering || seeking); }

    @UsedByGodot public String calibration_url() {
        int resource = getContext().getResources().getIdentifier("stereo_test", "raw", getContext().getPackageName());
        return "android.resource://" + getContext().getPackageName() + "/" + resource;
    }

    @UsedByGodot public boolean calibration_requested() {
        return getActivity() != null && getActivity().getIntent().getBooleanExtra("jellyframe_calibration", false);
    }

    @UsedByGodot public void set_paused(boolean paused) {
        main.post(() -> {
            if (player == null || !prepared) return;
            if (paused) player.pause(); else player.start();
        });
    }

    @UsedByGodot public void seek_to(int milliseconds) {
        main.post(() -> {
            if (player != null && prepared) {
                seeking = true;
                player.seekTo(Math.max(0, Math.min(milliseconds, player.getDuration())), MediaPlayer.SEEK_CLOSEST);
            }
        });
    }

    @UsedByGodot public void stop_video() { main.post(this::releasePlayer); }

    private void releasePlayer() {
        generation++;
        prepared = false;
        buffering = false;
        seeking = false;
        position = 0;
        duration = 0;
        if (player != null) { player.release(); player = null; }
    }

    private void releaseSurface() {
        frameAvailable.set(false);
        if (surface != null) { surface.release(); surface = null; }
        if (texture != null) { texture.release(); texture = null; }
    }

    @Override public void onMainPause() { set_paused(true); }

    @Override public void onMainDestroy() {
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
