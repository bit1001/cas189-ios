import Foundation

/// One video as presented by any site adapter. Keeps the UI site-agnostic.
public struct SiteVideo: Sendable, Hashable, Identifiable {
    public let site: String          // "haijiao" | "pornshop" | "hstv" | "theporny" | "51porn" | "thdh" | "javhd" | "douyin"
    public let id: String            // site-native id used for detail lookup
    public let title: String
    public let author: String
    public let cover: String?
    public let views: Int
    public let durationText: String?
    public let playURL: String?      // m3u8 when the list already carries it

    public var uid: String { "\(site):\(id)" }

    public init(site: String, id: String, title: String, author: String = "",
                cover: String? = nil, views: Int = 0, durationText: String? = nil,
                playURL: String? = nil) {
        self.site = site
        self.id = id
        self.title = title
        self.author = author
        self.cover = cover
        self.views = views
        self.durationText = durationText
        self.playURL = playURL
    }

    public var durationSeconds: Int? {
        guard let t = durationText else { return nil }
        let parts = t.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}

public struct SitePage: Sendable {
    public let site: String
    public let page: Int
    public let items: [SiteVideo]
    public init(site: String, page: Int, items: [SiteVideo]) {
        self.site = site; self.page = page; self.items = items
    }
}

/// Every site adapter implements this so the app can switch sources with one call.
public protocol SiteAdapter: Sendable {
    var siteID: String { get }
    var displayName: String { get }
    func feed(page: Int) async throws -> SitePage
    func search(_ keyword: String, page: Int) async throws -> SitePage
    /// Resolve a playable m3u8 (or mp4) URL for the given site-native id.
    func playURL(videoID: String) async throws -> URL
}
