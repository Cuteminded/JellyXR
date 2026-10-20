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

To build the Windows app locally, install Godot 4.7.2 with matching export templates and Python 3.12. Build the PC plugin before importing or exporting the project:

```powershell
./tools/build-pc-video.ps1 -Python 'C:/path/to/python.exe'
New-Item -ItemType Directory -Force dist/windows
godot --headless --xr-mode off --path . --editor --import --quit
godot --headless --xr-mode off --path . --export-release 'Windows' dist/windows/jellyframe.exe
```

The plugin build script downloads pinned CMake, LLVM-MinGW, godot-cpp, libmpv, and FFmpeg archives into `build/desktop`, verifies their checksums, and generates `addons/jellyframe_mpv` without requiring a system-wide compiler installation. Close running Jellyframe instances before rebuilding; Git ignores the generated plugin, and Android exports exclude it.

The Windows workflow builds the plugin, exports the app, verifies the output files, and uploads the build. Tests run separately using the commands below. Build commands disable OpenXR, while the exported app keeps it enabled. The workflow needs no repository secrets, and GitHub keeps its build artifacts for 14 days.

After building the PC plugin, run its decoder tests without a headset:

```powershell
godot --headless --xr-mode off --path . --script tests/test_pc_video.gd
python tests/test_pc_streaming.py --godot 'C:/path/to/godot_console.exe'
```

Run GPU playback checks with a graphics context:

```powershell
godot --xr-mode off --rendering-method gl_compatibility --path . --script tests/test_pc_gpu_video.gd
godot --xr-mode off --rendering-method mobile --rendering-driver vulkan --path . --script tests/test_pc_gpu_video.gd
python tests/test_pc_vulkan.py --godot 'C:/path/to/godot_console.exe' --ffmpeg 'C:/path/to/ffmpeg.exe'
python tests/test_pc_hdr.py --godot 'C:/path/to/godot_console.exe' --ffmpeg 'C:/path/to/ffmpeg.exe'
python tests/test_pc_streaming.py --godot 'C:/path/to/godot_console.exe' --vulkan
```

The Vulkan test generates ten-bit video fixtures and checks BT.601 limited-range and BT.709 full-range colors, paused seeks, completion, and playback with audio. Pass `--video=<path>` and `--size=7680x4320` to `test_pc_gpu_video.gd` to check an 8K source and reopening at 1080p. These checks do not measure sustained frame rate or verify headset playback.

OpenGL keeps its libmpv renderer and shared GPU textures. Vulkan uses a separate FFmpeg decoder and a compute shader on Godot's main Vulkan device. Native NV12, P010, and planar 4:2:0 frames keep their original plane layout; other formats are converted to ten-bit planar data. Windows tries CUDA/NVDEC before D3D11VA, while Linux tries VA-API or CUDA. CUDA downloads go directly into reusable pinned upload buffers.

A reader thread buffers compressed video packets independently of decoding, up to four seconds, 128 MiB, or 512 packets. After video falls behind, audio waits for video to catch up and for one second of compressed video to accumulate, unless the reader reaches the end or the buffer limit. Seeking clears queued packets and flushes the decoder. Decoding and downloads run on another worker; uploads are queued through Godot's render thread, with one upload scheduled at a time. Uploads still share the renderer's frame budget. Decoded planes pass through system memory, so this is not a zero-copy backend.

Desktop RenderingDevice settings allow up to 512 MiB of staging buffers and use larger upload regions to reduce stalls with 8K ten-bit frames. The engine allocates this memory as needed. OpenGL and Android Compatibility rendering do not use these buffers.

PQ and HLG video use Hable tone mapping to SDR, using mastering or content-light metadata when available and a 1,000-nit default otherwise. The HDR test compares gray patches with FFmpeg's reference conversion and checks their brightness through the actual 3D video material. HDR output and display calibration are not supported.

Measure presentation rate and frame times with a source long enough for the requested sample, including one second of warm-up:

```powershell
godot --xr-mode off --rendering-method mobile --rendering-driver vulkan --path . --script tests/test_pc_video_performance.gd -- --video='C:/videos/8k.mp4' --seconds=20 --minimum-fps=57
```

The result reports presented frames per second, dropped frames, decoder and transfer timings, and main-loop frame times. The default source is the locally generated `build/gpu-worker/8k-av1-test.mp4`; supply your own file on a fresh checkout. This windowed benchmark does not establish SteamVR performance. During ordinary playback, the startup log identifies the renderer, codec, hardware device, HDR transfer, and backend version. Set `JELLYFRAME_VIDEO_STATS=1` to log counters every five seconds. Isolated corrupt video packets are skipped; repeated errors still trigger the software fallback.

For videos with audio, libmpv opens the source separately with video disabled and supplies the audio clock. Remote playback can therefore make two sets of media requests. Silent videos use the FFmpeg frames and a local playback clock. Initialization failures, decoder failures, and stalled GPU playback fall back to the existing software renderer. `JELLYFRAME_PC_RENDERER=software` forces that fallback for troubleshooting.

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
sudo apt-get install build-essential cmake pkg-config python3 curl unzip libmpv-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
bash tools/build-pc-video.sh
godot --headless --xr-mode off --path . --editor --import --quit
```

The script detects x64 or ARM64, downloads and verifies the godot-cpp bindings, and builds the matching plugin in `addons/jellyframe_mpv` using the system libmpv and FFmpeg development packages. FFmpeg 6 or newer is required. Close Jellyframe before rebuilding its plugin.

For x64:

```sh
mkdir -p dist/linux-x86_64
godot --headless --xr-mode off --path . --export-release 'Linux x64' dist/linux-x86_64/jellyframe-opengl.x86_64
godot --headless --xr-mode off --path . --export-release 'Linux x64 Vulkan' dist/linux-x86_64/jellyframe-vulkan.x86_64
```

For ARM64:

```sh
mkdir -p dist/linux-arm64
godot --headless --xr-mode off --path . --export-release 'Linux ARM64' dist/linux-arm64/jellyframe-opengl.arm64
godot --headless --xr-mode off --path . --export-release 'Linux ARM64 Vulkan' dist/linux-arm64/jellyframe-vulkan.arm64
```

The OpenXR presets select OpenGL Compatibility. The Vulkan presets select the Mobile renderer and Vulkan through custom feature tags. Both executables embed their own resources and share the native decoder library in the output folder.

**Build Linux** uses native `ubuntu-24.04` and `ubuntu-24.04-arm` runners. Each job builds its plugin, exports the OpenGL and Vulkan apps, checks output files and decoder dependencies, and packages a system-libraries archive plus separate OpenGL and Vulkan AppImages. Tests run separately using the commands below. The system-libraries artifact is a tar archive that preserves Linux executable permissions; GitHub keeps them for 14 days, and the workflow needs no repository secrets.

To package AppImages after exporting and copying the licenses into `dist/linux-<arch>`, install `patchelf` and run:

```sh
bash tools/package-linux-appimages.sh x86_64
# On an ARM64 build machine:
bash tools/package-linux-appimages.sh arm64
```

The packager reuses the decoder library bundler, includes its license notices and package manifest, and leaves graphics drivers and OpenXR to the host. It downloads appimagetool 1.9.1 for the selected architecture, verifies its SHA-256 checksum, and runs it without requiring FUSE. appimagetool downloads its AppImage runtime during packaging, so packaging requires network access. Outputs are `dist/jellyframe-linux-<arch>-opengl.AppImage` and `dist/jellyframe-linux-<arch>-vulkan.AppImage`.

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
