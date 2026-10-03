#!/bin/sh
# Run crates/hlwgpu/test/host in headless Chrome: xgpu.wasm loaded and driven
# by a minimal JavaScript host instead of Ash, holding it to the contract in
# crates/hlwgpu/IMPORTS.md.
#
#     scripts/host_test.sh
#
# Exits 0 when the host prints PASS. Needs node 22 or later, nightly with
# rust-src (build_wasm.sh), and Google Chrome with WebGPU, or CHROME=<path>.
# CHROME_FLAGS adds flags, such as a software adapter on a machine without a
# GPU. Work files go to target/host-test.
set -e

here=$(cd "$(dirname "$0")/.." && pwd)
work="$here/target/host-test"
mkdir -p "$work"
seconds=${SECONDS_LIMIT:-120}

fail() { echo "host_test: $*" >&2; exit 1; }

chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
[ -x "$chrome" ] || fail "no Chrome at $chrome: set CHROME"

"$here/scripts/build_wasm.sh" "$work/wasm"

site="$work/site"
rm -rf "$site"
mkdir -p "$site"
cp "$work/wasm/xgpu.wasm" "$work/wasm/gpu-agent.mjs" "$site/"
cp "$here/crates/hlwgpu/test/host/index.html" "$here/crates/hlwgpu/test/host/program.mjs" \
  "$here/crates/hlwgpu/test/host/agent.mjs" "$site/"

free_port() { node -e 'const s = require("net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); })'; }
port=$(free_port)
debug=$(free_port)
node "$here/crates/hlwgpu/test/host/serve.mjs" "$site" "$port" > "$work/serve.log" 2>&1 &
server=$!
rm -rf "$work/chrome-profile"
# shellcheck disable=SC2086
"$chrome" --headless=new --no-first-run --no-default-browser-check \
  --user-data-dir="$work/chrome-profile" --remote-debugging-port="$debug" $CHROME_FLAGS \
  about:blank > "$work/chrome.log" 2>&1 &
browser=$!

status=0
node "$here/crates/hlwgpu/test/browser/drive.mjs" "http://127.0.0.1:$port/index.html" "$debug" "$seconds" || status=$?
kill "$browser" "$server" 2>/dev/null || true
wait "$browser" "$server" 2>/dev/null || true
[ $status -eq 0 ] && echo "host_test: PASS" || echo "host_test: FAIL"
exit $status
