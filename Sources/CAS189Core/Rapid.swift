import Foundation

extension Cloud189Client {

    /// 秒传：与 APK `rapidUpload` / `rapidUploadVia` 一致的两段式流程
    /// ```
    /// initMultiUpload  → fileDataExists
    ///   == 1  → commitMultiUploadFile  → 秒传成功
    ///   != 1  → 未命中（需要真实分片上传，本实现暂不提供）
    /// ```
    public func rapidUpload(_ item: CasItem,
                            parentFolderId: String = "-11",
                            overwrite: Bool = false) async throws -> RapidResult {
        let prefix = "/person"
        let sliceMd5 = item.sliceMd5.isEmpty ? item.fileMd5 : item.sliceMd5
        let upperMd5 = item.fileMd5.uppercased()
        let upperSlice = sliceMd5.uppercased()

        let initParams: [(String, String)] = [
            ("parentFolderId", parentFolderId),
            ("fileName", Self.percentEncode(item.name)),
            ("fileSize", String(item.size)),
            ("sliceSize", String(item.sliceSize)),
            ("extend", "{\"opScene\":\"1\",\"relativepath\":\"\",\"rootfolderid\":\"\"}"),
            ("fileMd5", upperMd5),
            ("sliceMd5", upperSlice)
        ]

        var lastError: Error?
        for method in ["POST", "GET"] {
            do {
                let initJSON = try await signedRequest(uri: prefix + "/initMultiUpload",
                                                       params: initParams, method: method)
                guard let data = initJSON["data"] as? [String: Any],
                      let uploadFileId = data["uploadFileId"] as? String,
                      !uploadFileId.isEmpty else {
                    throw CASError.missing("initMultiUpload 未返回 uploadFileId")
                }
                let exists = (data["fileDataExists"] as? NSNumber)?.intValue ?? 0
                debugLog?("init[\(method)] fileDataExists=\(exists) id=\(uploadFileId)")

                if exists != 1 {
                    return RapidResult(ok: false, message: "云端没有该文件内容，无法秒传（需要真实上传）",
                                       uploadFileId: uploadFileId)
                }

                var commitParams: [(String, String)] = [("uploadFileId", uploadFileId)]
                if method == "GET" {
                    commitParams.append(contentsOf: [
                        ("fileMd5", upperMd5),
                        ("sliceMd5", upperSlice),
                        ("lazyCheck", "1")
                    ])
                }
                if overwrite { commitParams.append(("opertype", "3")) }

                _ = try await signedRequest(uri: prefix + "/commitMultiUploadFile",
                                            params: commitParams, method: method)
                debugLog?("命中 \(item.name)，\(method) 通道提交成功")
                return RapidResult(ok: true, message: "秒传成功", uploadFileId: uploadFileId)
            } catch {
                lastError = error
                // 会话失效直接抛；其它错误换下一种 method 再试
                if case CASError.sessionExpired = error { throw error }
                continue
            }
        }
        throw lastError ?? CASError.api(code: "-1", message: "秒传失败")
    }

    /// 批量秒传（串行，便于展示进度；服务端有频控，不建议高并发）
    public func rapidUpload(items: [CasItem],
                            parentFolderId: String = "-11",
                            overwrite: Bool = false,
                            progress: ((Int, Int, CasItem, RapidResult) -> Void)? = nil) async -> [(CasItem, RapidResult)] {
        var results: [(CasItem, RapidResult)] = []
        for (index, item) in items.enumerated() {
            do {
                let result = try await rapidUpload(item, parentFolderId: parentFolderId, overwrite: overwrite)
                results.append((item, result))
                progress?(index + 1, items.count, item, result)
            } catch {
                let failure = RapidResult(ok: false, message: error.localizedDescription)
                results.append((item, failure))
                progress?(index + 1, items.count, item, failure)
            }
        }
        return results
    }

    /// 参数里的 fileName 需要 percent-encode（APK 用 Util.quote）
    static func percentEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
