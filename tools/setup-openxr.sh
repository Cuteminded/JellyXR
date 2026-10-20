#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version='5.1.0-stable'
expected_hash='6a838dbdf4115549e4511ebee0da9a5dcc8f9f6258d4cc2f2ee57a907a3e2911'
cache="$project_root/build/openxr"
destination="$project_root/addons/godotopenxrvendors"
marker="$destination/installed-version.txt"

mkdir -p "$cache"
touch "$project_root/build/.gdignore"
if [[ -f "$marker" && "$(< "$marker")" == "$version" ]]; then
    exit 0
fi

archive="$cache/vendors.zip"
if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 3 "https://github.com/GodotVR/godot_openxr_vendors/releases/download/$version/godotopenxrvendorsaddon.zip" -o "$archive.part"
    mv "$archive.part" "$archive"
fi
if ! printf '%s  %s\n' "$expected_hash" "$archive" | sha256sum --check; then
    printf 'OpenXR Vendors archive checksum does not match the pinned release: %s\n' "$archive" >&2
    exit 1
fi

release="$(mktemp -d "$cache/release.XXXXXX")"
trap 'rm -rf -- "$release"' EXIT
unzip -q "$archive" -d "$release"
addon="$release/asset/addons/godotopenxrvendors"
curl --fail --location --retry 3 "https://raw.githubusercontent.com/GodotVR/godot_openxr_vendors/$version/LICENSE" -o "$addon/LICENSE"
mkdir -p "$destination"
cp -R "$addon/." "$destination/"
printf '%s\n' "$version" > "$marker"
