import Foundation
#if canImport(Security)
import Security
#endif

/// 黑暗抖阴的两处额外加密：封面 RC4、预览 HLS 的 RSA-OAEP 包裹密钥。
public enum DouyinCrypto {
    static let coverKey = Array("WbBpLt8!OTl7kTx%".utf8)

    /// 站点直接下发 RC4 密文；先看文件头，已经是图片就原样返回。
    public static func decodeCover(_ data: Data) -> Data {
        if looksLikeImage(data) { return data }
        let plain = rc4(key: coverKey, data: [UInt8](data))
        return looksLikeImage(Data(plain)) ? Data(plain) : data
    }

    public static func looksLikeImage(_ data: Data) -> Bool {
        let b = [UInt8](data.prefix(4))
        guard b.count == 4 else { return false }
        if b[0] == 0xFF, b[1] == 0xD8 { return true }                       // JPEG
        if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return true } // PNG
        if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return true }        // GIF
        if b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46 { return true } // WEBP/RIFF
        return false
    }

    public static func rc4(key: [UInt8], data: [UInt8]) -> [UInt8] {
        var s = Array(0...255).map { UInt8($0) }
        var j = 0
        for i in 0..<256 {
            j = (j + Int(s[i]) + Int(key[i % key.count])) & 0xFF
            s.swapAt(i, j)
        }
        var out = [UInt8](repeating: 0, count: data.count)
        var i = 0; j = 0
        for k in 0..<data.count {
            i = (i + 1) & 0xFF
            j = (j + Int(s[i])) & 0xFF
            s.swapAt(i, j)
            let t = (Int(s[i]) + Int(s[j])) & 0xFF
            out[k] = data[k] ^ s[t]
        }
        return out
    }

    // MARK: - HLS key

    /// `encryption.key` 正常是 16 字节裸 key；预览流是 256 字节 RSA-OAEP(SHA-256) 包裹。
    public static func unwrapMediaKey(_ blob: Data) throws -> [UInt8] {
        if blob.count == 16 { return [UInt8](blob) }
        guard blob.count >= 128 else { throw QHError.crypto("douyin key is \(blob.count) bytes") }
        #if canImport(Security)
        for pkcs8 in Self.privateKeys {
            guard let der = Data(base64Encoded: pkcs8) else { continue }
            // PKCS#8 → PKCS#1: drop the 26-byte PrivateKeyInfo header.
            let pkcs1 = der.dropFirst(26)
            let attrs: [CFString: Any] = [
                kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            ]
            var err: Unmanaged<CFError>?
            guard let key = SecKeyCreateWithData(Data(pkcs1) as CFData, attrs as CFDictionary, &err) else { continue }
            guard let plain = SecKeyCreateDecryptedData(key, .rsaEncryptionOAEPSHA256, blob as CFData, &err) else { continue }
            let bytes = [UInt8](plain as Data)
            if bytes.count == 16 { return bytes }
        }
        throw QHError.crypto("douyin RSA unwrap failed")
        #else
        // Linux CLI harness: shell out to openssl (same operation, same padding).
        for pkcs8 in Self.privateKeys {
            guard let der = Data(base64Encoded: pkcs8) else { continue }
            let pem = "-----BEGIN PRIVATE KEY-----\n" +
                der.base64EncodedString(options: [.lineLength64Characters]) +
                "\n-----END PRIVATE KEY-----\n"
            let dir = FileManager.default.temporaryDirectory
            let keyFile = dir.appendingPathComponent("dy-\(UUID().uuidString).pem")
            let inFile = dir.appendingPathComponent("dy-\(UUID().uuidString).bin")
            try pem.write(to: keyFile, atomically: true, encoding: .utf8)
            try blob.write(to: inFile)
            defer { try? FileManager.default.removeItem(at: keyFile); try? FileManager.default.removeItem(at: inFile) }

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            p.arguments = ["pkeyutl", "-decrypt", "-inkey", keyFile.path, "-in", inFile.path,
                           "-pkeyopt", "rsa_padding_mode:oaep",
                           "-pkeyopt", "rsa_oaep_md:sha256",
                           "-pkeyopt", "rsa_mgf1_md:sha256"]
            let out = Pipe(), errPipe = Pipe()
            p.standardOutput = out
            p.standardError = errPipe
            try p.run()
            p.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            if p.terminationStatus == 0, data.count == 16 { return [UInt8](data) }
        }
        throw QHError.crypto("douyin RSA unwrap failed (openssl)")
        #endif
    }

    /// PKCS#8 DER base64, copied from DouyinMediaKeys.PRIVATE_KEY_TEXTS.
    static let privateKeys: [String] = [
        "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",
    ]
}
