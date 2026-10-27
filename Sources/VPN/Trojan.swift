import Foundation

// Original implementation from the public protocol description:
// https://trojan-gfw.github.io/trojan/protocol
// The client authenticates inside TLS with hex(SHA-224(password)). The server sends no
// response header, so after the request TCP payload flows unchanged in both directions.
// UDP ASSOCIATE carries datagrams inside the same TLS stream, each framed as
// ATYP | address | port | length | CRLF | payload.

enum TrojanCommand: UInt8 {
    case connect = 0x01
    case udpAssociate = 0x03
}

final class TrojanSession {
    static let maxDatagram = 65_507
    private static let crlf = Data([0x0d, 0x0a])
    private let token: Data
    private let destination: Data
    private let udp: Bool
    private var headerSent = false
    private var incoming = ByteQueue()

    init(password: String, destinationHost: String, destinationPort: UInt16, udp: Bool) throws {
        guard !password.isEmpty else { throw ProxyError.configuration("Trojan requires a non-empty password") }
        token = Self.token(password)
        destination = try ProxyAddress.socks(destinationHost, destinationPort)
        self.udp = udp
    }

    /// 56 lowercase hex characters of SHA-224(password).
    static func token(_ password: String) -> Data {
        let digest = SHA224.hash([UInt8](password.utf8))
        let digits = Array("0123456789abcdef".utf8)
        return Data(digest.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 15)]] })
    }

    func requestHeader() throws -> Data {
        guard !headerSent else { throw ProxyError.malformed("Trojan header already sent") }
        headerSent = true
        let command: TrojanCommand = udp ? .udpAssociate : .connect
        return token + Self.crlf + Data([command.rawValue]) + destination + Self.crlf
    }

    func encodeDatagram(_ plain: Data) throws -> Data {
        guard udp, headerSent else { throw ProxyError.malformed("Trojan UDP association is not open") }
        guard plain.count <= Self.maxDatagram else { throw ProxyError.bufferLimit }
        return destination + WireBytes.be16(UInt16(plain.count)) + Self.crlf + plain
    }

    /// Server datagrams arrive as a byte stream; returns each complete payload in order.
    func decodeDatagrams(_ received: Data) throws -> [Data] {
        guard udp else { throw ProxyError.malformed("Trojan TCP sessions carry no datagram framing") }
        guard incoming.count + received.count <= 1024 * 1024 else { throw ProxyError.bufferLimit }
        incoming.append(received)
        var output = [Data]()
        while !incoming.isEmpty {
            let head = [UInt8](incoming.prefix(2))
            let address: Int
            switch head[0] {
            case 1: address = 4
            case 4: address = 16
            case 3:
                guard head.count >= 2 else { return output }
                guard head[1] > 0 else { throw ProxyError.malformed("Invalid Trojan UDP domain address") }
                address = 1 + Int(head[1])
            default: throw ProxyError.malformed("Invalid Trojan UDP address type")
            }
            let header = 1 + address + 2 + 2 + 2   // type, address, port, length, CRLF
            guard incoming.count >= header else { break }
            let fields = [UInt8](incoming.prefix(header))
            guard fields[header - 2] == 0x0d, fields[header - 1] == 0x0a else {
                throw ProxyError.malformed("Missing Trojan UDP CRLF")
            }
            let length = Int(fields[header - 4]) << 8 | Int(fields[header - 3])
            guard incoming.count >= header + length else { break }
            _ = incoming.take(header)
            output.append(incoming.take(length))
        }
        return output
    }

    func finishReceiving() throws {
        guard incoming.isEmpty else { throw ProxyError.malformed("The Trojan stream ended within a UDP packet") }
    }
}

extension TrojanSession: ProxySession {
    var usesDatagramSocket: Bool { false }
    func openingBytes() throws -> Data? { try requestHeader() }
    func encode(_ payload: Data) throws -> [Data] { udp ? [try encodeDatagram(payload)] : [payload] }
    func decode(_ received: Data) throws -> [Data] { udp ? try decodeDatagrams(received) : [received] }
    func closingBytes() throws -> Data? { nil }
    func transportEnded() throws { if udp { try finishReceiving() } }
    var remoteEnded: Bool { false }
}

/// SHA-224 (FIPS 180-4): SHA-256 with its own initial state, truncated to 28 bytes.
/// CryptoKit and swift-crypto do not expose it, so Trojan tokens use this portable version.
enum SHA224 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939,
                           0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4]
        var padded = message
        padded.append(0x80)
        while padded.count % 64 != 56 { padded.append(0) }
        let bits = UInt64(message.count) &* 8
        for shift in stride(from: 56, through: 0, by: -8) { padded.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }

        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        var w = [UInt32](repeating: 0, count: 64)
        for block in stride(from: 0, to: padded.count, by: 64) {
            for i in 0..<16 {
                let o = block + i * 4
                w[i] = UInt32(padded[o]) << 24 | UInt32(padded[o + 1]) << 16 | UInt32(padded[o + 2]) << 8 | UInt32(padded[o + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var v = h
            for i in 0..<64 {
                let s1 = rotr(v[4], 6) ^ rotr(v[4], 11) ^ rotr(v[4], 25)
                let choice = (v[4] & v[5]) ^ (~v[4] & v[6])
                let t1 = v[7] &+ s1 &+ choice &+ k[i] &+ w[i]
                let s0 = rotr(v[0], 2) ^ rotr(v[0], 13) ^ rotr(v[0], 22)
                let majority = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2])
                let t2 = s0 &+ majority
                v[7] = v[6]; v[6] = v[5]; v[5] = v[4]; v[4] = v[3] &+ t1
                v[3] = v[2]; v[2] = v[1]; v[1] = v[0]; v[0] = t1 &+ t2
            }
            for i in 0..<8 { h[i] = h[i] &+ v[i] }
        }
        return h.prefix(7).flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> UInt32(24 - 8 * $0)) } }
    }
}
