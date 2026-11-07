#if !canImport(Security)
import Foundation
import BigInt

/// Linux 下的 RSA PKCS#1 v1.5 加密实现。
/// 只为验证签名流程存在：Security.framework 里对应的是
/// SecKeyCreateEncryptedData(.rsaEncryptionPKCS1)。
public enum LinuxRSA {

    public static func encryptPKCS1(_ message: Data, x509Base64: String) throws -> Data {
        guard let der = Data(base64Encoded: x509Base64,
                             options: .ignoreUnknownCharacters) else {
            throw CASError.unsupported("RSA 公钥不是合法 Base64")
        }
        let (n, e) = try parseSubjectPublicKeyInfo(der)
        let k = (n.bitWidth + 7) / 8
        guard message.count <= k - 11 else {
            throw CASError.unsupported("RSA 明文过长：\(message.count) > \(k - 11)")
        }

        var em = Data([0x00, 0x02])
        let psLen = k - message.count - 3
        var ps = Data(capacity: psLen)
        var rng = SystemRandomNumberGenerator()
        while ps.count < psLen {
            let b = UInt8.random(in: 1...255, using: &rng)
            ps.append(b)
        }
        em.append(ps)
        em.append(0x00)
        em.append(message)

        let m = BigUInt(em)
        let c = m.power(BigUInt(e), modulus: n)

        var out = c.serialize()
        if out.count < k { out = Data(repeating: 0, count: k - out.count) + out }
        return out
    }

    // MARK: - DER

    private static func readTLV(_ der: Data, _ i: inout Int) throws -> (tag: UInt8, value: Data) {
        guard i + 2 <= der.count else { throw CASError.unsupported("DER 截断") }
        let tag = der[i]; i += 1
        var len = Int(der[i]); i += 1
        if len & 0x80 != 0 {
            let n = len & 0x7f
            guard n > 0, n <= 4, i + n <= der.count else { throw CASError.unsupported("DER 长度非法") }
            len = 0
            for _ in 0..<n { len = (len << 8) | Int(der[i]); i += 1 }
        }
        guard i + len <= der.count else { throw CASError.unsupported("DER 越界") }
        let value = der.subdata(in: i..<(i + len))
        i += len
        return (tag, value)
    }

    /// SubjectPublicKeyInfo → (n, e)
    private static func parseSubjectPublicKeyInfo(_ der: Data) throws -> (BigUInt, BigUInt) {
        var i = 0
        let outer = try readTLV(der, &i)
        guard outer.tag == 0x30 else { throw CASError.unsupported("不是 DER SEQUENCE") }

        var j = 0
        let alg = try readTLV(outer.value, &j)
        guard alg.tag == 0x30 else { throw CASError.unsupported("缺少 AlgorithmIdentifier") }
        let bits = try readTLV(outer.value, &j)
        guard bits.tag == 0x03 else { throw CASError.unsupported("缺少 BIT STRING") }

        // BIT STRING 首字节是 unused-bits 计数
        var keyBytes = bits.value
        if keyBytes.first == 0x00 { keyBytes = Data(keyBytes.dropFirst()) }

        var k = 0
        let seq = try readTLV(keyBytes, &k)
        guard seq.tag == 0x30 else { throw CASError.unsupported("RSAPublicKey 不是 SEQUENCE") }

        var m = 0
        let nInt = try readTLV(seq.value, &m)
        let eInt = try readTLV(seq.value, &m)
        guard nInt.tag == 0x02, eInt.tag == 0x02 else { throw CASError.unsupported("RSA 整数标签错误") }

        let n = BigUInt(nInt.value)
        let e = BigUInt(eInt.value)
        guard n > 0, e > 1 else { throw CASError.unsupported("RSA 参数非法") }
        return (n, e)
    }
}
#endif
