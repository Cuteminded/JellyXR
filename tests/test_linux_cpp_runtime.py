"""Exercise shared C++ driver initialization from the Linux decoder thread."""

import argparse
import os
from pathlib import Path
import platform
import subprocess
import tempfile


DRIVER = r'''
#include <mutex>
#include <cstdio>
static std::once_flag initialized;
__attribute__((constructor)) static void initialize_driver() {
    std::call_once(initialized, [] {
        std::puts("Shared C++ driver initialization: PASS");
    });
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--compiler', default='c++')
    args = parser.parse_args()
    if platform.system() != 'Linux':
        parser.error('Run this integration test on Linux.')
    project = args.project.resolve()
    output = project / 'build/cpp-runtime-tests'
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output) as directory:
        directory = Path(directory)
        source = directory / 'driver.cpp'
        source.write_text(DRIVER)
        subprocess.run(
            [args.compiler, '-shared', '-fPIC', '-pthread', str(source),
             '-Wl,-soname,libcuda.so.1', '-o', str(directory / 'libcuda.so.1')],
            check=True, timeout=30,
        )
        environment = dict(os.environ)
        search_path = environment.get('LD_LIBRARY_PATH', '')
        environment['LD_LIBRARY_PATH'] = str(directory) + (os.pathsep + search_path if search_path else '')
        environment['GODOT_SILENCE_ROOT_WARNING'] = '1'
        result = subprocess.run(
            [str(args.godot.resolve()), '--headless', '--xr-mode', 'off', '--path', str(project),
             '--script', 'tests/test_pc_video.gd'],
            env=environment, capture_output=True, text=True, timeout=45,
        )
        log = result.stdout + result.stderr
        (output / 'driver-initialization.log').write_text(log)
        if result.returncode or 'Shared C++ driver initialization: PASS' not in log or 'PC video checks: PASS' not in log:
            raise RuntimeError(f'Driver initialization failed, exit {result.returncode}:\n{log}')
    print('Shared C++ driver initialization and playback: PASS')


if __name__ == '__main__':
    main()
