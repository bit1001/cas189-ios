import Foundation

extension Cloud189Client {

    // MARK: - 文件管理（PC 网页通道，Cookie 即可，无需签名）

    /// 删除文件（可批量）。接口成功时返回空 body。
    public func deleteFiles(_ ids: [String]) async throws {
        for id in ids {
            let data = try await webGetData("/api/open/file/deleteFile.action", [("fileId", id)])
            if let err = Self.xmlError(data) {
                throw CASError.api(code: err.0, message: err.1)
            }
        }
    }

    /// 重命名，返回新条目
    @discardableResult
    public func rename(fileId: String, to newName: String) async throws -> CloudEntry? {
        let data = try await webGetData("/api/open/file/renameFile.action",
                                        [("fileId", fileId), ("destFileName", newName)])
        if let err = Self.xmlError(data) {
            throw CASError.api(code: err.0, message: err.1)
        }
        return try WebListParser.parse(data).first
    }

    // MARK: - 搜索

    /// 189 没有可用的服务端搜索接口（几个候选路径都是 404），
    /// 只能递归遍历目录做本地匹配。depth 限制避免深树把请求打爆。
    public func search(_ keyword: String,
                       folderId: String = "-11",
                       depth: Int = 3,
                       progress: (@Sendable (Int) -> Void)? = nil) async -> [CloudEntry] {
        let needle = keyword.lowercased()
        var hits: [CloudEntry] = []
        var queue: [(String, Int)] = [(folderId, 0)]
        var visited = 0

        while !queue.isEmpty {
            let (current, level) = queue.removeFirst()
            guard let entries = try? await listEntries(folderId: current, pageSize: 200) else { continue }
            visited += 1
            progress?(visited)
            for e in entries {
                if e.name.lowercased().contains(needle) { hits.append(e) }
                if e.isFolder, level + 1 < depth { queue.append((e.id, level + 1)) }
            }
        }
        return hits
    }

    // MARK: - XML 错误

    /// 189 的错误格式：<error><code>..</code><message>..</message></error>
    static func xmlError(_ data: Data) -> (String, String)? {
        guard let text = String(data: data, encoding: .utf8),
              text.contains("<error>") else { return nil }
        let code = xmlTag(text, "code") ?? "?"
        let message = xmlTag(text, "message") ?? ""
        return (code, message)
    }
}
