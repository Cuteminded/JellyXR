#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -m)" in
    x86_64) arch=x86_64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) printf 'Unsupported Linux architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac
if [[ "$(uname -s)" != Linux ]]; then
    printf 'Run this script on Linux. Use build-pc-video.ps1 on Windows.\n' >&2
    exit 1
fi

for tool in cmake c++ pkg-config python3 curl unzip sha256sum; do
    command -v "$tool" >/dev/null || { printf 'Missing build dependency: %s\n' "$tool" >&2; exit 1; }
done
if ! pkg-config --atleast-version=2.0 mpv; then
    printf 'Install libmpv API 2 development files, such as libmpv-dev on Ubuntu.\n' >&2
    exit 1
fi
if ! pkg-config --exists 'libavcodec >= 60' 'libavformat >= 60' 'libavutil >= 58' 'libswscale >= 7'; then
    printf 'Install FFmpeg development files: libavcodec-dev libavformat-dev libavutil-dev libswscale-dev.\n' >&2
    exit 1
fi

dependency_root="$project_root/build/linux/deps"
build_root="$project_root/build/linux/$arch"
mkdir -p "$dependency_root" "$build_root"
touch "$project_root/build/.gdignore"

if [[ -z "${GODOT_CPP_PATH:-}" ]]; then
    archive="$dependency_root/godot-cpp.zip"
    if [[ ! -f "$archive" ]]; then
        curl --fail --location --retry 3 'https://github.com/godotengine/godot-cpp/archive/refs/tags/godot-4.5-stable.zip' -o "$archive.part"
        mv "$archive.part" "$archive"
    fi
    printf '%s  %s\n' '0316ea168750b5f4f1caea6457657a6c64241f890f78e2f042aee4be2b1085bf' "$archive" | sha256sum --check
    GODOT_CPP_PATH="$dependency_root/godot-cpp-godot-4.5-stable"
    if [[ ! -d "$GODOT_CPP_PATH" ]]; then
        unzip -q "$archive" -d "$dependency_root"
    fi
fi

cmake -S "$project_root/native/pc" -B "$build_root" -DCMAKE_BUILD_TYPE=Release "-DGODOT_CPP_PATH=$GODOT_CPP_PATH" "-DPython3_EXECUTABLE=$(command -v python3)"
cmake --build "$build_root" --parallel "${JOBS:-4}"

plugin_root="$project_root/addons/jellyxr_mpv"
mkdir -p "$plugin_root/bin"
cp "$build_root/jellyxr_mpv.linux.$arch.so" "$plugin_root/bin/"
cp "$project_root/native/pc/jellyxr_mpv.gdextension" "$plugin_root/"
mkdir -p "$build_root/licenses"
cp "$GODOT_CPP_PATH/LICENSE.md" "$build_root/licenses/godot-cpp.txt"
cp "$project_root/LICENSING.md" "$build_root/licenses/"
printf 'Architecture: %s\nlibmpv API: %s\ngodot-cpp: godot-4.5-stable\n' "$arch" "$(pkg-config --modversion mpv)" > "$build_root/build-info.txt"
printf 'PC video plugin built for Linux %s in %s\n' "$arch" "$plugin_root"
