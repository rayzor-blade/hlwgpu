#!/bin/sh
# Build hlwindow's wasm side module and its page agent modules.
#
#     scripts/build_window_wasm.sh [output directory]
#
# Built as scripts/build_wasm.sh builds xgpu.wasm: a position-independent
# standard library on nightly, the threaded WASI target for the mailbox's
# shared memory, and every primitive named as an export.
set -e

here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-"$here/target/wasm"}
mkdir -p "$out"
rm -f "$out/xwindow.wasm" "$out/xwindow.mjs" "$out/xwindow_wire.mjs"

# The build script generates the page modules into its OUT_DIR, which cargo
# reports among its JSON messages.
messages=$(
  CARGO_PROFILE_RELEASE_LTO=false \
  RUSTFLAGS="-C relocation-model=pic -C target-feature=+mutable-globals -C panic=abort" \
    cargo +nightly rustc -p hlwindow --lib --crate-type staticlib \
      --target wasm32-wasip1-threads --release \
      -Z build-std=std,panic_abort --message-format=json-render-diagnostics
)
page=$(printf '%s\n' "$messages" \
  | grep '"reason":"build-script-executed"' | grep '/crates/hlwindow#' \
  | sed -n 's/.*"out_dir":"\([^"]*\)".*/\1/p' | tail -1)/page
[ -f "$page/xwindow.mjs" ] || { echo "no page modules in $page" >&2; exit 1; }
cp "$page/xwindow.mjs" "$page/xwindow_wire.mjs" "$out/"

lld=$(find "$(rustc +nightly --print sysroot)/lib/rustlib" -name rust-lld -type f | head -1)
[ -n "$lld" ] || { echo "no rust-lld in the nightly sysroot" >&2; exit 1; }

# One resolver export per generated Haxe primitive. The file name is
# xwindow.wasm because @:hlNative("xwindow", ...) names the library.
exports=$(sed -n 's/.*@:hlNative("xwindow", "\([^"]*\)").*/--export=hlp_\1/p' \
  "$here"/crates/hlwindow/haxe/window/*.hx | sort -u)
[ -n "$exports" ] || { echo "no xwindow primitives found in crates/hlwindow/haxe" >&2; exit 1; }

# shellcheck disable=SC2086
"$lld" -flavor wasm \
  --experimental-pic -shared --no-entry \
  --unresolved-symbols=import-dynamic --gc-sections --no-export-dynamic \
  --shared-memory --max-memory=1073741824 \
  $exports \
  --whole-archive "$here/target/wasm32-wasip1-threads/release/libhlwindow.a" --no-whole-archive \
  -o "$out/xwindow.wasm"

echo "wrote $out/xwindow.wasm ($(wc -c < "$out/xwindow.wasm" | tr -d ' ') bytes), xwindow.mjs and xwindow_wire.mjs"
