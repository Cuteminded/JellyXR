# Jellyframe

Watch your Jellyfin movies and shows on a virtual screen in VR.

Jellyframe connects to your Jellyfin server. Browse your library, choose a title,
and adjust the screen to your viewing position. The app is free and open source.
You supply the movies and shows through your server.

## From JellyQuest to Jellyframe

This project started as JellyQuest, a Jellyfin VR app for the Quest 3. I plan to
switch to Steam Frame, so I renamed the app to Jellyframe and made Steam Frame
the primary target for future development. I do not have a Steam Frame yet,
so testing on the headset will have to wait. Development of the Quest version continues under the Jellyframe name.

## Project status

Jellyframe is in active development. Basic playback, including 3D video, has been
tested on Quest 3, but some features are still missing and playback compatibility
needs more testing.

Steam Frame support still needs testing on the headset.

The Windows version plays video in VR. Stereo video and controller playback
controls have been checked with SteamVR.

Linux x64 and ARM64 builds use the same player through libmpv and OpenXR. The
Linux workflow builds and tests each architecture separately. Playback and
authenticated MP4/HLS streaming checks pass in Ubuntu 24.04, with
ARM64 tested through emulation. Linux headset behavior has not been fully tested yet.

## What works right now

- Sign in with your Jellyfin username and password or Quick Connect.
- Browse and search your libraries, view title details, and continue watching.
- Watch 2D movies and side-by-side 3D videos.
- Resize the screen and adjust its distance, height, and curvature.
- Recenter the screen in your viewing direction.
- Watch against a dark background, in a cinema, or with your room visible through passthrough.
- Use your controllers to select titles, type, pause, and skip through a video.
- Select episodes and cancel the countdown before the next episode starts.

Jellyframe saves your screen settings and can remember your sign-in on Quest.
It supports one server and one user at a time. It does not save your password.

For 3D video, Jellyframe reads the format from Jellyfin's metadata or the filename.
If a video looks wrong, you can select half or full side-by-side mode and swap
the left and right views in Settings. These changes are not saved per title.

## What you need

- A Quest 3 with developer mode and USB debugging enabled.
- Access to a Jellyfin server and an account on that server.
- A computer to build and install the app.

The initial Jellyfin compatibility target is version 10.11.6. Use HTTPS when
connecting to a server outside your home network.

## Try it on Quest 3

Download a test APK from a successful **Build Android APK** run in the repository's
**Actions** tab. Under **Artifacts**, download `jellyframe-android-debug-<run number>`
and extract the ZIP. You can also build the app from source using the instructions below.

Once you have built the APK, connect your headset to your computer, approve USB
debugging in the headset, and install it with Android's `adb` tool:

```powershell
adb devices
adb install -r dist/jellyframe-android.apk
```

Open Jellyframe from Unknown Sources in your headset. Enter your Jellyfin server
address, then sign in with your account or use Quick Connect. Select a library
and choose a title to watch.

Settings has separate pages for library sorting, screen controls and environments.
Library sorting sets the field and order for your libraries. Home always shows the
newest additions first.

Choose Void for a dark background, Theatre for a cinema, or Passthrough to see
your room around the screen. Passthrough is disabled on unsupported devices.
Theatre has a fixed front screen. Black bars keep the picture in proportion.
Void and Passthrough let you adjust the screen size, distance, height and curve.
Reset to defaults restores those screen controls and keeps your environment choice.

## Try it on Windows with SteamVR

Open **Actions > Build Windows > Run workflow** in the repository.
After the build succeeds, download `jellyframe-windows-<run number>` from
**Artifacts** and extract the entire ZIP. Keep the executable, PCK, and any DLLs
together in the same folder.

