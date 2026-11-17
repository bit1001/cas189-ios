import Foundation

/// Wraps the Haijiao client in the common adapter interface.
public struct HaijiaoAdapter: SiteAdapter {
    public let siteID = "haijiao"
    public let displayName = "海角"
    private let client = HaijiaoClient()

    public init() {}

    public func feed(page: Int) async throws -> SitePage {
        let result = try await client.feed(.hot, page: page)
        return SitePage(site: siteID, page: page, items: result.topics.map { t in
            SiteVideo(site: siteID,
                      id: String(t.id),
                      title: t.title,
                      author: t.author,
                      cover: t.cover,
                      views: t.views,
                      durationText: nil,
                      playURL: t.videos.first?.url)
        })
    }

    public func search(_ keyword: String, page: Int) async throws -> SitePage {
        throw QHError.api("海角搜索需要登录，暂未接入")
    }

    public func playURL(videoID: String) async throws -> URL {
        guard let id = Int(videoID) else { throw QHError.api("bad haijiao id") }
        let topic = try await client.detail(id: id)
        guard let v = topic.videos.first, let url = URL(string: v.url) else {
            throw QHError.api("topic \(videoID) has no video")
        }
        return url
    }
}

public enum SiteRegistry {
    public struct Entry: Sendable, Hashable {
        public let id: String
        public let label: String
        public let group: String
    }

    /// Every site the Android original ships, in the same order.
    public static let entries: [Entry] = [
        Entry(id: "haijiao", label: "海角", group: "海角"),
        Entry(id: "pornshop", label: "PornShop", group: "PornShop 系"),
        Entry(id: "hstv", label: "好色TV", group: "PornShop 系"),
        Entry(id: "theporny", label: "thePorny", group: "PornShop 系"),
        Entry(id: "51porn", label: "51视频", group: "PornShop 系"),
        Entry(id: "thdh", label: "探花", group: "独立站"),
        Entry(id: "javhd", label: "JAVHD", group: "独立站"),
        Entry(id: "douyin", label: "黑暗抖阴", group: "独立站"),
        Entry(id: "pinse", label: "91PinSe", group: "独立站"),
    ]

    public static func adapter(for siteID: String) throws -> any SiteAdapter {
        switch siteID {
        case "haijiao": return HaijiaoAdapter()
        case "pornshop", "hstv", "theporny", "51porn":
            return try PornShopClient(siteID: siteID)
        case "thdh":
            return try ThdhClient()
        case "javhd":
            return try JavhdClient()
        case "douyin":
            return try DouyinClient()
        case "pinse":
            return try PinseClient()
        default:
            throw QHError.api("unknown site \(siteID)")
        }
    }

    /// Sites whose streams AVPlayer cannot play as-is:
    ///  * haijiao — HLS key needs a per-video JPEG-XOR transform
    ///  * douyin — HLS key is RSA-wrapped
    ///  * pinse  — segments are MPEG-TS but named `.jpg`, so AVPlayer treats them as images
    public static func requiresLocalDecrypt(_ siteID: String) -> Bool {
        siteID == "haijiao" || siteID == "douyin" || siteID == "pinse"
    }
}
