# MockMini

**A small, auditable proxy core in C and Swift.** Shadowsocks AEAD, VMess and
Trojan over TCP, TLS or WebSocket, on top of a bounded userspace TCP/IP endpoint.
About 2,600 lines, fuzzed, Apache-2.0.

**Site:** https://mockmini.danielye2011.uk/  
**License:** Apache License 2.0 (`LICENSE`, `NOTICE`) · credit **daniel.ye**

- **Small enough to review.** The whole core is about 2,600 lines of C and Swift.
  No vendored proxy kernel, no third-party TCP/IP stack, no Go runtime. It is
  **not** based on mihomo, Clash, sing-box, gVisor, or WireGuard.
- **Tested hard.** A stateful, checksum-aware fuzzer (≈99% line coverage of the
  packet engine) checks byte-exact in-order delivery on every run. libFuzzer
  smoke tests and ASan/UBSan run in CI on Linux and macOS.
- **Permissive license.** Apache-2.0: ship it in open- or closed-source apps.

| | |
|---|---|
| Protocols | Shadowsocks AEAD (aes-128-gcm, aes-256-gcm, chacha20-ietf-poly1305), VMess (legacy + AEAD; AES-128-GCM / ChaCha20-Poly1305), Trojan (TCP and UDP) |
| Transports | TCP, TLS, WebSocket (RFC 6455) |
| Packet engine | IPv4/IPv6 TCP + UDP, fragment reassembly, up to 1024 flows; portable C |
| Platforms | macOS 13+ (Network.framework, CryptoKit); packet engine builds anywhere |

```c
#include "wlp.h"

wlp_callbacks cb = { on_connect, on_data, on_close, on_packet, on_eof };
wlp_engine *engine = wlp_new(cb, ctx);

wlp_tick(engine, now_ms());                 // then at least every 100 ms
wlp_input(engine, ip_packet, length);       // raw IP packet from your tun device
// on_connect(flow, host, port, udp): dial upstream, then:
wlp_remote_open(engine, flow);
wlp_remote_data(engine, flow, bytes, n);    // upstream -> client
```

**Status:** young and actively developed. Known limits are listed honestly
[below](#known-limits-honest). Bug reports and reviews are very welcome.

| Path | Role |
|------|------|
| `Sources/Packet/` | Bounded userspace IP→proxy endpoint (`wlp`) + macOS `utun` adapter |
| `Sources/VPN/` | Shadowsocks AEAD, VMess, Trojan, WebSocket framing, Network.framework transport |
| `Tests/packet_test.c`, `Tests/packet_fuzz.c` | Portable C engine tests and stateful fuzzer |
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
| Concurrent flows | **1024** (hash lookup by tuple and id) |
| TCP receive reassembly | 32 KiB / flow, allocated on use, freed after 1s empty |
| Unacked remote TCP data | 256 KiB / flow, allocated on use, freed after 1s empty |
| Send queues held at once | **128** (32 MiB); `wlp_remote_capacity` reports 0 for others until one frees |
| UDP hold before remote open | 32 datagrams / 64 KiB |
| Fragment reassembly | 16 datagrams, 15s expiry |
| TCP options negotiated | **MSS + window scaling** (RFC 7323 receive side: client shift honoured up to 14, we echo shift 0; no SACK, timestamps, ECN) |
| Unsupported | ICMP, PMTUD, IPv6 jumbograms, IPsec, TCP urgent |

Protocol surface today: **Shadowsocks AEAD (aes-128-gcm, aes-256-gcm, chacha20-ietf-poly1305)** over TCP;
**VMess** (legacy + AEAD; aes-128-gcm or chacha20-poly1305 body) over TCP or WebSocket, with
optional TLS; **Trojan** (CONNECT and UDP ASSOCIATE) over TLS or WebSocket+TLS. Trojan
always verifies the server certificate; no uTLS fingerprinting, Reality or gRPC transport. Throughput and edge protocols are still behind mature Clash/mihomo
kernels; that gap is expected while MockMini stays original and small.

## Embedding

MockMini is the network core; your application supplies the rest:

- the tunnel device and routes (`utun` on macOS), feeding raw IP packets to `wlp_input`;
- one upstream connection per flow from `on_connect` (`ProxyConnection` in `Sources/VPN/`);
- node configuration, subscriptions and UI.

Keep secrets and subscription URLs out of this core. Treat `wlp_remote_capacity() == 0`
as "pause reads and retry after the next input or tick". Until a Swift package lands,
add `Sources/Packet` and `Sources/VPN` to your target directly.

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

Swift protocol tests and Network.framework transport require macOS 13+ SDKs:

```bash
xcrun swiftc -swift-version 5 -parse-as-library \
  Sources/VPN/*.swift Tests/ProtocolTests.swift Tests/ProtocolMain.swift -o .build/protocol-tests
.build/protocol-tests
```

Do not add mihomo or other third-party proxy-core binaries to this tree.

## Provenance

See `PROVENANCE.md`.
