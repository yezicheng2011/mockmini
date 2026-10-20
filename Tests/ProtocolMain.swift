// Standalone entry point for running ProtocolTests outside the macOS app.
// The app repository calls ProtocolTests.run() from its own NativeTests.swift.
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
