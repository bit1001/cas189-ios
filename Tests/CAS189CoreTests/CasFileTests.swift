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

    /// 不同导出工具的字段名：fileSize / file_name / fileMd5
    func testParseAlternateFieldNames() throws {
        let json = """
        {"fileName":"The Scandal S01E01.mkv","fileSize":123456789,"fileMd5":"AABBCCDDEEFF00112233445566778899","sliceMd5":"11223344556677889900AABBCCDDEEFF","sliceSize":10485760}
        """
        let item = try CasFile.parse(data: Data(json.utf8))
        XCTAssertEqual(item.name, "The Scandal S01E01.mkv")
        XCTAssertEqual(item.size, 123456789)
        XCTAssertEqual(item.fileMd5, "AABBCCDDEEFF00112233445566778899")
        XCTAssertEqual(item.sliceMd5, "11223344556677889900AABBCCDDEEFF")
    }

    /// 内容套在 data 里
    func testParseNestedObject() throws {
        let json = """
        {"code":0,"data":{"name":"a.mkv","size":100,"md5":"AABBCCDDEEFF00112233445566778899"}}
        """
        let item = try CasFile.parse(data: Data(json.utf8))
        XCTAssertEqual(item.name, "a.mkv")
        XCTAssertEqual(item.size, 100)
    }

    /// 带 BOM 的 .cas
    func testParseStripsBOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("""
        {"name":"b.mkv","size":10,"md5":"AABBCCDDEEFF00112233445566778899"}
        """.utf8))
        let item = try CasFile.parse(data: data)
        XCTAssertEqual(item.name, "b.mkv")
    }

    /// 错误信息里要带内容开头，便于定位
    func testParseErrorIncludesPreview() {
        let data = Data("this is not json".utf8)
        XCTAssertThrowsError(try CasFile.parse(data: data)) { error in
            XCTAssertTrue(error.localizedDescription.contains("this is not json"),
                          "错误信息应包含内容预览，实际：\(error.localizedDescription)")
        }
    }

    /// Base64(JSON) 形式的 .cas（实测来自「The Scandal」凭证包）
    func testParseBase64WrappedJSON() throws {
        let inner = #"{"name":"a.mkv","size":6523591955,"md5":"EA48540AD707F5669E250E1C4FF7A791","sliceMd5":"7C3680CAF37D082DC054AEB6A67BDD42","create_time":"1793859645"}"#
        let text = Data(inner.utf8).base64EncodedString()
        let item = try CasFile.parse(data: Data(text.utf8))
        XCTAssertEqual(item.name, "a.mkv")
        XCTAssertEqual(item.size, 6523591955)
        XCTAssertEqual(item.fileMd5, "EA48540AD707F5669E250E1C4FF7A791")
        XCTAssertEqual(item.sliceMd5, "7C3680CAF37D082DC054AEB6A67BDD42")
        XCTAssertEqual(item.sliceSize, 10485760)
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
