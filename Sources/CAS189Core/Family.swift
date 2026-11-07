import Foundation

/// 家庭云（family cloud）
///
/// 和「我的云盘」完全不是一套通道：
/// - 主机是 **api.cloud.189.cn**（不是 cloud.189.cn，走错域名只会得到 `AppNotExist`）
/// - 鉴权用 `AccessToken` + MD5 签名头，而不是 Cookie
/// - 上传走 `upload.cloud.189.cn/family/*`，参数多一个 `familyId`
extension Cloud189Client {

    /// 家庭云固定 appKey（网页版家庭云用的就是这个）
    static let familyAppKey = "600100422"

    // MARK: - AccessToken

    /// 用 SessionKey 换 AccessToken（12 小时内有效，可在进程内缓存）
    public func fetchAccessToken() async throws -> String {
        if let cached = cachedAccessToken, cached.expiry > Date() { return cached.value }

        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        let signText = "AppKey=\(Self.familyAppKey)&SessionKey=\(session.sessionKey)&Timestamp=\(ts)"
        let signature = CryptoTool.hexLower(CryptoTool.md5(Data(signText.utf8)))

        var comps = URLComponents(string: C.webURL + "/api/open/oauth2/getAccessTokenBySsKey.action")!
        comps.queryItems = [
            URLQueryItem(name: "sessionKey", value: session.sessionKey),
            URLQueryItem(name: "appKey", value: Self.familyAppKey)
        ]

        let res = try await transport.request(comps.url!, method: "GET", headers: [
            "AppKey": Self.familyAppKey,
            "SessionKey": session.sessionKey,
            "Sign-Type": "1",
            "Signature": signature,
            "Timestamp": ts,
            "Accept": "application/json"
        ])

        guard let json = try? res.json(),
              let token = json["accessToken"] as? String, !token.isEmpty else {
            throw CASError.missing("未取得 AccessToken（家庭云需要网页版登录态）")
        }
        // expiresIn 2026 的语义是「过期时间戳(ms)」，保险起见按 12 小时缓存
        cachedAccessToken = (token, Date().addingTimeInterval(12 * 3600))
        debugLog?("家庭云 AccessToken 已获取")
        return token
    }

    // MARK: - 签名请求

