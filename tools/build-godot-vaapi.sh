#!/usr/bin/env bash
set -euo pipefail
source_root="${1:?Repository path required}"
output_root="${2:?Output directory required}"
work_root="${3:-$source_root/build/linux/godot-vaapi}"
arch="${4:-$(uname -m)}"
case "$arch" in
    x86_64) ;;
    aarch64|arm64) arch=arm64 ;;
    *) printf 'Unsupported Linux architecture: %s\n' "$arch" >&2; exit 1 ;;
esac
mkdir -p "$work_root" "$output_root"
work_root="$(realpath "$work_root")"
output_root="$(realpath "$output_root")"
engine="$work_root/godot"
if [[ ! -d "$engine" ]]; then
    archive="$work_root/godot-4.7.2.tar.gz"
    curl --fail --location --retry 3 --retry-all-errors \
        https://codeload.github.com/godotengine/godot/tar.gz/refs/tags/4.7.2-stable -o "$archive"
    mkdir "$engine"
    tar -xf "$archive" -C "$engine" --strip-components=1
fi
if [[ ! -f "$engine/.jellyxr-vaapi-patched" ]]; then
    python3 "$source_root/tools/prepare-godot-vaapi.py" "$engine"
    touch "$engine/.jellyxr-vaapi-patched"
fi
cd "$engine"
scons platform=linuxbsd target=template_release arch="$arch" dev_build=no \
    debug_symbols=no use_static_cpp=no -j"${JOBS:-4}" > "$output_root/godot-build.log" 2>&1
cp "bin/godot.linuxbsd.template_release.$arch" "$output_root/godot-vaapi.$arch"
cp LICENSE.txt "$output_root/godot-license.txt"
cp COPYRIGHT.txt "$output_root/godot-copyright.txt"
