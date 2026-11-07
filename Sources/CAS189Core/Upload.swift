import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

extension Cloud189Client {

    /// 真实分片上传（秒传未命中时的兜底）。
    /// 协议由 APK `uploadPart()` 反编译得到：
    /// ``` 
    /// params = { partInfo: "<partNumber>-<Base64(rawMD5)>", uploadFileId: … }
    /// POST /person/getMultiUploadUrls  → uploadUrls.partNumber_N.{requestURL, requestHeader}
    /// PUT requestURL  (headers 来自 requestHeader，按 & 拆分)
    /// 全部分片完成 → POST /person/commitMultiUploadFile
    /// ```
    public func uploadFile(at url: URL,
                           name: String? = nil,
                           parentFolderId: String = "-11",
                           overwrite: Bool = false,
                           progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> RapidResult {

        let item = try CryptoTool.fingerprintFile(url)
        let info = CasItem(name: name ?? url.lastPathComponent,
                           size: item.size,
                           fileMd5: item.fileMd5,
                           sliceMd5: item.sliceMd5,
                           sliceSize: item.sliceSize,
                           parts: item.parts)
        let prefix = "/person"

        let initParams: [(String, String)] = [
            ("parentFolderId", parentFolderId),
            ("fileName", Self.percentEncode(info.name)),
            ("fileSize", String(info.size)),
            ("sliceSize", String(info.sliceSize)),
            ("extend", "{\"opScene\":\"1\",\"relativepath\":\"\",\"rootfolderid\":\"\"}"),
            ("fileMd5", info.fileMd5.uppercased()),
            ("sliceMd5", info.sliceMd5.uppercased())
        ]

        var method = "POST"
        var initJSON = try await signedRequest(uri: prefix + "/initMultiUpload", params: initParams, method: method)
        if (initJSON["code"] as? String) != "SUCCESS" {
            method = "GET"
            initJSON = try await signedRequest(uri: prefix + "/initMultiUpload", params: initParams, method: method)
        }
        guard let data = initJSON["data"] as? [String: Any],
              let uploadFileId = data["uploadFileId"] as? String,
              !uploadFileId.isEmpty else {
            throw CASError.missing("initMultiUpload 未返回 uploadFileId")
        }
        let exists = (data["fileDataExists"] as? NSNumber)?.intValue ?? 0

        // 命中就直接提交，省掉全部分片
        if exists == 1 {
            try await commit(uploadFileId: uploadFileId, item: info, method: method, overwrite: overwrite)
            return RapidResult(ok: true, message: "秒传成功", uploadFileId: uploadFileId)
        }

        // 真实上传
        let sliceSize = info.sliceSize
        let count = max(1, info.parts.count)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        for index in 0..<count {
            try handle.seek(toOffset: UInt64(index * sliceSize))
            let chunk = handle.readData(ofLength: sliceSize)
            guard !chunk.isEmpty else { break }

            let digest = Data(Insecure.MD5.hash(data: chunk))
            let b64 = digest.base64EncodedString()
            let partNumber = index + 1

            let json = try await signedRequest(uri: prefix + "/getMultiUploadUrls", params: [
                ("partInfo", "\(partNumber)-\(b64)"),
                ("uploadFileId", uploadFileId)
            ], method: "POST")

            guard let urls = json["uploadUrls"] as? [String: Any],
                  let part = urls["partNumber_\(partNumber)"] as? [String: Any],
                  let requestURL = part["requestURL"] as? String,
                  let target = URL(string: requestURL) else {
                throw CASError.api(code: "UPLOAD", message: "分片 \(partNumber) 未拿到上传地址")
            }

            var headers: [String: String] = [:]
            for pair in (part["requestHeader"] as? String ?? "").split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { headers[String(kv[0])] = String(kv[1]) }
            }
            headers["Content-Length"] = String(chunk.count)

            let res = try await transport.request(target, method: "PUT", headers: headers, body: chunk)
            guard (200..<300).contains(res.status) else {
                throw CASError.api(code: String(res.status),
                                   message: "分片 \(partNumber) 上传失败：\(res.text.prefix(200))")
            }
            progress?(partNumber, count)
            debugLog?("分片 \(partNumber)/\(count) 完成 \(chunk.count)B")
        }

        try await commit(uploadFileId: uploadFileId, item: info, method: method, overwrite: overwrite)
        return RapidResult(ok: true, message: "上传成功（\(count) 个分片）", uploadFileId: uploadFileId)
    }

    private func commit(uploadFileId: String, item: CasItem, method: String, overwrite: Bool) async throws {
        // 与 APK buildRapidCommitParams 一致：这两个 md5 与 opertype 都必须常驻
        let params: [(String, String)] = [
            ("uploadFileId", uploadFileId),
            ("fileMd5", item.fileMd5.uppercased()),
            ("sliceMd5", item.sliceMd5.uppercased()),
            ("lazyCheck", "1"),
            ("opertype", overwrite ? "3" : "1")
        ]
        _ = try await signedRequest(uri: "/person/commitMultiUploadFile", params: params, method: method)
    }
}
