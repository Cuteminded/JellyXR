import ctypes
import importlib.util
import json
import os
from pathlib import Path
import platform
import subprocess
import struct
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "bundle-linux-libraries.py"
SPEC = importlib.util.spec_from_file_location("linux_bundle", SCRIPT)
linux_bundle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(linux_bundle)


class DependencyChecks(unittest.TestCase):
    def test_missing_transitive_dependency_stops_packaging(self):
        with self.assertRaisesRegex(RuntimeError, "Unresolved"):
            linux_bundle.parse_dependencies("libmpv.so.2 => /usr/lib/libmpv.so.2 (0x123)\nlibavcodec.so.60 => not found")

    def test_graphics_drivers_and_glibc_stay_on_the_host(self):
        host_libraries = (
            "libc.so.6", "libm.so.6", "libpthread.so.0", "libstdc++.so.6", "libgcc_s.so.1",
            "libGLX.so.0", "libvulkan.so.1", "libdrm_amdgpu.so.1",
            "libxcb.so.1", "libxcb-dri3.so.0", "libxcb-present.so.0", "libX11.so.6",
            "libX11-xcb.so.1", "libXrandr.so.2", "libwayland-client.so.0",
            "libwayland-cursor.so.0", "libxkbcommon.so.0", "libdecor-0.so.0",
            "libglib-2.0.so.0", "libgobject-2.0.so.0", "libgio-2.0.so.0",
            "libgmodule-2.0.so.0", "libgthread-2.0.so.0", "libgdk_pixbuf-2.0.so.0",
            "libgtk-3.so.0", "libgdk-3.so.0",
            "libmount.so.1", "libblkid.so.1", "libuuid.so.1", "libsmartcols.so.1",
            "libjpeg.so.8", "libtiff.so.6",
        )
        for name in host_libraries:
            self.assertIsNotNone(linux_bundle.HOST_LIBRARIES.match(name), name)
        for name in ("libmpv.so.2", "libavcodec.so.60", "libavutil.so.58", "libcairo.so.2", "libXpresent.so.1"):
            self.assertIsNone(linux_bundle.HOST_LIBRARIES.match(name), name)

    def test_system_library_resolution_is_not_a_successful_bundle(self):
        with patch.object(linux_bundle, "dependencies", return_value={"libmpv.so.2": Path("/usr/lib/libmpv.so.2")}):
            with self.assertRaisesRegex(RuntimeError, "bundled copy"):
                linux_bundle.verify_bundle(Path("plugin.so"), Path("bundle/lib"), ["libmpv.so.2"])


@unittest.skipUnless(platform.system() == "Linux" and os.getenv("JELLYXR_BUNDLE_INTEGRATION") == "1", "Requires Linux build dependencies")
class BundleIntegration(unittest.TestCase):
    def test_relocated_bundle_loads_decoder_and_preserves_system_package(self):
        arch = "arm64" if platform.machine() in ("aarch64", "arm64") else "x86_64"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = root / "system"
            original.mkdir()
            plugin = original / ("jellyxr_mpv.linux." + arch + ".so")
            source = root / "probe.c"
            source.write_text(
                '#include <mpv/client.h>\n'
                'int probe(void) { mpv_handle *h = mpv_create(); if (!h) return 1; mpv_destroy(h); return 0; }\n'
            )
            subprocess.run(["cc", "-shared", "-fPIC", str(source), "-lmpv", "-o", str(plugin)], check=True)
            before = plugin.read_bytes()
            linux_bundle.bundle(original, root / "bundled", arch)
            relocated = root / "relocated"
            (root / "bundled").rename(relocated)
            linux_bundle.verify_bundle(relocated / plugin.name, relocated / "lib", ["libmpv.so.2"])
            linux_bundle.verify_bundle(relocated / plugin.name, relocated / "lib", ["libXpresent.so.1"])
            decoder = ctypes.CDLL(str(relocated / plugin.name))
            self.assertEqual(decoder.probe(), 0)
            check_host_tiff_loader(root)
            self.assertEqual(plugin.read_bytes(), before)
            self.assertFalse((original / "lib").exists())
            self.assertFalse((relocated / "lib" / "libstdc++.so.6").exists())
            self.assertFalse((relocated / "lib" / "libgcc_s.so.1").exists())
            self.assertFalse((relocated / "lib" / "libjpeg.so.8").exists())
            self.assertFalse((relocated / "lib" / "libtiff.so.6").exists())
            for name in ("libglib-2.0.so.0", "libgobject-2.0.so.0", "libgio-2.0.so.0", "libmount.so.1", "libblkid.so.1", "libuuid.so.1"):
                self.assertFalse((relocated / "lib" / name).exists())
            for name in ("libxcb-dri3.so.0", "libX11.so.6", "libwayland-client.so.0", "libmount.so.1"):
                self.assertFalse((relocated / "lib" / name).exists())
                resolved = linux_bundle.dependencies(relocated / plugin.name)
                self.assertIn(name, resolved)
                self.assertNotEqual(resolved[name].resolve().parent, (relocated / "lib").resolve())
            manifest = json.loads((relocated / "bundled-libraries.json").read_text())
            self.assertTrue(any(item["library"] == "libmpv.so.2" for item in manifest))
            self.assertTrue(all(item["source_version"] for item in manifest))
            self.assertTrue(list((relocated / "licenses" / "linux-libraries").glob("*.txt")))


def check_host_tiff_loader(directory):
    tags = ((256, 4, 1), (257, 4, 1), (258, 3, 8), (259, 3, 1), (262, 3, 1),
            (273, 4, 122), (277, 3, 1), (278, 4, 1), (279, 4, 1))
    image = directory / "probe.tiff"
    data = b"II" + struct.pack("<HIH", 42, 8, len(tags))
    data += b"".join(struct.pack("<HHII", tag, kind, 1, value) for tag, kind, value in tags)
    image.write_bytes(data + struct.pack("<I", 0) + b"\x80")
    pixbuf_library = ctypes.CDLL("libgdk_pixbuf-2.0.so.0")
    pixbuf_library.gdk_pixbuf_new_from_file.argtypes = (ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p))
    pixbuf_library.gdk_pixbuf_new_from_file.restype = ctypes.c_void_p
    error = ctypes.c_void_p()
    pixbuf = pixbuf_library.gdk_pixbuf_new_from_file(os.fsencode(image), ctypes.byref(error))
    if not pixbuf:
        raise AssertionError("The host TIFF loader failed after loading the bundled decoder.")
    gobject = ctypes.CDLL("libgobject-2.0.so.0")
    gobject.g_object_unref.argtypes = (ctypes.c_void_p,)
    gobject.g_object_unref(pixbuf)


if __name__ == "__main__":
    unittest.main()
