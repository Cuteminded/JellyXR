package nu.lizzy.jellyxr.video;

import android.content.Context;
import android.util.Log;
import android.view.Surface;
import androidx.media3.common.C;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.VideoSize;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.analytics.AnalyticsListener;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.exoplayer.source.LoadEventInfo;
import androidx.media3.exoplayer.source.MediaLoadData;
import java.util.Collections;

final class BufferedPlayback {
    interface Listener {
        void ready();
        void completed();
        void failed(String message);
        void sizeChanged(int width, int height);
    }

    private final ExoPlayer player;
    private boolean prepared;
    private boolean failed;

    BufferedPlayback(Context context, Surface surface, String url, String authorization,
                     int startMs, Listener listener) {
        DefaultHttpDataSource.Factory http = new DefaultHttpDataSource.Factory()
            .setUserAgent("jellyXR")
            .setDefaultRequestProperties(Collections.singletonMap("Authorization", authorization));
        DefaultLoadControl loadControl = new DefaultLoadControl.Builder()
            .setBufferDurationsMs(15000, 30000, 6000, 6000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build();
        player = new ExoPlayer.Builder(context)
            .setMediaSourceFactory(new DefaultMediaSourceFactory(new DefaultDataSource.Factory(context, http)))
            .setLoadControl(loadControl)
            .build();
        try {
            prepare(surface, url, startMs, listener);
        } catch (RuntimeException exception) {
            player.release();
            throw exception;
        }
    }

    private void prepare(Surface surface, String url, int startMs, Listener listener) {
        player.setVideoSurface(surface);
        player.addAnalyticsListener(new AnalyticsListener() {
            @Override public void onLoadCompleted(EventTime eventTime, LoadEventInfo load,
                                                   MediaLoadData media) {
                if (media.dataType != C.DATA_TYPE_MEDIA) return;
                long duration = media.mediaEndTimeMs == C.TIME_UNSET || media.mediaStartTimeMs == C.TIME_UNSET
                    ? -1 : media.mediaEndTimeMs - media.mediaStartTimeMs;
                Log.i("JellyXRVideo", "Media3 load: media_ms=" + duration
                    + ", load_ms=" + load.loadDurationMs + ", bytes=" + load.bytesLoaded);
            }
        });
        player.setTrackSelectionParameters(player.getTrackSelectionParameters().buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build());
        player.addListener(new Player.Listener() {
            @Override public void onPlaybackStateChanged(int state) {
                Log.i("JellyXRVideo", "Media3 state=" + state + ", position=" + position()
                    + ", buffered=" + bufferedPosition());
                if (state == Player.STATE_READY && !prepared) {
                    prepared = true;
                    listener.ready();
                }
                if (state == Player.STATE_ENDED) listener.completed();
            }

            @Override public void onVideoSizeChanged(VideoSize size) {
                listener.sizeChanged(size.width, size.height);
            }

            @Override public void onPlayerError(PlaybackException error) {
                failed = true;
                Log.e("JellyXRVideo", "Media3 playback error", error);
                listener.failed("Android playback failed (" + error.getErrorCodeName() + ").");
            }
        });
        player.setMediaItem(MediaItem.fromUri(url), Math.max(0, startMs));
        player.prepare();
        player.play();
    }

    int position() { return milliseconds(player.getCurrentPosition()); }
    int duration() { return milliseconds(player.getDuration()); }
    int bufferedPosition() { return failed ? -1 : milliseconds(player.getBufferedPosition()); }
    boolean buffering() { return !failed && player.getPlaybackState() == Player.STATE_BUFFERING; }
    boolean paused() { return !player.getPlayWhenReady(); }
    boolean ended() { return failed || player.getPlaybackState() == Player.STATE_ENDED; }
    void setPaused(boolean paused) { player.setPlayWhenReady(!paused); }
    void seek(int position) { player.seekTo(Math.max(0, position)); }
    void release() { player.release(); }

    private static int milliseconds(long value) {
        return value == C.TIME_UNSET ? 0 : (int) Math.max(0, Math.min(Integer.MAX_VALUE, value));
    }
}
