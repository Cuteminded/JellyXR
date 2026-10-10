# Jellyframe

Watch your Jellyfin movies and shows on a virtual screen in VR.

Jellyframe connects to your own Jellyfin server so you can browse your library,
pick something to watch, and adjust the screen to suit your viewing position.
It is free and open source. Movies and shows come from your server; Jellyframe
does not include a media library.

## Project status

Jellyframe is an early prototype. Basic playback, including 3D video, has been
tested on Quest 3, but some features are still missing and playback compatibility
needs more testing.

Steam Frame is the intended target headset. It has not been tested yet, so
Jellyframe does not currently claim Steam Frame support.

The desktop version lets you preview the interface and browse your library.
It cannot play videos.

## What you can do

- Sign in with your Jellyfin username and password or Quick Connect.
- Browse and search your libraries, view title details, and continue watching.
- Watch 2D movies and side-by-side 3D videos.
- Resize the screen and adjust its distance, height, and curvature.
- Recenter the screen in your viewing direction.
- Choose a dark viewing space or a simple theatre.
- Use your controllers to select titles, type, pause, and skip through a video.
- Select episodes and cancel the countdown before the next episode starts.

Jellyframe saves your screen settings and can remember your sign-in on Quest.
It supports one server and one user at a time. It does not save your password.

For 3D video, Jellyframe reads the format from Jellyfin's metadata or the filename.
If a video looks wrong, you can select half or full side-by-side mode and swap
the left and right views in Screen settings. These changes are not saved per title.

## What you need

- A Quest 3 with developer mode and USB debugging enabled.
- Access to a Jellyfin server and an account on that server.
- A computer to build and install the prototype.

The initial Jellyfin compatibility target is version 10.11.6. Use HTTPS when
connecting to a server outside your home network.

## Try it on Quest 3

The current installation process requires building the Android app from source.
The build instructions are below. The resulting APK is a test build.

Once you have built the APK, connect your headset to your computer, approve USB
debugging in the headset, and install it with Android's `adb` tool:

```powershell
adb devices
adb install -r dist/jellyframe-quest3.apk
```

Open Jellyframe from Unknown Sources in your headset. Enter your Jellyfin server
address, then sign in with your account or use Quick Connect. Select a library
and choose a title to watch.

Use Screen settings to adjust your view. Press A or B during playback to show
or hide the controls. If the screen is in the wrong place, select Recenter.

## Current limitations

- Steam Frame installation and playback remain untested.
- Specific 4K HEVC and HDR videos still need testing. HDR videos rely on your
  Jellyfin server to convert them to standard dynamic range with correct colours.
- Some files may need your Jellyfin server to convert the video during playback.
  Playback can fail if the server cannot handle that conversion.
- Audio and subtitle selection, favourites, collections, and full season
  navigation are not available yet.
- Passthrough, watched-status controls, and automatic control hiding are still planned.
- Episode lists show at most 100 episodes. Libraries load 24 titles at a time.
- Recenter at the start of a new headset tracking session.

## Build from source

<details>
<summary>Developer setup, build instructions, and tests</summary>

Jellyframe uses Godot and OpenXR, with an Android plugin for video playback.

### Build requirements

- Godot 4.7.2 with matching Android export templates.
- JDK 17.
- Android SDK platforms 35 and 36, with build tools 36.1.0.
- Gradle 8.10.2.

The Android plugin compiles against Godot's 4.5.1 Android API. The project uses
the Compatibility renderer because video playback uses an external OpenGL texture.
Jellyframe declares a fixed Android codec profile rather than checking which
codecs the headset can decode. There is no native Linux video backend yet.

### Build the Quest APK

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

### Preview on a computer

Import `project.godot` into Godot, or run:

```powershell
godot --path . --xr-mode off
```

Connect to your Jellyfin server to browse your library. Desktop sessions are
not saved, and desktop mode cannot play videos.

### Run the core and HTTP tests

```powershell
godot --headless --xr-mode off --path . --editor --import --quit
godot --headless --xr-mode off --path . --script tests/test_core.gd
godot --headless --xr-mode off --path . --script tests/test_http.gd
```

### Code layout

- `scripts/jellyfin` handles the server API and requests playback streams.
- `scripts/vr` handles controller pointing.
- `scripts/player` connects Godot to the Android plugin in `native/video`.
- `scripts/core` contains screen settings and stereo geometry.

</details>

## Licence

Copyright (c) 2026 Cuteminded. Jellyframe's code uses the [MIT licence](LICENSE).
Godot and Android components retain their own licences. Library artwork comes
from your Jellyfin server and is not bundled with Jellyframe.
