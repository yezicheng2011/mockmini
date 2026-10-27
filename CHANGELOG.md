# Changelog

All notable changes to MockMini are recorded here. Versions follow
[Semantic Versioning](https://semver.org/); until 1.0.0, minor versions may change the API.

## [Unreleased]

### Protocols
- Trojan over plaintext TCP (`tls: false`) and plaintext WebSocket; TLS stays the default.
- Shadowsocks over WebSocket and/or system TLS (`network: ws`, `tls: true`).
- With these, `trojan-raw-none`, `trojan-websocket-none`, `shadowsocks-raw-none` and
  `shadowsocks-websocket-systemtls` (protocol-framing-security) are all usable.

### Tests
- Fixed an intermittent libFuzzer failure (`REQUIRE(t->id == 0)` in `on_connect`, seen on
  the v0.1.0 CI run). The engine was correct: RFC 791 reassembly keys only on source,
  destination, protocol and id, so with the UDP checksum omitted a stale fragment of one
  tuple plus a tail from another completes under the first fragment's ports. The harness
  attributed that connect to the wrong tuple; fragment ids are now tuple-disjoint.
- New `test_fragment_cross_datagram` pins this behaviour: the mix completes under the
  first fragment's tuple when the IPv4 UDP checksum is zero, and is rejected when present.

## [0.1.0] - 2026-10-24

First tagged release.

### Protocols
- Shadowsocks AEAD: aes-128-gcm, aes-256-gcm and chacha20-ietf-poly1305, over TCP and UDP,
  with a shared salt replay cache.
- VMess, legacy and AEAD headers, with AES-128-GCM or ChaCha20-Poly1305 body security, over
  TCP or WebSocket and optional TLS. The 16-bit body nonce counter wraps as in other
  implementations, so long transfers are no longer cut off after about 1 GiB.
- Trojan: CONNECT and UDP ASSOCIATE over TLS or WebSocket+TLS.
- VLESS: TCP and UDP over TCP, TLS or WebSocket+TLS (no flow control).

### Transports
- Network.framework dialing: A/AAAA resolution capped at 8 addresses, IPv4 first, at most 4
  attempts with a short per-attempt timeout, and clear dial errors.
- System TLS with mandatory certificate and host name verification.
- RFC 6455 WebSocket client framing with a dedicated HTTP 101 upgrade deadline.

### Packet engine (`wlp`)
- Bounded userspace IPv4/IPv6 TCP and UDP endpoint with fragment reassembly, written in
  portable C, plus a macOS `utun` adapter.
- Up to 1024 concurrent flows, found by seeded tuple and id hashes.
- Receive and send buffers are allocated on first use and freed after a second without use;
  at most 128 send queues (32 MiB) are held at once.
- TCP options: MSS and window scaling (RFC 7323 receive side).

### Architecture
- Layered connection stack: protocol (`ProxySession`), framing, security and dial
  (`TransportPlan`), assembled by `TransportStack`.
- Swift package with `MockMiniPacket` and `MockMiniVPN` products. The portable core builds on
  Linux against swift-crypto.

### Testing
- Deterministic C engine tests and a stateful, checksum-aware fuzzer under ASan/UBSan, plus a
  stress build with lowered limits and a libFuzzer smoke test.
- Swift wire fixtures computed independently from the public protocol descriptions.
- Real-server interop on macOS CI: a pinned, checksum-verified Xray release serves every
  supported protocol and transport on loopback, and MockMini's client streams verified TCP
  bytes and UDP datagrams through each, including 1.25 GiB through VMess.

### Known limits
See "Known limits (honest)" in the README: no SACK, timestamps, ECN, ICMP or PMTUD in the
packet engine; no gRPC transport; no VLESS flow control.

[0.1.0]: https://github.com/yezicheng2011/mockmini/releases/tag/v0.1.0
