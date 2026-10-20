# Build from source

Jellyframe uses Godot and OpenXR, with an Android video plugin and a shared libmpv video plugin for Windows and Linux.

## Android build requirements

- Godot 4.7.2 with matching Android export templates.
- JDK 17.
- Android SDK platforms 35 and 36, with build tools 36.1.0.
- Gradle 8.10.2.

The Android plugin compiles against Godot's 4.5.1 Android API and uses the Compatibility renderer because video playback requires an external OpenGL texture. Jellyframe uses a fixed Android codec profile and does not check which codecs the headset can decode, while Windows and Linux use libmpv for PC VR playback.

## Build the Quest APK

To build a Quest 3 debug APK, open **Actions > Build Android APK > Run workflow**, which builds the native video plugin, exports the APK, and checks its signature. The workflow needs no repository secrets and keeps the APK artifact for 14 days.

Each workflow run creates a new debug signing key, so an installed APK signed with a different key must be uninstalled before you can install the new build. Uninstalling removes saved settings and sign-in, and these APKs are test builds rather than store releases.

To build locally:

1. Install the build requirements and accept the Android SDK licences.
2. Set the Android SDK and Java SDK paths in Godot's editor settings.
3. Select Project > Install Android Build Template.
4. Run the build script with the paths to your installed tools:

On Linux, install `curl`, `unzip`, and `sha256sum`, then run:

```sh
export JAVA_HOME='/path/to/jdk-17'
export ANDROID_HOME='/path/to/android-sdk'
GODOT='/path/to/godot' GRADLE='/path/to/gradle' bash tools/build-android.sh
```

If `godot` and `gradle` are on your `PATH`, omit the `GODOT` and `GRADLE` overrides. The script also accepts `ANDROID_SDK_ROOT` when `ANDROID_HOME` is unset. The Android workflow uses this Bash script.

On Windows, use PowerShell:

```powershell
./tools/build-android.ps1 -Godot 'C:/tools/godot.exe' `
  -Gradle 'C:/tools/gradle/bin/gradle.bat' `
  -AndroidSdk 'C:/tools/android-sdk' -JavaHome 'C:/tools/jdk-17'
```

The script creates `dist/jellyframe-android.apk` for installation on your headset and downloads Godot OpenXR Vendors 5.1.0 for Quest passthrough support. It checks the archive's SHA-256 checksum and includes the vendor licences in the APK, keeping the downloaded addon in the ignored `addons/godotopenxrvendors` directory.

## Build and test on Windows

To build the Windows SteamVR app locally, install Godot 4.7.2 with matching export templates and Python 3.12. Build the PC plugin before importing or exporting the project:

```powershell
./tools/build-pc-video.ps1 -Python 'C:/path/to/python.exe'
New-Item -ItemType Directory -Force dist/windows
godot --headless --xr-mode off --path . --editor --import --quit
godot --headless --xr-mode off --path . --export-release 'Windows SteamVR' dist/windows/jellyframe.exe
```

The plugin build script downloads pinned CMake, LLVM-MinGW, godot-cpp, and libmpv archives into `build/desktop`, verifies their checksums, and generates `addons/jellyframe_mpv` without requiring a system-wide compiler installation. Close running Jellyframe instances before rebuilding; Git ignores the generated plugin, and Android exports exclude it.

The Windows workflow builds the plugin, exports the app, verifies the output files, and uploads the build. Tests run separately using the commands below. Build commands disable OpenXR, while the exported app keeps it enabled. The workflow needs no repository secrets, and GitHub keeps its build artifacts for 14 days.

After building the PC plugin, run its decoder tests without a headset:

```powershell
godot --headless --xr-mode off --path . --script tests/test_pc_video.gd
python tests/test_pc_streaming.py --godot 'C:/path/to/godot_console.exe'
```

With SteamVR and your headset running, test the stereo screen and controllers:

```powershell
godot --path . --script tests/test_steamvr_video.gd
```

The headset test loops a labelled stereo clip for two minutes so you can close one eye at a time to check the LEFT and RIGHT labels, then press A or B to open the playback controls. The decoder tests cover resume, pause, seeking, completion, reopening, and errors.

Import `project.godot` into Godot, or run:

```powershell
godot --path . --xr-mode off
```

Connect to your Jellyfin server to browse your library in desktop mode, which does not save sessions or play videos.

## Build Linux x64 or ARM64

Build natively on the target architecture with Godot 4.7.2 and matching export templates. On Ubuntu, install the build dependencies:

```sh
sudo apt-get install build-essential cmake pkg-config python3 curl unzip libmpv-dev
bash tools/build-pc-video.sh
godot --headless --xr-mode off --path . --editor --import --quit
```

The script detects x64 or ARM64, downloads and verifies the godot-cpp bindings, and builds the matching plugin in `addons/jellyframe_mpv` using the system libmpv development package. Close Jellyframe before rebuilding its plugin.

For x64:

```sh
mkdir -p dist/linux-x86_64
godot --headless --xr-mode off --path . --export-release 'Linux x64 OpenXR' dist/linux-x86_64/jellyframe-opengl.x86_64
godot --headless --xr-mode off --path . --export-release 'Linux x64 Vulkan' dist/linux-x86_64/jellyframe-vulkan.x86_64
```

For ARM64:

```sh
mkdir -p dist/linux-arm64
godot --headless --xr-mode off --path . --export-release 'Linux ARM64 OpenXR' dist/linux-arm64/jellyframe-opengl.arm64
godot --headless --xr-mode off --path . --export-release 'Linux ARM64 Vulkan' dist/linux-arm64/jellyframe-vulkan.arm64
```

The OpenXR presets select OpenGL Compatibility. The Vulkan presets select the Mobile renderer and Vulkan through custom feature tags. Both executables embed their own resources and share the native decoder library in the output folder.

**Build Linux** uses native `ubuntu-24.04` and `ubuntu-24.04-arm` runners. Each job builds its plugin, exports the OpenGL and Vulkan apps, checks output files and decoder dependencies, and packages both library variants. Tests run separately using the commands below. The artifacts contain tar archives that preserve Linux executable permissions; GitHub keeps them for 14 days, and the workflow needs no repository secrets.

The decoder and headset tests in [Build and test on Windows](#build-and-test-on-windows) also work on Linux, where you should use `python3` for the HTTP streaming test and pass the path to your Linux Godot executable.

## Run the core and HTTP tests

```powershell
godot --headless --xr-mode off --path . --editor --import --quit
godot --headless --xr-mode off --path . --script tests/test_core.gd
godot --headless --xr-mode off --path . --script tests/test_360_video.gd
godot --headless --xr-mode off --path . --script tests/test_http.gd
godot --headless --xr-mode off --path . --script tests/test_autoplay.gd
godot --headless --xr-mode off --path . --script tests/test_player_return.gd
godot --headless --xr-mode off --path . --script tests/test_player_tooltips.gd
```

## Check 180° and 360° rendering

To render synthetic panoramas, check top-bottom eye selection, and check that the view behind a 180° video stays dark on desktop:

```powershell
godot --xr-mode off --path . --script tests/capture_360.gd
```

The check tests the PC shader with a generated texture and saves panorama and settings previews in `dist`, without enabling desktop video playback. It cannot validate headset tracking, Android textures, or stereo output in a headset.

## Code layout

- `scripts/jellyfin` handles the server API and requests playback streams.
- `scripts/vr` handles environments, controller pointing, and recentering.
- `scripts/player` selects Android playback or PC VR playback.
- `native/android` contains the Android decoder.
- `native/pc` contains the libmpv PC decoder.
- `scripts/core` contains screen settings and stereo geometry.
