#!/usr/bin/env python3
"""Release invariants hlwgpu keeps with xgpu.

    scripts/release_check.py pins          # fail unless they hold
    scripts/release_check.py notes <file>  # write the release notes' xgpu section

`pins` checks that xgpu-core, xgpu-backend and xgpu-bindgen are pinned to one
revision in the workspace's Cargo.toml and resolved to it in Cargo.lock, and
that hlwgpu carries no WebGPU IDL of its own: the public API is xgpu's. The
committed haxe/gpu package matching the pin is CI's generated-files check.

`notes` names the pinned xgpu revision and the WebGPU IDL snapshot it carries,
read from the checkout cargo resolved.
"""

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CRATES = ("xgpu-core", "xgpu-backend", "xgpu-bindgen")
REPO = "https://github.com/rayzor-blade/xgpu.git"


def fail(message: str) -> None:
    print(f"release_check: {message}", file=sys.stderr)
    sys.exit(1)


def pinned_revision() -> str:
    manifest = (ROOT / "Cargo.toml").read_text()
    revs = {}
    for crate in CRATES:
        found = re.findall(rf'^{crate}\s*=\s*{{[^}}]*rev\s*=\s*"([0-9a-f]+)"', manifest, re.M)
        if not found:
            fail(f"the workspace's Cargo.toml does not pin {crate} by rev")
        revs.update({crate if n == 0 else f"{crate} (#{n + 1})": rev for n, rev in enumerate(found)})
    if len(set(revs.values())) != 1:
        listed = ", ".join(f"{name} at {rev}" for name, rev in sorted(revs.items()))
        fail(f"the xgpu crates are pinned to different revisions: {listed}. Pin all three to one rev.")
    rev = next(iter(revs.values()))
    if len(rev) != 40:
        fail(f"xgpu is pinned to {rev}; pin the full 40-character revision")
    return rev


def check_lock(rev: str) -> None:
    lock = (ROOT / "Cargo.lock").read_text()
    for crate in CRATES:
        match = re.search(rf'name = "{crate}"\nversion = "[^"]*"\nsource = "([^"]*)"', lock)
        if not match:
            fail(f"Cargo.lock has no git source for {crate}; run cargo build and commit Cargo.lock")
        if not match.group(1).endswith(f"#{rev}"):
            fail(f"Cargo.lock resolves {crate} to {match.group(1)}, not xgpu {rev}; "
                 "run cargo build and commit Cargo.lock")


def check_no_local_idl() -> None:
    tracked = subprocess.run(["git", "ls-files", "*.idl"], cwd=ROOT, capture_output=True, text=True, check=True)
    if tracked.stdout.strip():
        fail("hlwgpu tracks WebGPU IDL of its own, which is not the public API's source: "
             + ", ".join(tracked.stdout.split()) + ". The API comes from xgpu's api/spec.")


def xgpu_checkout() -> Path:
    metadata = subprocess.run(["cargo", "metadata", "--format-version", "1", "--locked"], cwd=ROOT,
                              capture_output=True, text=True, check=True)
    for package in json.loads(metadata.stdout)["packages"]:
        if package["name"] == "xgpu-core":
            # crates/xgpu-core/Cargo.toml, two levels below the repository.
            return Path(package["manifest_path"]).parents[2]
    fail("cargo metadata has no xgpu-core")


def notes(path: Path) -> None:
    rev = pinned_revision()
    root = xgpu_checkout()
    idl = root / "api" / "spec" / "webgpu.idl"
    if not idl.is_file():
        fail(f"xgpu {rev} has no api/spec/webgpu.idl")
    digest = hashlib.sha256(idl.read_bytes()).hexdigest()
    readme = (root / "api" / "README.md").read_text()
    fetched = re.search(r"fetched on (\d{4}-\d{2}-\d{2})\s+from\s+<([^>]+)>", readme)
    if not fetched:
        fail(f"xgpu {rev}'s api/README.md does not say when webgpu.idl was fetched and from where")
    path.write_text(
        f"Built on [xgpu {rev[:12]}](https://github.com/rayzor-blade/xgpu/tree/{rev}). "
        f"Its WebGPU IDL snapshot, [`api/spec/webgpu.idl`](https://github.com/rayzor-blade/xgpu/blob/{rev}/api/spec/webgpu.idl), "
        f"was fetched on {fetched.group(1)} from <{fetched.group(2)}> (sha256 `{digest}`).\n"
    )
    print(path.read_text(), end="")


def main() -> None:
    if len(sys.argv) >= 2 and sys.argv[1] == "pins":
        rev = pinned_revision()
        check_lock(rev)
        check_no_local_idl()
        print(f"xgpu-core, xgpu-backend and xgpu-bindgen are at xgpu {rev}")
    elif len(sys.argv) == 3 and sys.argv[1] == "notes":
        notes(Path(sys.argv[2]))
    else:
        fail(__doc__)


if __name__ == "__main__":
    main()
