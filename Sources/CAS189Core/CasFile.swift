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
        var data = data
        // 去掉 UTF-8 BOM（有些 Windows 工具导出的 .cas 带 BOM，JSONSerialization 会报错）
        if data.count >= 3, data[data.startIndex] == 0xEF,
           data[data.startIndex + 1] == 0xBB, data[data.startIndex + 2] == 0xBF {
            data = data.subdata(in: (data.startIndex + 3)..<data.endIndex)
        }
        // 有些工具导出的 .cas 是 Base64(JSON)，甚至 Base64(Base64(JSON))
        var decoded = data
        for _ in 0..<3 {
            guard decoded.first != UInt8(ascii: "{"),
                  let text = String(data: decoded, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty,
                  let raw = decodeBase64(text),
                  raw.first == UInt8(ascii: "{") else { break }
            decoded = raw
        }

        guard let any = try? JSONSerialization.jsonObject(with: decoded,
                                                         options: [.fragmentsAllowed]) else {
            throw FormatError(message: "不是 JSON（开头：\(preview(data))）")
        }
        // 有些导出工具把内容套在 data/result 里
        var obj: [String: Any]
        if let dict = any as? [String: Any] {
            obj = dict
            for key in ["data", "result", "cas"] {
                if let inner = dict[key] as? [String: Any] { obj = inner; break }
            }
        } else {
            throw FormatError(message: "JSON 顶层不是对象（开头：\(preview(data))）")
        }

        func first(_ keys: String...) -> String {
            for k in keys {
                if let v = obj[k] as? String, !v.isEmpty { return v }
                if let v = obj[k] as? NSNumber { return v.stringValue }
            }
            return ""
        }
        func int64(_ keys: String...) -> Int64? {
            for k in keys {
                if let v = obj[k] as? NSNumber { return v.int64Value }
                if let v = obj[k] as? String, let n = Int64(v.trimmingCharacters(in: .whitespaces)) { return n }
            }
            return nil
        }

        var name = first("name", "fileName", "file_name", "path", "originalName")
        let md5 = first("md5", "fileMd5", "file_md5", "fileHash", "hash").uppercased()
        var sliceMd5 = first("slice_md5", "sliceMd5", "SliceMd5", "SLICE_MD5").uppercased()
        let size = int64("size", "fileSize", "file_size", "length") ?? 0
        let sliceSize = Int(int64("slice_size", "sliceSize", "fileSliceSize") ?? Int64(C.sliceSize))

        var parts: [String] = []
        for key in ["slice_md5s", "sliceMd5s", "sliceMd5List", "parts", "md5s"] {
            if let list = obj[key] as? [String] {
                parts = list.map { $0.uppercased() }
                break
            } else if let list = obj[key] as? [Any] {
                let mapped = list.compactMap { ($0 as? String)?.uppercased() }
                if !mapped.isEmpty { parts = mapped; break }
            }
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

    /// 宽松 Base64 解码：容忍换行、空白、缺省 padding、URL-safe 字符
    static func decodeBase64(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // 只允许 base64 字符，避免把普通文本误判
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    /// 出错时把内容开头带进错误信息，方便判断到底是哪种格式
    static func preview(_ data: Data, limit: Int = 80) -> String {
        if let text = String(data: data.prefix(limit), encoding: .utf8) {
            let one = text.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .trimmingCharacters(in: .whitespaces)
            return one.isEmpty ? "<空白>" : one
        }
        return data.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")
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
    public static func parse(data: Data, fileName: String = "") throws -> CasItem {
        if fileName.lowercased().hasSuffix(".torrent") {
            return try CasTorrent.parse(data)
        }
        return try parse(json: data, fallbackName: fileName)
    }

    // MARK: - .cas.zip

    /// 压缩包里的**所有文件条目**（不做扩展名过滤）。
    /// 凭证包通常就叫 `xxx.zip`，里面文件也可能不带 `.cas` 后缀，
    /// 是否需要某个条目由调用方按内容判断。
    public static func allEntries(inArchive url: URL) throws -> [(name: String, data: Data)] {
        #if canImport(ZIPFoundation)
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw FormatError(message: "无法打开压缩包（仅支持 ZIP，RAR/7z 请先自行解压）")
        }
        var out: [(String, Data)] = []
        for entry in archive where entry.type == .file {
            if entry.path.hasPrefix("__MACOSX/") { continue }
            let base = (entry.path as NSString).lastPathComponent
            if base == ".DS_Store" || base.isEmpty { continue }
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            out.append((base, data))
        }
        return out
        #else
        throw FormatError(message: "当前平台未编译 ZIP 支持")
        #endif
    }

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
