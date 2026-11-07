import Foundation

/// 分享链接（189 的 createShareLink 返回）
public struct ShareLink: Sendable, Identifiable, Hashable {
    public let fileId: String
    public let url: String
    public let accessCode: String
    public let accessUrl: String
    public var id: String { url }

    /// 带提取码的完整文案，方便直接粘贴
    public var shareText: String {
        if accessCode.isEmpty { return "\(url)（公开分享，点开即用）" }
        return "\(url) 提取码：\(accessCode)"
    }
}

extension Cloud189Client {

    /// 创建分享链接。web 通道，Cookie 即可。
    /// 实测：shareType / expireTime 都可省略，服务端会用默认值。
    /// ```xml
    /// <shareLinkList><shareLink><fileId>..</fileId><url>https://cloud.189.cn/t/..</url>
    ///   <accessCode>4suu</accessCode><accessUrl>..</accessUrl></shareLink></shareLinkList>
    /// ```
    public func createShare(fileId: String,
                            shareType: Int? = nil,
                            expireDays: Int? = nil) async throws -> ShareLink {
        var query: [(String, String)] = [("fileId", fileId)]
        if let shareType { query.append(("shareType", String(shareType))) }
        if let expireDays { query.append(("expireTime", String(expireDays))) }

        let data = try await webGetData("/api/open/share/createShareLink.action", query)
        if let err = Self.xmlError(data) {
            throw CASError.api(code: err.0, message: err.1)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CASError.api(code: "SHARE", message: "分享响应不是文本")
        }
        let url = Self.xmlTag(text, "url") ?? ""
        let code = Self.xmlTag(text, "accessCode") ?? ""
        let accessUrl = Self.xmlTag(text, "accessUrl") ?? ""
        guard !url.isEmpty else {
            throw CASError.api(code: "SHARE", message: "未返回分享链接")
        }
        return ShareLink(fileId: fileId, url: url, accessCode: code, accessUrl: accessUrl)
    }

    /// 从任意文本里抠分享链接（对应 APK 的 extractShareLink / normalizeShareUrl）
    public static func extractShareLink(from text: String) -> (code: String, accessCode: String?)? {
        // 支持 cloud.189.cn/t/xxxxx、h5.cloud.189.cn/share.html#/t/xxxxx
        let patterns = [
            #"cloud\.189\.cn/t/([A-Za-z0-9]+)"#,
            #"cloud\.189\.cn/share\.html#/t/([A-Za-z0-9]+)"#,
            #"/t/([A-Za-z0-9]{8,})"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text) {
                let code = String(text[range])
                // 提取码：4 位字母数字，常跟在“提取码/密码/访问码”后面
                var accessCode: String?
                let codePatterns = [
                    #"(?:提取码|访问码|密码|code)[:：\s]*([A-Za-z0-9]{4})"#,
                    #"pwd=([A-Za-z0-9]{4})"#
                ]
                for cp in codePatterns {
                    if let r = try? NSRegularExpression(pattern: cp, options: [.caseInsensitive]),
                       let m = r.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                       m.numberOfRanges > 1,
                       let cr = Range(m.range(at: 1), in: text) {
                        accessCode = String(text[cr]); break
                    }
                }
                return (code, accessCode)
            }
        }
        return nil
    }
}
