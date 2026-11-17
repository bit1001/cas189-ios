import XCTest
@testable import QHCore

final class QHCoreTests: XCTestCase {
    func testAESBlockVector() throws {
        let key: [UInt8] = (0...15).map { UInt8($0) }
        let cipher = Data(hexString: "69c4e0d86a7b0430d8cdb78070b4c55a")!
        let plain = try AES128(key: key).decryptBlock(Array(cipher))
        XCTAssertEqual(Data(plain), Data(hexString: "00112233445566778899aabbccddeeff")!)
    }

    func testCBCAgainstOpenSSLVector() throws {
        // openssl enc -aes-128-cbc -K 2b7e151628aed2a6abf7158809cf4f3c \
        //   -iv 000102030405060708090a0b0c0d0e0f -nopad
        // over the NIST SP800-38A block sequence.
        let key = Data(hexString: "2b7e151628aed2a6abf7158809cf4f3c")!.map { $0 }
        let iv = Data(hexString: "000102030405060708090a0b0c0d0e0f")!.map { $0 }
        let cipher = Data(hexString:
            "7649abac8119b246cee98e9b12e9197d" +
            "5086cb9b507219ee95db113a917678b2" +
            "73bed6b8e3c1743b7116e69e22229516" +
            "3ff1caa1681fac09120eca307586e1a7")!
        let out = try AES128(key: key).decryptCBC(Array(cipher), iv: iv)
        let expected = Data(hexString:
            "6bc1bee22e409f96e93d7e117393172a" +
            "ae2d8a571e03ac9c9eb76fac45af8e51" +
            "30c81c46a35ce411e5fbc1191a0a52ef" +
            "f69f2445df4f9b17ad2b417be66c3710")!
        XCTAssertEqual(Data(out), expected)
    }

    func testBase64PeelFiveLayers() {
        // "hello" wrapped five times
        var text = "hello"
        for _ in 0..<5 { text = Data(text.utf8).base64EncodedString() }
        XCTAssertEqual(Base64Peel.peel(text), "hello")
    }

    func testPlaylistParsing() throws {
        let m3u8 = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-KEY:METHOD=AES-128,URI="enc_1.key",IV=0x00112233445566778899aabbccddeeff
        #EXTINF:1.25,
        a.ts
        #EXTINF:1.25,
        b.ts
        #EXT-X-ENDLIST
        """
        let base = URL(string: "https://cdn.example.com/v/577981_i_preview.m3u8")!
        let p = try HLSPlaylist.parse(m3u8, base: base)
        XCTAssertEqual(p.segments.count, 2)
        XCTAssertEqual(p.keyURI?.absoluteString, "https://cdn.example.com/v/enc_1.key")
        XCTAssertEqual(p.iv, [0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff])
        XCTAssertEqual(p.totalDuration, 2.5, accuracy: 0.001)
    }
}
