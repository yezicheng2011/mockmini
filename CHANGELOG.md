# Changelog

All notable changes to MockMini are recorded here. Versions follow
[Semantic Versioning](https://semver.org/); until 1.0.0, minor versions may change the API.

## [Unreleased]

### Protocols
- Trojan over plaintext TCP (`tls: false`) and plaintext WebSocket; TLS stays the default.
- Shadowsocks over WebSocket and/or system TLS (`network: ws`, `tls: true`).
- With these, `trojan-raw-none`, `trojan-websocket-none`, `shadowsocks-raw-none` and
  `shadowsocks-websocket-systemtls` (protocol-framing-security) are all usable.
- Trojan no longer needs CommonCrypto: its SHA-224 password token comes from a small
  original FIPS 180-4 implementation (`Sources/VPN/SHA224.swift`), so Trojan builds and its
  wire tests run in the Linux CI job too. Tokens are byte-identical to before.
- VMess no longer needs CommonCrypto either: the AES-128 block cipher it uses for the legacy
  CFB128 header and the AEAD auth ID is a small original FIPS 197 implementation
  (`Sources/VPN/AES128.swift`). VMess now builds on Linux, MockMiniVPN has no CommonCrypto
  dependency at all, and all VMess wire fixtures (AEAD and legacy, AES-GCM and ChaCha20) are
  byte-identical to before.

### Performance
- WebSocket client frames are now built in one allocation and masked in place instead of
  appending each masked payload byte to a growing `Data`. Output is byte-identical; this
  removes a per-byte cost from every VMess/VLESS/Trojan/Shadowsocks-over-WebSocket upload.
- Stream connections now merge the wire chunks of one application write into as few
  transport writes as possible (`StreamCoalescer`, capped at 256 KiB per write). A 40 KB
  Shadowsocks or VMess upload used to leave as three separate sends (three TLS records,
  three WebSocket frames); it is now one. When a connection becomes ready, the protocol
  header and all data queued while dialing also go out together, so the first segment is no
  longer a header on its own. Bytes on the wire are unchanged; UDP sockets (Shadowsocks UDP)
  still send exactly one datagram per write.

### Tests
- Stream write coalescing: empty input, single chunk, empty-chunk dropping, exact-limit and
  oversize-chunk cases, 200 randomized chunk sets (bytes identical, limit respected), and a
  Shadowsocks header plus three AEAD chunks leaving as one write.
- SHA-224 vectors (empty, "abc", the 448-bit NIST message, 55/56/64-byte padding edges and
  one million "a") on every platform; Trojan wire fixtures now also run on Linux.
- AES-128 vectors (FIPS 197 appendices B and C.1, SP 800-38A ECB-AES128) plus the existing
  NIST CFB128 and VMess wire fixtures now run in the Linux CI job.
- WebSocket client masking checked against a naive reference at every length-encoding
  boundary (0 to 300,001 bytes), including sliced payloads with a non-zero start index,
  plus the 2 MiB data-frame and 125-byte control-frame limits.
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
