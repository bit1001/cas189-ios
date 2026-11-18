import Foundation

/// A self-shot ("自拍") sub-section exposed by a site.
/// `key` is the site-specific token sent to that site's API/URL.
public struct SelfShotSection: Sendable, Hashable, Identifiable {
    public let key: String
    public let label: String
    public var id: String { key }
    public init(key: String, label: String) { self.key = key; self.label = label }
}

/// Per-site 自拍 sub-sections, modeled from the original app's Catalog + live probes (2026-11).
/// The user only wants three sites; each implements 自拍 its own way:
///  - hstv / theporny: PornShop JSON API, `type` = section key
///  - pinse: HTML search `keyword=自拍`, `sort` = section key (or rank page)
public enum SelfShotCatalog {
    /// PornShop-family 自拍: "国产自拍" group. `hot` is the main 国产自拍 feed;
    /// the rest are the group's sort choices (recent/hot/favs/month_hot...).
    public static let pornshopSections: [SelfShotSection] = [
        SelfShotSection(key: "hot",            label: "国产自拍"),   // main
        SelfShotSection(key: "recent",         label: "最新"),
        SelfShotSection(key: "favs",           label: "最多收藏"),
        SelfShotSection(key: "recent_hot",     label: "最近加精"),
        SelfShotSection(key: "month_hot",      label: "本月最热"),
        SelfShotSection(key: "last_month_hot", label: "上月最热"),
        SelfShotSection(key: "month_favs",     label: "本月收藏"),
        SelfShotSection(key: "month_discuss",  label: "本月讨论"),
        SelfShotSection(key: "hd",             label: "高清视频"),
        SelfShotSection(key: "10mins",         label: "10分钟以上"),
        SelfShotSection(key: "20mins",         label: "20分钟以上"),
    ]

    /// pinse 自拍 sections. Search `keyword=自拍` with `sort`; the site only
    /// distinguishes default (最新) and `hot` (最热). Rank pages add time-window views.
    public static let pinseSections: [SelfShotSection] = [
        SelfShotSection(key: "latest",          label: "最新自拍"),   // search, no sort
        SelfShotSection(key: "hot",             label: "最热自拍"),   // search sort=hot
        SelfShotSection(key: "current-hot",     label: "当前热门"),   // rank page
        SelfShotSection(key: "weekly-hot",      label: "本周热门"),
        SelfShotSection(key: "month-hot",       label: "月度趋势"),
        SelfShotSection(key: "month-favorite",  label: "月度收藏"),
        SelfShotSection(key: "recently-featured", label: "精选视频"),
        SelfShotSection(key: "popular-now",     label: "大家都在看"),
    ]

    public static func sections(for siteID: String) -> [SelfShotSection] {
        switch siteID {
        case "hstv", "theporny": return pornshopSections
        case "pinse": return pinseSections
        default: return []
        }
    }
}
