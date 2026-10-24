// Real-server interop driver for scripts/run-interop.sh. Each case pushes a verified
// byte stream, then a few datagrams, through ProxyConnection and a real Xray server
// to a loopback echo server.
import Foundation
import Dispatch

@main
enum InteropMain {
    private struct Failure: Error, CustomStringConvertible { let description: String }
    private static let environment = ProcessInfo.processInfo.environment
    private static let echoPort = UInt16(environment["MOCKMINI_ECHO_PORT"] ?? "") ?? 7000
    private static let uuid = "b831381d-6324-4d53-ad4f-8cda48b30811"

    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)   // stream results as they happen, not at exit
        func node(_ name: String, _ type: String, _ port: UInt16, cipher: String? = nil,
                  password: String? = nil, uuid: String? = nil, tls: Bool? = nil,
                  network: String? = nil, path: String? = nil) -> ProxyNode {
            let secure = tls == true || type == "trojan"
            return ProxyNode(id: name, name: name, type: type, server: "127.0.0.1", port: port,
                             cipher: cipher, password: password, uuid: uuid, alterId: 0, tls: tls,
                             serverName: secure ? "localhost" : nil, network: network,
                             wsPath: path, udp: true)
        }
        let mib = 1 << 20
        var cases: [(node: ProxyNode, bytes: Int, udp: Bool)] = [
            (node("ss-aes-256-gcm", "ss", 10388, cipher: "aes-256-gcm", password: "mockmini-ss"), 4 * mib, true),
            (node("ss-aes-128-gcm", "ss", 10390, cipher: "aes-128-gcm", password: "mockmini-ss"), 4 * mib, true),
            (node("ss-chacha20", "ss", 10389, cipher: "chacha20-ietf-poly1305", password: "mockmini-ss"), 4 * mib, true),
            (node("vmess-aes", "vmess", 10086, cipher: "aes-128-gcm", uuid: uuid), 4 * mib, true),
            (node("vmess-chacha", "vmess", 10086, cipher: "chacha20-poly1305", uuid: uuid), 4 * mib, true),
            (node("vmess-ws-tls", "vmess", 10087, uuid: uuid, tls: true, network: "ws", path: "/vmess"), 4 * mib, true),
            (node("trojan-tls", "trojan", 10443, password: "mockmini-trojan"), 4 * mib, true),
            (node("trojan-ws-tls", "trojan", 10444, password: "mockmini-trojan", network: "ws", path: "/trojan"), 4 * mib, true),
            (node("vless", "vless", 10500, uuid: uuid), 4 * mib, true),
            (node("vless-tls", "vless", 10501, uuid: uuid, tls: true), 4 * mib, true),
            (node("vless-ws-tls", "vless", 10502, uuid: uuid, tls: true, network: "ws", path: "/vless"), 4 * mib, true),
        ]
        if let long = Int(environment["MOCKMINI_INTEROP_LONG_MB"] ?? ""), long > 0 {
            // VMess body nonces are 16-bit and wrap after 65,536 chunks (about 1 GiB).
            cases.append((node("vmess-long", "vmess", 10086, cipher: "aes-128-gcm", uuid: uuid), long * mib, false))
        }
        var failures = 0
        for entry in cases {
            var checks: [(String, () throws -> Void)] = [("tcp \(entry.bytes / mib) MiB", { try stream(entry.node, total: entry.bytes) })]
            if entry.udp { checks.append(("udp", { try datagrams(entry.node) })) }
            for (label, check) in checks {
                let start = Date()
                let seconds = { String(format: "%.1fs", Date().timeIntervalSince(start)) }
                do {
                    try check()
                    print("ok    \(entry.node.name) \(label) (\(seconds()))")
                } catch {
                    failures += 1
                    print("FAIL  \(entry.node.name) \(label) (\(seconds())): \(error)")
                }
            }
        }
        if failures > 0 { print("interop failed: \(failures) check(s)"); exit(1) }
        print("interop passed: \(cases.count) server configurations")
    }

    /// Deterministic, position-dependent bytes so loss, duplication or reordering is caught.
    private static func pattern(_ offset: Int, _ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            var x = UInt64(offset + i) &* 0x9e37_79b9_7f4a_7c15
            x ^= x >> 29
            bytes[i] = UInt8(truncatingIfNeeded: x)
        }
        return Data(bytes)
    }

    private static func stream(_ node: ProxyNode, total: Int) throws {
        let queue = DispatchQueue(label: "interop.stream")
        let done = DispatchSemaphore(value: 0)
        let connection = ProxyConnection(node: node, destinationHost: "127.0.0.1",
                                         destinationPort: echoPort, udp: false, queue: queue)
        let window = 1 << 20, piece = 64 << 10
        var sent = 0, verified = 0, failure: String?, finished = false
        func finish(_ reason: String?) {
            guard !finished else { return }
            finished = true; failure = reason; done.signal()
        }
        func pump() {
            while sent < total, sent - verified < window {
                let count = min(piece, total - sent)
                connection.send(pattern(sent, count)); sent += count
            }
        }
        connection.onReady = { pump() }
        connection.onData = { data in
            guard !finished else { return }
            guard verified + data.count <= total, data == pattern(verified, data.count) else {
                finish("stream corrupted at byte \(verified)"); return
            }
            verified += data.count
            if verified == total { finish(nil) } else { pump() }
        }
        connection.onError = { finish("error after \(verified) bytes: \($0.localizedDescription)") }
        connection.onClose = { finish("closed after \(verified) of \(total) bytes") }
        connection.start()
        let waited = done.wait(timeout: .now() + Double(max(30, total >> 22)))
        connection.close()
        try queue.sync {
            if waited == .timedOut { throw Failure(description: "timed out after \(verified) of \(total) bytes") }
            if let failure { throw Failure(description: failure) }
        }
    }

    private static func datagrams(_ node: ProxyNode) throws {
        let queue = DispatchQueue(label: "interop.udp")
        let done = DispatchSemaphore(value: 0)
        let connection = ProxyConnection(node: node, destinationHost: "127.0.0.1",
                                         destinationPort: echoPort, udp: true, queue: queue)
        let packets = [Data("mockmini-udp-1".utf8), pattern(0, 1200), Data("mockmini-udp-3".utf8)]
        let expected = Set(packets)
        var seen = Set<Data>(), failure: String?, finished = false, attempts = 0
        func finish(_ reason: String?) {
            guard !finished else { return }
            finished = true; failure = reason; done.signal()
        }
        // Loopback rarely drops datagrams; resend the unanswered ones a few times anyway.
        func send() {
            guard !finished, attempts < 5 else { return }
            attempts += 1
            for packet in packets where !seen.contains(packet) { connection.send(packet) }
            queue.asyncAfter(deadline: .now() + 1) { send() }
        }
        connection.onReady = { send() }
        connection.onData = { data in
            guard !finished else { return }
            guard expected.contains(data) else { finish("unexpected \(data.count)-byte datagram"); return }
            seen.insert(Data(data))
            if seen == expected { finish(nil) }
        }
        connection.onError = { finish("error: \($0.localizedDescription)") }
        connection.onClose = { finish("closed after \(seen.count) of \(packets.count) datagrams") }
        connection.start()
        let waited = done.wait(timeout: .now() + 15)
        connection.close()
        try queue.sync {
            if waited == .timedOut { throw Failure(description: "timed out with \(seen.count) of \(packets.count) datagrams") }
            if let failure { throw Failure(description: failure) }
        }
    }
}
