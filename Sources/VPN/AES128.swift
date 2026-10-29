import Foundation

#if canImport(CommonCrypto)
import CommonCrypto
#else
import Crypto
import _CryptoExtras
#endif

/// The AES-128 forward block operation used by VMess auth IDs and legacy CFB128 headers.
/// Apple uses CommonCrypto; Linux uses swift-crypto's BoringSSL-backed AES.permute.
struct AES128 {
    #if canImport(CommonCrypto)
    private let key: Data
    #else
    private let key: SymmetricKey
    #endif

    init(key: Data) throws {
        guard key.count == 16 else { throw ProxyError.authentication }
        #if canImport(CommonCrypto)
        self.key = key
        #else
        self.key = SymmetricKey(data: key)
        #endif
    }

    func encrypt(_ block: [UInt8]) throws -> [UInt8] {
        guard block.count == 16 else { throw ProxyError.authentication }
        #if canImport(CommonCrypto)
        var output = [UInt8](repeating: 0, count: 32)
        var written = 0
        let status = key.withUnsafeBytes { keyBytes in
            block.withUnsafeBytes { blockBytes in
                output.withUnsafeMutableBytes { outputBytes in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionECBMode), keyBytes.baseAddress, key.count,
                            nil, blockBytes.baseAddress, block.count,
                            outputBytes.baseAddress, outputBytes.count, &written)
                }
            }
        }
        guard status == kCCSuccess, written == 16 else { throw ProxyError.authentication }
        return Array(output.prefix(written))
        #else
        var output = block
        do {
            try AES.permute(&output, key: key)
        } catch {
            throw ProxyError.authentication
        }
        return output
        #endif
    }
}
