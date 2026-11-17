import Foundation


public struct DouyinClient: SiteAdapter {
    public let siteID = "douyin"
    public let displayName = "黑暗抖阴"
    public init() throws {}
    public func feed(page: Int) async throws -> SitePage { throw QHError.api("黑暗抖阴 接入中") }
    public func search(_ keyword: String, page: Int) async throws -> SitePage { throw QHError.api("黑暗抖阴 接入中") }
    public func playURL(videoID: String) async throws -> URL { throw QHError.api("黑暗抖阴 接入中") }
}
