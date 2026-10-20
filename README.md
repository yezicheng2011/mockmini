# MockMini

Original native VPN / packet core used by [WLSAPlus for macOS](https://github.com/yezicheng2011/wlsaplus-enablemacos).

**Site:** https://mockmini.danielye2011.uk/  
**License:** Apache License 2.0 (`LICENSE`, `NOTICE`) · credit **daniel.ye**

This repository is **not** based on mihomo, Clash, sing-box, gVisor, or WireGuard.
MockMini is under **continuous development**: dial reliability, protocol coverage, and
packet-engine hardening land here first, then vendor into the macOS app.

| Path | Role |
|------|------|
| `Sources/Packet/` | Bounded userspace IP→proxy endpoint (`wlp`) + macOS `utun` adapter |
| `Sources/VPN/` | Shadowsocks AEAD, VMess, WebSocket framing, Network.framework transport |
| `Tests/packet_test.c` | Portable C engine tests |
| `Tests/ProtocolTests.swift` | Crypto/wire fixtures (requires Apple CryptoKit / macOS SDK) |

## Dial behavior (SS / WS)

Outbound TCP/TLS dials:

1. Resolve A/AAAA (cap 8 addresses).
2. **Prefer IPv4**, then IPv6.
3. Dial at most **4** addresses with a short per-attempt timeout (~6s).
4. Surface a clear `ProxyError.dial` when every candidate fails.
5. WebSocket paths add a dedicated **HTTP 101 upgrade deadline** (~12s) after TCP is ready,
   so a silent HTTP listener cannot burn the whole outer probe budget.

Root cause of earlier SS/WS smoke failures was often a firewalled AAAA consuming the
authenticated-probe window before Shadowsocks or WebSocket negotiation started.

## Known limits (honest)

The packet engine is a **small TCP/UDP proxy endpoint**, not a general IP stack:

| Limit | Value |
|-------|--------|
| Concurrent flows | **128** |
| TCP receive reassembly | 32 KiB / flow |
| Unacked remote TCP data | 256 KiB / flow |
| UDP hold before remote open | 32 datagrams / 64 KiB |
| Fragment reassembly | 16 datagrams, 15s expiry |
| TCP options negotiated | **MSS only** (no window scaling, SACK, timestamps, ECN) |
| Unsupported | ICMP, PMTUD, IPv6 jumbograms, IPsec, TCP urgent |

Protocol surface today: **Shadowsocks AEAD (aes-256-gcm)**, **VMess** (legacy + AEAD) over
TCP or WebSocket+TLS. Throughput and edge protocols are still behind mature Clash/mihomo
kernels; that gap is expected while MockMini stays original and small.

## How the macOS app consumes this

The app **vendors by copy** into `wlsaplus-enablemacos/native/Sources/{Packet,VPN}`
(and matching tests). Keep secrets and subscription URLs out of this core.

App-only glue that stays in the application repository:

- `VPNHelper` / `VPNService` / UI / privileged helper lifecycle
- Subscription URL handling and node catalog persistence

## Build / test

```bash
# Portable packet engine (Linux or macOS): unit tests + stateful fuzzer, ASan/UBSan
bash scripts/run-packet-tests.sh

# Longer fuzz run, or replay one seed
MOCKMINI_FUZZ_STEPS=5000000 bash scripts/run-packet-tests.sh
MOCKMINI_FUZZ_SEED=42 ./.build/packet-fuzz
```

The fuzzer (`Tests/packet_fuzz.c`) builds checksum-valid traffic so it reaches the TCP state
machine, reassembly, fragment cache and flow limit (≈99% line coverage of `wlp.c`), and checks
byte-exact in-order delivery plus well-formed output on every callback. CI runs it on Linux
(gcc/clang), as a libFuzzer smoke, and on macOS together with the Swift protocol tests.

Swift protocol tests and Network.framework transport require macOS 13+ SDKs
(see the app’s `native/scripts/test.sh`).

Do not add mihomo or other third-party proxy-core binaries to this tree.

## Provenance

See `PROVENANCE.md`.
