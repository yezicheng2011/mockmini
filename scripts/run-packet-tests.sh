#!/usr/bin/env bash
# Portable packet-engine checks: unit tests + stateful fuzzer (default and stress limits).
#   SANITIZE=0         build without ASan/UBSan (default: sanitizers on)
#   MOCKMINI_FUZZ_STEPS / MOCKMINI_FUZZ_SEED   tune the fuzzer (see Tests/packet_fuzz.c)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build"
FLAGS=(-std=c11 -g -Wall -Wextra -Werror)
if [[ "${SANITIZE:-1}" != 0 ]]; then
  FLAGS+=(-O1 -fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all)
fi
if [[ "$(uname -s)" == Darwin ]]; then export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"; fi
${CC:-cc} "${FLAGS[@]}" \
  "$ROOT/Sources/Packet/wlp.c" "$ROOT/Sources/Packet/utun.c" "$ROOT/Tests/packet_test.c" \
  -o "$ROOT/.build/packet-tests"
${CC:-cc} "${FLAGS[@]}" \
  "$ROOT/Sources/Packet/wlp.c" "$ROOT/Tests/packet_fuzz.c" \
  -o "$ROOT/.build/packet-fuzz"
# Stress build: limits below the fuzzer's 160 tuples, so the flow limit and the
# send-queue budget are hit constantly.
${CC:-cc} "${FLAGS[@]}" -DWLP_FLOW_LIMIT=128u -DWLP_TX_BUFFERS=4u \
  "$ROOT/Sources/Packet/wlp.c" "$ROOT/Tests/packet_fuzz.c" \
  -o "$ROOT/.build/packet-fuzz-stress"
"$ROOT/.build/packet-tests"
"$ROOT/.build/packet-fuzz"
"$ROOT/.build/packet-fuzz-stress"
