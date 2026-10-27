# Install and start jellyXR

Download the package for your platform from **Assets** on the [latest release page](https://github.com/Cuteminded/jellyframe/releases/latest).

You need a Jellyfin server and an account to use the app. To build jellyXR yourself, follow the [build instructions](DEVELOPMENT.md).

## Quest 3

Enable developer mode and USB debugging on your headset. Install Android's `adb` tool on your computer and download `jellyxr-android.apk`.

Connect your headset to your computer by USB and approve USB debugging in the headset. Run these commands from the folder containing the APK:

```powershell
adb devices
adb install -r jellyxr-android.apk
```

Open jellyXR from **Unknown Sources** in your headset.

## Windows with SteamVR

Download the Windows ZIP and extract the entire archive. Keep all files together in the extracted folder.

Install SteamVR and connect your headset. In SteamVR's **Settings > OpenXR**, set SteamVR as the active OpenXR runtime. Start SteamVR, then run `jellyxr.exe`.

If jellyXR cannot start with Vulkan, try OpenGL from PowerShell in the extracted folder:

```powershell
.\jellyxr.exe --rendering-method gl_compatibility
```

## Linux x64 or ARM64

Download the AppImage for your computer's architecture, `x86_64` or `arm64`. The builds target Ubuntu 24.04 and need compatible system libraries, graphics drivers, and an OpenXR runtime.

Connect your headset and start your OpenXR runtime. On x64, set SteamVR as the active runtime. Make the AppImage executable and launch it:

```sh
chmod +x jellyxr-linux-x86_64.AppImage
./jellyxr-linux-x86_64.AppImage
```

For ARM64, replace the filename with `jellyxr-linux-arm64.AppImage`. On SteamOS, add the AppImage to Steam as a non-Steam game.

If jellyXR cannot start with Vulkan, try OpenGL:

```sh
./jellyxr-linux-x86_64.AppImage --rendering-method gl_compatibility
```

If mounting an AppImage fails because FUSE is unavailable, run it with `--appimage-extract-and-run`.

### Use system libraries instead of an AppImage

Download the `system-libs` archive for your architecture. On Ubuntu x64, install libmpv, extract the archive, and launch jellyXR:

```sh
sudo apt-get install libmpv2
tar -xzf jellyxr-linux-x86_64-system-libs.tar.gz
./jellyxr.x86_64
```

Keep the executable and the `.so` file together. For ARM64, use `jellyxr-linux-arm64-system-libs.tar.gz` and launch `./jellyxr.arm64`.

## After installation

Follow the [usage guide](USAGE.md) to sign in and play a video. See the [current limitations](README.md#current-limitations) for platform and headset compatibility.
