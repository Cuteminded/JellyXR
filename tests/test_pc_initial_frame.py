"""Check Vulkan startup and paused seeking when video begins after audio."""

import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--ffmpeg', type=Path, required=True)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    project = args.project.resolve()
    output = project / 'build/initial-frame-tests'
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output) as directory:
        for offset in ['0', '0.042', '0.200']:
            video = Path(directory) / f'video-{offset}.mkv'
            subprocess.run(
                [str(args.ffmpeg.resolve()), '-v', 'error', '-itsoffset', offset,
                 '-i', str(project / 'tests/fixtures/stereo_test.mp4'),
                 '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo',
                 '-map', '0:v', '-map', '1:a', '-c:v', 'copy', '-c:a', 'pcm_s16le',
                 '-t', '8', '-y', str(video)], check=True, timeout=30,
            )
            result = subprocess.run(
                [str(args.godot.resolve()), '--xr-mode', 'off', '--path', str(project),
                 '--rendering-method', 'mobile', '--rendering-driver', 'vulkan',
                 '--audio-driver', 'Dummy', '--resolution', '640x360',
                 '--script', str(Path(__file__).with_suffix('.gd')), '--', str(video)],
                capture_output=True, text=True, timeout=30,
            )
            (output / f'offset-{offset}.log').write_text(result.stdout + result.stderr)
            if result.returncode:
                raise RuntimeError(f'First-frame offset {offset} failed:\n{result.stdout}{result.stderr}')
            print(f'Initial video offset {offset} seconds: PASS')


if __name__ == '__main__':
    main()
