import Foundation

/// Only three sites: 好色TV (hstv), 91PinSe (pinse), thePorny (theporny).
/// All connections are DIRECT — no proxy/tunnel is configured anywhere in the app.
public enum SiteRegistry {
    public struct Entry: Sendable, Hashable {
        public let id: String
        public let label: String
        public let group: String
    }

    public static let entries: [Entry] = [
        Entry(id: "hstv", label: "好色TV", group: "PornShop 系"),
        Entry(id: "pinse", label: "91PinSe", group: "独立站"),
        Entry(id: "theporny", label: "thePorny", group: "PornShop 系"),
    ]

    public static func adapter(for siteID: String) throws -> any SiteAdapter {
        switch siteID {
        case "hstv", "theporny":
            return try PornShopClient(siteID: siteID)
        case "pinse":
            return try PinseClient()
        default:
            throw QHError.api("unknown site \(siteID)")
        }
    }

    /// Sites whose streams AVPlayer cannot play as-is:
    ///  * pinse — segments are MPEG-TS but named `.jpg`, so AVPlayer treats them as images.
    /// PornShop-family HLS is plain MPEG-TS (signed URL, no key) and plays directly.
    public static func requiresLocalDecrypt(_ siteID: String) -> Bool {
        siteID == "pinse"
    }
}
