import ctypes
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description='Verify LGPL playback library configurations.')
parser.add_argument('--bin-directory', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--platform', choices=['windows', 'linux'], default='windows')
args = parser.parse_args()
bin_dir = args.bin_directory.resolve()
def library_path(name):
    matches = list({path.resolve() for path in bin_dir.rglob(name)})
    if len(matches) != 1:
        raise RuntimeError(f'Expected one {name} in {bin_dir}, found {len(matches)}')
    return str(matches[0])


libraries = [('avcodec-62.dll', 'avcodec'), ('avformat-62.dll', 'avformat'),
             ('avutil-60.dll', 'avutil'), ('swscale-9.dll', 'swscale'),
             ('swresample-6.dll', 'swresample')]
if args.platform == 'linux':
    libraries = [(f'lib{prefix}.so*', prefix) for _, prefix in libraries]
report = {}
for library, prefix in libraries:
    dll = ctypes.CDLL(library_path(library))
    report[library] = {}
    for field in ['license', 'configuration']:
        function = getattr(dll, f'{prefix}_{field}')
        function.restype = ctypes.c_char_p
        report[library][field] = function().decode()
    if 'LGPL' not in report[library]['license']:
        raise RuntimeError(f'{library} does not report an LGPL license')
    if any(flag in report[library]['configuration'] for flag in ['--enable-gpl', '--enable-nonfree']):
        raise RuntimeError(f'{library} enables GPL or nonfree components')
mpv = ctypes.CDLL(library_path('libmpv-2.dll' if args.platform == 'windows' else 'libmpv.so*'))
mpv.mpv_create.restype = ctypes.c_void_p
mpv.mpv_set_option_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
mpv.mpv_initialize.argtypes = [ctypes.c_void_p]
mpv.mpv_get_property_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
mpv.mpv_get_property_string.restype = ctypes.c_void_p
mpv.mpv_free.argtypes = [ctypes.c_void_p]
mpv.mpv_terminate_destroy.argtypes = [ctypes.c_void_p]
handle = mpv.mpv_create()
for name, value in [(b'config', b'no'), (b'vo', b'null'), (b'ao', b'null'), (b'idle', b'yes')]:
    assert mpv.mpv_set_option_string(handle, name, value) >= 0
assert mpv.mpv_initialize(handle) >= 0
report['mpv'] = {}
for name in ['mpv-version', 'mpv-configuration', 'ffmpeg-version', 'license']:
    pointer = mpv.mpv_get_property_string(handle, name.encode())
    if pointer:
        report['mpv'][name] = ctypes.string_at(pointer).decode()
        mpv.mpv_free(pointer)
mpv.mpv_terminate_destroy(handle)
if '-Dgpl=false' not in report['mpv'].get('mpv-configuration', ''):
    raise RuntimeError('libmpv does not report -Dgpl=false')
if args.platform == 'windows':
    data = Path(library_path('libmpv-2.dll')).read_bytes()
    configurations = re.findall(rb'--prefix=[^\x00]+', data)
    embedded = sorted({value.decode('ascii') for value in configurations
                       if b'--enable-static' in value and b'--disable-shared' in value})
    if len(embedded) != 1:
        raise RuntimeError('Cannot identify the statically linked FFmpeg configuration in libmpv')
    if any(flag in embedded[0] for flag in ['--enable-gpl', '--enable-nonfree']):
        raise RuntimeError('The FFmpeg build inside libmpv enables GPL or nonfree components')
    report['mpv']['embedded-ffmpeg-configuration'] = embedded[0]
args.output.write_text(json.dumps(report, indent=2))
print('LGPL FFmpeg libraries and libmpv configuration: PASS')
