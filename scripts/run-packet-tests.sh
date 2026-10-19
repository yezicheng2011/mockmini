#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build"
${CC:-cc} -std=c11 -g -Wall -Wextra -Werror \
  "$ROOT/Sources/Packet/wlp.c" "$ROOT/Sources/Packet/utun.c" "$ROOT/Tests/packet_test.c" \
  -o "$ROOT/.build/packet-tests"
exec "$ROOT/.build/packet-tests"
