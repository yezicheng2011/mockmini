# Provenance

The Swift and C sources in this repository are an original implementation of a
bounded userspace packet endpoint plus Shadowsocks AEAD, VMess (legacy and AEAD),
Trojan, and RFC6455 WebSocket client framing. They were written for WLSAPlus macOS and
extracted here for reuse. No third-party VPN kernel, TCP/IP stack, or proxy-core
source or binary (including mihomo, clash, sing-box, gVisor, or WireGuard) is
included or vendored.

Allowed runtime dependencies are platform-provided: Network.framework,
Security/CryptoKit/CommonCrypto, and Darwin utun on Apple platforms. The C
packet engine (`Sources/Packet/wlp.c`) is portable and has no third-party code.

Protocol references (not incorporated source):

- https://shadowsocks.org/doc/aead.html
- https://www.v2fly.org/developer/protocols/vmess.html
- https://trojan-gfw.github.io/trojan/protocol
- https://www.rfc-editor.org/rfc/rfc6455
- https://www.rfc-editor.org/rfc/rfc9293

This note is not a legal audit or patent search.
