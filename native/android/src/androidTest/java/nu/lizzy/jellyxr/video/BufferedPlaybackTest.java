package nu.lizzy.jellyxr.video;

import android.graphics.ImageFormat;
import android.media.Image;
import android.media.ImageReader;
import android.os.Handler;
import android.os.Looper;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

@RunWith(AndroidJUnit4.class)
public final class BufferedPlaybackTest {
    @Test public void buffersPausesSeeksAndCompletes() throws Exception {
        checkPlayback("asset:///playback.mp4");
        checkPlayback("asset:///stream.m3u8");
    }

    private void checkPlayback(String url) throws Exception {
        CountDownLatch ready = new CountDownLatch(1);
        CountDownLatch completed = new CountDownLatch(1);
        AtomicReference<String> error = new AtomicReference<>();
        AtomicReference<BufferedPlayback> playback = new AtomicReference<>();
        AtomicInteger bufferedAtStart = new AtomicInteger();
        AtomicInteger position = new AtomicInteger();
        AtomicInteger width = new AtomicInteger();
        ImageReader output = ImageReader.newInstance(1920, 1080, ImageFormat.PRIVATE, 3);
        output.setOnImageAvailableListener(reader -> {
            try (Image image = reader.acquireLatestImage()) { }
        }, new Handler(Looper.getMainLooper()));
        try {
            onMain(() -> playback.set(new BufferedPlayback(
                InstrumentationRegistry.getInstrumentation().getContext(), output.getSurface(), url, "", 0,
                new BufferedPlayback.Listener() {
                    public void ready() {
                        bufferedAtStart.set(playback.get().bufferedPosition());
                        ready.countDown();
                    }
                    public void completed() { completed.countDown(); }
                    public void failed(String message) { error.set(message); ready.countDown(); }
                    public void sizeChanged(int w, int h) { width.set(w); }
                })));
            assertTrue("Playback must become ready", ready.await(30, TimeUnit.SECONDS));
            assertNull(error.get());
            assertTrue("Startup must buffer at least six seconds", bufferedAtStart.get() >= 6000);
            onMain(() -> {
                assertTrue(playback.get().duration() >= 11000);
                playback.get().setPaused(true);
                position.set(playback.get().position());
            });
            Thread.sleep(500);
            onMain(() -> {
                assertTrue("Pause must hold the playback position",
                    Math.abs(playback.get().position() - position.get()) < 100);
                playback.get().seek(5000);
                playback.get().setPaused(false);
            });
            Thread.sleep(1500);
            onMain(() -> {
                assertTrue("Playback must advance after seeking", playback.get().position() >= 5500);
                assertTrue("Buffered position must follow the seek",
                    playback.get().bufferedPosition() >= playback.get().position());
            });
            assertTrue("Playback must complete", completed.await(20, TimeUnit.SECONDS));
            assertNull(error.get());
            assertEquals("Video size must reach the plugin", 1920, width.get());
        } finally {
            onMain(() -> { if (playback.get() != null) playback.get().release(); });
            output.close();
        }
    }

    private void onMain(Runnable action) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(action);
    }
}
