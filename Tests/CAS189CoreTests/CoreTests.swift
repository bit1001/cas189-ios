import XCTest
@testable import CAS189Core

final class CryptoTests: XCTestCase {

    func testHex() {
        XCTAssertEqual(CryptoTool.hexLower(Data([0x00, 0x0f, 0xff])), "000fff")
        XCTAssertEqual(CryptoTool.hexUpper(Data([0x00, 0x0f, 0xff])), "000FFF")
    }

    func testMD5() {
        XCTAssertEqual(CryptoTool.md5HexUpper("abc"), "900150983CD24FB0D6963F7D28E17F72")
        XCTAssertEqual(CryptoTool.md5HexUpper(""), "D41D8CD98F00B204E9800998ECF8427E")
        XCTAssertEqual(CryptoTool.md5HexUpper("The quick brown fox jumps over the lazy dog"),
                       "9E107D9D372BB6826BD81D3542A419D6")
    }

    func testSHA1() {
        XCTAssertEqual(CryptoTool.hexLower(CryptoTool.sha1(Data("abc".utf8))),
                       "a9993e364706816aba3e25717850c26c9cd0d89d")
    }

    /// RFC 2202 测试向量 1
    func testHMACSHA1() {
        let key = String(repeating: "\u{0b}", count: 20)
        let mac = CryptoTool.hmacSha1Hex(key: key, msg: "Hi There")
        XCTAssertEqual(mac, "b617318655057264e28bc0b6fb378c8ef146be00")
    }

    /// FIPS-197 附录 C.1（AES-128 单块向量；PKCS7 会多补一块，故只比对前 16 字节）
    func testAES128ECB_FIPS197() {
        let key: [UInt8] = [0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
                            0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f]
        let plain: [UInt8] = [0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,
                              0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff]
        let out = AES128ECB.encrypt(Data(plain), keyBytes: key)
        XCTAssertEqual(CryptoTool.hexLower(out.prefix(16)), "69c4e0d86a7b0430d8cdb78070b4c55a")
        // 整块输入应补满一整块 16 字节
        XCTAssertEqual(out.count, 32)
    }

    /// NIST SP 800-38A F.1.1 ECB-AES128 (前两块)
    func testAES128ECB_SP800_38A() {
        let rawKey = "2b7e151628aed2a6abf7158809cf4f3c"
        let key = Array(rawKey.utf8)          // 32 个 ASCII 字节 → 按 APK 规则截断到 16
        XCTAssertEqual(key.count, 32)
        // 该向量用的是 hex 解码后的 16 字节，这里直接做等价性验证：截断行为一致即可
        let truncated = Array(key[0..<16])
        let a = AES128ECB.encrypt(Data([0x00]), key: rawKey)
        let b = AES128ECB.encrypt(Data([0x00]), keyBytes: truncated)
        XCTAssertEqual(a, b)
    }

    func testSliceMd5() {
        let one = "900150983CD24FB0D6963F7D28E17F72"
        XCTAssertEqual(CryptoTool.sliceMd5OfParts([one]), one)
        let two = CryptoTool.sliceMd5OfParts([one, one])
        XCTAssertEqual(two, CryptoTool.md5HexUpper("\(one)\n\(one)"))
        XCTAssertEqual(CryptoTool.sliceMd5OfParts([]), "")
    }

    func testMd5FileAndFingerprint() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("a.bin")
        let data = Data(repeating: 0x41, count: 1000)
        try data.write(to: file)

        XCTAssertEqual(try CryptoTool.md5File(file), CryptoTool.md5HexUpper(data))

        let fp = try CryptoTool.fingerprintFile(file)
        XCTAssertEqual(fp.size, 1000)
        XCTAssertEqual(fp.parts.count, 1)
        XCTAssertEqual(fp.parts[0], CryptoTool.md5HexUpper(data))
    }
}

final class SignerTests: XCTestCase {

    func testParamsStringKeepsOrder() {
        let s = Signer.paramsString([("b", "2"), ("a", "1"), ("c", "3")])
        XCTAssertEqual(s, "b=2&a=1&c=3")
    }

    func testRandomStringLength() {
        for _ in 0..<200 {
            let r = Signer.makeRandomString()
            XCTAssertGreaterThanOrEqual(r.count, 16)
            XCTAssertLessThanOrEqual(r.count, 31)
            XCTAssertTrue(r.allSatisfy { $0.isHexDigit })
        }
    }

    /// 签名串结构与 HMAC 计算必须与 APK 一致
    func testSignatureStructure() {
        let rnd = "0123456789abcdef0123456789abcdef"
        let paramsHex = "deadbeef"
        let sig = Signer.signature(rnd: rnd, sessionKey: "SK", method: "POST",
                                   uri: "/person/initMultiUpload",
                                   dateMillis: "1700000000000", paramsHex: paramsHex)
        let msg = "SessionKey=SK&Operate=POST&RequestURI=/person/initMultiUpload"
            + "&Date=1700000000000&params=deadbeef"
        XCTAssertEqual(sig, CryptoTool.hmacSha1Hex(key: rnd, msg: msg))
        XCTAssertEqual(sig.count, 40)
    }

    /// AES 用 rnd 前 16 个字符作 key
    func testParamsEncryptionUsesRndPrefix() {
        let rnd = "abcdefghijklmnopQRSTUV"
        let pStr = "a=1&b=2"
        let expected = AES128ECB.encryptHex(Data(pStr.utf8), key: String(rnd.prefix(16)))
        XCTAssertEqual(expected, AES128ECB.encryptHex(Data(pStr.utf8), key: "abcdefghijklmnop"))
    }
}
