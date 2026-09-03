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

The Linux builds link against the distribution's libmpv instead of bundling the
Windows decoder. Install that library and its codec dependencies through the
distribution's package manager. Each Linux artifact records its compile-time
libmpv version in `build-info.txt` and includes the godot-cpp licence.

The Windows build script pins download versions and SHA-256 checksums. It downloads
build tools into the ignored build directory and does not install them system-wide.
The Linux build script verifies the same godot-cpp archive checksum and uses the
host's compiler, CMake, Python, and libmpv development package.
