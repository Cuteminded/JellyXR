<img src="assets/logo/jellyxr-wordmark.png" alt="jellyXR" style="width:400px;"/>

Watch your Jellyfin movies and shows on a virtual screen in VR.

jellyXR is a free, open source app for browsing your Jellyfin library and watching videos in VR. Choose a title and position the screen where you want it. Your Jellyfin server supplies the movies and shows.

## Hardware status

| Device | Status | Build | Notes |
|---|---|---|---|
| [Quest 1](https://www.meta.com/quest/) | Pending | Android | Installed but not fully tested |
| [Quest 3](https://www.meta.com/quest/) | Working | Android |  |
| [Xreal aura](https://www.xreal.com/aura) | Waiting for device | Android | Not yet released in Europe |
| [Steam Frame](https://store.steampowered.com/hardware/steamframe) | Waiting for device | Linux ARM64 | On reservation queue |
| [SteamVR](https://store.steampowered.com/steamvr) | Partially Working | Linux X64 | Needs further testing with Vulkan |
| [SteamVR](https://store.steampowered.com/steamvr) | Working | Windows | |

> **Note:** If you have a device that isn't listed here, or can test jellyXR on any of the listed devices, we'd love to hear from you!
>
> Please [open an issue](https://github.com/Cuteminded/jellyframe/issues) to share your results and help us keep the hardware compatibility list accurate and up to date.


## From JellyQuest to jellyXR

This project started as **JellyQuest**, a Jellyfin VR app for the Quest. I renamed it **jellyXR** because I want the app to work across multiple VR and AR devices, without tying its name to a single headset or platform.

The goal is to support standalone headsets and devices connected to a PC. Support depends on each device's capabilities and testing. The hardware status table above shows what works today and what still needs testing.

## Will it be available in a store?

If we think jellyXR is ready for a wider release, then yes. I'd be happy to put in the work to make it available on Steam or the Meta Store.

## Documentation

- [Install and start](INSTALLATION.md)
- [Using jellyXR](USAGE.md)
- [Build from source, tests, and code layout](DEVELOPMENT.md)
- [Contributing](CONTRIBUTING.md)
- [Licence and attribution](LICENSING.md)

## Licence

jellyXR uses GPL-3.0-only; see [Licence and attribution](LICENSING.md) for licence terms and third-party credits.
