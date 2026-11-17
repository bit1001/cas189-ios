import Foundation

// MARK: - Models

public struct Attachment: Sendable, Hashable, Identifiable {
    public let id: Int
    public let url: String
    public let category: String
    public let cover: String?
    public let durationSec: Int?
}

public struct Topic: Sendable, Hashable, Identifiable {
    public let id: Int
    public let title: String
    public let author: String
    public let views: Int
    public let created: String
    public let cover: String?
    public let attachments: [Attachment]
    public let moneyType: Int

    public var videos: [Attachment] { attachments.filter { $0.category == "video" } }
}

public struct TopicPage: Sendable, Hashable {
    public let page: Int
    public let total: Int
    public let topics: [Topic]
}

// MARK: - Client

/// Haijiao (海角) client. Verified anonymously:
///  - GET /api/topic/hot/topics?page=N
///  - GET /api/topic/node/topics?type=7&page=N   (原创)
///  - GET /api/topic/node/news?page=N
///  - GET /api/topic/{id}
/// Payloads arrive as nested Base64 ("isEncrypted": true).
public struct HaijiaoClient: Sendable {
    public static let host = URL(string: "https://www.haijiao.com")!

    private let http: HTTPClient

    public init(http: HTTPClient = HTTPClient(defaultHeaders: [
        "Accept": "application/json, text/plain, */*",
        "pcVer": "2",
        "Origin": "https://www.haijiao.com",
        "Referer": "https://www.haijiao.com/",
    ])) {
        self.http = http
    }

    public enum Feed: String, Sendable {
        case hot, latest, cream, original, news

        var path: (Int) -> String {
            switch self {
            case .hot: return { "/api/topic/hot/topics?page=\($0)" }
            case .latest: return { "/api/topic/node/topics?type=1&nodeId=0&page=\($0)" }
            case .cream: return { "/api/topic/node/topics?type=3&nodeId=0&page=\($0)" }
            case .original: return { "/api/topic/node/topics?type=7&page=\($0)" }
            case .news: return { "/api/topic/node/news?page=\($0)" }
            }
        }
    }

    public func feed(_ feed: Feed = .hot, page: Int = 1) async throws -> TopicPage {
        try await getPage(feed.path(max(1, page)))
    }

    public func node(nodeId: Int, page: Int = 1, type: Int = 1) async throws -> TopicPage {
        try await getPage("/api/topic/node/topics?type=\(type)&nodeId=\(nodeId)&page=\(max(1, page))")
    }

    public func detail(id: Int) async throws -> Topic {
        let data = try await request("/api/topic/\(id)")
        guard let obj = data as? [String: Any] else { throw QHError.api("topic detail is not an object") }
        return Self.parseTopic(obj)
    }

    /// Nodes (categories) shown in the app's drawer.
    public func nodes() async throws -> [(id: Int, name: String, parent: Int)] {
        let data = try await request("/api/topic/nodes_by_ver/v2?ver=0")
        guard let dict = data as? [String: Any], let list = dict["list"] as? [[String: Any]] else {
            throw QHError.api("nodes payload missing list")
        }
        return list.compactMap { n in
            guard let id = n["nodeId"] as? Int, let name = n["name"] as? String else { return nil }
            return (id, name, n["parentId"] as? Int ?? 0)
        }
    }

    // MARK: internals

    private func getPage(_ path: String) async throws -> TopicPage {
        let data = try await request(path)
        guard let dict = data as? [String: Any] else { throw QHError.api("page is not an object") }
        let pageInfo = dict["page"] as? [String: Any] ?? [:]
        let rows = dict["results"] as? [[String: Any]] ?? []
        return TopicPage(
            page: pageInfo["page"] as? Int ?? 1,
            total: pageInfo["total"] as? Int ?? rows.count,
            topics: rows.map(Self.parseTopic)
        )
    }

    private func request(_ path: String) async throws -> Any {
        // Build manually: appendingPathComponent percent-escapes the query string.
        guard let url = URL(string: Self.host.absoluteString + path) else {
            throw QHError.decode("bad url \(path)")
        }
        // haijiao.com intermittently resets connections (NSURLError -1); retry briefly.
        var body: Data?
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                body = try await http.data(url).0
                lastError = nil
                break
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: UInt64(400_000_000 * (attempt + 1)))
            }
        }
        if let lastError { throw lastError }
        guard let body else { throw QHError.api("empty response for \(path)") }
        let root = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        if let success = root["success"] as? Bool, success == false {
            throw QHError.api(root["message"] as? String ?? "request failed")
        }
        guard let payload = root["data"] else { throw QHError.api("missing data") }
        if let text = payload as? String {
            return try Base64Peel.peelJSON(text)
        }
        return payload
    }

    static func parseTopic(_ obj: [String: Any]) -> Topic {
        let user = obj["user"] as? [String: Any] ?? [:]
        let rawAttachments = obj["attachments"] as? [[String: Any]] ?? []
        let attachments: [Attachment] = rawAttachments.compactMap { a in
            guard let id = a["id"] as? Int, let url = a["remoteUrl"] as? String else { return nil }
            return Attachment(
                id: id,
                url: url,
                category: a["category"] as? String ?? "",
                cover: (a["coverUrl"] as? String).map(Self.cleanImageURL),
                durationSec: a["video_time_length"] as? Int
            )
        }
        let imageURL = attachments.first(where: { $0.category == "images" }).map { Self.cleanImageURL($0.url) }
        return Topic(
            id: obj["topicId"] as? Int ?? 0,
            title: obj["title"] as? String ?? "",
            author: user["nickname"] as? String ?? "",
            views: obj["viewCount"] as? Int ?? 0,
            created: obj["createTime"] as? String ?? "",
            cover: imageURL,
            attachments: attachments,
            moneyType: obj["money_type"] as? Int ?? 0
        )
    }

    /// Haijiao serves stills as `.jpg.txt`; the app rejects `.txt` paths for display.
    static func cleanImageURL(_ raw: String) -> String {
        raw.hasSuffix(".txt") ? String(raw.dropLast(4)) : raw
    }
}
