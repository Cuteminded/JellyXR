#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot="${GODOT:-godot}"
gradle="${GRADLE:-gradle}"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]] ||
    fail 'Set JAVA_HOME to your JDK 17 installation.'
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[[ -n "$ANDROID_HOME" && -d "$ANDROID_HOME" ]] ||
    fail 'Set ANDROID_HOME to your Android SDK directory.'
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME

for tool in "$godot" "$gradle" curl unzip sha256sum; do
    command -v "$tool" >/dev/null || fail "Missing build dependency: $tool"
done
godot="$(command -v "$godot")"
gradle="$(command -v "$gradle")"
[[ "$godot" = /* ]] || godot="$PWD/$godot"
[[ "$gradle" = /* ]] || gradle="$PWD/$gradle"

cd "$project_root"
[[ -f android/build/gradlew ]] ||
    fail 'Install the Android build template in Godot before building.'

printf 'Installing OpenXR vendors...\n'
bash tools/setup-openxr.sh

printf 'Building the Android video plugin...\n'
"$gradle" -p native :android:stagePlugin

printf 'Importing the Godot project...\n'
"$godot" --headless --xr-mode off --path . --editor --import --quit

printf 'Exporting the Quest 3 debug APK...\n'
mkdir -p dist
"$godot" --headless --xr-mode off --path . --export-debug 'Quest 3' dist/jellyxr-android.apk
[[ -s dist/jellyxr-android.apk ]] || fail 'Godot did not produce a nonempty APK.'
printf 'Android APK built at %s/dist/jellyxr-android.apk\n' "$project_root"
