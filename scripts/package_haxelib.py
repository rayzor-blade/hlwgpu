#!/usr/bin/env python3
"""Build a self-contained Haxelib ZIP from the platform release HDLLs."""

import argparse
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "native" / "hdlls.json"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path, help="directory holding each manifest releaseAsset")
    parser.add_argument("--check", action="store_true", help="only check that every asset exists")
    args = parser.parse_args()

    platforms = json.loads(MANIFEST.read_text())
    missing = [
        spec["releaseAsset"]
        for spec in platforms.values()
        if not (args.assets / spec["releaseAsset"]).is_file()
    ]
    if missing:
        parser.error("missing release HDLLs: " + ", ".join(missing))
    if args.check:
        return

    lib = json.loads((ROOT / "haxelib.json").read_text())
    output = args.assets / f"{lib['name']}-{lib['version']}.zip"
    with ZipFile(output, "w", compression=ZIP_DEFLATED) as archive:
        for name in ("haxelib.json", "README.md", "LICENSE", "extraParams.hxml", "native/hdlls.json"):
            archive.write(ROOT / name, name)
        for source in sorted((ROOT / lib["classPath"]).rglob("*")):
            if source.is_file():
                archive.write(source, source.relative_to(ROOT))
        for spec in platforms.values():
            archive.write(args.assets / spec["releaseAsset"], spec["packagePath"])
    print(f"wrote {output}")


if __name__ == "__main__":
    main()
