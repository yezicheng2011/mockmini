# Tests

- `packet_test.c` — deterministic protocol tests; compile and link with `Sources/Packet/wlp.c`
  (utun is stubbed off macOS).
- `packet_fuzz.c` — stateful, structure-aware fuzzer. Generates checksum-valid IPv4/IPv6
  TCP/UDP traffic (options, extension headers, fragments, duplicate ACKs, truncation) mixed
  with random remote-side calls and clock jumps, and checks engine invariants on every
  callback: fresh flow ids, no events after close, ≤`WLP_FLOW_LIMIT` live flows, byte-exact in-order TCP
  delivery, valid emitted packets (lengths, checksums, MSS, window), and capacity bounds.
  `MOCKMINI_FUZZ_STEPS` / `MOCKMINI_FUZZ_SEED` tune it; build with
  `clang -DMOCKMINI_LIBFUZZER -fsanitize=fuzzer,address,undefined` for coverage-guided runs.
- `ProtocolTests.swift` + `ProtocolMain.swift` — crypto/wire fixtures; compile together with
  `Sources/VPN/*.swift` on macOS with CryptoKit (`-parse-as-library`).
- `InteropMain.swift` + `interop/` — real-server interop. `scripts/run-interop.sh` starts Xray
  (Shadowsocks ×3 ciphers, VMess, VMess+WS+TLS, Trojan, Trojan+WS+TLS, VLESS, VLESS+TLS,
  VLESS+WS+TLS) and a TCP/UDP echo
  server on loopback with a throwaway CA, then streams position-checked bytes and datagrams
  through MockMini's client. The Xray binary is supplied by the caller, never stored here.

`scripts/run-packet-tests.sh` runs both C suites under ASan/UBSan. CI (`.github/workflows/ci.yml`)
runs them on Linux (gcc + clang), a 60-second libFuzzer smoke, macOS including Swift, and the
interop suite against a pinned, checksum-verified Xray release (including 1.25 GiB through VMess,
past its 16-bit nonce wrap).

No live subscription credentials belong in this repository.
