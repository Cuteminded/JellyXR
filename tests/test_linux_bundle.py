import ctypes
import importlib.util
import json
import os
from pathlib import Path
import platform
import subprocess
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
        for name in ("libc.so.6", "libm.so.6", "libpthread.so.0", "libGLX.so.0", "libvulkan.so.1", "libdrm_amdgpu.so.1"):
            self.assertIsNotNone(linux_bundle.HOST_LIBRARIES.match(name), name)
        for name in ("libmpv.so.2", "libavcodec.so.60", "libavutil.so.58", "libstdc++.so.6", "libcairo.so.2"):
            self.assertIsNone(linux_bundle.HOST_LIBRARIES.match(name), name)

    def test_system_library_resolution_is_not_a_successful_bundle(self):
        with patch.object(linux_bundle, "dependencies", return_value={"libmpv.so.2": Path("/usr/lib/libmpv.so.2")}):
            with self.assertRaisesRegex(RuntimeError, "bundled copy"):
                linux_bundle.verify_bundle(Path("plugin.so"), Path("bundle/lib"), ["libmpv.so.2"])


@unittest.skipUnless(platform.system() == "Linux" and os.getenv("JELLYFRAME_BUNDLE_INTEGRATION") == "1", "Requires Linux build dependencies")
class BundleIntegration(unittest.TestCase):
    def test_relocated_bundle_loads_decoder_and_preserves_system_package(self):
        arch = "arm64" if platform.machine() in ("aarch64", "arm64") else "x86_64"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = root / "system"
            original.mkdir()
            plugin = original / ("jellyframe_mpv.linux." + arch + ".so")
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
            decoder = ctypes.CDLL(str(relocated / plugin.name))
            self.assertEqual(decoder.probe(), 0)
            self.assertEqual(plugin.read_bytes(), before)
            self.assertFalse((original / "lib").exists())
            manifest = json.loads((relocated / "bundled-libraries.json").read_text())
            self.assertTrue(any(item["library"] == "libmpv.so.2" for item in manifest))
            self.assertTrue(all(item["source_version"] for item in manifest))
            self.assertTrue(list((relocated / "licenses" / "linux-libraries").glob("*.txt")))


if __name__ == "__main__":
    unittest.main()
