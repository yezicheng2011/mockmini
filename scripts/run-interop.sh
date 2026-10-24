#!/usr/bin/env bash
# Real-server interop: Xray serves Shadowsocks, VMess, VMess+WS+TLS, Trojan and
# Trojan+WS+TLS on loopback; MockMini's own client streams verified TCP bytes and UDP
# datagrams through each to a local echo server.
#   XRAY=/path/to/xray            server binary (CI fetches a pinned, checksummed release)
#   MOCKMINI_TRUST_CA=1           trust the generated test CA in the System keychain (sudo);
#                                 its key is deleted once the leaf is signed, and outside CI
#                                 the CA is removed from the keychain again on exit (macOS
#                                 asks for confirmation; CI runners are discarded instead)
#   MOCKMINI_INTEROP_LONG_MB=N    also stream N MiB through VMess (crosses the nonce wrap)
#   MOCKMINI_SERVERS_ONLY=1       start the servers and wait (for testing other clients)
# The Swift client needs macOS 13+ (Network.framework, CryptoKit).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.build/interop"
XRAY="${XRAY:-xray}"
ECHO_PORT="${MOCKMINI_ECHO_PORT:-7000}"
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

# Throwaway CA and a localhost leaf that Apple's TLS policy accepts (SAN, serverAuth, <825 days).
printf '[req]\ndistinguished_name=dn\n[dn]\n[ca]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n' > ca.cnf
printf 'basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n' > leaf.ext
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -sha256 -subj "/CN=MockMini Interop Test CA" \
  -config ca.cnf -extensions ca -keyout ca-key.pem -out ca.pem 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=localhost" -keyout key.pem -out leaf.csr 2>/dev/null
openssl x509 -req -in leaf.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -days 30 -sha256 \
  -extfile leaf.ext -out cert.pem 2>/dev/null
rm -f ca-key.pem   # nothing else may ever be signed by a CA this machine might trust
TRUSTED=0
cleanup() {
  kill ${ECHO_PID:-} ${XRAY_PID:-} 2>/dev/null || true
  # remove-trusted-cert waits for an authorization dialog, which would hang a headless runner.
  if [[ $TRUSTED == 1 && -z "${CI:-}" ]]; then
    sudo security remove-trusted-cert -d "$WORK/ca.pem" || true
    sudo security delete-certificate -c "MockMini Interop Test CA" /Library/Keychains/System.keychain || true
  fi
}
trap cleanup EXIT
if [[ "${MOCKMINI_TRUST_CA:-0}" == 1 && "$(uname -s)" == Darwin ]]; then
  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.pem
  TRUSTED=1
fi

cp "$ROOT/Tests/interop/xray.json" config.json
python3 "$ROOT/Tests/interop/echo.py" "$ECHO_PORT" & ECHO_PID=$!
"$XRAY" run -c config.json > xray.log 2>&1 & XRAY_PID=$!
for port in "$ECHO_PORT" 10388 10389 10390 10086 10087 10443 10444; do
  for _ in $(seq 50); do (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && break; sleep 0.1; done
  (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null || { echo "port $port never opened"; cat xray.log; exit 1; }
done
if [[ "${MOCKMINI_SERVERS_ONLY:-0}" == 1 ]]; then echo "servers ready"; wait "$XRAY_PID"; fi

xcrun swiftc -O -swift-version 5 -parse-as-library \
  "$ROOT"/Sources/VPN/*.swift "$ROOT/Tests/InteropMain.swift" -o "$WORK/interop-tests"
MOCKMINI_ECHO_PORT="$ECHO_PORT" "$WORK/interop-tests" || { echo "--- xray.log"; cat xray.log; exit 1; }
