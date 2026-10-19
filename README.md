# wlsaplus-vpn-core

Original native VPN / packet core used by [WLSAPlus for macOS](https://github.com/yezicheng2011/wlsaplus-enablemacos).

**License: Apache License 2.0** (see `LICENSE` and `NOTICE`).

This repository is **not** based on mihomo, clash, sing-box, gVisor, or WireGuard.
It contains:

| Path | Role |
|------|------|
| `Sources/Packet/` | Original bounded userspace IP→proxy endpoint (`wlp`) + macOS `utun` adapter |
| `Sources/VPN/` | Original Shadowsocks AEAD, VMess, WebSocket framing, and Network.framework transport |
| `Tests/packet_test.c` | Portable C engine tests |
| `Tests/ProtocolTests.swift` | Crypto/wire fixtures (requires Apple CryptoKit to run) |

## Dial behavior (SS / WS)

Outbound TCP/TLS dials resolve A/AAAA records, **prefer IPv4**, and walk up to several
addresses with a short per-attempt timeout so a firewalled AAAA cannot exhaust the
authenticated probe budget before Shadowsocks or WebSocket negotiation starts.

## How the macOS app consumes this

Today the app **vendors by copy** from this tree into
`wlsaplus-enablemacos/native/Sources/{Packet,VPN}` (and matching tests). A git
submodule or Swift package pin can replace the copy later; keep secrets and
subscription URLs out of this core.

App-only glue that stays in the application repository:

- `VPNHelper` / `VPNService` / UI / privileged helper lifecycle
- Subscription URL handling and node catalog persistence

## Build notes

- `packet_test.c` builds with a C11 compiler on Linux/macOS (see the app’s `native/scripts/test.sh` for the exact flags used in CI).
- Swift protocol tests and Network.framework transport require macOS 13+ SDKs.
- Do not add mihomo or other GPL-incompatible proxy binaries to this tree.

## Provenance

See `PROVENANCE.md`.
