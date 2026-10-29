#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
dependency_root="$project_root/build/linux/playback"
prefix="$dependency_root/prefix"
sources="$dependency_root/sources"
mkdir -p "$prefix" "$sources" "$dependency_root/licenses"

fetch_source() {
    local name="$1" url="$2" checksum="$3" archive="$sources/$1"
    if [[ ! -f "$archive" ]]; then
        curl --fail --location --retry 3 "$url" -o "$archive.part"
        mv "$archive.part" "$archive"
    fi
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check
    if [[ ! -d "$sources/$name.src" ]]; then
        mkdir "$sources/$name.src"
        tar -xf "$archive" -C "$sources/$name.src" --strip-components=1
    fi
}

fetch_source ffmpeg.tar.xz https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz 7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3
fetch_source mpv.tar.gz https://codeload.github.com/mpv-player/mpv/tar.gz/refs/tags/v0.41.0 ee21092a5ee427353392360929dc64645c54479aefdb5babc5cfbb5fad626209
fetch_source nv-codec-headers.tar.gz https://codeload.github.com/FFmpeg/nv-codec-headers/tar.gz/refs/tags/n13.0.19.0 86d15d1a7c0ac73a0eafdfc57bebfeba7da8264595bf531cf4d8db1c22940116

export PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/lib/$(gcc -dumpmachine)/pkgconfig"
export LD_LIBRARY_PATH="$prefix/lib:$prefix/lib/$(gcc -dumpmachine)"
make -C "$sources/nv-codec-headers.tar.gz.src" PREFIX="$prefix" install
cd "$sources/ffmpeg.tar.xz.src"
./configure --prefix="$prefix" --enable-shared --disable-static --disable-gpl --disable-nonfree \
    --enable-gnutls --enable-libdav1d --enable-ffnvcodec --disable-doc --disable-debug
make -j"${JOBS:-4}"
make install
cp COPYING.LGPLv2.1 "$dependency_root/licenses/ffmpeg-lgpl.txt"
cd "$sources/mpv.tar.gz.src"
setup_options=()
if [[ -f "$dependency_root/mpv-build/build.ninja" ]]; then setup_options+=(--reconfigure); fi
meson setup "${setup_options[@]}" "$dependency_root/mpv-build" --prefix="$prefix" \
    -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dlua=luajit -Djavascript=disabled --buildtype=release
meson compile -C "$dependency_root/mpv-build" -j "${JOBS:-4}"
meson install -C "$dependency_root/mpv-build"
cp LICENSE.LGPL "$dependency_root/licenses/mpv-lgpl.txt"
cp Copyright "$dependency_root/licenses/mpv-copyright.txt"
mkdir -p "$dependency_root/licenses/nv-codec-headers"
cp "$sources/nv-codec-headers.tar.gz.src/include/ffnvcodec/"*.h "$dependency_root/licenses/nv-codec-headers/"
for library in "$prefix"/lib/*.so.* "$prefix"/lib/*/*.so.*; do
    if [[ -f "$library" && ! -L "$library" ]]; then
        patchelf --force-rpath --set-rpath '$ORIGIN:$ORIGIN/..' "$library"
    fi
done
python3 "$project_root/tools/inspect-playback-libraries.py" --platform linux --bin-directory "$prefix" --output "$dependency_root/library-report.json"
