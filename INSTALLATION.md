# Install and start Jellyframe

## What you need

- Access to a Jellyfin server and an account on that server.
- For Quest, a Quest 3 with developer mode and USB debugging enabled, plus a computer to install the app.
- For Windows or Linux, a computer and a headset with a compatible OpenXR runtime.

The initial Jellyfin compatibility target is version 10.11.6. Use HTTPS when connecting to a server outside your home network.

## Try it on Quest 3

Download a test APK from a successful **Build Android APK** run in the repository's **Actions** tab by opening **Artifacts**, downloading `jellyframe-android-debug-<run number>`, and extracting the ZIP. To build the APK yourself, follow the [build instructions](DEVELOPMENT.md).

After downloading or building the APK, connect your headset to your computer, approve USB debugging in the headset, and install it with Android's `adb` tool:

```powershell
adb devices
adb install -r dist/jellyframe-android.apk
```

Open Jellyframe from Unknown Sources in your headset, enter your Jellyfin server address, and sign in with your account or Quick Connect. Select a library and choose a title to watch.

## Try it on Windows with SteamVR

Open **Actions > Build Windows > Run workflow** in the repository, then download `jellyframe-windows-<run number>` from **Artifacts** after the build succeeds. Extract the entire ZIP and keep the executable, PCK, and any DLLs together in the same folder.

Install SteamVR, connect your headset, and set SteamVR as the active OpenXR runtime in SteamVR's **Settings > OpenXR**. Start SteamVR and run `jellyframe.exe`; Godot uses the active OpenXR runtime, as described in the [Godot Windows PCVR guide](https://www.khronos.org/assets/uploads/developers/presentations/Godot_guide_to_OpenXR_for_Windows_PCVR.pdf).

Sign in to Jellyfin and select a title to play it in VR, using the same pause, seek, resume, and side-by-side 3D controls as the Quest build. Keep `jellyframe_mpv.dll` and `libmpv-2.dll` beside the executable.

## Try it on Linux x64 or ARM64

Open **Actions > Build Linux > Run workflow** to produce `jellyframe-linux-x86_64-<run number>` and `jellyframe-linux-arm64-<run number>`. Download the artifact for your computer's architecture, open its ZIP, and extract the `.tar.gz` inside, keeping the executable, PCK, and `.so` file together.

The builds target Ubuntu 24.04 and use the system libmpv runtime. On Ubuntu, install libmpv and start the x64 build with:

```sh
sudo apt-get install libmpv2
tar -xzf jellyframe-linux-x86_64.tar.gz
./jellyframe.x86_64
```

For ARM64, use `jellyframe-linux-arm64.tar.gz` and `./jellyframe.arm64` instead. Start your OpenXR runtime with the headset connected before opening Jellyframe, and set SteamVR as the active runtime on x64. ARM64 needs a compatible ARM64 OpenXR runtime with OpenGL support; SteamVR on ARM64 and standalone Steam Frame support still need headset testing.

Sign in and play a title using the same VR controls as Windows; desktop preview with `--xr-mode off` does not play video.
