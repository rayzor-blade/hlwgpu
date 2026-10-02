#!/bin/sh
# Run crates/hlwgpu/test/browser/GpuTest.hx in headless Chrome, through Ash's
# page, against the browser bundle scripts/build_wasm.sh makes.
#
#     scripts/browser_test.sh
#
# Exits 0 when the program prints PASS. It checks what the GPU hands back:
# a compute pass's integers, rendered pixels, copies, queries, and the
# errors and rejections a program observes through ash.Future. A broken
# mailbox or a future that never wakes fails by timeout.
#
# Needs:
#   * Ash that loads side modules in a page: `ash` on PATH, or ASH=/path/to/ash.
#   * ash-future's Haxe sources: ASH_FUTURE=<dir with ash/Future.hx>, else
#     `haxelib libpath ash-future`, else haxelib/ash-future in the Ash
#     checkout ASH was built in.
#   * haxe 4.3, node 22 or later, and nightly with rust-src (build_wasm.sh).
#   * Google Chrome with WebGPU, or CHROME=/path/to/chrome. CHROME_FLAGS adds
#     flags, such as a software adapter on a machine without a GPU.
# Work files go to target/browser-test.
set -e

here=$(cd "$(dirname "$0")/.." && pwd)
work="$here/target/browser-test"
mkdir -p "$work"
seconds=${SECONDS_LIMIT:-120}

fail() { echo "browser_test: $*" >&2; exit 1; }

ash=${ASH:-$(command -v ash || true)}
[ -x "$ash" ] || fail "no ash: put it on PATH or set ASH"

future=${ASH_FUTURE:-$(haxelib libpath ash-future 2>/dev/null || true)}
[ -f "$future/ash/Future.hx" ] || future="$(dirname "$ash")/../../haxelib/ash-future"
[ -f "$future/ash/Future.hx" ] || fail "no ash-future sources: set ASH_FUTURE"

chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
[ -x "$chrome" ] || fail "no Chrome at $chrome: set CHROME"

"$here/scripts/build_wasm.sh" "$work/wasm"

site="$work/site"
rm -rf "$site"
mkdir -p "$site"
cp "$work/wasm/xgpu.wasm" "$work/wasm/gpu.mjs" "$work/wasm/gpu-worker.mjs" \
  "$work/wasm/gpu-agent.mjs" "$work/wasm/hlwgpu.js" "$site/"

echo "== compiling crates/hlwgpu/test/browser/GpuTest.hx"
haxe -cp "$here/crates/hlwgpu/test/browser" -cp "$here/haxe" -cp "$future" \
  -main GpuTest -hl "$work/gputest.hl"
# Built beside the side module, so the page loads it. The fiber transform
# lets an await suspend while the page completes it.
ASH_WASM_FIBERS=1 "$ash" --build "$site/gputest.wasm" --target wasm32-wasip1-threads "$work/gputest.hl"

free_port() { node -e 'const s = require("net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); })'; }
port=$(free_port)
debug=$(free_port)
"$ash" serve --port "$port" "$site" > "$work/serve.log" 2>&1 &
server=$!
rm -rf "$work/chrome-profile"
# shellcheck disable=SC2086
"$chrome" --headless=new --no-first-run --no-default-browser-check \
  --user-data-dir="$work/chrome-profile" --remote-debugging-port="$debug" \
  --force-device-scale-factor=2 --window-size=1280,1000 $CHROME_FLAGS \
  about:blank > "$work/chrome.log" 2>&1 &
browser=$!

status=0
node "$here/crates/hlwgpu/test/browser/drive.mjs" "http://127.0.0.1:$port/index.html" "$debug" "$seconds" || status=$?
kill "$browser" "$server" 2>/dev/null || true
wait "$browser" "$server" 2>/dev/null || true
[ $status -eq 0 ] && echo "browser_test: PASS" || echo "browser_test: FAIL"
exit $status
