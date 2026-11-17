import Foundation

/// 91PinSe — Cloudflare 前置 + 按出口 IP 限区（非 CN IP 一律 `error code: 1034`）。
///
/// 站点结构：
///  * 列表 `/v/?page=N`（20 条/页），卡片在 `<article class="video-card">`
///  * 搜索 `/v/search?keyword=<kw>`（参数名是关键，`q` 无效）
///  * 播放 `POST /api/videos/<id>/playback`，body `{}`，必须带 Origin + Referer
///  * 返回的 m3u8 分段是 **TS 但扩展名 .jpg**（`i0.jpg`…），AVPlayer 播不了，
///    只能下载后拼接（`SiteRegistry.requiresLocalDecrypt` 返回 true）
public struct PinseClient: SiteAdapter {
    public let siteID = "pinse"
    public let displayName = "91PinSe"

    static let host = "https://91pinse.com"
    static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private let http: HTTPClient

    public init() throws {
        // insecureTLS 让 Linux CLI 走 curl 分支：验证时需要通过 `ALL_PROXY` 从 CN 出口访问，
        // URLSession 不认这个环境变量。站点本身证书是有效的。
        self.http = HTTPClient(userAgent: Self.mobileUA, defaultHeaders: [
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9",
        ], insecureTLS: true)
    }

    public func feed(page: Int) async throws -> SitePage {
        let html = try await http.text(try Self.url("/v/?page=\(max(1, page))"))
        try Self.rejectGate(html)
        return SitePage(site: siteID, page: page, items: Self.parseCards(html))
    }

    public func search(_ keyword: String, page: Int) async throws -> SitePage {
        let enc = keyword.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? keyword
        let html = try await http.text(try Self.url("/v/search?keyword=\(enc)&page=\(max(1, page))"))
        try Self.rejectGate(html)
        return SitePage(site: siteID, page: page, items: Self.parseCards(html))
    }

    public func playURL(videoID: String) async throws -> URL {
        let (data, _) = try await http.data(
            try Self.url("/api/videos/\(videoID)/playback"),
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "Origin": Self.host,
                "Referer": Self.host + "/v/\(videoID)",
                "Accept": "application/json, text/plain, */*",
            ],
            body: Data("{}".utf8))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QHError.decode("pinse playback is not JSON")
        }
        let raw = (root["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (root["fallback_url"] as? String)
        guard let raw, let u = URL(string: raw) else {
            throw QHError.api("91PinSe \(videoID): playback 未返回地址")
        }
        return u
    }

    // MARK: - parsing

    static func url(_ path: String) throws -> URL {
        guard let u = URL(string: host + path) else { throw QHError.decode("bad pinse url \(path)") }
        return u
    }

    static func rejectGate(_ html: String) throws {
        if html.contains("Edge IP Restricted") {
            throw QHError.api("91PinSe 限制出口 IP（非中国大陆 IP 会 403），需用 CN 网络")
        }
        if html.contains("Just a moment") || html.contains("error code: 1034") {
            throw QHError.api("91PinSe 被 Cloudflare 拦截")
        }
    }

    static func parseCards(_ html: String) -> [SiteVideo] {
        var seen = Set<String>()
        var out: [SiteVideo] = []
        for chunk in html.components(separatedBy: "<article") {
            guard chunk.contains("video-card"),
                  let id = ThdhClient.firstMatch(#"href="/v/(\d+)""#, in: chunk),
                  !seen.contains(id) else { continue }
            seen.insert(id)
            let title = ThdhClient.firstMatch(#"aria-label="([^"]+)""#, in: chunk)
                ?? ThdhClient.firstMatch(#"alt="([^"]+)""#, in: chunk)
                ?? "视频 \(id)"
            let cover = ThdhClient.firstMatch(#"<img[^>]+src="([^"]+)""#, in: chunk)
            let duration = ThdhClient.firstMatch(#"video-duration[^>]*>([^<]+)<"#, in: chunk)
            let author = ThdhClient.firstMatch(#"href="/(?:u|user|author)/[^"]+"[^>]*>([^<]+)<"#, in: chunk)
            out.append(SiteVideo(site: "pinse", id: id,
                                 title: ThdhClient.decodeEntities(title),
                                 author: author.map(ThdhClient.decodeEntities) ?? "",
                                 cover: cover, views: 0, durationText: duration))
        }
        return out
    }
}
