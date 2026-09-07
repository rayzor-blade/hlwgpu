#!/bin/sh
# Build the wasm side module: `wgpu.wasm`, which a page loads beside a program.
#
#     scripts/build_wasm.sh [output directory]
#
# Two things about this build are not obvious and are not negotiable.
#
# * The standard library has to be rebuilt. A side module is
#   position-independent by definition, and the toolchain ships core and std
#   compiled without it, so linking against the shipped ones fails with a page
#   of "recompile with -fPIC". That needs nightly and the rust-src component.
#
# * The primitives have to be named as exports. `--gc-sections` would
#   otherwise remove every one of them, since nothing inside the module calls
#   them: the program does, by name, after loading it.
set -e

here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-"$here/target/wasm"}
mkdir -p "$out"

RUSTFLAGS="-C relocation-model=pic -C target-feature=+mutable-globals -C panic=abort" \
  cargo +nightly build -p hlwgpu \
    --target wasm32-wasip1 --no-default-features --release \
    -Z build-std=std,panic_abort

lld=$(find "$(rustc +nightly --print sysroot)/lib/rustlib" -name rust-lld -type f | head -1)
[ -n "$lld" ] || { echo "no rust-lld in the nightly sysroot" >&2; exit 1; }

# One --export per primitive, from the declaration that generated them.
exports=$(sed -n "s/^prim \([a-z_0-9]*\).*/--export=hlp_wgpu_\1/p" "$here/crates/hlwgpu/wgpu.api")

# shellcheck disable=SC2086
"$lld" -flavor wasm \
  --experimental-pic -shared --no-entry \
  --unresolved-symbols=import-dynamic --gc-sections \
  $exports \
  -o "$out/wgpu.wasm" \
  "$here/target/wasm32-wasip1/release/libhlwgpu.a"

cp "$here/crates/hlwgpu/js/hlwgpu.js" "$out/hlwgpu.js"
echo "wrote $out/wgpu.wasm ($(wc -c < "$out/wgpu.wasm" | tr -d ' ') bytes) and hlwgpu.js"
