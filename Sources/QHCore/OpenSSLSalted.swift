import Foundation
import Crypto

/// OpenSSL "Salted__" AES: the format produced by `openssl enc -aes-256-cbc -pass pass:…`.
/// Payload = "Salted__" + 8-byte salt + ciphertext; key/iv come from EVP_BytesToKey(MD5).
public enum OpenSSLSalted {
    public static func decrypt(base64: String, passphrase: String) throws -> Data {
        let compact = base64.filter { !$0.isWhitespace }
        guard let blob = Data(base64Encoded: compact), blob.count >= 32 else {
            throw QHError.crypto("not base64 / too short")
        }
        let bytes = [UInt8](blob)
        guard Array(bytes[0..<8]) == Array("Salted__".utf8) else {
            throw QHError.crypto("missing Salted__ header")
        }
        let salt = Array(bytes[8..<16])
        let cipherBytes = Array(bytes[16...])
        let (key, iv) = try evpBytesToKey(password: Array(passphrase.utf8), salt: salt, keyLen: 32)
        let aes = try AES(key: key)
        let plain = try aes.decryptCBC(cipherBytes, iv: iv, removePadding: true)
        return Data(plain)
    }

    /// OpenSSL's EVP_BytesToKey with MD5 and a single iteration (OpenSSL 1.x default, `-md md5`).
    static func evpBytesToKey(password: [UInt8], salt: [UInt8], keyLen: Int) throws -> ([UInt8], [UInt8]) {
        var derived: [UInt8] = []
        var previous: [UInt8] = []
        while derived.count < keyLen + 16 {
            var input = previous
            input.append(contentsOf: password)
            input.append(contentsOf: salt)
            previous = Array(Insecure.MD5.hash(data: Data(input)))
            derived.append(contentsOf: previous)
        }
        return (Array(derived[0..<keyLen]), Array(derived[keyLen..<(keyLen + 16)]))
    }
}
