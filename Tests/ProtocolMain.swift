// Standalone entry point for running ProtocolTests; embedding projects can call
// ProtocolTests.run() from their own test runner instead.
import Foundation

@main
enum ProtocolMain {
    static func main() {
        do {
            try ProtocolTests.run()
            print("protocol tests passed: primitives, Shadowsocks, VMess, WebSocket, config, resolver")
        } catch {
            FileHandle.standardError.write(Data("protocol tests failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
