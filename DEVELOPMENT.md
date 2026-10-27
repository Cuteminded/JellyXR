# Development

jellyXR uses Godot 4.7.2 and OpenXR. Install Godot and its matching export templates before building. Run the commands below from the project root, with `godot` on your `PATH`.

Build the native video plugin for your platform before importing the project. Close jellyXR before rebuilding the plugin.

## Build the Quest APK

### Requirements

- JDK 17.
- Android SDK platforms 35 and 36, with build tools 36.1.0.
- Gradle 8.10.2.

Set the Android SDK and Java SDK paths in Godot's editor settings, accept the Android SDK licences, and select **Project > Install Android Build Template**.

On Linux, install `curl`, `unzip`, and `sha256sum`, then run:

```sh
export JAVA_HOME='/path/to/jdk-17'
export ANDROID_HOME='/path/to/android-sdk'
GODOT='/path/to/godot' GRADLE='/path/to/gradle' bash tools/build-android.sh
```

Omit `GODOT` and `GRADLE` if both tools are on your `PATH`. The script also accepts `ANDROID_SDK_ROOT` when `ANDROID_HOME` is unset.

On Windows, use PowerShell:

```powershell
./tools/build-android.ps1 -Godot 'C:/tools/godot.exe' `
  -Gradle 'C:/tools/gradle/bin/gradle.bat' `
  -AndroidSdk 'C:/tools/android-sdk' -JavaHome 'C:/tools/jdk-17'
```

The scripts build the Android plugin and export `dist/jellyxr-android.apk`. They download and verify Godot OpenXR Vendors for Quest passthrough support.

To build through GitHub Actions, select **Actions > Build Android APK > Run workflow**. Each run creates a new debug signing key. If it differs from the installed APK's key, uninstall the old build first. Uninstalling removes saved settings and sign-in.

## Build on Windows

Install Python 3.12, then build the PC plugin and export the app:

```powershell
./tools/build-pc-video.ps1 -Python 'C:/path/to/python.exe'
New-Item -ItemType Directory -Force dist/windows
godot --headless --xr-mode off --path . --editor --import --quit
godot --headless --xr-mode off --path . --export-release 'Windows' dist/windows/jellyxr.exe
```

The plugin script downloads pinned build tools and libraries into `build/desktop`, verifies their checksums, and generates `addons/jellyxr_mpv`. You do not need a system-wide compiler installation.

The output is in `dist/windows`. Keep all exported files together. Include the third-party licences when distributing a build, following the copy steps in the [Windows workflow](.github/workflows/build-windows.yml).

## Build on Linux x64 or ARM64

Build natively on the target architecture. On Ubuntu 24.04, install the dependencies and build the PC plugin:

```sh
sudo apt-get install build-essential cmake pkg-config python3 curl unzip libmpv-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
bash tools/build-pc-video.sh
godot --headless --xr-mode off --path . --editor --import --quit
```

The script detects x64 or ARM64 and generates `addons/jellyxr_mpv`. It downloads and verifies godot-cpp, and uses the system libmpv and FFmpeg development packages. FFmpeg 6 or newer is required.

Export for x64:

```sh
mkdir -p dist/linux-x86_64
godot --headless --xr-mode off --path . --export-release 'Linux x64' dist/linux-x86_64/jellyxr.x86_64
```

Export for ARM64:

```sh
mkdir -p dist/linux-arm64
godot --headless --xr-mode off --path . --export-release 'Linux ARM64' dist/linux-arm64/jellyxr.arm64
```

Keep the executable and native decoder `.so` file together.

### Package an AppImage

Install `patchelf`. Copy the licences into the export folder as shown below for x64. Replace `x86_64` with `arm64` for an ARM64 build.

```sh
cp -r build/linux/x86_64/licenses dist/linux-x86_64/
cp LICENSE dist/linux-x86_64/licenses/jellyxr.txt
cp LICENSING.md dist/linux-x86_64/licenses/
bash tools/package-linux-appimages.sh x86_64
```

The packager bundles decoder libraries and licence notices. It needs network access to download appimagetool and its AppImage runtime. The output is `dist/jellyxr-linux-<arch>.AppImage`. The host supplies graphics drivers and OpenXR.

## Run the app during development

Import `project.godot` into Godot, or launch the desktop library preview:

```sh
godot --path . --xr-mode off
```

Desktop preview supports sign-in and library browsing. Use a headset for video playback in the app.

Windows and Linux default to Vulkan and fall back to OpenGL if Vulkan cannot initialize. To select OpenGL manually:

```sh
godot --path . --rendering-method gl_compatibility
```

For VR, connect your headset and start its OpenXR runtime before launching. See [installation](INSTALLATION.md) for runtime setup and [usage](USAGE.md) for controls.

## Run the core and HTTP tests

Build the native plugin and import the project before running tests:

```sh
godot --headless --xr-mode off --path . --editor --import --quit
godot --headless --xr-mode off --path . --script tests/test_core.gd
godot --headless --xr-mode off --path . --script tests/test_360_video.gd
godot --headless --xr-mode off --path . --script tests/test_http.gd
godot --headless --xr-mode off --path . --script tests/test_autoplay.gd
godot --headless --xr-mode off --path . --script tests/test_player_return.gd
godot --headless --xr-mode off --path . --script tests/test_player_tooltips.gd
godot --headless --xr-mode off --path . --script tests/test_player_loading.gd
godot --headless --xr-mode off --path . --script tests/test_photos.gd
```