    /// 对 https://api.cloud.189.cn/open/family/... 发签名请求
    /// 签名串 = AccessToken=..&Timestamp=..&<参数按 key 升序 k=v，用 & 连接> → MD5 小写
    public func familyGet(_ path: String,
                          params: [(String, String)] = []) async throws -> [String: Any] {
        let token = try await fetchAccessToken()
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))

        var sorted = params.sorted { $0.0 < $1.0 }
        var signText = "AccessToken=\(token)&Timestamp=\(ts)"
        for (k, v) in sorted { signText += "&\(k)=\(v)" }
        let signature = CryptoTool.hexLower(CryptoTool.md5(Data(signText.utf8)))

        var comps = URLComponents(string: "https://api.cloud.189.cn" + path)!
        if !sorted.isEmpty {
            comps.queryItems = sorted.map { URLQueryItem(name: $0.0, value: $0.1) }
        }

        let res = try await transport.request(comps.url!, method: "GET", headers: [
            "AccessToken": token,
            "Sign-Type": "1",
            "Signature": signature,
            "Timestamp": ts,
            "Accept": "application/json;charset=UTF-8"
        ])

        if let text = String(data: res.body, encoding: .utf8),
           text.trimmingCharacters(in: .whitespaces).hasPrefix("<") {
            if let err = Self.xmlError(res.body) {
                throw CASError.api(code: err.0, message: err.1)
            }
        }
        return try res.json()
    }

    // MARK: - 家庭云列表

    /// 家庭云列表（当前账号第一个家庭）
    public func familyInfo() async throws -> [FamilyInfo] {
        let json = try await familyGet("/open/family/manage/getFamilyList.action")
        let list = (json["familyInfoResp"] as? [[String: Any]]) ?? []
        return list.compactMap { item in
            guard let id = (item["familyId"] as? NSNumber)?.stringValue
                ?? (item["familyId"] as? String) else { return nil }
            return FamilyInfo(id: id, name: (item["remarkName"] as? String) ?? "家庭云")
        }
    }

    public func familyList(folderId: String = "-11",
                           familyId: String) async throws -> [CloudEntry] {
        let json = try await familyGet("/open/family/file/listFiles.action", params: [
            ("familyId", familyId),
            ("folderId", folderId),
            ("pageSize", "200"),
            ("mediaType", "0")
        ])
        guard let ao = json["fileListAO"] as? [String: Any] else { return [] }

        func entry(_ d: [String: Any], isFolder: Bool) -> CloudEntry? {
            let id = (d["id"] as? NSNumber)?.stringValue ?? (d["id"] as? String)
            let name = d["name"] as? String
            guard let id, let name else { return nil }
            let size = (d["size"] as? NSNumber)?.int64Value ?? 0
            let parent = (d["parentId"] as? NSNumber)?.stringValue ?? (d["parentId"] as? String)
            return CloudEntry(id: id, name: name, size: size, isFolder: isFolder,
                              md5: d["md5"] as? String, parentId: parent)
        }

        let folders = (ao["folderList"] as? [[String: Any]] ?? []).compactMap { entry($0, isFolder: true) }
        let files = (ao["fileList"] as? [[String: Any]] ?? []).compactMap { entry($0, isFolder: false) }
        return folders + files
    }

    /// 家庭云新建文件夹
    public func familyMkdir(name: String, familyId: String,
                            parentFolderId: String = "-11") async throws -> String {
        let json = try await familyGet("/open/family/file/createFolder.action", params: [
            ("familyId", familyId),
            ("parentFolderId", parentFolderId),
            ("folderName", name)
        ])
        let id = (json["id"] as? NSNumber)?.stringValue ?? (json["id"] as? String) ?? ""
        guard !id.isEmpty else { throw CASError.missing("建文件夹未返回 id") }
        return id
    }

    // MARK: - 家庭云上传 / 秒传

    /// 家庭云真实上传（秒传未命中时用）
    public func familyUpload(at url: URL,
                             familyId: String,
                             name: String? = nil,
                             parentFolderId: String = "-11",
                             progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> RapidResult {
        try await uploadFile(at: url, name: name, parentFolderId: parentFolderId,
                             channel: .family(familyId: familyId), progress: progress)
    }

    /// 家庭云秒传（通道与个人云一致，只是 uri 前缀变 /family 且多传 familyId）
    public func familyRapidUpload(_ item: CasItem,
                                  familyId: String,
                                  parentFolderId: String = "-11") async throws -> RapidResult {
        let sliceMd5 = item.sliceMd5.isEmpty ? item.fileMd5 : item.sliceMd5
        let upperMd5 = item.fileMd5.uppercased()
        let upperSlice = sliceMd5.uppercased()

        let initParams: [(String, String)] = [
            ("parentFolderId", parentFolderId),
            ("fileName", Self.percentEncode(item.name)),
            ("fileSize", String(item.size)),
            ("sliceSize", String(item.sliceSize)),
            ("familyId", familyId),
            ("fileMd5", upperMd5),
            ("sliceMd5", upperSlice)
        ]

        var lastError: Error?
        for method in ["POST", "GET"] {
            do {
                let initJSON = try await signedRequest(uri: "/family/initMultiUpload",
                                                       params: initParams, method: method)
                guard let data = initJSON["data"] as? [String: Any],
                      let uploadFileId = data["uploadFileId"] as? String,
                      !uploadFileId.isEmpty else {
                    throw CASError.missing("family initMultiUpload 未返回 uploadFileId")
                }
                let exists = (data["fileDataExists"] as? NSNumber)?.intValue ?? 0
                debugLog?("family init[\(method)] fileDataExists=\(exists)")

                if exists != 1 {
                    return RapidResult(ok: false,
                                       message: "家庭云没有该文件内容，无法秒传",
                                       uploadFileId: uploadFileId)
                }

                var committed = false
                var lastErr: Error?

                // 变体 1：带 familyId 的 checkTransSecond
                // checkTransSecond 必须带 familyId，否则 InfoSecurityErrorCode
                _ = try await signedRequest(uri: "/family/checkTransSecond", params: [
                    ("fileMd5", upperMd5),
                    ("sliceMd5", upperSlice),
                    ("uploadFileId", uploadFileId),
                    ("familyId", familyId)
                ], method: method)

                // 实测唯一通过的组合：opertype=1、不带 lazyCheck、带 familyId
                _ = try await signedRequest(uri: "/family/commitMultiUploadFile", params: [
                    ("uploadFileId", uploadFileId),
                    ("fileMd5", upperMd5),
                    ("sliceMd5", upperSlice),
                    ("opertype", "1"),
                    ("familyId", familyId)
                ], method: method)
                committed = true

                if !committed {
                    return RapidResult(ok: false,
                                       message: "家庭云秒传被拒：\(lastErr?.localizedDescription ?? "未知")",
                                       uploadFileId: uploadFileId)
                }
                return RapidResult(ok: true, message: "家庭云秒传成功", uploadFileId: uploadFileId)
            } catch {
                lastError = error
                if case CASError.sessionExpired = error { throw error }
                continue
            }
        }
        throw lastError ?? CASError.api(code: "-1", message: "家庭云秒传失败")
    }
}

// MARK: - 家庭云 POST / 批量任务

extension Cloud189Client {

