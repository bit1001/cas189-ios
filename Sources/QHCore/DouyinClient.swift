import Foundation
import Crypto

/// 黑暗抖阴 — 全站加密 API（实机逆向确认）:
///  * URL  `https://<ip>/<md5hex(uuid)>`，这段路径服务端忽略；真路径在 `x-ph` 头里
///  * `x-ph = b64url(AES-192-CBC(path + "/" + b64url(md5(uuid)) , PATH_KEY, iv = x-trace-id))`
///  * body = base64(AES-192-CBC-PKCS7(json, BODY_KEY, BODY_IV))，key/iv 固定
///  * 响应是一个 JSON 字符串字面量，内容用同一组 BODY_KEY/BODY_IV 解密
///  * 证书自签（CN=localhost），必须 trust-all；匿名需先注册游客拿 JWT
public struct DouyinClient: SiteAdapter {
    public let siteID = "douyin"
    public let displayName = "黑暗抖阴"

    static let host = "ecsvnp1.cn1-hongkong.aliyuncs.com"
    static let ips = ["143.92.60.55", "143.92.60.68", "143.92.60.99", "27.124.42.79", "27.124.42.98"]
    static let bodyKey = Array("KivItun6MHYOU55hlQECIa==".utf8)   // 24 B → AES-192
    static let bodyIV = Array("efa3s7w8fbe3jae2".utf8)
    static let pathKey = Array("WhtRldf4KJHUY22hlJRUSo==".utf8)   // 24 B → AES-192

    private let http: HTTPClient

    public init() throws {
        // The original app sends an *empty* User-Agent on this site.
        self.http = HTTPClient(userAgent: "", defaultHeaders: [:], insecureTLS: true)
    }

    // MARK: - SiteAdapter

    public func feed(page: Int) async throws -> SitePage {
        let data = try await post("/video/list", body: ["page": max(1, page), "pageSize": 20, "type": 1])
        return SitePage(site: siteID, page: page, items: Self.parseList(data))
    }

    public func search(_ keyword: String, page: Int) async throws -> SitePage {
        let data = try await post("/video/list", body: [
            "page": max(1, page), "pageSize": 20, "type": 1, "title": keyword,
        ])
        return SitePage(site: siteID, page: page, items: Self.parseList(data))
    }

    public func playURL(videoID: String) async throws -> URL {
        guard let id = Int(videoID) else { throw QHError.api("bad douyin id") }
        let data = try await post("/video/detail/v2", body: ["id": id])
        guard let root = data as? [String: Any],
              let info = root["playInfo"] as? [String: Any],
              let plays = info["playUrl"] as? [[String: Any]] else {
            throw QHError.api("抖阴 \(videoID): 详情无 playInfo")
        }
        // 匿名账号只下发 preview（正片 videoLink 恒为空），这是站点限制而非解析失败。
        for p in plays {
            if let s = p["videoLink"] as? String, !s.isEmpty, let u = URL(string: s) { return u }
        }
        for p in plays {
            if let s = p["previewVideoLink"] as? String, !s.isEmpty, let u = URL(string: s) { return u }
        }
        throw QHError.api("抖阴 \(videoID): 无可用播放地址（可能需要登录/购买）")
    }

    // MARK: - session

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedSession: (uuid: String, token: String)?

    private func session() async throws -> (uuid: String, token: String) {
        Self.lock.lock()
        let hit = Self.cachedSession
        Self.lock.unlock()
        if let hit { return hit }

        let uuid = UUID().uuidString.lowercased()
        _ = try await post("/user/guest/register", body: [:], uuid: uuid, token: nil)
        let login = try await post("/user/login", body: [:], uuid: uuid, token: nil)
        guard let root = login as? [String: Any], let token = root["token"] as? String else {
            throw QHError.api("抖阴: 游客登录未返回 token")
        }
        let s = (uuid, token)
        Self.lock.lock(); Self.cachedSession = s; Self.lock.unlock()
        return s
    }

