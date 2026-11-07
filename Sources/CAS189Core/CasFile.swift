import Foundation
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

/// `.cas` 秒传凭证（JSON）与 `.cas.zip`（打包多个凭证）的读写。
///
/// `.cas` 文件格式（与天翼云盘 App 的 `CasParser.buildCasJson` 一致）：
/// ```json
/// {
///   "cloud": "189",
///   "name": "movie.mkv",
///   "size": 122055775557,
///   "md5": "ABCD…",           // 全文件 MD5（大写）
///   "slice_md5": "EF01…",     // 分片 MD5 串联后的 MD5（大写）
///   "slice_size": 10485760,
///   "slice_md5s": ["…", "…"]  // 仅多分片时出现
/// }
/// ```
public enum CasFile {

    public struct FormatError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    // MARK: - .cas JSON

    /// 解析 `.cas` 文本
    public static func parse(json data: Data, fallbackName: String = "") throws -> CasItem {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FormatError(message: "不是合法的 .cas JSON")
        }

        func first(_ keys: String...) -> String {
            for k in keys {
                if let v = obj[k] as? String, !v.isEmpty { return v }
            }
            return ""
        }

        var name = first("name", "fileName")
        let md5 = first("md5", "fileMd5", "file_md5").uppercased()
        var sliceMd5 = first("slice_md5", "sliceMd5").uppercased()
        let size = (obj["size"] as? NSNumber)?.int64Value
            ?? (obj["size"] as? String).flatMap { Int64($0) }
            ?? 0
        let sliceSize = (obj["slice_size"] as? NSNumber)?.intValue
            ?? (obj["slice_size"] as? String).flatMap { Int($0) }
            ?? C.sliceSize

        var parts: [String] = []
        if let list = obj["slice_md5s"] as? [String] {
            parts = list.map { $0.uppercased() }
        } else if let list = obj["slice_md5s"] as? [Any] {
            parts = list.compactMap { ($0 as? String)?.uppercased() }
        }

        if name.isEmpty || name.lowercased().hasSuffix(".cas") || name.lowercased().hasSuffix(".cas.torrent") {
            name = stripCasName(fallbackName.isEmpty ? name : fallbackName)
        }
        guard size > 0 else { throw FormatError(message: "CAS 未包含原始文件大小，无法秒传") }
        guard md5.count == 32 else { throw FormatError(message: "CAS 中的 MD5 不合法") }
        if sliceMd5.isEmpty { sliceMd5 = md5 }

        return CasItem(name: name, size: size, fileMd5: md5,
                       sliceMd5: sliceMd5, sliceSize: sliceSize, parts: parts)
    }

    /// 生成 `.cas` 文本
    public static func build(_ item: CasItem) -> Data {
        var obj: [String: Any] = [
            "cloud": "189",
            "name": item.name,
            "size": item.size,
            "md5": item.fileMd5.uppercased(),
            "slice_md5": (item.sliceMd5.isEmpty ? item.fileMd5 : item.sliceMd5).uppercased(),
            "slice_size": item.sliceSize
        ]
        if item.parts.count > 1 {
            obj["slice_md5s"] = item.parts.map { $0.uppercased() }
        }
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
    }

    public static func isCasName(_ n: String) -> Bool {
        let l = n.lowercased()
        return l.hasSuffix(".cas") || l.hasSuffix(".cas.torrent")
    }

    public static func stripCasName(_ n: String) -> String {
        let l = n.lowercased()
        if l.hasSuffix(".cas.torrent") { return String(n.dropLast(12)) }
        if l.hasSuffix(".cas") { return String(n.dropLast(4)) }
        return n
    }

    /// 按扩展名解析：`.torrent` 走 bencode，其余当 JSON
    public static func parse(data: Data, fileName: String) throws -> CasItem {
        if fileName.lowercased().hasSuffix(".torrent") {
            return try CasTorrent.parse(data)
        }
        return try parse(json: data, fallbackName: fileName)
    }

    // MARK: - .cas.zip

    /// 从压缩包里取出所有 `.cas` / `.cas.torrent` 条目（跳过目录与其他文件）
    public static func entries(inArchive url: URL) throws -> [(name: String, data: Data)] {
        #if canImport(ZIPFoundation)
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw FormatError(message: "无法打开压缩包（仅支持 ZIP，RAR/7z 请先自行解压）")
        }
        var out: [(String, Data)] = []
        for entry in archive where entry.type == .file {
            guard isCasName(entry.path) else { continue }
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            let base = (entry.path as NSString).lastPathComponent
            out.append((base, data))
        }
        return out
        #else
        throw FormatError(message: "当前平台未编译 ZIP 支持")
        #endif
    }

    /// 打包多个 `.cas` 成 zip（对应 App 的「秒传凭证压缩包已生成」）
    public static func archive(_ items: [(name: String, data: Data)], to url: URL) throws {
        #if canImport(ZIPFoundation)
        try? FileManager.default.removeItem(at: url)
        guard let archive = Archive(url: url, accessMode: .create) else {
            throw FormatError(message: "无法创建压缩包")
        }
        for (name, data) in items {
            try archive.addEntry(with: name, type: .file,
                                 uncompressedSize: Int64(data.count),
                                 compressionMethod: .deflate) { position, size in
                let start = data.startIndex + Int(position)
                let end = min(start + size, data.endIndex)
                return data[start..<end]
            }
        }
        #else
        throw FormatError(message: "当前平台未编译 ZIP 支持")
        #endif
    }
}
