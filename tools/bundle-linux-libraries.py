#!/usr/bin/env python3
"""Bundle Ubuntu decoder libraries without replacing the host graphics drivers."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


HOST_LIBRARIES = re.compile(
    r"^(?:lib(?:c|m|dl|pthread|rt|resolv|util|anl)\.so\."
    r"|libnss_|ld-linux|lib(?:stdc\+\+|gcc_s)\.so\."
    r"|lib(?:X(?!present\.so\.)|xcb|xkbcommon|wayland|decor)"
    r"|lib(?:glib|gobject|gio|gmodule|gthread)-2\.0\.so\."
    r"|libgdk_pixbuf-2\.0\.so\."
    r"|lib(?:gtk|gdk)-[234]\.so\."
    r"|lib(?:fontconfig|freetype|harfbuzz(?:-[\w]+)?|fribidi|graphite2|expat|png16)\.so\."
    r"|libpcre2-\d+\.so\."
    r"|libva(?:-(?:drm|x11|wayland|glx))?\.so\."
    r"|lib(?:mount|blkid|uuid|smartcols)\.so\."
    r"|lib(?:jpeg|tiff)\.so\."
    r"|lib(?:GL|EGL|GLES|OpenGL|vulkan|drm|gbm))"
)


def run(*arguments, cwd=None):
    environment = dict(os.environ, LC_ALL="C")
    environment.pop("LD_LIBRARY_PATH", None)
    environment.pop("LD_PRELOAD", None)
    return subprocess.check_output(arguments, text=True, cwd=cwd, env=environment)


def parse_dependencies(output):
    if "not found" in output:
        raise RuntimeError("Unresolved shared libraries:\n" + output)
    libraries = {}
    for line in output.splitlines():
        match = re.match(r"\s*(\S+) => (/\S+) \(", line)
        if match:
            libraries[match[1]] = Path(match[2])
    return libraries


def dependencies(binary):
    return parse_dependencies(run("ldd", str(binary)))


def package_owner(library):
    resolved = library.resolve()
    candidates = [str(resolved)]
    if str(resolved).startswith("/usr/lib/"):
        candidates.append(str(resolved)[4:])
    for candidate in candidates:
        try:
            result = run("dpkg-query", "-S", candidate)
            return result.splitlines()[0].rsplit(": ", 1)[0]
        except subprocess.CalledProcessError:
            continue
    raise RuntimeError("No Ubuntu package owns " + str(library))


def package_metadata(package):
    fields = run(
        "dpkg-query", "-W", "-f=${binary:Package}\t${Version}\t${source:Package}\t${source:Version}", package
    ).strip().split("\t")
    return dict(zip(("package", "version", "source", "source_version"), fields))


def copy_notices(packages, output):
    notices = output / "licenses" / "linux-libraries"
    notices.mkdir(parents=True)
    for package in packages:
        name = package.split(":", 1)[0]
        copyright_file = Path("/usr/share/doc") / name / "copyright"
        shutil.copy2(copyright_file, notices / (name + ".txt"))


def verify_bundle(plugin, library_directory, names):
    resolved = dependencies(plugin)
    for name in names:
        if name not in resolved or resolved[name].resolve().parent != library_directory.resolve():
            raise RuntimeError("The decoder does not load its bundled copy of " + name)


def bundle(input_directory, output_directory, arch):
    plugin_name = "jellyxr_mpv.linux." + arch + ".so"
    libraries = dependencies(input_directory / plugin_name)
    bundled = {name: path for name, path in libraries.items() if not HOST_LIBRARIES.match(name)}
    if "libmpv.so.2" not in bundled:
        raise RuntimeError("The decoder must link to libmpv.so.2.")
    packages = {}
    manifest = []
    playback = Path(__file__).resolve().parents[1] / "build/linux/playback"
    for name, path in sorted(bundled.items()):
        if path.resolve().is_relative_to(playback / "prefix"):
            component = "mpv" if name.startswith("libmpv.") else "ffmpeg"
            metadata = {"source": component, "source_version": "0.41.0" if component == "mpv" else "8.1.3"}
        else:
            owner = package_owner(path)
            if owner not in packages:
                packages[owner] = package_metadata(owner)
            metadata = packages[owner]
        manifest.append(dict(library=name, **metadata))
    shutil.copytree(input_directory, output_directory)
    library_directory = output_directory / "lib"
    library_directory.mkdir()
    for name, path in bundled.items():
        destination = library_directory / name
        shutil.copy2(path, destination)
        run("patchelf", "--force-rpath", "--set-rpath", "$ORIGIN", str(destination))
    plugin = output_directory / plugin_name
    run("patchelf", "--force-rpath", "--set-rpath", "$ORIGIN/lib", str(plugin))
    verify_bundle(plugin, library_directory, bundled)
    copy_notices(packages, output_directory)
    subprocess.run([
        "python3", str(Path(__file__).with_name("inspect-playback-libraries.py")),
        "--platform", "linux", "--bin-directory", str(library_directory),
        "--output", str(output_directory / "library-report.json"),
    ], check=True)
    manifest_text = json.dumps(manifest, indent=2) + "\n"
    (output_directory / "bundled-libraries.json").write_text(manifest_text)
    print("Bundled %d shared libraries from %d packages." % (len(bundled), len(packages)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-directory", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--arch", choices=("x86_64", "arm64"), required=True)
    args = parser.parse_args()
    bundle(args.input_directory.resolve(), args.output_directory.resolve(), args.arch)


if __name__ == "__main__":
    main()
