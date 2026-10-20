# License and Attribution

Copyright © 2026 Cuteminded.

Jellyframe's source code is licensed under the [GNU General Public License v3.0 only](LICENSE) (`GPL-3.0-only`).

## Third-Party Components

Jellyframe uses third-party software and assets that are subject to their respective licenses:

- **Godot and Android:** Components retain their original licenses and copyright notices.
- **Material Symbols:** Icons used throughout the player and library interfaces are sourced from [Google's Material Symbols Rounded](https://github.com/google/material-design-icons).
- **Cinema Environment:** The virtual cinema environment is based on [Comicaroid's Cinema/Movie Theater Interior](https://sketchfab.com/3d-models/cinemamovie-theater-interior-dcaf6cdebcad4f03879c24186da257ee), licensed under [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).

## Media Artwork

Movie posters, backdrops, and other media artwork are retrieved from the user's Jellyfin server. These assets are not included in Jellyframe's source code or distributed with the application.

# PC Playback Dependencies

The Windows version of Jellyframe includes third-party libraries required for video playback and integration with Godot.

The build bundles **libmpv** from [shinchiro's Windows builds](https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/20261010), using release `20261010`, based on mpv revision `b2c255c13e`. It also links against **godot-cpp**, using the `godot-4.5-stable` version.

The Vulkan video backend also links against FFmpeg. Windows builds bundle the shared libraries from [BtbN's release of October 19, 2026](https://github.com/BtbN/FFmpeg-Builds/releases/tag/autobuild-2026-10-19-13-06), archive `ffmpeg-n8.1.3-18-g46d899d7a0-win64-gpl-shared-8.1.zip`. 
This archive uses FFmpeg revision `46d899d7a0` with GPL components enabled. Its GPLv3 license is included in the exported app's `licenses/ffmpeg.txt`.
The [build scripts](https://github.com/BtbN/FFmpeg-Builds) describe its configuration and dependency sources, and the [FFmpeg source](https://github.com/FFmpeg/FFmpeg/tree/46d899d7a0) is available separately. 
Linux builds use distribution FFmpeg libraries, with their notices included when packaging the bundled libraries.

## Sources and Attribution

The following links provide access to the original source code, build configurations, and licensing information:

- **libmpv:** [Windows binary release (20261010)](https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/20261010)
- **mpv:** [Source code and copyright information (b2c255c13e)](https://github.com/mpv-player/mpv/tree/b2c255c13e)
- **Windows Decoder Dependencies:** [Build scripts and dependency sources](https://github.com/shinchiro/mpv-winbuild-cmake)
- **godot-cpp:** [Source code (Godot 4.5 stable)](https://github.com/godotengine/godot-cpp/tree/godot-4.5-stable)

These components remain subject to their respective licenses and copyright notices.
