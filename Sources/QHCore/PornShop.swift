import Foundation

/// PornShop 系四站共用同一套 JSON API（`POST {v2-host}/js`），差异只在 `app` / Origin。
/// 实测：响应 `{"r": "<OpenSSL salted base64>"}`，口令固定为 "xxx"，AES-256-CBC + PKCS7。
/// WAF 会概率性返回 403 {"blocked":true}，必须在 8 个 CDN host 间轮换重试。
public struct PornShopClient: SiteAdapter {
    public struct Site: Sendable {
        public let id: String
        public let app: String
        public let origin: String
        public let label: String
    }

    public static let sites: [Site] = [
        Site(id: "hstv", app: "hstv.fun", origin: "https://hstv.fun/", label: "好色TV"),
        Site(id: "theporny", app: "theporny.com", origin: "https://theporny.com/", label: "thePorny"),
    ]

    public static let hosts = [
        "https://v2.cdn199.com", "https://v2.kekecdn.net", "https://v2.luchu.org",
        "https://v2.madou.ws", "https://v2.papapa.biz", "https://v2.tianmtv.com",
        "https://v2.xiaoshuo.info", "https://v2.xiaoshuo.la",
    ]

    static let apiVersion = "260901"
    static let passphrase = "xxx"

    public let siteID: String
    public let displayName: String
    private let site: Site
    private let http: HTTPClient

    public init(siteID: String, http: HTTPClient = HTTPClient(insecureTLS: true)) throws {
        guard let s = Self.sites.first(where: { $0.id == siteID }) else {
            throw QHError.api("unknown PornShop site \(siteID)")
        }
        self.site = s
        self.siteID = s.id
        self.displayName = s.label
        self.http = http
    }

    // MARK: - SiteAdapter

    public func feed(page: Int) async throws -> SitePage {
        // Default 自拍 landing = 国产自拍 ("hot"), the main shelf.
        try await feed(section: "hot", page: page)
    }

    /// Self-shot section: the section key is sent verbatim as the API `type`
    /// (verified against the live API: hot/recent/favs/month_hot/... are distinct).
    public func feed(section: String, page: Int) async throws -> SitePage {
        let type = section.isEmpty ? "hot" : section
        let arr = try await callArray("/sevenVideos?page=\(max(1, page))&type=\(type)")
        return SitePage(site: siteID, page: page, items: arr.compactMap(parse))
    }

    public func search(_ keyword: String, page: Int) async throws -> SitePage {
        let arr = try await callArray("/searchSevenVideos", extra: [
            "page": max(1, page),
            "keywords": keyword,
            "keywordLogic": "or",
        ])
        return SitePage(site: siteID, page: page, items: arr.compactMap(parse))
    }

    public func playURL(videoID: String) async throws -> URL {
        let obj = try await callObject("/sevenVideos/\(videoID)")
        if let list = obj["m3u8s"] as? [String], let first = list.first, let url = URL(string: first) {
            return url
        }
        if let s = obj["m3u8"] as? String, let url = URL(string: s) {
            return url
        }
        throw QHError.api("no m3u8 in detail for \(videoID)")
    }

    // MARK: - parsing

    private func parse(_ o: [String: Any]) -> SiteVideo? {
        guard let vid = (o["vId"] as? String) ?? (o["id"] as? String), !vid.isEmpty else { return nil }
        let thumbs = (o["thumbnails"] as? [String]) ?? (o["thumbNails"] as? [String]) ?? []
        let m3 = (o["m3u8s"] as? [String])?.first ?? (o["m3u8"] as? String)
        return SiteVideo(
            site: siteID,
            id: vid,
            title: (o["title"] as? String) ?? "",
            author: (o["user"] as? String) ?? "",
            cover: thumbs.first,
            views: intValue(o["views"]),
            durationText: o["durationStr"] as? String,
            playURL: m3
        )
    }

    private func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let s = any as? String { return Int(s) ?? 0 }
        return 0
    }

    // MARK: - transport

    private func callArray(_ path: String, extra: [String: Any] = [:]) async throws -> [[String: Any]] {
        let data = try await call(path, extra: extra)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw QHError.decode("expected JSON array for \(path)")
        }
        return arr
    }

    private func callObject(_ path: String) async throws -> [String: Any] {
        let data = try await call(path, extra: [:])
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QHError.decode("expected JSON object for \(path)")
        }
        return obj
    }

    private func call(_ path: String, extra: [String: Any]) async throws -> Data {
        var body: [String: Any] = [
            "app": site.app,
            "isStandalone": false,
            "theLink": "novaluenull",
            "uuid": "novalue",
            "url": path,
            "version": Self.apiVersion,
        ]
        for (k, v) in extra { body[k] = v }
        let payload = try JSONSerialization.data(withJSONObject: body)

        var lastError = "no host tried"
        for _ in 0..<3 {
            for host in Self.hosts {
                guard let url = URL(string: host + "/js") else { continue }
                do {
                    let (raw, _) = try await http.data(url, method: "POST", headers: [
                        "Content-Type": "application/json",
                        "Authorization": "Bearer undefined",
                        "Origin": site.origin.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                        "Referer": site.origin,
                    ], body: payload)
                    guard let obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
                        lastError = "bad json from \(host)"
                        continue
                    }
                    if let encoded = obj["r"] as? String {
                        return try OpenSSLSalted.decrypt(base64: encoded, passphrase: Self.passphrase)
                    }
                    lastError = "blocked by \(host): \(String(decoding: raw.prefix(40), as: UTF8.self))"
                } catch {
                    lastError = "\(host): \(error)"
                }
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        throw QHError.api(lastError)
    }
}
