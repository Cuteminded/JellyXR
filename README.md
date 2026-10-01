<img src="assets/logo/jellyframe-wordmark.png" alt="Jellyframe" style="width:400px;"/>
Watch your Jellyfin movies and shows on a virtual screen in VR.

Jellyframe connects to your Jellyfin server. Browse your library, choose a title,
and position the screen where you want it. The app is free and open source.
Your server supplies the movies and shows.

## From JellyQuest to Jellyframe

This project started as JellyQuest, a Jellyfin VR app for the Quest 3. I plan to
switch to Steam Frame, so I renamed the app to Jellyframe and made Steam Frame
the primary target for future development. I do not have a Steam Frame yet,
so I cannot test it on the headset. I am still developing the Quest version
under the Jellyframe name.

## What you can do

Browse and search your Jellyfin libraries, watch 2D and side-by-side 3D video,
and adjust your virtual screen. Point with your controllers to select titles and
control playback. Choose a dark background, a cinema, or passthrough on supported
devices. Episodes can play automatically in series order.

See [Using Jellyframe](USAGE.md) for controls, screen settings, environments,
and sign-in behaviour.

## Get started

You need a Jellyfin server and an account on that server. The initial Jellyfin
compatibility target is version 10.11.6.

Follow the [installation guide](INSTALLATION.md) for Quest 3, Windows
with SteamVR, or Linux x64 and ARM64 with OpenXR. It explains how to download
a build, install the app, and sign in.

## Documentation

- [Install and start](INSTALLATION.md)
- [Using Jellyframe](USAGE.md)
- [Build from source, tests, and code layout](DEVELOPMENT.md)
- [Contributing](CONTRIBUTING.md)
- [Licence and attribution](LICENSING.md)

## Current limitations

- Steam Frame installation and playback remain untested.
- Linux x64 and ARM64 headset behaviour remains untested. The CI playback checks
  run without a headset and cannot validate tracking, controllers, or stereo output.
- The PC decoder copies video frames through system memory. High-resolution
  playback needs performance testing, especially 4K and full-SBS files.
- Specific 4K HEVC and HDR videos still need testing. HDR videos rely on your
  Jellyfin server to convert them to standard dynamic range with correct colours.
- Some files may need your Jellyfin server to convert the video during playback.
  Playback can fail if the server cannot handle that conversion.
- Audio and subtitle selection, favourites, and collections are not available yet.
- Marking titles as watched manually and hiding playback controls automatically
  are planned but not available yet.

## Licence

Jellyframe uses GPL-3.0-only.
See [Licence and attribution](LICENSING.md) for licence terms and third-party credits.
