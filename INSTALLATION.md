# Install and start Jellyframe

## What you need

- Access to a Jellyfin server and an account on that server.
- For Quest, a Quest 3 with developer mode and USB debugging enabled, plus a computer to install the app.
- For Windows or Linux, a computer and a headset with a compatible OpenXR runtime.

The initial Jellyfin compatibility target is version 10.11.6. Use HTTPS when connecting to a server outside your home network.

## Try it on Quest 3

Download the Android APK from **Assets** on the [latest release page](https://github.com/Cuteminded/jellyframe/releases/latest). To build the APK yourself, follow the [build instructions](DEVELOPMENT.md).

Connect your headset to your computer and approve USB debugging in the headset. Install the APK with Android's `adb` tool. Run these commands from the folder containing the downloaded APK:

```powershell
adb devices
adb install -r jellyframe-android.apk
```

If you built the APK yourself, use `dist/jellyframe-android.apk` as the install path instead.

Open Jellyframe from Unknown Sources in your headset, enter your Jellyfin server address, and sign in with your account or Quick Connect. Select a library and choose a title to watch.

## Try it on Windows with SteamVR

Download the Windows ZIP from **Assets** on the [latest release page](https://github.com/Cuteminded/jellyframe/releases/latest). Extract the entire ZIP and keep the executable, PCK, and any DLLs together in the same folder.

Install SteamVR and connect your headset. In SteamVR's **Settings > OpenXR**, set SteamVR as the active OpenXR runtime. Start SteamVR, then run `jellyframe.exe`. Godot uses the active OpenXR runtime, as described in the [Godot Windows PCVR guide](https://www.khronos.org/assets/uploads/developers/presentations/Godot_guide_to_OpenXR_for_Windows_PCVR.pdf).

The current Windows export defaults to OpenGL. To use the Vulkan backend tested with HDR, 4K, and 8K video, run this from the extracted folder in PowerShell:

```powershell
.\jellyframe.exe --rendering-method mobile --rendering-driver vulkan
```

For OpenGL:

```powershell
.\jellyframe.exe --rendering-method gl_compatibility
```

Sign in to Jellyfin and select a title to play it in VR. Pause, seek, resume, and side-by-side 3D controls work as they do in the Quest build.

Keep all DLLs from the matching build beside the executable. Current source builds need `jellyframe_mpv.dll`, `libmpv-2.dll`, `avcodec-62.dll`, `avformat-62.dll`, `avutil-60.dll`, `swscale-9.dll`, and `swresample-6.dll`.

The confirmed Vulkan HDR, 4K, and 8K results apply to a Windows SteamVR setup with an NVIDIA RTX 4070. Check the [current limitations](README.md#current-limitations) for other configurations. A published release may predate these changes; use [the source build instructions](DEVELOPMENT.md#build-and-test-on-windows) when testing the current implementation.

## Try it on Linux x64 or ARM64

Download an OpenGL or Vulkan AppImage from **Assets** on the [latest release page](https://github.com/Cuteminded/jellyframe/releases/latest). Choose the file for your computer's architecture, `x86_64` or `arm64`. AppImages include libmpv and the bundled decoder libraries.

Make the downloaded AppImage executable and launch it. For x64 OpenGL:

```sh
chmod +x jellyframe-linux-x86_64-opengl.AppImage
./jellyframe-linux-x86_64-opengl.AppImage
```

If OpenGL shows a black screen, download and run `jellyframe-linux-x86_64-vulkan.AppImage`. Use the Vulkan AppImage when adding Jellyframe to Steam on SteamOS. For ARM64, use the corresponding `jellyframe-linux-arm64-opengl.AppImage` or `jellyframe-linux-arm64-vulkan.AppImage`.

If mounting an AppImage fails because FUSE is unavailable, run it with `--appimage-extract-and-run`.

The builds target Ubuntu 24.04. AppImages need compatible system libraries, graphics drivers, and an OpenXR runtime. They may not work on older Linux distributions.

Connect your headset and start your OpenXR runtime before opening Jellyframe. On x64, set SteamVR as the active runtime. The runtime must support the selected graphics API. SteamVR on ARM64 and standalone Steam Frame support still need headset testing.

SteamOS Vulkan playback was confirmed with an earlier PC backend. The current native Vulkan decoder, HDR conversion, and high-resolution playback still need Linux headset testing. The Windows results do not confirm those cases on Linux. See the [current limitations](README.md#current-limitations).

The `system-libs` archive remains available if you prefer to install libmpv yourself. It contains both renderers. On Ubuntu x64:

```sh
sudo apt-get install libmpv2
tar -xzf jellyframe-linux-x86_64-system-libs.tar.gz
./jellyframe-opengl.x86_64
```

Keep both executables and the `.so` file together. For ARM64, use `jellyframe-linux-arm64-system-libs.tar.gz` and launch `./jellyframe-opengl.arm64` or `./jellyframe-vulkan.arm64`.

Sign in and play a title using the same VR controls as Windows; desktop preview with `--xr-mode off` does not play video.
