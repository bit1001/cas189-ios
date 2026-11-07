import XCTest
@testable import CAS189Core

final class TorrentTests: XCTestCase {

    func testBencodeRoundTrip() throws {
        let v = Bencode.Value.dict([
            ("a", .int(1)),
            ("b", .str("hi")),
            ("c", .list([.int(2), .str("x")]))
        ])
        let data = Bencode.encode(v)
        XCTAssertEqual(String(data: data, encoding: .utf8), "d1:ai1e1:b2:hi1:cli2e1:xee")
        XCTAssertEqual(try Bencode.decode(data), v)
    }

    func testCasTorrentRoundTrip() throws {
        // 造一个 25MB 的临时文件（3 片）
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "cas_torrent_test.bin")
        var data = Data()
        for i in 0..<(25 * 1024 * 1024) { data.append(UInt8(i % 251)) }
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let torrent = try CasTorrent.build(fromFile: url)
        let item = try CasTorrent.parse(torrent)

        XCTAssertEqual(item.name, "cas_torrent_test.bin")
        XCTAssertEqual(item.size, 25 * 1024 * 1024)
        XCTAssertEqual(item.sliceSize, C.sliceSize)
        XCTAssertEqual(item.parts.count, 3)
        XCTAssertEqual(item.fileMd5.count, 32)
        // sliceMd5 必须等于「每片 MD5 用 \n 连接后再 MD5」
        XCTAssertEqual(item.sliceMd5, CryptoTool.sliceMd5OfParts(item.parts))
    }

    func testRejectTorrentWithoutCasExtension() throws {
        let plain = Bencode.encode(.dict([
            ("info", .dict([("name", .str("x.bin")), ("length", .int(100))]))
        ]))
        XCTAssertThrowsError(try CasTorrent.parse(plain)) { error in
            XCTAssertTrue(error.localizedDescription.contains("file_md5"))
        }
    }
}
