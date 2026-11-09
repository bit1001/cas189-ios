import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 跨平台流式下载（Linux 的 Foundation 没有 `URLSession.bytes(for:)`，所以走 delegate）
final class StreamingDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private var continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>?
    private let progress: ((Int64, Int64) -> Void)?
    private var session: URLSession!

    init(progress: ((Int64, Int64) -> Void)? = nil) {
        self.progress = progress
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func run(_ request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let task = session.downloadTask(with: request)
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let http = downloadTask.response as? HTTPURLResponse else {
            continuation?.resume(throwing: CASError.missing("下载无响应"))
            continuation = nil
            return
        }
        // 把临时文件挪到稳定位置（delegate 回调结束后系统会删）
        let keep = FileManager.default.temporaryDirectory
            .appendingPathComponent("cas189-dl-\(UUID().uuidString)")
        do {
            try? FileManager.default.removeItem(at: keep)
            try FileManager.default.moveItem(at: location, to: keep)
            continuation?.resume(returning: (keep, http))
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        progress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, continuation != nil else { return }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension Cloud189Client {

    /// 与官方 App 的 normalizeDownloadUrl 保持一致：去掉空白、反 HTML 转义、
    /// `//host` 补 `https:`、`http://` 强制改写成 `https://`。
    /// 189 下载直链常是明文 http，改写后既绕开 ATS 也走官方同款路径。
    static func normalizeDownloadURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
        if s.hasPrefix("//") { s = "https:" + s }
        if s.hasPrefix("http://") { s = "https://" + String(s.dropFirst(7)) }
        return s
    }

    /// 取下载直链。web 通道返回的 XML 里 URL 被 HTML 转义过（`&amp;`），必须反转义。
    /// 家庭云走另一条通道：api.cloud.189.cn 上的签名接口
    /// `/open/family/file/getFileDownloadUrl.action`，参数 fileId + familyId + type=1，
    /// 用 web 通道带 familyId 只会得到 PermissionDenied。
    public func downloadURL(fileId: String, familyId: String? = nil) async throws -> URL {
        if let familyId, !familyId.isEmpty {
            let json = try await familyGet("/open/family/file/getFileDownloadUrl.action", params: [
                ("fileId", fileId), ("familyId", familyId), ("type", "1")
            ])
            guard let raw = json["fileDownloadUrl"] as? String, !raw.isEmpty else {
                throw CASError.missing("未返回下载地址（家庭云）")
            }
            let normalized = Self.normalizeDownloadURL(raw)
            guard let url = URL(string: normalized) else {
                throw CASError.missing("下载地址不合法：\(normalized.prefix(80))")
            }
            return url
        }
        let data = try await webGetData("/api/open/file/getFileDownloadUrl.action",
                                        [("fileId", fileId)])
        if let err = Self.xmlError(data) {
            throw CASError.api(code: err.0, message: err.1)
        }
        guard let text = String(data: data, encoding: .utf8),
              let raw = Self.xmlTag(text, "fileDownloadUrl") ?? Self.xmlTag(text, "fileUrl"),
              !raw.isEmpty else {
            throw CASError.missing("未返回下载地址")
        }
        let normalized = Self.normalizeDownloadURL(raw)
        guard let url = URL(string: normalized) else {
            throw CASError.missing("下载地址不合法：\(normalized.prefix(80))")
        }
        return url
    }

    /// 下载文件到本地路径；已存在同名文件时用 Range 续传。
    @discardableResult
    public func download(fileId: String,
                         to destination: URL,
                         familyId: String? = nil,
                         progress: ((Int64, Int64) -> Void)? = nil) async throws -> Int64 {
        let url = try await downloadURL(fileId: fileId, familyId: familyId)

        var request = URLRequest(url: url)
        request.timeoutInterval = 120

        var existing: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path),
           let size = (attrs[.size] as? NSNumber)?.int64Value, size > 0 {
            existing = size
            request.setValue("bytes=\(size)-", forHTTPHeaderField: "Range")
        }

        let downloader = StreamingDownloader(progress: progress)
        let tmp: URL
        let http: HTTPURLResponse
        do {
            (tmp, http) = try await downloader.run(request)
        } catch {
            // 把直链的域名/协议带进错误，方便判断是 ATS、重定向还是网络问题
            let where_ = "\(url.scheme ?? "?")://\(url.host ?? "?")"
            throw CASError.api(code: "下载失败", message: "下载地址 \(where_)：\(error.localizedDescription)")
        }

        guard http.statusCode == 200 || http.statusCode == 206 else {
            try? FileManager.default.removeItem(at: tmp)
            throw CASError.api(code: "HTTP\(http.statusCode)", message: "下载失败")
        }

        // 206 = 续传：把新数据追加到已有文件后面
        if http.statusCode == 206, existing > 0 {
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            try handle.seekToEnd()
            let incoming = try FileHandle(forReadingFrom: tmp)
            defer { try? incoming.close() }
            while let chunk = try incoming.read(upToCount: 1 << 20), !chunk.isEmpty {
                try handle.write(contentsOf: chunk)
            }
            try? FileManager.default.removeItem(at: tmp)
        } else {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tmp, to: destination)
        }

        let finalSize = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value
            ?? existing
        return finalSize
    }
}
