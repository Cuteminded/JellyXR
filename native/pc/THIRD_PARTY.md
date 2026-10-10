# PC playback dependencies

The Windows build bundles libmpv from shinchiro's `20261010` build,
mpv revision `b2c255c13e`, and links godot-cpp `godot-4.5-stable`.

- [libmpv binary release](https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/20261010)
- [mpv source and copyright information](https://github.com/mpv-player/mpv/tree/b2c255c13e)
- [Windows decoder build scripts and dependency sources](https://github.com/shinchiro/mpv-winbuild-cmake)
- [godot-cpp source](https://github.com/godotengine/godot-cpp/tree/godot-4.5-stable)

godot-cpp is MIT licensed. libmpv and its bundled codec dependencies have their
own licences, including GPL components. Redistributors must provide the required
copyright notices and corresponding source for the exact decoder build they ship.
These links identify upstream projects; they do not replace those obligations.

The build script pins download versions and SHA-256 checksums. It downloads build
tools into the ignored build directory and does not install them system-wide.
