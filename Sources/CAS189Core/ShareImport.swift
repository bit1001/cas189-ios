import Foundation

/// 分享链接转存（web 通道，Cookie 即可）
///
/// 完整流程（抓包自官方分享页）：
/// ```
/// GET  /api/open/share/getShareInfoByCodeV2.action?shareCode=<code>      → <shareVO> 拿 shareId
/// GET  /api/open/share/listShareDir.action?fileId=&shareMode=3&isFolder=&shareId=&iconOption=5&pageNum=&pageSize=&accessCode=
/// POST /api/open/batch/createBatchTask.action
///        type=SHARE_SAVE
///        taskInfos=[{"fileId":"..","fileName":"..","isFolder":0}]
///        targetFolderId=-11&shareId=<shareId>
/// POST /api/open/batch/checkBatchTask.action   type=SHARE_SAVE
/// ```
public struct ShareInfo: Sendable, Equatable {
    public let shareId: String
    public let fileId: String
    public let fileName: String
    public let fileSize: Int64
    public let isFolder: Bool
    public let needAccessCode: Bool
    public let accessCode: String
}

extension Cloud189Client {

    /// 解析分享链接 → 基本信息（含 shareId）
    public func shareInfo(code: String, accessCode: String = "") async throws -> ShareInfo {
        var query: [(String, String)] = [("shareCode", code)]
        if !accessCode.isEmpty { query.append(("accessCode", accessCode)) }
        let data = try await webGetData("/api/open/share/getShareInfoByCodeV2.action", query)
        if let err = Self.xmlError(data) { throw CASError.api(code: err.0, message: err.1) }

        let text = String(data: data, encoding: .utf8) ?? ""
        let shareId = Self.xmlTag(text, "shareId") ?? ""
        guard !shareId.isEmpty else {
            throw CASError.missing("分享不存在或已失效")
        }
        return ShareInfo(
            shareId: shareId,
            fileId: Self.xmlTag(text, "fileId") ?? "",
            fileName: Self.xmlTag(text, "fileName") ?? "",
            fileSize: Int64(Self.xmlTag(text, "fileSize") ?? "0") ?? 0,
            isFolder: (Self.xmlTag(text, "isFolder") ?? "false") == "true",
            needAccessCode: (Self.xmlTag(text, "needAccessCode") ?? "0") == "1",
            accessCode: Self.xmlTag(text, "accessCode") ?? ""
        )
    }

    /// 列出分享目录（不传 fileId 时用分享根目录）
    public func shareList(info: ShareInfo,
                          fileId: String? = nil,
                          accessCode: String = "") async throws -> [CloudEntry] {
        let data = try await webGetData("/api/open/share/listShareDir.action", [
            ("fileId", fileId ?? info.fileId),
            ("shareMode", "3"),
            ("isFolder", fileId == nil ? String(info.isFolder) : "true"),
            ("shareId", info.shareId),
            ("iconOption", "5"),
            ("pageNum", "1"),
            ("pageSize", "200"),
            ("accessCode", accessCode)
        ])
        if let err = Self.xmlError(data) { throw CASError.api(code: err.0, message: err.1) }
        return try WebListParser.parse(data)
    }

    /// 转存到自己的云盘。返回服务端原始 JSON（成功时 res_code == "0"）。
    @discardableResult
    public func saveShare(info: ShareInfo,
                          fileIds: [String]? = nil,
                          targetFolderId: String = "-11",
                          accessCode: String = "") async throws -> [String: Any] {
        // 需要转存哪几个文件：默认整个分享
        let items: [(id: String, name: String, isFolder: Bool)]
        if let fileIds, !fileIds.isEmpty {
            items = fileIds.map { ($0, info.fileName, info.isFolder) }
        } else if info.isFolder {
            let entries = try await shareList(info: info)
            items = entries.map { ($0.id, $0.name, $0.isFolder) }
        } else {
            items = [(info.fileId, info.fileName, false)]
        }

        let taskInfos = items.map { item -> [String: Any] in
            ["fileId": item.id, "fileName": item.name, "isFolder": item.isFolder ? 1 : 0]
        }
        let jsonData = try JSONSerialization.data(withJSONObject: taskInfos)
        let jsonText = String(data: jsonData, encoding: .utf8) ?? "[]"

        var fields: [(String, String)] = [
            ("type", "SHARE_SAVE"),
            ("taskInfos", jsonText),
            ("targetFolderId", targetFolderId),
            ("shareId", info.shareId)
        ]
        if !accessCode.isEmpty { fields.append(("accessCode", accessCode)) }
        let body = fields
            .map { "\($0.0)=\(Self.formEncode($0.1))" }
            .joined(separator: "&")

        let url = URL(string: C.webURL + "/api/open/batch/createBatchTask.action")!
        let res = try await transport.request(url, method: "POST",
                                             headers: ["Content-Type": "application/x-www-form-urlencoded"],
                                             body: body.data(using: .utf8))
        debugLog?("createBatchTask HTTP \(res.status)")
        let text = res.text

        // 成功时返回 XML：<TaskIdResp><taskId>202611072045195266</taskId></TaskIdResp>
        if let taskId = Self.xmlTag(text, "taskId"), !taskId.isEmpty {
            return ["taskId": taskId]
        }
        // 失败是 <error><code>..</code><message>..</message></error>
        if let err = Self.xmlError(res.body) {
            if err.0 == "BatchOperFileFailed" && err.1.contains("AlreadyExist") {
                throw CASError.api(code: err.0, message: "该文件已在转存队列中（同一任务不可重复提交）")
            }
            throw CASError.api(code: err.0, message: err.1)
        }
        throw CASError.api(code: "HTTP\(res.status)", message: "转存请求失败：\(text.prefix(120))")
    }

    /// 查询转存任务进度
    public func checkShareSaveTask(taskId: String) async throws -> [String: Any] {
        let url = URL(string: C.webURL + "/api/open/batch/checkBatchTask.action")!
        let body = "type=SHARE_SAVE&taskId=\(taskId)"
        let res = try await transport.request(url, method: "POST",
                                             headers: ["Content-Type": "application/x-www-form-urlencoded"],
                                             body: body.data(using: .utf8))
        debugLog?("checkBatchTask HTTP \(res.status)")
        let text = res.text
        // XML: <TaskResultResp><taskStatus>4</taskStatus><successedCount>1</successedCount>…
        if let status = Self.xmlTag(text, "taskStatus") {
            return [
                "taskId": Self.xmlTag(text, "taskId") ?? taskId,
                "taskStatus": status,
                "successedCount": Self.xmlTag(text, "successedCount") ?? "0",
                "failedCount": Self.xmlTag(text, "failedCount") ?? "0",
                "skipCount": Self.xmlTag(text, "skipCount") ?? "0",
                "subTaskCount": Self.xmlTag(text, "subTaskCount") ?? "0"
            ]
        }
        return ["raw": text]
    }

    static func formEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
