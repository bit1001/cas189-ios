import XCTest
@testable import CAS189Core

final class CasFileTests: XCTestCase {

    func testParseCasJson() throws {
        let json = """
        {"cloud":"189","md5":"1DAE32B788C62AFEB631F3E9E16557E5","name":"ig.mp4",
         "size":13720309,"slice_md5":"9071960F0FEB99188AD6D5B95CC59ECF",
         "slice_md5s":["7C0DA90A6E11AA9076A05380FBAF4984","F058DE4E420B15CBEC769DEC8D9E561F"],
         "slice_size":10485760}
        """.data(using: .utf8)!

        let item = try CasFile.parse(json: json, fallbackName: "ig.mp4.cas")
        XCTAssertEqual(item.name, "ig.mp4")
        XCTAssertEqual(item.size, 13720309)
        XCTAssertEqual(item.fileMd5, "1DAE32B788C62AFEB631F3E9E16557E5")
        XCTAssertEqual(item.sliceMd5, "9071960F0FEB99188AD6D5B95CC59ECF")
        XCTAssertEqual(item.parts.count, 2)
        XCTAssertEqual(item.sliceSize, 10485760)
    }

    func testParseFallsBackToFileName() throws {
        // name 为空 → 用文件名去 .cas 后缀
        let json = #"{"md5":"E53B7768ED1AC024080F1D68B36DF58F","size":300000}"#.data(using: .utf8)!
        let item = try CasFile.parse(json: json, fallbackName: "small_test.bin.cas")
        XCTAssertEqual(item.name, "small_test.bin")
        XCTAssertEqual(item.sliceMd5, item.fileMd5, "缺 slice_md5 时应回退到 md5")
    }

    func testRejectBadMd5() {
        let json = #"{"md5":"XYZ","size":1,"name":"a"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try CasFile.parse(json: json)) { error in
            XCTAssertTrue(error.localizedDescription.contains("MD5"))
        }
    }

    func testBuildRoundTrip() throws {
        let item = CasItem(name: "a.bin", size: 25_000_000,
                           fileMd5: "0123456789ABCDEF0123456789ABCDEF", sliceMd5: "FEDCBA9876543210FEDCBA9876543210",
                           sliceSize: C.sliceSize, parts: ["c1", "c2", "c3"])
        let data = CasFile.build(item)
        let back = try CasFile.parse(json: data, fallbackName: "a.bin.cas")
        XCTAssertEqual(back.name, "a.bin")
        XCTAssertEqual(back.size, 25_000_000)
        XCTAssertEqual(back.fileMd5, "0123456789ABCDEF0123456789ABCDEF")
        XCTAssertEqual(back.sliceMd5, "FEDCBA9876543210FEDCBA9876543210")
        XCTAssertEqual(back.parts, ["C1", "C2", "C3"], "parts 应大写")
    }

    func testZipRoundTrip() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "creds_test.cas.zip")
        defer { try? FileManager.default.removeItem(at: url) }

        let payload: [(String, Data)] = [
            ("a.cas", Data(#"{"md5":"1111","size":10,"name":"a.bin"}"#.utf8)),
            ("b.cas.torrent", Data("not-really-a-torrent".utf8))
        ]
        try CasFile.archive(payload, to: url)

        let entries = try CasFile.entries(inArchive: url)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map { $0.name }.sorted(), ["a.cas", "b.cas.torrent"])
    }

    func testIsCasName() {
        XCTAssertTrue(CasFile.isCasName("movie.mkv.cas"))
        XCTAssertTrue(CasFile.isCasName("movie.mkv.cas.torrent"))
        XCTAssertFalse(CasFile.isCasName("movie.mkv"))
        XCTAssertEqual(CasFile.stripCasName("movie.mkv.cas.torrent"), "movie.mkv")
        XCTAssertEqual(CasFile.stripCasName("movie.mkv.cas"), "movie.mkv")
    }
}

final class ThumbnailTests: XCTestCase {
    func testParseIconFromListXML() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <listFiles><fileList><count>1</count><file>
        <id>123</id><name>a.mp4</name><size>100</size><md5>ABC</md5>
        <icon><smallUrl>https://preview.cloud.189.cn/image/imageAction?param=AAA</smallUrl>
        <largeUrl>https://preview.cloud.189.cn/image/imageAction?param=BBB</largeUrl></icon>
        </file></fileList></listFiles>
        """.data(using: .utf8)!
        let entries = try WebListParser.parse(xml)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].iconURL, "https://preview.cloud.189.cn/image/imageAction?param=AAA")
    }

    func testNoIconStaysNil() throws {
        let xml = """
        <listFiles><fileList><count>1</count><file>
        <id>456</id><name>b.iso</name><size>1</size></file></fileList></listFiles>
        """.data(using: .utf8)!
        XCTAssertNil(try WebListParser.parse(xml)[0].iconURL)
    }
}
