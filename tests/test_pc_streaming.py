"""Run native playback checks against an authenticated local HTTP server."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import threading


AUTHORIZATION = 'MediaBrowser Client="Jellyframe", Token="test-token"'


class VideoHandler(SimpleHTTPRequestHandler):
    authenticated_requests = 0
    rejected_requests = 0

    def log_message(self, *_args):
        pass

    def send_head(self):
        if self.headers.get("Authorization") != AUTHORIZATION:
            type(self).rejected_requests += 1
            self.send_error(401)
            return None
        type(self).authenticated_requests += 1
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
        return stream

    def copyfile(self, source, output):
        try:
            while self.remaining:
                chunk = source.read(min(self.remaining, 65536))
                if not chunk:
                    break
                output.write(chunk)
                self.remaining -= len(chunk)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--hls-directory", type=Path)
    graphics = parser.add_mutually_exclusive_group()
    graphics.add_argument("--opengl", action="store_true", help="Test OpenGL GPU playback in a window")
    graphics.add_argument("--vulkan", action="store_true", help="Test Vulkan GPU playback in a window")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    media = [(project / "tests/fixtures", "stereo_test.mp4")]
    if args.hls_directory:
        media.append((args.hls_directory.resolve(), "stream.m3u8"))
    for directory, name in media:
        handler = partial(VideoHandler, directory=str(directory))
        with ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                result = subprocess.run(
                    [args.godot, *(["--resolution", "640x360", "--rendering-method", "mobile", "--rendering-driver", "vulkan"]
                                  if args.vulkan else ["--resolution", "640x360", "--rendering-method", "gl_compatibility"]
                                  if args.opengl else ["--headless"]),
                     "--xr-mode", "off", "--path", str(project),
                     "--script", "tests/test_pc_video.gd", "--",
                     f"--video=http://127.0.0.1:{server.server_port}/{name}",
                     f"--auth={AUTHORIZATION}",
                     f"--expect-renderer={'vulkan' if args.vulkan else 'opengl' if args.opengl else 'software'}"],
                    timeout=45, check=False,
                )
                if result.returncode:
                    raise SystemExit(result.returncode)
            finally:
                server.shutdown()
                thread.join()
    assert VideoHandler.authenticated_requests > 0, "The decoder must request HTTP media"
    assert VideoHandler.rejected_requests == 0, "Authorization must survive commas and quotes"
    print("Authenticated PC streaming checks: PASS")


if __name__ == "__main__":
    main()
