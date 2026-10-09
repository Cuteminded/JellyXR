# Jellyframe

Jellyframe is an MIT-licensed Jellyfin client for watching movies on a virtual
screen in a standalone VR headset. Steam Frame is the target device. Quest 3
is the first development and testing platform.

**Status: early prototype.** The project contains a Godot/OpenXR interface and
an Android video plugin. It is not yet a complete or validated media client.
Desktop mode previews the interface; it does not decode movies.

Quest 3 testing confirmed the VR panel, controller pointing/clicking, upright
per-eye calibration output, and real-server video playback including 3D.
Specific 4K HEVC and HDR cases, and Steam Frame, remain unverified.

## Prototype features

- Jellyfin username/password login and Quick Connect.
- One server and one user, with Android Keystore-protected saved sign-in.
- Library sidebar, featured artwork, Continue Watching, movie details, and
  search and pagination within the selected Jellyfin library.
- Controller laser interaction and an in-app keyboard.
- Android video playback, Jellyfin playback reporting, and transcoding fallback.
- Half-SBS and full-SBS rendering with manual overrides and eye swapping.
- Screen size, distance, height, curvature, and recenter controls, with
  automatic startup placement after headset tracking becomes available.
- A dark viewing space and a minimal theatre environment.
- Episode selection and a cancellable next-episode countdown.

Automatic 3D selection uses explicit Jellyfin metadata and unambiguous half/full-SBS
filename markers. Unlabelled or ambiguous videos start in 2D. Adjust the mode in
Screen settings. Manual 3D overrides are not saved per title.

## Requirements

- A Jellyfin server, with 10.11.6 as the initial compatibility target.
- Godot 4.7.2 with matching Android export templates for the tested build setup.
- JDK 17, Android SDK platforms 35 and 36, and build tools 36.1.0.
- Gradle 8.10.2 for the Android video plugin.
- A Quest 3 with developer mode and USB debugging enabled for device testing.

The native plugin compiles against Godot's 4.5.1 Android API. The project uses
the Compatibility renderer because the video bridge uses an external OpenGL texture.

## Run the interface on a computer

Import `project.godot` into Godot, or run:

```powershell
godot --path . --xr-mode off
```

Use a real Jellyfin server to browse your library. Desktop sessions are not saved.
Passwords are never saved. Use HTTPS for remote connections.

## Build and install on Quest

1. Install the requirements above. Accept the Android SDK licences.
2. In Godot's editor settings, set the Android SDK and Java SDK paths.
3. Use Project > Install Android Build Template with matching export templates.
4. Run the build script, supplying your installed tool paths:

```powershell
./tools/build-android.ps1 -Godot 'C:/tools/godot.exe' `
  -Gradle 'C:/tools/gradle/bin/gradle.bat' `
  -AndroidSdk 'C:/tools/android-sdk' -JavaHome 'C:/tools/jdk-17'
```

5. Connect the headset, approve USB debugging, and install the APK:

```powershell
adb devices
adb install -r dist/jellyframe-quest3.apk
```

Open Jellyframe from Unknown Sources in the headset. The initial package is a
debug build for testing, not a store release. See [device testing](docs/testing.md).

## Development

```powershell
godot --headless --xr-mode off --path . --editor --import --quit
godot --headless --xr-mode off --path . --script tests/test_core.gd
godot --headless --xr-mode off --path . --script tests/test_http.gd
```

`scripts/jellyfin` handles the server API and playback negotiation. `scripts/vr`
handles pointing. `scripts/player` connects Godot to the Android plugin in
`native/video`. `scripts/core` contains screen settings and stereo geometry.
No Jellyfin server credentials or test media belong in the repository.

## Current limits

- Steam Frame deployment and decoding are not verified. No native Linux video backend exists yet.
- HDR sources request an SDR-compatible transcoded stream. Correct tone mapping depends on the server.
- Codec declarations are an initial Android profile, not a hardware capability probe.
- Passthrough, audio/subtitle selection, favourites, collections, full season navigation,
  watched-status controls, automatic menu hiding, and final poster/backdrop design remain planned.
- Episode lists currently show at most 100 episodes. Library pages contain 24 titles.
- The theatre is simple geometry; there are no third-party environment assets.
- Screen dimensions persist. Recenter again when entering a new tracking session.

## Licence

Copyright (c) 2026 Cuteminded. Jellyframe's code uses the [MIT licence](LICENSE).
Godot and Android components retain their own licences. Jellyfin library artwork
comes from the user's server and is not bundled with Jellyframe.
