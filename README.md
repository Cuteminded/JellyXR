<img src="assets/logo/jellyframe-wordmark.png" alt="Jellyframe" style="width:400px;"/>

Watch your Jellyfin movies and shows on a virtual screen in VR.

Jellyframe is a free, open source app for browsing your Jellyfin library and watching videos in VR. Choose a title and position the screen where you want it. Your Jellyfin server supplies the movies and shows.

## From JellyQuest to Jellyframe

This project started as JellyQuest, a Jellyfin VR app for the Quest 3. I renamed it Jellyframe because I plan to switch to Steam Frame. 

Steam Frame is now the main target for future development.

> I do not have a Steam Frame yet, so I cannot test it on the headset. Development of the Quest version continues under the Jellyframe name.

## What has been tested

- Browsing and searching Jellyfin libraries.
- Selecting titles and controlling playback with controllers.
- Dark backgrounds, cinema environments, and passthrough on supported devices.
- 2D, side-by-side 3D, 180° and 360° video.
- Automatic episode playback in series order.
- HDR, 1080p, 4K, and 8K video playback.

## Current limitations

- Steam Frame installation and playback remain untested.
- 180° projection and top-bottom 3D still need headset testing. Desktop projection tests cannot confirm stereo output or viewing comfort in VR.
- Quest HLS seeking still needs in-headset confirmation after the timeline fix.
- Linux VR playback was previously tested on a Steam Machine running SteamOS with Vulkan and SteamVR. The new native Vulkan decoder, HDR conversion, and 4K/8K playback still need Linux headset testing.
- ARM64 and other Linux systems also need headset testing.
- Quest and OpenGL HDR behaviour still need separate testing.
- Native HDR output and display calibration are not implemented.
- Some files need conversion by your Jellyfin server during playback. This can fail if the server cannot handle the conversion.
- Audio and subtitle selection, favourites, and collections are not available yet.
- Manually marking titles as watched and automatically hiding playback controls are planned but not available yet.

## Documentation

- [Install and start](INSTALLATION.md)
- [Using Jellyframe](USAGE.md)
- [Build from source, tests, and code layout](DEVELOPMENT.md)
- [Contributing](CONTRIBUTING.md)
- [Licence and attribution](LICENSING.md)

## Licence

Jellyframe uses GPL-3.0-only; see [Licence and attribution](LICENSING.md) for licence terms and third-party credits.
