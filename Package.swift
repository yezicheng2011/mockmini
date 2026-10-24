// swift-tools-version:5.9
import PackageDescription

// MockMiniPacket: the portable C packet engine (wlp) and the macOS utun adapter.
// MockMiniVPN: proxy protocols and transports. On Apple platforms it uses CryptoKit,
// CommonCrypto and Network.framework; on Linux the portable core (model, transport plans,
// Shadowsocks, WebSocket framing) builds against swift-crypto for unit tests.
let package = Package(
    name: "MockMini",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "MockMiniPacket", targets: ["MockMiniPacket"]),
        .library(name: "MockMiniVPN", targets: ["MockMiniVPN"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"4.0.0"),
    ],
    targets: [
        .target(name: "MockMiniPacket", path: "Sources/Packet", exclude: ["README.md"],
                publicHeadersPath: "."),
        .target(name: "MockMiniVPN",
                dependencies: [.product(name: "Crypto", package: "swift-crypto",
                                        condition: .when(platforms: [.linux]))],
                path: "Sources/VPN"),
        .executableTarget(name: "mockmini-protocol-tests", dependencies: ["MockMiniVPN"], path: "Tests",
                          exclude: ["README.md", "packet_test.c", "packet_fuzz.c", "interop", "InteropMain.swift"],
                          sources: ["ProtocolTests.swift", "ProtocolMain.swift"]),
    ]
)
