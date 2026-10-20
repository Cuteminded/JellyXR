#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
arch="${1:?Usage: bash tools/package-linux-appimages.sh x86_64|arm64}"
case "$arch" in
    x86_64)
        appimage_arch=x86_64
        tool_hash=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
        ;;
    arm64)
        appimage_arch=aarch64
        tool_hash=f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158
        ;;
    *) printf 'Unsupported architecture: %s\n' "$arch" >&2; exit 1 ;;
esac

for tool in curl sha256sum python3 unzip patchelf; do
    command -v "$tool" >/dev/null || { printf 'Missing dependency: %s\n' "$tool" >&2; exit 1; }
done

cache="$project_root/build/appimage"
mkdir -p "$cache"
touch "$project_root/build/.gdignore"
appimagetool="$cache/appimagetool-1.9.1-$appimage_arch.AppImage"
if [[ ! -f "$appimagetool" ]]; then
    curl --fail --location --retry 3 "https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-$appimage_arch.AppImage" -o "$appimagetool.part"
    mv "$appimagetool.part" "$appimagetool"
fi
printf '%s  %s\n' "$tool_hash" "$appimagetool" | sha256sum --check
chmod +x "$appimagetool"

staging="$(mktemp -d "$cache/staging-$arch.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
python3 tools/bundle-linux-libraries.py --input-directory "dist/linux-$arch" --output-directory "$staging/bundle" --arch "$arch"

appdir="$staging/Jellyframe.AppDir"
mkdir -p "$appdir/usr/bin"
cp -a "$staging/bundle/." "$appdir/usr/bin/"
cat > "$appdir/AppRun" <<EOF
#!/bin/sh
appdir=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
exec "\$appdir/usr/bin/jellyframe.$arch" "\$@"
EOF
chmod +x "$appdir/AppRun"
cat > "$appdir/jellyframe.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Jellyframe
Exec=AppRun
Icon=jellyframe
Categories=AudioVideo;Player;
Terminal=false
EOF
cp assets/logo/jellyframe-logo.png "$appdir/jellyframe.png"
ln -s jellyframe.png "$appdir/.DirIcon"
output="$project_root/dist/jellyframe-linux-$arch.AppImage"
ARCH="$appimage_arch" "$appimagetool" --appimage-extract-and-run "$appdir" "$output"
[[ -s "$output" ]]
chmod +x "$output"
