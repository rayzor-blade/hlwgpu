"""The Haxelib ZIP carries the web build, for a build defined `wasm` to stage; no native compilation needed."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts/package_haxelib.py"
WEB = ("xgpu.wasm", "gpu.mjs", "gpu-worker.mjs", "gpu-agent.mjs", "hlwgpu.js")


def fake_assets(directory: Path) -> Path:
    assets = directory / "assets"
    assets.mkdir()
    for spec in json.loads((ROOT / "native/hdlls.json").read_text()).values():
        (assets / spec["releaseAsset"]).write_bytes(b"hdll")
    return assets


def fake_web(directory: Path, names=WEB) -> Path:
    web = directory / "web"
    web.mkdir()
    for name in names:
        (web / name).write_bytes(name.encode())
    return web


class PackageTest(unittest.TestCase):
    def test_the_web_build_is_in_the_zip_beside_the_haxe_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            assets, web = fake_assets(directory), fake_web(directory)
            subprocess.run([sys.executable, str(SCRIPT), str(assets), "--web", str(web)], check=True, capture_output=True)
            names = ZipFile(assets / "hlwgpu.zip").namelist()
            for name in WEB:
                self.assertIn(f"web/{name}", names)

    def test_a_web_build_missing_a_file_stops_the_release(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            assets, web = fake_assets(directory), fake_web(directory, WEB[:-1])
            result = subprocess.run([sys.executable, str(SCRIPT), str(assets), "--web", str(web)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("hlwgpu.js", result.stderr)
            self.assertFalse((assets / "hlwgpu.zip").exists())


if __name__ == "__main__":
    unittest.main()
