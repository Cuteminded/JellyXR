"""Compare Vulkan PQ/HLG tone mapping and the 3D screen against FFmpeg references."""

import argparse
from array import array
import math
from pathlib import Path
import subprocess
import tempfile


def pq_signal(nits):
    value = (nits / 10000) ** (2610 / 16384)
    return ((3424 / 4096 + 2413 / 128 * value) / (1 + 2392 / 128 * value)) ** (2523 / 32)


def hlg_signal(nits):
    value = (nits / 1000) ** (1 / 1.2)
    return math.sqrt(3 * value) if value <= 1 / 12 else 0.17883277 * math.log(12 * value - 0.28466892) + 0.55991073


def run(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--require-d3d11", action="store_true")
    parser.add_argument("--require-d3d12", action="store_true")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    output = project / "build" / "hdr-tests"
    output.mkdir(parents=True, exist_ok=True)
    ffmpeg = str(args.ffmpeg.resolve())
    with tempfile.TemporaryDirectory(dir=output) as directory:
        directory = Path(directory)
        for transfer, peak in [("pq", 1000), ("hlg", 1000), ("pq", 4000), ("sdr", 1000)]:
            levels = [0, .1, 1, 5, 18, 50, 100, 203, 400, 1000]
            signals = [pq_signal(nits) if transfer == "pq" else hlg_signal(nits) if transfer == "hlg" else nits / 1000 for nits in levels]
            pixels = array("H")
            row = array("H")
            for signal in signals:
                row.extend([round(64 + 876 * signal)] * 64)
            for _ in range(192):
                pixels.extend(row)
            pixels.extend([512] * (640 * 192 // 2))
            raw = directory / "levels.yuv"
            raw.write_bytes(pixels.tobytes())
            video = directory / "levels.mp4"
            reference = directory / "reference.png"
            trc = {"pq": "smpte2084", "hlg": "arib-std-b67", "sdr": "bt709"}[transfer]
            primaries = "bt709" if transfer == "sdr" else "bt2020"
            matrix = "bt709" if transfer == "sdr" else "bt2020nc"
            encoder = f"lossless=1:log-level=error:colorprim={primaries}:transfer={trc}:colormatrix={matrix}:max-cll={peak},100"
            run([ffmpeg, "-v", "error", "-f", "rawvideo", "-pixel_format", "yuv420p10le", "-video_size", "640x192",
                 "-framerate", "1", "-i", str(raw), "-c:v", "libx265", "-preset", "ultrafast", "-x265-params", encoder,
                 "-color_trc", trc, "-color_primaries", primaries, "-colorspace", matrix, "-y", str(video)])
            filters = "format=rgb24" if transfer == "sdr" else (
                "zscale=transfer=linear:npl=203,format=gbrpf32le,zscale=primaries=bt709,"
                f"tonemap=tonemap=hable:desat=0:peak={peak / 203},"
                "zscale=transfer=iec61966-2-1:range=full,format=rgb24")
            run([ffmpeg, "-v", "error", "-i", str(video), "-vf", filters, "-frames:v", "1", "-y", str(reference)])
            command = [str(args.godot.resolve()), "--path", str(project), "--xr-mode", "off", "--audio-driver", "Dummy",
                            "--rendering-method", "mobile", "--rendering-driver", "vulkan", "--resolution", "640x360",
                            "--script", "tests/test_pc_hdr_video.gd", "--", str(video), str(reference), transfer]
            if args.require_d3d11:
                command.append("--require-d3d11")
            if args.require_d3d12:
                command.append("--require-d3d12")
            subprocess.run(command, check=True, timeout=30)
    print("PQ, HLG, mastering peaks, and SDR screen checks: PASS")


if __name__ == "__main__":
    main()