## Test PC video

These tests work on Windows and Linux. The examples use Windows paths. On Linux, use `python3` and replace the executable paths. The Python video tests need FFmpeg. Keep `ffprobe` beside the FFmpeg executable for the buffering tests.

### Decoder and streaming

```powershell
godot --headless --xr-mode off --path . --script tests/test_pc_video.gd
python tests/test_pc_streaming.py --godot 'C:/path/to/godot_console.exe'
```

### GPU playback and transitions

Run these with a graphics context:

```powershell
godot --xr-mode off --rendering-method gl_compatibility --path . --script tests/test_pc_gpu_video.gd
godot --xr-mode off --rendering-method mobile --rendering-driver vulkan --path . --script tests/test_pc_gpu_video.gd
godot --xr-mode off --rendering-method gl_compatibility --path . --script tests/test_pc_video_transitions.gd
godot --xr-mode off --rendering-method mobile --rendering-driver vulkan --path . --script tests/test_pc_video_transitions.gd
godot --xr-mode off --rendering-method mobile --rendering-driver vulkan --path . --script tests/test_pc_yuv_material.gd
python tests/test_pc_vulkan.py --godot 'C:/path/to/godot_console.exe' --ffmpeg 'C:/path/to/ffmpeg.exe'
python tests/test_pc_hdr.py --godot 'C:/path/to/godot_console.exe' --ffmpeg 'C:/path/to/ffmpeg.exe'
python tests/test_pc_streaming.py --godot 'C:/path/to/godot_console.exe' --vulkan
```

The transition test checks the black screen before playback and after stopping, then checks that a reopened video becomes visible. The Vulkan and HDR tests generate video fixtures and check color conversion, including HDR-to-SDR tone mapping.

PC Vulkan playback uploads the decoded YUV planes and samples them directly in the video material. Color conversion and HDR tone mapping run while drawing the screen or panorama, without a full-resolution RGBA intermediate texture. Hardware frames still pass through system memory before upload. OpenGL and software playback use the RGB material path. The YUV material test checks decoder padding, rotation, and stereo eye boundaries.

### Performance

Use a video long enough for the sample plus one second of warm-up:

```powershell
godot --xr-mode off --rendering-method mobile --rendering-driver vulkan --path . --script tests/test_pc_video_performance.gd -- --video='C:/videos/8k.mp4' --seconds=20 --minimum-fps=57
```

The test reports presentation rate, dropped frames, decoder and transfer timings, and main-loop frame times. It does not measure SteamVR performance.

### Buffering and recovery

Supply a video with audio and at least 20 seconds of content:

```powershell
python tests/test_pc_video_recovery.py --godot 'C:/path/to/godot_console.exe' --ffmpeg 'C:/path/to/ffmpeg.exe' --video 'C:/videos/8k-with-audio.mp4'
python tests/test_pc_video_recovery.py --godot 'C:/path/to/godot_console.exe' --ffmpeg 'C:/path/to/ffmpeg.exe' --video 'C:/videos/8k-with-audio.mp4' --expect-buffer-free
```

The first command checks recovery, audio synchronization, and a manual pause during interrupted delivery. The second checks that read-ahead absorbs a short interruption without buffering. Omitting `--video` generates a 4K HEVC fixture and requires FFmpeg's NVIDIA NVENC encoder.

### Headset playback

Start SteamVR and connect your headset, then run:

```sh
godot --rendering-method mobile --rendering-driver vulkan --path . --script tests/test_steamvr_video.gd
```

The test loops a labelled stereo clip for two minutes. Close one eye at a time to check the LEFT and RIGHT labels. Press A to open playback controls. When signed in, press B to browse the library during playback. Replace the Vulkan arguments with `--rendering-method gl_compatibility` to test OpenGL.

Desktop and headless tests do not verify headset tracking, controller behavior, stereo output, or playback performance in VR.

### Playback logs

To record a Vulkan playback log, run the exported app with SteamVR active:

```powershell
New-Item -ItemType Directory -Force logs | Out-Null
$env:JELLYXR_VIDEO_STATS = '1'
.\dist\windows\jellyxr.exe --rendering-method mobile --rendering-driver vulkan --log-file (Join-Path $PWD 'logs/vulkan-playback.log')
```

Set `JELLYXR_PC_RENDERER=software` to force the software fallback for troubleshooting. Remove access tokens and private server details before sharing logs.

## Check 180° and 360° rendering

```sh
godot --xr-mode off --path . --script tests/capture_360.gd
```

This renders synthetic panoramas to check top-bottom eye selection and the dark area behind a 180° video. It saves previews in `dist` and does not test Android textures or headset stereo output.

## GitHub Actions

The [Android](.github/workflows/build-android.yml), [Windows](.github/workflows/build-windows.yml), and [Linux](.github/workflows/build-linux.yml) workflows build and upload their platform packages. They need no repository secrets and keep artifacts for 14 days. Run the playback tests separately with the commands above.

## Code layout

- `scripts/jellyfin` handles the server API and requests playback streams.
- `scripts/vr` handles environments, controller pointing, and recentering.
- `scripts/player` selects Android playback or PC VR playback.
- `native/android` contains the Android decoder.
- `native/pc` contains the libmpv OpenGL renderer and FFmpeg Vulkan decoder.
- `scripts/core` contains screen settings and stereo geometry.