    /// POST 表单到 api.cloud.189.cn（签名包含表单参数，键值各自 URL 编码）
    public func familyPost(_ path: String,
                           params: [(String, String)]) async throws -> [String: Any] {
        let token = try await fetchAccessToken()
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        let sorted = params.sorted { $0.0 < $1.0 }

        var signText = "AccessToken=\(token)&Timestamp=\(ts)"
        for (k, v) in sorted { signText += "&\(k)=\(v)" }
        let signature = CryptoTool.hexLower(CryptoTool.md5(Data(signText.utf8)))

        let body = sorted
            .map { "\(Self.formEncode($0.0))=\(Self.formEncode($0.1))" }
            .joined(separator: "&")

        let url = URL(string: "https://api.cloud.189.cn" + path)!
        let res = try await transport.request(url, method: "POST", headers: [
            "AccessToken": token,
            "Sign-Type": "1",
            "Signature": signature,
            "Timestamp": ts,
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json;charset=UTF-8"
        ], body: body.data(using: .utf8))

        debugLog?("familyPost \(path) HTTP \(res.status)")
        if let text = String(data: res.body, encoding: .utf8),
           text.trimmingCharacters(in: .whitespaces).hasPrefix("<") {
            if let err = Self.xmlError(res.body) {
                throw CASError.api(code: err.0, message: err.1)
            }
        }
        return try res.json()
    }

    /// 家庭云文件转存到个人云（COPY，copyType=2）
    /// 实测：taskStatus=4、successedCount=1，文件出现在个人云目标目录
    @discardableResult
    public func familyCopyToPersonal(fileId: String,
                                     fileName: String,
                                     familyId: String,
                                     targetFolderId: String = "-11") async throws -> String {
        let infos = [["fileId": fileId, "fileName": fileName, "isFolder": 0]] as [[String: Any]]
        let jsonData = try JSONSerialization.data(withJSONObject: infos)
        let jsonText = String(data: jsonData, encoding: .utf8) ?? "[]"

        let json = try await familyPost("/open/batch/createBatchTask.action", params: [
            ("type", "COPY"),
            ("taskInfos", jsonText),
            ("targetFolderId", targetFolderId),
            ("familyId", familyId),
            ("groupId", "null"),
            ("copyType", "2"),
            ("shareId", "null")
        ])

        let taskId = (json["taskId"] as? String)
            ?? (json["taskId"] as? NSNumber)?.stringValue
            ?? ""
        guard !taskId.isEmpty else {
            throw CASError.api(code: (json["res_code"] as? String) ?? "COPY",
                               message: (json["res_message"] as? String) ?? "未取得 taskId")
        }
        return taskId
    }

    /// 查询家庭云批量任务
    public func familyCheckTask(type: String, taskId: String, familyId: String) async throws -> [String: Any] {
        try await familyPost("/open/batch/checkBatchTask.action", params: [
            ("type", type),
            ("taskId", taskId),
            ("familyId", familyId)
        ])
    }

    /// 轮询直到 taskStatus == 4 或子任务都有结果
    public func familyWaitTask(type: String, taskId: String, familyId: String,
                               timeoutSeconds: Double = 30) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var last: [String: Any] = [:]
        while Date() < deadline {
            last = try await familyCheckTask(type: type, taskId: taskId, familyId: familyId)
            let status = (last["taskStatus"] as? NSNumber)?.intValue
                ?? Int((last["taskStatus"] as? String) ?? "") ?? 0
            let done = ((last["successedCount"] as? NSNumber)?.intValue ?? 0)
                     + ((last["failedCount"] as? NSNumber)?.intValue ?? 0)
                     + ((last["skipCount"] as? NSNumber)?.intValue ?? 0)
            let total = (last["subTaskCount"] as? NSNumber)?.intValue ?? 0
            if status == 4 { return last }
            if total > 0 && done >= total { return last }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
        return last
    }
}

// MARK: - 家庭云 文件管理

extension Cloud189Client {

    /// 家庭云重命名（实测：返回改名后的文件对象）
    public func familyRename(fileId: String, to newName: String, familyId: String) async throws {
        let json = try await familyGet("/open/family/file/renameFile.action", params: [
            ("familyId", familyId),
            ("fileId", fileId),
            ("destFileName", newName)
        ])
        if let code = json["errorCode"] as? String, !code.isEmpty {
            throw CASError.api(code: code, message: (json["errorMsg"] as? String) ?? "")
        }
    }

    /// 家庭云删除
    public func familyDelete(fileId: String, familyId: String) async throws {
        let json = try await familyGet("/open/family/file/deleteFile.action", params: [
            ("familyId", familyId),
            ("fileId", fileId)
        ])
        if let code = json["errorCode"] as? String, !code.isEmpty {
            throw CASError.api(code: code, message: (json["errorMsg"] as? String) ?? "")
        }
    }

    /// 任意空间的目录列表（给目录选择器用）
    public func entries(space: String, folderId: String, familyId: String) async throws -> [CloudEntry] {
        if space == "family" {
            return try await familyList(folderId: folderId, familyId: familyId)
        }
        return try await listEntries(folderId: folderId)
    }
}
