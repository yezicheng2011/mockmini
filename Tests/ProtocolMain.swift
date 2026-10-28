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
            #if canImport(Network)
            let scope = "primitives, AES-128, Shadowsocks, VMess, SHA-224, Trojan, VLESS, WebSocket, config, transport plans, resolver"
            #else
            let scope = "portable core: primitives, AES-128, Shadowsocks, VMess, SHA-224, Trojan, VLESS, WebSocket, config, transport plans"
            #endif
            print("protocol tests passed: \(scope)")
        } catch {
            FileHandle.standardError.write(Data("protocol tests failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