Install SteamVR, connect your headset, and set SteamVR as the active OpenXR runtime
in SteamVR's **Settings > OpenXR**. Start SteamVR, then run `jellyframe.exe`.
Godot uses the active OpenXR runtime, as described in the
[Godot Windows PCVR guide](https://www.khronos.org/assets/uploads/developers/presentations/Godot_guide_to_OpenXR_for_Windows_PCVR.pdf).

Sign in to Jellyfin and select a title to play it in VR. Pause, seeking, resume,
and side-by-side 3D use the same controls as the Quest build.
Keep `jellyframe_mpv.dll` and `libmpv-2.dll`
beside the executable

## Try it on Linux x64 or ARM64

Open **Actions > Build Linux > Run workflow**. The workflow produces
`jellyframe-linux-x86_64-<run number>` and `jellyframe-linux-arm64-<run number>`.
Download the artifact matching your computer, open its ZIP, and extract the
`.tar.gz` inside. Keep the executable, PCK, and `.so` file together.

The builds target Ubuntu 24.04 and use the system libmpv runtime. On Ubuntu:

```sh
sudo apt-get install libmpv2
tar -xzf jellyframe-linux-x86_64.tar.gz
./jellyframe.x86_64
```

For ARM64, use `jellyframe-linux-arm64.tar.gz` and `./jellyframe.arm64` instead.
Start your OpenXR runtime with the headset connected before opening Jellyframe.
On x64, set SteamVR as the active OpenXR runtime. ARM64 needs a compatible ARM64
OpenXR runtime with OpenGL support. SteamVR on ARM64 and standalone Steam Frame
support still need headset testing.

Sign in and play a title using the same VR controls as Windows. Desktop preview
with `--xr-mode off` does not play video.

## Current limitations

- Steam Frame installation and playback remain untested.
- Linux x64 and ARM64 headset behavior remains untested. The CI playback checks
  run without a headset and cannot validate tracking, controllers, or stereo output.
- The PC decoder copies video frames through system memory. High-resolution
  playback needs performance testing. especially 4K and full-SBS files.
- Specific 4K HEVC and HDR videos still need testing. HDR videos rely on your
  Jellyfin server to convert them to standard dynamic range with correct colours.
- Some files may need your Jellyfin server to convert the video during playback.
  Playback can fail if the server cannot handle that conversion.
- Audio and subtitle selection, favourites, and collections are not available yet.
- Manually marking titles as watched and automatically hiding playback controls are still planned.

## Build from source

<details>
<summary>Developer setup, build instructions, and tests</summary>

Jellyframe uses Godot and OpenXR, with an Android video plugin and a shared
libmpv video plugin for Windows and Linux.

### Build requirements

- Godot 4.7.2 with matching Android export templates.
- JDK 17.
- Android SDK platforms 35 and 36, with build tools 36.1.0.
- Gradle 8.10.2.

The Android plugin compiles against Godot's 4.5.1 Android API. The project uses
the Compatibility renderer because video playback uses an external OpenGL texture.
Jellyframe declares a fixed Android codec profile rather than checking which
codecs the headset can decode. Windows and Linux use libmpv for PC VR playback.

### Build the Quest APK

To build a Quest 3 debug APK, open **Actions > Build Android APK > Run workflow**.
The workflow builds the native video plugin, exports the APK, checks its signature,
and keeps the APK artifact for 14 days. No repository secrets are required.

Each workflow run creates a new debug signing key. Installing a build over an APK
signed with another key requires uninstalling the previous app first, which removes
its saved settings and sign-in. These APKs are for testing, not store releases.

To build locally:

1. Install the build requirements and accept the Android SDK licences.
2. Set the Android SDK and Java SDK paths in Godot's editor settings.
3. Select Project > Install Android Build Template.
4. Run the build script with the paths to your installed tools:

```powershell
./tools/build-android.ps1 -Godot 'C:/tools/godot.exe' `
  -Gradle 'C:/tools/gradle/bin/gradle.bat' `
  -AndroidSdk 'C:/tools/android-sdk' -JavaHome 'C:/tools/jdk-17'
```

The script creates `dist/jellyframe-quest3.apk` for installation on your headset.
It also downloads Godot OpenXR Vendors 5.1.0 for Quest passthrough support,
checks the archive's SHA-256 checksum, and includes the vendor licences in the APK.
The downloaded addon stays in the ignored `addons/godotopenxrvendors` directory.

### Build and test on Windows

To build Windows SteamVR locally, install Godot 4.7.2 with matching export templates
and Python 3.12. Build the PC plugin before importing or exporting the project:

```powershell
./tools/build-pc-video.ps1 -Python 'C:/path/to/python.exe'
New-Item -ItemType Directory -Force dist/windows
godot --headless --xr-mode off --path . --editor --import --quit
godot --headless --xr-mode off --path . --export-release 'Windows SteamVR' dist/windows/jellyframe.exe
```

The plugin build script downloads pinned CMake, LLVM-MinGW, godot-cpp, and libmpv
archives into `build/desktop`, verifies their checksums, and generates
`addons/jellyframe_mpv`. Close running Jellyframe instances before rebuilding.
No system-wide compiler installation is required. The generated plugin is ignored
by Git and excluded from Android exports.

The Windows workflow builds the plugin, tests decoding and controls, exports the
app, and checks that the exported executable starts with VR disabled. OpenXR
is disabled for build commands only; the exported app keeps OpenXR enabled.
Build artifacts are retained for 14 days. No repository secrets are required.

After building the PC plugin, run its decoder tests without a headset:

```powershell
godot --headless --xr-mode off --path . --script tests/test_pc_video.gd
python tests/test_pc_streaming.py --godot 'C:/path/to/godot_console.exe'
```

With SteamVR and your headset running, test the stereo screen and controllers:

```powershell
godot --path . --script tests/test_steamvr_video.gd
```

The headset test loops a labelled stereo clip for two minutes. Close one eye at a
time to check the LEFT and RIGHT labels. Press A or B to open the playback controls.
The decoder tests cover resume, pause, seeking, completion, reopening, and errors.

Import `project.godot` into Godot, or run:

```powershell
godot --path . --xr-mode off
```

Connect to your Jellyfin server to browse your library. Desktop sessions are
not saved, and desktop mode cannot play videos.

### Build Linux x64 or ARM64

Build natively on the target architecture with Godot 4.7.2 and matching export
templates. On Ubuntu, install the build dependencies:

```sh
sudo apt-get install build-essential cmake pkg-config python3 curl unzip libmpv-dev ffmpeg
bash tools/build-pc-video.sh
godot --headless --xr-mode off --path . --editor --import --quit
```

The script detects x64 or ARM64, downloads and verifies the godot-cpp bindings,
and builds the matching plugin in `addons/jellyframe_mpv`. It uses the system
libmpv development package. Close Jellyframe before rebuilding its plugin.

For x64:

```sh
mkdir -p dist/linux-x86_64
godot --headless --xr-mode off --path . --export-release 'Linux x64 OpenXR' dist/linux-x86_64/jellyframe.x86_64
```

For ARM64:

```sh
mkdir -p dist/linux-arm64
godot --headless --xr-mode off --path . --export-release 'Linux ARM64 OpenXR' dist/linux-arm64/jellyframe.arm64
```

**Build Linux** uses native `ubuntu-24.04` and `ubuntu-24.04-arm` runners.
Each job builds its plugin, checks local and authenticated MP4/HLS playback,
runs the control tests, and starts the exported app without VR.
The artifacts contain tar archives that preserve Linux executable permissions.
GitHub keeps the artifacts for 14 days. No repository secrets are required.

The same decoder and headset test scripts above work on Linux. Use `python3`
for the HTTP streaming test and pass the path to your Linux Godot executable.

### Run the core and HTTP tests

```powershell
godot --headless --xr-mode off --path . --editor --import --quit
godot --headless --xr-mode off --path . --script tests/test_core.gd
godot --headless --xr-mode off --path . --script tests/test_http.gd
```

### Code layout

- `scripts/jellyfin` handles the server API and requests playback streams.
- `scripts/vr` handles environments, controller pointing, and recentering.
- `scripts/player` selects Android playback or PC VR playback.
- `native/android` contains the Android decoder; `native/pc` contains the libmpv PC decoder.
- `scripts/core` contains screen settings and stereo geometry.

</details>

## Licence

Copyright (c) 2026 Cuteminded. 

Jellyframe's code is licensed under the [GNU General Public License, version 3 only](LICENSE) (`GPL-3.0-only`).

Godot and Android components retain their own licences. 

Library artwork comes from your Jellyfin server and is not bundled with Jellyframe.
