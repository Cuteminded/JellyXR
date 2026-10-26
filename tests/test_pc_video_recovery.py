"""Interrupt a paced 4K video connection while the separate audio connection continues."""

import argparse
import json
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import threading
import time


class RecoveryHandler(SimpleHTTPRequestHandler):
    lock = threading.Lock()
    video_connection = None
    stalled = False
    byte_rate = 1
    stall_after = 4
    stall_seconds = 2

    def log_message(self, *_args):
        pass

    def do_GET(self):
        with self.lock:
            if type(self).video_connection is None:
                type(self).video_connection = self.connection
        super().do_GET()

    def send_head(self):
        path = Path(self.translate_path(self.path))
        if not path.is_file():
            self.send_error(404)
            return None
        size = path.stat().st_size
        start, end = 0, size - 1
        byte_range = self.headers.get("Range")
        if byte_range:
            first, last = byte_range.removeprefix("bytes=").split("-", 1)
            start = int(first or 0)
            end = min(int(last), end) if last else end
        if start > end or start >= size:
            self.send_error(416)
            return None
        self.send_response(206 if byte_range else 200)
        self.send_header("Content-Type", self.guess_type(str(path)))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if byte_range:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        stream = path.open("rb")
        stream.seek(start)
        self.remaining = end - start + 1
        self.pace_video = start < size // 2
        return stream

    def copyfile(self, source, output):
        video = self.pace_video and self.connection is self.video_connection
        started = time.monotonic()
        sent = 0
        try:
            while self.remaining:
                chunk = source.read(min(self.remaining, 65536))
                if not chunk:
                    break
                output.write(chunk)
                self.remaining -= len(chunk)
                sent += len(chunk)
                if not video:
                    continue
                if not type(self).stalled and sent / self.byte_rate >= self.stall_after:
                    type(self).stalled = True
                    time.sleep(self.stall_seconds)
                    started += self.stall_seconds
                time.sleep(max(0, started + sent / self.byte_rate - time.monotonic()))
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--video", type=Path, help="Use an existing video with audio instead of generating 4K HEVC")
    parser.add_argument("--expect-buffer-free", action="store_true", help="Deliver at twice the bitrate and check read-ahead absorbs a short interruption")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    directory = project / "build" / "video-recovery"
    directory.mkdir(parents=True, exist_ok=True)
    video = args.video.resolve() if args.video else directory / "recovery.mp4"
    if not args.video:
        subprocess.run([str(args.ffmpeg.resolve()), "-v", "error", "-y", "-f", "lavfi", "-i",
                        "testsrc2=size=3840x2160:rate=30:duration=20", "-f", "lavfi", "-i",
                        "sine=frequency=440:duration=20", "-c:v", "hevc_nvenc", "-preset", "p1",
                        "-rc", "cbr", "-b:v", "12M", "-g", "60", "-c:a", "aac",
                        "-movflags", "+faststart", str(video)], check=True, timeout=90)
    probe = args.ffmpeg.resolve().with_name("ffprobe" + args.ffmpeg.suffix)
    metadata = json.loads(subprocess.check_output([str(probe), "-v", "error", "-show_format", "-show_streams", "-of", "json", str(video)]))
    assert any(stream["codec_type"] == "audio" for stream in metadata["streams"]), "The fixture must have audio"
    RecoveryHandler.byte_rate = video.stat().st_size / float(metadata["format"]["duration"])
    if args.expect_buffer_free:
        RecoveryHandler.byte_rate *= 2
        RecoveryHandler.stall_after = 4
        RecoveryHandler.stall_seconds = 1.5
    with ThreadingHTTPServer(("127.0.0.1", 0), partial(RecoveryHandler, directory=str(video.parent))) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            subprocess.run([str(args.godot.resolve()), "--path", str(project), "--xr-mode", "off",
                            "--rendering-method", "mobile", "--rendering-driver", "vulkan",
                            "--audio-driver", "Dummy", "--resolution", "640x360", "--script",
                            "tests/test_pc_video_recovery.gd", "--",
                            f"--video=http://127.0.0.1:{server.server_port}/{video.name}",
                            *(["--expect-buffer-free"] if args.expect_buffer_free else [])],
                           check=True, timeout=45)
            assert RecoveryHandler.stalled, "The video delivery interruption did not run"
        finally:
            server.shutdown()
            thread.join()
    print("Video interruption and audio synchronization recovery: PASS")


if __name__ == "__main__":
    main()