    // MARK: - transport

    private func post(_ path: String, body: [String: Any], uuid: String? = nil, token: String? = nil) async throws -> Any {
        let session: (uuid: String, token: String)
        if let uuid, let token {
            session = (uuid, token)
        } else if let uuid {
            session = (uuid, "")
        } else {
            session = try await self.session()
        }

        var payload = body
        payload["deviceType"] = 1
        payload["oauthId"] = session.uuid
        payload["oauthType"] = "android"
        payload["platform"] = "App"

        let json = try JSONSerialization.data(withJSONObject: payload)
        let bodyCipher = try AES(key: Self.bodyKey).encryptCBC([UInt8](json), iv: Self.bodyIV)
        let bodyB64 = Data(bodyCipher).base64EncodedString()

        let trace = Self.traceID()
        let tail = Self.b64url(Data(Insecure.MD5.hash(data: Data(session.uuid.utf8))))
        let plainPath = path + "/" + tail
        let pathCipher = try AES(key: Self.pathKey).encryptCBC([UInt8](plainPath.utf8), iv: Array(trace.utf8))
        let xph = Self.b64url(Data(pathCipher))

        let urlPath = Self.md5Hex(session.uuid)
        var lastError = "no ip tried"
        for ip in Self.ips {
            guard let url = URL(string: "https://\(ip)/\(urlPath)") else { continue }
            var headers: [String: String] = [
                "Host": Self.host,
                "CLIENT": "android",
                "Content-Type": "application/json",
                "x-trace-id": trace,
                "Accept": "*",
                "x-tp": trace,
                "x-ph": xph,
            ]
            if !session.token.isEmpty { headers["Authorization"] = "Bearer \(session.token)" }
            do {
                let (raw, _) = try await http.data(url, method: "POST", headers: headers,
                                                   body: Data(bodyB64.utf8))
                return try Self.decodeResponse(raw)
            } catch {
                lastError = "\(ip): \(error)"
            }
        }
        throw QHError.api(lastError)
    }

    static func decodeResponse(_ raw: Data) throws -> Any {
        var text = String(decoding: raw, as: UTF8.self)
        text = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\"") {
            if let data = text.data(using: .utf8),
               let unquoted = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String {
                text = unquoted
            }
        }
        let compact = text.filter { !$0.isWhitespace }
        guard let blob = Data(base64Encoded: compact) else {
            throw QHError.decode("抖阴响应不是 base64: \(compact.prefix(40))")
        }
        let plain = try AES(key: bodyKey).decryptCBC([UInt8](blob), iv: bodyIV, removePadding: true)
        let obj = try JSONSerialization.jsonObject(with: Data(plain), options: [.fragmentsAllowed])
        if let dict = obj as? [String: Any], let code = dict["code"] as? Int, code != 200 {
            throw QHError.api("抖阴业务错误 \(code): \(dict["message"] ?? "")")
        }
        if let dict = obj as? [String: Any] { return dict["data"] ?? [:] }
        return obj
    }

    // MARK: - parsing

    static func parseList(_ data: Any) -> [SiteVideo] {
        guard let root = data as? [String: Any], let list = root["list"] as? [[String: Any]] else { return [] }
        return list.compactMap { o in
            guard let id = o["id"] as? Int else { return nil }
            let user = o["appUser"] as? [String: Any]
            return SiteVideo(
                site: "douyin",
                id: String(id),
                title: (o["title"] as? String) ?? "视频 \(id)",
                author: (user?["nickname"] as? String) ?? "",
                cover: o["cover"] as? String,
                views: (o["playCount"] as? Int) ?? 0,
                durationText: o["durationStr"] as? String
            )
        }
    }

    // MARK: - helpers

    static func md5Hex(_ s: String) -> String {
        Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 13 位毫秒 + 3 位随机数 = 16 字符；同时用作 x-ph 的 IV。
    static func traceID() -> String {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        return String(ms) + String(format: "%03d", Int.random(in: 0...999))
    }
}
