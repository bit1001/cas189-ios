import Foundation
import Crypto

/// 哈希 / HMAC / RSA，对应 APK 中 com.ty189.cas.Crypto
public enum CryptoTool {

    // MARK: - Hex

    public static func hexLower(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public static func hexUpper(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    // MARK: - MD5 / SHA1

    public static func md5(_ data: Data) -> Data {
        Data(Insecure.MD5.hash(data: data))
    }

    public static func md5HexUpper(_ string: String) -> String {
        hexUpper(md5(Data(string.utf8)))
    }

    public static func md5HexUpper(_ data: Data) -> String {
        hexUpper(md5(data))
    }

    public static func sha1(_ data: Data) -> Data {
        Data(Insecure.SHA1.hash(data: data))
    }

    /// HMAC-SHA1(key:key, msg:msg) -> 小写十六进制
    public static func hmacSha1Hex(key: String, msg: String, upper: Bool = false) -> String {
        let mac = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(msg.utf8),
            using: SymmetricKey(data: Data(key.utf8))
        )
        let data = Data(mac)
        return upper ? hexUpper(data) : hexLower(data)
    }

    // MARK: - 分片指纹

    /// 计算单个 10MB 切片的 MD5（大写十六进制）
    public static func sliceMD5(_ data: Data) -> String {
        md5HexUpper(data)
    }

    /// 与 APK 一致：单个分片直接返回该分片；多分片则把各分片 MD5（大写）用 \n 连接后再取 MD5
    public static func sliceMd5OfParts(_ parts: [String]) -> String {
        guard !parts.isEmpty else { return "" }
        if parts.count == 1 { return parts[0].uppercased() }
        let joined = parts.map { $0.uppercased() }.joined(separator: "\n")
        return md5HexUpper(joined)
    }

    /// 整个文件的 MD5（大写十六进制），带进度回调；支持只用前 N 字节（limit<0 表示全部）
    public static func md5File(_ url: URL, limit: Int64 = -1,
                               progress: ((Int64) -> Bool)? = nil) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = Insecure.MD5()
        var read: Int64 = 0
        let chunk = 256 * 1024
        while true {
            if limit >= 0 && read >= limit { break }
            let want = limit >= 0 ? Int(min(Int64(chunk), limit - read)) : chunk
            let data = handle.readData(ofLength: want)
            if data.isEmpty { break }
            hasher.update(data: data)
            read += Int64(data.count)
            if let progress, progress(read) == false { break }
        }
        return hexUpper(Data(hasher.finalize()))
    }

    /// 按 10MB 切片计算 sliceMd5（并发）；返回 (整文件MD5, sliceMd5, 分片数, 分片MD5列表)
    public static func fingerprintFile(_ url: URL,
                                       sliceSize: Int = C.sliceSize,
                                       threads: Int = 4,
                                       progress: ((Int, Int) -> Bool)? = nil)
    throws -> SliceFingerprint {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let count = max(1, Int((size + Int64(sliceSize) - 1) / Int64(sliceSize)))
        var parts = [String](repeating: "", count: count)
        let lock = NSLock()
        var cancelled = false

        let fileMD5 = try md5File(url)

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = max(1, threads)
        for index in 0..<count {
            queue.addOperation {
                lock.lock(); let stop = cancelled; lock.unlock()
                if stop { return }
                do {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    try handle.seek(toOffset: UInt64(index * sliceSize))
                    let data = handle.readData(ofLength: sliceSize)
                    parts[index] = sliceMD5(data)
                    if let progress, progress(index + 1, count) == false {
                        lock.lock(); cancelled = true; lock.unlock()
                    }
                } catch {
                    lock.lock(); cancelled = true; lock.unlock()
                }
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        if cancelled { throw CASError.notDecompilable("指纹计算被取消或失败") }

        let cloudMd5 = sliceMd5OfParts(parts)
        return SliceFingerprint(
            size: size,
            fileMd5: fileMD5,
            sliceMd5: cloudMd5,
            sliceSize: sliceSize,
            parts: parts
        )
    }

    // MARK: - RSA（PKCS1 v1.5 加密）

    #if canImport(Security)
    /// 判断公钥是否可用（等价 APK 的 isUsableRsaKey）
    public static func isUsableRSAPubKey(_ base64: String) -> Bool {
        guard base64.count >= 64,
              let der = Data(base64Encoded: base64
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return (try? pkcs1PublicKeyDER(fromX509: der)) != nil
    }

    /// 把 189 下发的 X.509/SPKI Base64 公钥转成 iOS 需要的 PKCS#1 RSAPublicKey DER
    static func pkcs1PublicKeyDER(fromX509 der: Data) throws -> Data {
        var bytes = [UInt8](der)
        var i = 0
        func readLength() throws -> Int {
            guard i < bytes.count else { throw CASError.notDecompilable("DER 长度越界") }
            let first = bytes[i]; i += 1
            if first < 0x80 { return Int(first) }
            let n = Int(first & 0x7F)
            guard n > 0, n <= 4, i + n <= bytes.count else { throw CASError.notDecompilable("DER 长度非法") }
            var value = 0
            for _ in 0..<n { value = (value << 8) | Int(bytes[i]); i += 1 }
            return value
        }
        // SEQUENCE (SubjectPublicKeyInfo)
        guard i < bytes.count, bytes[i] == 0x30 else { throw CASError.notDecompilable("不是 X.509 公钥") }
        i += 1
        _ = try readLength()
        // SEQUENCE (AlgorithmIdentifier)
        guard i < bytes.count, bytes[i] == 0x30 else { throw CASError.notDecompilable("缺少算法标识") }
        i += 1
        let algLen = try readLength()
        i += algLen
        // BIT STRING
        guard i < bytes.count, bytes[i] == 0x03 else { throw CASError.notDecompilable("缺少 BIT STRING") }
        i += 1
        _ = try readLength()
        guard i < bytes.count, bytes[i] == 0x00 else { throw CASError.notDecompilable("BIT STRING 未对齐") }
        i += 1
        return Data(bytes[i...])
    }

    public static func rsaEncryptBase64(x509PubKeyB64: String, plaintext: String) throws -> String {
        let cleaned = x509PubKeyB64
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 64, let der = Data(base64Encoded: cleaned) else {
            throw CASError.missing("上传加密公钥")
        }
        let pkcs1 = try pkcs1PublicKeyDER(fromX509: der)
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &error) else {
            throw CASError.notDecompilable("公钥导入失败 \((error?.takeRetainedValue() as Error?)?.localizedDescription ?? "")")
        }
        var err: Unmanaged<CFError>?
        guard let cipher = SecKeyCreateEncryptedData(
            key, .rsaEncryptionPKCS1, Data(plaintext.utf8) as CFData, &err
        ) else {
            throw CASError.notDecompilable("RSA 加密失败 \((err?.takeRetainedValue() as Error?)?.localizedDescription ?? "")")
        }
        return (cipher as Data).base64EncodedString()
    }
    #else
    /// Linux 上无法用 Security 解析，退化为格式检查
    public static func isUsableRSAPubKey(_ base64: String) -> Bool {
        let cleaned = base64
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count >= 64 && Data(base64Encoded: cleaned) != nil
    }

    public static func rsaEncryptBase64(x509PubKeyB64: String, plaintext: String) throws -> String {
        throw CASError.unsupported("RSA 加密需要 Apple 平台的 Security.framework")
    }
    #endif
}

public struct SliceFingerprint: Sendable, Equatable {
    public let size: Int64
    public let fileMd5: String
    public let sliceMd5: String
    public let sliceSize: Int
    public let parts: [String]
}
