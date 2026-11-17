import Foundation

/// JAVHD — 列表是「JSON 包 HTML 片段」，播放是 progressive MP4（站点没有 HLS）。
///
/// 三个坑：
///  1. 不带 `X-Requested-With: XMLHttpRequest` 会返回整页 HTML，而不是 JSON。
///  2. 列表 id (`video-id`) ≠ 播放 id (`content-id`)：必须先进详情页取 `content-id`。
///  3. 详情里 `content-path` 带 `&is_trailer=1`，照抄只能拿到预告片；要自己拼 `player_api?videoId=<content-id>`。
public struct JavhdClient: SiteAdapter {
    public let siteID = "javhd"
    public let displayName = "JAVHD"

    static let host = "https://javhd.com"

    static let xhrHeaders = [
        "X-Requested-With": "XMLHttpRequest",
        "Accept": "application/json, text/plain, */*",
    ]

    /// `video-id` alone is not a valid detail URL: `/zh/id/<id>` 500s, the working form is
    /// the `link-content` slug from the listing. Cache it while parsing.
    private static let detailPaths = NSCache<NSString, NSString>()

    private let http: HTTPClient

    public init() throws {
        // NB: `X-Requested-With` must NOT be a default header — the HTML detail page
        // returns 500 when it looks like an XHR. It is sent only on list/search calls.
        self.http = HTTPClient(defaultHeaders: [
            "Referer": "https://javhd.com/zh/",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9",
        ], insecureTLS: true)
    }

    public func feed(page: Int) async throws -> SitePage {
        let path = page <= 1
            ? "/zh/japanese-porn-videos"
            : "/zh/japanese-porn-videos/justadded/all/\(page)"
        let (data, _) = try await http.data(try Self.url(path), method: "POST",
                                            headers: Self.xhrHeaders, body: Data())
        let items = try Self.parseListing(data)
        return SitePage(site: siteID, page: page, items: items)
    }

    public func search(_ keyword: String, page: Int) async throws -> SitePage {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? keyword
        let (data, _) = try await http.data(try Self.url("/zh/search?page=\(max(1, page))&q=\(encoded)"),
                                            headers: Self.xhrHeaders)
        return SitePage(site: siteID, page: page, items: try Self.parseListing(data))
    }

    public func playURL(videoID: String) async throws -> URL {
        // 1. 详情页取 content-id（播放器 id），不是列表的 video-id。
        let detailPath = Self.detailPaths.object(forKey: videoID as NSString) as String? ?? "/zh/id/\(videoID)"
        let html = try await http.text(try Self.url(detailPath))
        guard let contentID = Self.playerID(in: html) else {
            throw QHError.api("JAVHD \(videoID): 详情页没有播放器 id")
        }
        // 2. player_api 拿 sources，挑码率最高的一档。
        let (data, _) = try await http.data(try Self.url("/zh/player_api?videoId=\(contentID)"))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sources = root["sources"] as? [[String: Any]] else {
            throw QHError.api("JAVHD \(videoID): player_api 无 sources")
        }
        let playable = sources.compactMap { s -> (String, String)? in
            guard let file = (s["src"] as? String) ?? (s["file"] as? String), !file.isEmpty else { return nil }
            return (file, (s["type"] as? String) ?? "")
        }
        if let hls = playable.first(where: { $0.1.contains("mpegurl") || $0.0.contains(".m3u8") }),
           let u = URL(string: hls.0) { return u }
        if let mp4 = playable.first(where: { $0.0.contains(".mp4") }), let u = URL(string: mp4.0) { return u }
        throw QHError.api("JAVHD \(videoID): sources 里没有可播放地址")
    }

    // MARK: - parsing

    static func url(_ path: String) throws -> URL {
        guard let u = URL(string: host + path) else { throw QHError.decode("bad javhd url \(path)") }
        return u
    }

    static func parseListing(_ data: Data) throws -> [SiteVideo] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let template = root["template"] as? String else {
            throw QHError.decode("JAVHD listing is not JSON with template")
        }
        var seen = Set<String>()
        var out: [SiteVideo] = []
        let regex = try NSRegularExpression(pattern: #"<thumb-component\b([^>]*)>"#, options: [.caseInsensitive])
        let range = NSRange(template.startIndex..., in: template)
        for m in regex.matches(in: template, range: range) {
            guard let r = Range(m.range(at: 1), in: template) else { continue }
            let attrs = parseAttributes(String(template[r]))
            if let type = attrs["type-thumb"], !type.isEmpty, type != "video" { continue }
            guard let id = attrs["video-id"], id.allSatisfy(\.isNumber), !seen.contains(id) else { continue }
            seen.insert(id)
            let thumb = attrs["url-thumb"].map(resizeThumb)
            if let link = attrs["link-content"], let comps = URLComponents(string: link) {
                Self.detailPaths.setObject((comps.path.isEmpty ? link : comps.path) as NSString,
                                           forKey: id as NSString)
            }
            out.append(SiteVideo(
                site: "javhd",
                id: id,
                title: decode(attrs["title"] ?? "视频 \(id)"),
                author: attrs["studio"] ?? "",
                cover: thumb,
                views: Int(attrs["views"] ?? "") ?? 0,
                durationText: nil
            ))
        }
        return out
    }

    static func parseAttributes(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        let regex = try? NSRegularExpression(pattern: #"([A-Za-z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#)
        let range = NSRange(s.startIndex..., in: s)
        regex?.enumerateMatches(in: s, range: range) { m, _, _ in
            guard let m, let nameRange = Range(m.range(at: 1), in: s) else { return }
            let name = String(s[nameRange])
            if let r2 = Range(m.range(at: 2), in: s) { out[name] = String(s[r2]); return }
            if let r3 = Range(m.range(at: 3), in: s) { out[name] = String(s[r3]) }
        }
        return out
    }

    static func resizeThumb(_ url: String) -> String {
        url.replacingOccurrences(
            of: #"/(374x233|300x169|320x180|360x203|468x264|480x270|640x360)/"#,
            with: "/728x413/",
            options: .regularExpression)
    }

    static func playerID(in html: String) -> String? {
        for pattern in [#"content-id\s*=\s*"(\d+)""#, #"[?&]videoId=(\d+)"#, #"cms_id=(\d+)"#] {
            if let v = ThdhClient.firstMatch(pattern, in: html) { return v }
        }
        return nil
    }

    static func decode(_ s: String) -> String { ThdhClient.decodeEntities(s) }
}
