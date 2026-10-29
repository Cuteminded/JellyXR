# License and attribution

Copyright © 2026 Cuteminded.

jellyXR's own source code is licensed under the [Apache License, Version 2.0](LICENSE) (`Apache-2.0`). Third-party components and assets are excluded from this grant and retain their own licenses.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this work except in compliance with the License. You may obtain a copy of the License at <https://www.apache.org/licenses/LICENSE-2.0>.

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

Previously distributed GPL-licensed versions remain available under their original license terms. The Apache-2.0 grant does not revoke those rights.

## Third-party components

jellyXR uses third-party software and assets under their own licenses:

- Godot and Android components retain their original licenses and copyright notices.
- Icons in the player and library come from [Google's Material Symbols Rounded](https://github.com/google/material-design-icons).
- The virtual cinema is based on [Comicaroid's Cinema/Movie Theater Interior](https://sketchfab.com/3d-models/cinemamovie-theater-interior-dcaf6cdebcad4f03879c24186da257ee), licensed under [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).

## Media artwork

jellyXR retrieves movie posters, backdrops, and other media artwork from the user's Jellyfin server. It does not include these assets in its source code or distribute them with the app.

## PC playback libraries

Windows and Linux AppImages use shared LGPL builds of FFmpeg and libmpv. jellyXR loads them dynamically and keeps their original filenames so users can replace them with compatible builds.

- Windows uses FFmpeg 8.1.3, revision `46d899d7a0`, from [BtbN's LGPL shared build](https://github.com/BtbN/FFmpeg-Builds/releases/tag/autobuild-2026-10-19-13-06). Its license is LGPL version 3.
- Windows libmpv uses revision `cf764c61d195f64528df21887298bb616d49b426`, from [upstream build 40835379230](https://github.com/mpv-player/mpv/actions/runs/40835379230). It also contains FFmpeg revision `31ba826` and other statically linked dependencies.
- Linux AppImages build FFmpeg 8.1.3 and libmpv 0.41.0 from pinned sources, with GPL and nonfree features disabled. They bundle the playback libraries, supporting libraries, and notices. The system-libraries archive uses the installed distribution libraries instead. Graphics drivers, VAAPI, OpenXR, and the C++ runtime come from the host.
- The PC plugin uses MIT-licensed [godot-cpp godot-4.5-stable](https://github.com/godotengine/godot-cpp/tree/godot-4.5-stable).

The build scripts verify source or binary archive checksums and check the loaded library configurations. Android keeps its existing playback backend.

## Redistribution

Include the bundled licenses, copyright notices, corresponding sources, patches, and build instructions required by each component's license. This includes dependencies compiled into the Windows DLLs. The upstream Windows libmpv archive does not provide their complete source and notice packet.

LGPL version 3 incorporates the GPL version 3 text, so Windows packages include both texts. This does not change jellyXR's Apache-2.0 license.

See the [FFmpeg distribution guidance](https://ffmpeg.org/legal.html) and [mpv copyright information](https://github.com/mpv-player/mpv/blob/v0.41.0/Copyright).
