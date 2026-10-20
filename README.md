<img src="assets/logo/jellyframe-wordmark.png" alt="Jellyframe" style="width:400px;"/>
Watch your Jellyfin movies and shows on a virtual screen in VR.

Jellyframe is a free, open source app that connects to your Jellyfin server so you can browse your library, choose a title, and position the screen where you want it. Your server supplies the movies and shows.

## From JellyQuest to Jellyframe

This project started as JellyQuest, a Jellyfin VR app for the Quest 3. I renamed it Jellyframe because I plan to switch to Steam Frame, which is now the main target for future development. I do not have a Steam Frame yet, so I cannot test it on the headset, but I am still developing the Quest version under the Jellyframe name.

## What you can do

Browse and search your Jellyfin libraries, watch 2D, side-by-side 3D, 180° and 360° video, and use your controllers to select titles and control playback. Choose a dark background, a cinema, or passthrough on supported devices, and let episodes play automatically in series order.

See [Using Jellyframe](USAGE.md) for controls, screen settings, environments, and sign-in behaviour.

## Get started

You need a Jellyfin server and an account on that server; the initial compatibility target is Jellyfin 10.11.6.

Follow the [installation guide](INSTALLATION.md) to download a build, install the app, and sign in on Quest 3, Windows with SteamVR, or Linux x64 and ARM64 with OpenXR.

## Documentation

- [Install and start](INSTALLATION.md)
- [Using Jellyframe](USAGE.md)
- [Build from source, tests, and code layout](DEVELOPMENT.md)
- [Contributing](CONTRIBUTING.md)
- [Licence and attribution](LICENSING.md)

## Current limitations

- 180° projection and top-bottom 3D still need headset validation.
- Steam Frame installation and playback remain untested.
- Linux VR playback has been tested on a Steam Machine running SteamOS, using Vulkan and SteamVR. ARM64 and other Linux systems still need headset testing.
- CI playback checks run without a headset and do not verify tracking, controller input, or stereo output.
- Desktop mode only shows the interface. PC video playback requires an active OpenXR session with a connected headset.
- PC OpenGL builds render video on a worker thread into buffered GPU textures. Vulkan builds use FFmpeg to decode video and a Vulkan compute shader to convert YUV planes into the screen texture. Both paths have a software fallback and can copy decoded frames through system memory. High-resolution playback still needs headset performance testing, especially with 8K and full-SBS files.
- Specific 4K HEVC and HDR videos still need testing; HDR playback relies on your Jellyfin server to convert the video to standard dynamic range with correct colours.
- Some files need your Jellyfin server to convert the video during playback, which can fail if the server cannot handle the conversion.
- Audio and subtitle selection, favourites, and collections are not available yet.
- Marking titles as watched manually and hiding playback controls automatically are planned but not available yet.

## Licence

Jellyframe uses GPL-3.0-only; see [Licence and attribution](LICENSING.md) for licence terms and third-party credits.
