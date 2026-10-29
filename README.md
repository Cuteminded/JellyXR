<img src="assets/logo/jellyxr-wordmark.png" alt="jellyXR" style="width:400px;"/>

Watch your Jellyfin movies and shows on a virtual screen in VR.

jellyXR is a free, open source app for browsing your Jellyfin library and watching videos in VR. Choose a title and position the screen where you want it. Your Jellyfin server supplies the movies and shows.

## From JellyQuest to jellyXR

This project started as **JellyQuest**, a Jellyfin VR app for the Quest. I renamed it **jellyXR** because I want the app to work across multiple VR and AR devices, without tying its name to a single headset or platform.

The goal is to support standalone headsets and devices connected to a PC. Support depends on each device's capabilities and testing. The hardware status table below shows what has been tested.

## Will it be available in a store?

If we think jellyXR is ready for a wider release, then yes. I'd be happy to put in the work to make it available on Steam or the Meta Store.

## Documentation

- [Install and start](INSTALLATION.md)
- [Using jellyXR](USAGE.md)
- [Build from source, tests, and code layout](DEVELOPMENT.md)
- [Contributing](CONTRIBUTING.md)
- [Licence and attribution](LICENSING.md)

## Hardware status

| Device | Status | Build | Tested version | Notes |
|---|---|---|---|---|
| [Quest 1](https://www.meta.com/quest) | Working | Quest 1 | 0.1.3 | Testing depends on access to a borrowed headset. |
| [Quest 2](https://www.meta.com/quest) | Untested | * | * | We don't have a Quest 2 to test with |
| [Quest 3](https://www.meta.com/quest) | Working  | Android | 0.1.3 ||
| [Quest Pro](https://www.meta.com/quest) | Untested  | * | * | We don't have a Quest Pro to test with |
| [Xreal aura](https://www.xreal.com/aura) | Waiting for device | * | * | Not yet released in Europe |
| [Steam Frame](https://store.steampowered.com/hardware/steamframe) | Waiting for device | * | * | On reservation queue |
| [SteamVR](https://store.steampowered.com/steamvr) | Working | Linux x64 | 0.1.4 | Tested on a Steam Machine. 8K playback can drop frames. |
| [SteamVR](https://store.steampowered.com/steamvr) | Working | Windows X64 | 0.1.3 ||



To report results for a listed or unlisted device, [open an issue](https://github.com/Cuteminded/jellyframe/issues). Include the device, operating system, app version, and what you tested.

## Current limitations

Linux 8K playback can drop frames while copying decoded video between VAAPI and Vulkan. This also occurred with the previous GPL playback libraries.

Linux ARM64 builds still need headset testing. Other untested devices are listed in the hardware table.

## Licence

jellyXR is licensed under [Apache License, Version 2.0](LICENSE)
Third-party components retain their own licenses. See [Licence and attribution](LICENSING.md) for details.
