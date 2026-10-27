// Standalone entry point for running ProtocolTests; embedding projects can call
// ProtocolTests.run() from their own test runner instead.
import Foundation
#if canImport(MockMiniVPN)
@testable import MockMiniVPN
#endif

@main
enum ProtocolMain {
    static func main() {
        do {
            try ProtocolTests.run()
            #if canImport(CommonCrypto) && canImport(Network)
            let scope = "primitives, Shadowsocks, VMess, Trojan, VLESS, WebSocket, config, transport plans, resolver"
            #else
            let scope = "portable core: primitives, Shadowsocks, VLESS, WebSocket, config, transport plans"
            #endif
            print("protocol tests passed: \(scope)")
        } catch {
            FileHandle.standardError.write(Data("protocol tests failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
