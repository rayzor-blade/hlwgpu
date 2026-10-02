#!/usr/bin/env python3
"""Build a self-contained Haxelib ZIP from the platform release HDLLs."""

import argparse
import json
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "native" / "hdlls.json"
# Haxelib's SemVer: no leading zeros, and only these preview names.
SEMVER = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-(alpha|beta|rc)(\.(0|[1-9]\d*))?)?")


def version_of(tag: str) -> str:
    """A release tag as a Haxelib version: v2026.09.29 is 2026.9.29."""
    core, _, preview = tag.removeprefix("v").partition("-")
    if not re.fullmatch(r"\d+\.\d+\.\d+", core):
        raise ValueError(f"{tag} is not a Haxelib version")
    version = ".".join(str(int(part)) for part in core.split("."))
    if preview:
        version += "-" + preview
    if not SEMVER.fullmatch(version):
        raise ValueError(f"{tag} is not a Haxelib version")
    return version


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path, help="directory holding each manifest releaseAsset")
    parser.add_argument("--check", action="store_true", help="only check that every asset exists")
    parser.add_argument("--version", help="release tag to stamp into haxelib.json; haxelib.json's own otherwise")
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

    text = (ROOT / "haxelib.json").read_text()
    lib = json.loads(text)
    if args.version:
        try:
            version = version_of(args.version)
        except ValueError as error:
            parser.error(str(error))
        text = text.replace(f'"version": "{lib["version"]}"', f'"version": "{version}"', 1)
        if json.loads(text)["version"] != version:
            parser.error("could not stamp the version into haxelib.json")
    # Unversioned, so the nightly's link does not change from one build to the next.
    output = args.assets / f"{lib['name']}.zip"
    with ZipFile(output, "w", compression=ZIP_DEFLATED) as archive:
        archive.writestr("haxelib.json", text)
        for name in ("README.md", "LICENSE", "extraParams.hxml", "native/hdlls.json"):
            archive.write(ROOT / name, name)
        for source in sorted((ROOT / lib["classPath"]).rglob("*")):
            if source.is_file():
                archive.write(source, source.relative_to(ROOT))
        for spec in platforms.values():
            archive.write(args.assets / spec["releaseAsset"], spec["packagePath"])
    print(f"wrote {output}")


if __name__ == "__main__":
    main()
