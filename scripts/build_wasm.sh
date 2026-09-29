#!/bin/sh
# Build the Ash wasm side module and its browser-agent JavaScript.
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
# * xgpu's mailbox needs shared memory and wasm atomics. Rust's threaded WASI
#   target supplies a standard library compiled for both. The crate defines
#   its unused TLS errno slot locally because dylink cannot import TLS data.
set -e

here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-"$here/target/wasm"}
mkdir -p "$out"
rm -f "$out/wgpu.wasm" "$out/hlwgpu.js"

HLWGPU_WASM_JS_OUT="$out" \
CARGO_PROFILE_RELEASE_LTO=false \
RUSTFLAGS="-C relocation-model=pic -C target-feature=+mutable-globals -C panic=abort" \
  cargo +nightly rustc -p hlwgpu --lib --crate-type staticlib \
    --target wasm32-wasip1-threads --no-default-features --release \
    -Z build-std=std,panic_abort

lld=$(find "$(rustc +nightly --print sysroot)/lib/rustlib" -name rust-lld -type f | head -1)
[ -n "$lld" ] || { echo "no rust-lld in the nightly sysroot" >&2; exit 1; }

# One resolver export per generated Haxe primitive. The file name is xgpu.wasm
# because @:hlNative("xgpu", ...) uses the native library's name on wasm too.
exports=$(sed -n 's/.*@:hlNative("xgpu", "\([^"]*\)").*/--export=hlp_\1/p' \
  "$here"/haxe/gpu/*.hx | sort -u)
[ -n "$exports" ] || { echo "no xgpu primitives found in haxe/gpu" >&2; exit 1; }

# shellcheck disable=SC2086
"$lld" -flavor wasm \
  --experimental-pic -shared --no-entry \
  --unresolved-symbols=import-dynamic --gc-sections --no-export-dynamic \
  --shared-memory --max-memory=1073741824 \
  $exports \
  --whole-archive "$here/target/wasm32-wasip1-threads/release/libhlwgpu.a" --no-whole-archive \
  -o "$out/xgpu.wasm"

cp "$here/crates/hlwgpu/js/gpu.mjs" "$out/gpu.mjs"
cp "$here/crates/hlwgpu/js/gpu-worker.mjs" "$out/gpu-worker.mjs"
cp "$here/crates/hlwgpu/js/hlwgpu.js" "$out/hlwgpu.js"
echo "wrote $out/xgpu.wasm ($(wc -c < "$out/xgpu.wasm" | tr -d ' ') bytes), hlwgpu.js and browser agent modules"
