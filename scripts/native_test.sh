#!/bin/sh
# Run crates/hlwgpu/test/browser/GpuTest.hx natively on stock HashLink, with
# Ash Future's ABI from ash_future.hdll, or with ASH=<path> on Ash.
#
#     scripts/native_test.sh <xgpu.hdll> <ash-future dir>
#
# The ash-future dir is the unpacked ash-future Haxelib release ZIP: its
# Haxe sources and native/<platform>/ash_future.hdll. HL names the hl
# executable (default: hl on PATH) and HL_LIB_DIR the directory holding
# libhl. GPU_TEST_WITHOUT_ADAPTER=skip lets a machine with no GPU adapter
# pass with SKIP rather than fail. Exits 0 on PASS or SKIP.
#
# HashLink's JIT emits x86-64, so stock HashLink needs an x86-64 machine;
# Ash runs anywhere it is built.
set -e

here=$(cd "$(dirname "$0")/.." && pwd)
work="$here/target/native-test"
seconds=${SECONDS_LIMIT:-300}

fail() { echo "native_test: $*" >&2; exit 1; }

xgpu=$1
future=$2
[ -f "$xgpu" ] || fail "no xgpu.hdll: pass its path"
[ -f "$future/ash/Future.hx" ] || fail "no ash-future sources in '$future'"
if [ -n "$ASH" ]; then
  [ -x "$ASH" ] || fail "no ash at $ASH"
  runtime=Ash
else
  hl=${HL:-$(command -v hl || true)}
  [ -n "$hl" ] || fail "no hl: put it on PATH or set HL"
  runtime="stock HashLink"
fi

case "$(uname -s)" in
  Linux) platform=linux ;;
  Darwin) platform=macos ;;
  MINGW* | MSYS* | CYGWIN*) platform=windows ;;
  *) fail "unknown platform $(uname -s)" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) platform=$platform-x86_64 ;;
  arm64 | aarch64) platform=$platform-aarch64 ;;
esac
rm -rf "$work"
mkdir -p "$work"
cp "$xgpu" "$work/xgpu.hdll"
# Ash has Future built in; stock HashLink loads it from ash_future.hdll.
stock=""
if [ -z "$ASH" ]; then
  [ -f "$future/native/$platform/ash_future.hdll" ] || fail "no ash_future.hdll for $platform"
  cp "$future/native/$platform/ash_future.hdll" "$work/"
  stock="-D ash_future_stock"
fi

echo "== compiling crates/hlwgpu/test/browser/GpuTest.hx for $runtime"
# shellcheck disable=SC2086
haxe -cp "$here/crates/hlwgpu/test/browser" -cp "$here/haxe" -cp "$future" \
  $stock -main GpuTest -hl "$work/gputest.hl"

# Stock HashLink opens hdlls by bare name, which the loader finds on these
# paths, beside libhl from wherever hl was built. Ash stages its own.
if [ -z "$ASH" ]; then
  lib="$(dirname "$hl")${HL_LIB_DIR:+:$HL_LIB_DIR}"
  export LD_LIBRARY_PATH="$work:$lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export DYLD_LIBRARY_PATH="$work:$lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
  export PATH="$work:$lib:$PATH"
fi

status=0
(cd "$work" && timeout "$seconds" "${ASH:-$hl}" gputest.hl) > "$work/out.log" 2>&1 || status=$?
cat "$work/out.log"
[ $status -eq 0 ] || fail "$runtime exited with $status"
if grep -qx "PASS" "$work/out.log"; then
  echo "native_test: PASS"
elif grep -qx "SKIP: no adapter" "$work/out.log"; then
  echo "native_test: SKIP, no GPU adapter on this machine"
else
  fail "FAIL"
fi
