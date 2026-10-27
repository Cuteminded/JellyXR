# License and attribution

Copyright © 2026 Cuteminded.

jellyXR's source code is licensed under the [GNU General Public License v3.0 only](LICENSE) (`GPL-3.0-only`).

## Third-party components

jellyXR uses third-party software and assets under their own licenses:

- Godot and Android components retain their original licenses and copyright notices.
- Icons in the player and library come from [Google's Material Symbols Rounded](https://github.com/google/material-design-icons).
- The virtual cinema is based on [Comicaroid's Cinema/Movie Theater Interior](https://sketchfab.com/3d-models/cinemamovie-theater-interior-dcaf6cdebcad4f03879c24186da257ee), licensed under [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).

## Media artwork

jellyXR retrieves movie posters, backdrops, and other media artwork from the user's Jellyfin server. It does not include these assets in its source code or distribute them with the app.

# PC playback dependencies

The Windows build includes third-party libraries for video playback and integration with Godot.

The build bundles libmpv from [shinchiro's Windows builds](https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/20261010), release `20261010`, based on mpv revision `b2c255c13e`. It also links against godot-cpp version `godot-4.5-stable`.

The Vulkan video backend also links against FFmpeg. Windows builds bundle the shared libraries from [BtbN's release of October 19, 2026](https://github.com/BtbN/FFmpeg-Builds/releases/tag/autobuild-2026-10-19-13-06), archive `ffmpeg-n8.1.3-18-g46d899d7a0-win64-gpl-shared-8.1.zip`.

This archive uses FFmpeg revision `46d899d7a0` with GPL components enabled. The exported app includes its GPLv3 license in `licenses/ffmpeg.txt`.

The [build scripts](https://github.com/BtbN/FFmpeg-Builds) describe the configuration and dependency sources. The [FFmpeg source](https://github.com/FFmpeg/FFmpeg/tree/46d899d7a0) is available separately.

Linux builds use distribution FFmpeg libraries. Packaging includes the notices for the bundled libraries.

## Sources and attribution

Sources, build configurations, and license information:

- [libmpv Windows binary release, 20261010](https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/20261010)
- [mpv source code and copyright information, b2c255c13e](https://github.com/mpv-player/mpv/tree/b2c255c13e)
- [Windows decoder build scripts and dependency sources](https://github.com/shinchiro/mpv-winbuild-cmake)
- [godot-cpp source code, Godot 4.5 stable](https://github.com/godotengine/godot-cpp/tree/godot-4.5-stable)

Each component keeps its own license and copyright notices.
