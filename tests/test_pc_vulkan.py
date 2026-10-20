"""Generate ten-bit fixtures and verify Vulkan colors, seeking, and audio timing."""

import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    output = project / "build" / "vulkan-tests"
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output) as directory:
        for matrix, full_range, audio in [("bt601", False, False), ("bt709", True, False), ("bt709", False, True)]:
            video = Path(directory) / "colors.mkv"
            command = [str(args.ffmpeg.resolve()), "-v", "error"]
            for color in ("red", "lime", "blue"):
                command += ["-f", "lavfi", "-i", f"color={color}:size=1920x1080:rate=30:duration=2"]
            if audio:
                command += ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=6"]
            target_range = "pc" if full_range else "tv"
            filters = (f"[0:v][1:v][2:v]concat=n=3:v=1:a=0,"
                       f"scale=in_color_matrix=bt601:out_color_matrix={matrix}:in_range=tv:out_range={target_range},"
                       "format=yuv420p10le[video]")
            command += ["-filter_complex", filters, "-map", "[video]", "-c:v", "ffv1", "-threads", "2",
                        "-color_range", target_range, "-colorspace", "bt709" if matrix == "bt709" else "smpte170m"]
            if audio:
                command += ["-map", "3:a", "-c:a", "pcm_s16le"]
            subprocess.run([*command, "-y", str(video)], check=True, timeout=60)
            subprocess.run([str(args.godot.resolve()), "--path", str(project), "--xr-mode", "off",
                            "--rendering-method", "mobile", "--rendering-driver", "vulkan",
                            "--audio-driver", "Dummy", "--resolution", "640x360",
                            "--script", "tests/test_pc_vulkan_video.gd", "--", f"--video={video}"],
                           check=True, timeout=45)
    print("Vulkan limited-range, full-range, and audio clock checks: PASS")


if __name__ == "__main__":
    main()
