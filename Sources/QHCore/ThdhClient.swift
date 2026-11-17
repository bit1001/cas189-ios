import Foundation

/// 探花 (thdh.cc) — AppleCMS 站点，纯 HTML。
///
/// 两个非显而易见的点（由实机逆向确认）：
///  1. 播放页 `/index.php/vod/play/...` 恒被 WAF 拦（「系统提示」页），播放地址不在 HTML 里。
///     真正的 m3u8 由**封面图 URL 同目录推导**得到：把文件名换成 `index.m3u8`。
///  2. `hot` / `new` 榜只有第 1 页；分页要走分类页 `/index.php/vod/show/id/<34…60>/page/<n>.html`。
public struct ThdhClient: SiteAdapter {
    public let siteID = "thdh"
    public let displayName = "探花"

    static let host = "https://www.thdh.cc"
    /// 精品国产；hot/new 无分页，翻页统一落在这个分类上。
    static let pagingCategory = 34

    private let http: HTTPClient

    public init() throws {
        self.http = HTTPClient(defaultHeaders: [
            "Referer": "https://www.thdh.cc/",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9",
        ], insecureTLS: true)
    }

    public func feed(page: Int) async throws -> SitePage {
        let path = page <= 1
            ? "/index.php/label/hot.html"
            : "/index.php/vod/show/id/\(Self.pagingCategory)/page/\(page).html"
        let html = try await http.text(try Self.url(path))
        try Self.rejectGate(html)
        return SitePage(site: siteID, page: page, items: Self.parseCards(html, site: siteID))
    }

    public func search(_ keyword: String, page: Int) async throws -> SitePage {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? keyword
        let path = "/index.php/vod/search/page/\(max(1, page))/wd/\(encoded).html"
        let html = try await http.text(try Self.url(path))
        try Self.rejectGate(html)
        return SitePage(site: siteID, page: page, items: Self.parseCards(html, site: siteID))
    }

    public func playURL(videoID: String) async throws -> URL {
        let html = try await http.text(try Self.url("/index.php/vod/detail/id/\(videoID).html"))
        try Self.rejectGate(html)
        guard let poster = Self.firstMatch(#"<img[^>]+data-original="([^"]+)""#, in: html),
              let master = Self.deriveMasterPlaylist(poster: poster) else {
            throw QHError.api("探花 \(videoID): 未能从封面推导播放地址")
        }
        return master
    }

    // MARK: - URL helpers

    static func url(_ path: String) throws -> URL {
        guard let u = URL(string: host + path) else { throw QHError.decode("bad thdh url \(path)") }
        return u
    }

    /// 封面 `https://cdn/20261103/abc/1.jpg` → `https://cdn/20261103/abc/index.m3u8`
    static func deriveMasterPlaylist(poster: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: #"/[^/?#]+\.(?:jpe?g|png|webp|gif)(?:\?.*)?$"#,
                                                   options: [.caseInsensitive]) else { return nil }
        let range = NSRange(poster.startIndex..., in: poster)
        let replaced = regex.stringByReplacingMatches(in: poster, range: range, withTemplate: "/index.m3u8")
        return URL(string: replaced)
    }

    /// WAF / 跳转壳识别：命中就不是真实内容页。
    static func rejectGate(_ html: String) throws {
        if html.contains("系统提示") {
            throw QHError.api("探花返回拦截页（系统提示）")
        }
        if html.contains("立即进入") && html.count < 4000 {
            throw QHError.api("探花返回跳转壳页")
        }
    }

    // MARK: - parsing

    static func parseCards(_ html: String, site: String) -> [SiteVideo] {
        var seen = Set<String>()
        var out: [SiteVideo] = []
        let blocks = html.components(separatedBy: "<a ")
        for block in blocks.dropFirst() {
            guard let end = block.range(of: "</a>") else { continue }
            let anchor = String(block[..<end.lowerBound])
            guard anchor.contains("module-item"),
                  let id = firstMatch(#"/vod/(?:play|free|detail)/id/(\d+)"#, in: anchor),
                  !seen.contains(id) else { continue }
            let title = firstMatch(#"\btitle="([^"]*)""#, in: anchor)
                ?? firstMatch(#"module-poster-item-title[^>]*>([^<]+)<"#, in: anchor)
                ?? "视频 \(id)"
            let poster = firstMatch(#"data-original="([^"]+)""#, in: anchor)
                ?? firstMatch(#"data-src="([^"]+)""#, in: anchor)
                ?? firstMatch(#"<img[^>]+src="([^"]+)""#, in: anchor)
            let duration = firstMatch(#"th-dur[^>]*>([^<]+)<"#, in: anchor)
            let views = firstMatch(#"([\d,]+)\s*次观看"#, in: anchor).map { Int($0.replacingOccurrences(of: ",", with: "")) ?? 0 } ?? 0
            seen.insert(id)
            out.append(SiteVideo(site: site, id: id, title: decodeEntities(title),
                                 author: "", cover: normalizeImage(poster),
                                 views: views, durationText: duration))
        }
        return out
    }

    static func normalizeImage(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.contains("placeholder") || raw.contains("/loading") || raw.contains("lazy") { return nil }
        if raw.hasPrefix("//") { return "https:" + raw }
        return raw
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
