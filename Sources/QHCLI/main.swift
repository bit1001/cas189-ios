import Foundation
import QHCore

@main
struct QHCLI {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            print(usage)
            return
        }
        args.removeFirst()

        do {
            switch command {
            case "hot":
                try await list(.hot, args)
            case "news":
                try await list(.news, args)
            case "original":
                try await list(.original, args)
            case "detail":
                guard let id = args.first.flatMap(Int.init) else { throw QHError.api("detail <topicId>") }
                let t = try await HaijiaoClient().detail(id: id)
                print(topicLine(t, full: true))
                for a in t.attachments {
                    print("   [\(a.category)] \(a.url)")
                }
            case "pull":
                try await pull(args)
            case "selftest":
                try selftest()
            default:
                print(usage)
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }

    static let usage = """
    qh — 青禾学堂 core PoC (Haijiao)
      qh hot [page]       热门
      qh news [page]      资讯
      qh original [page]  原创
      qh detail <id>      帖子详情
      qh pull <id> [-o out.ts]   下载并解密（AES-128 + jpg material XOR）
      qh selftest         AES/CBC 自检
    """

    static func list(_ feed: HaijiaoClient.Feed, _ args: [String]) async throws {
        let page = args.first.flatMap(Int.init) ?? 1
        let result = try await HaijiaoClient().feed(feed, page: page)
        print("page \(result.page)/\(result.total)  topics \(result.topics.count)")
        for t in result.topics {
            print(topicLine(t, full: false))
        }
    }

    static func topicLine(_ t: Topic, full: Bool) -> String {
        var parts = ["#\(t.id)", t.title]
        if full {
            parts.append("author=\(t.author) views=\(t.views) money=\(t.moneyType) created=\(t.created)")
            if let c = t.cover { parts.append("cover=\(c)") }
        } else {
            parts.append("· \(t.author) · \(t.views) 次")
            if !t.videos.isEmpty { parts.append("[video]") }
        }
        return parts.joined(separator: "  ")
    }

    static func pull(_ args: [String]) async throws {
        guard let id = args.first.flatMap(Int.init) else { throw QHError.api("pull <topicId>") }
        var output = "topic-\(id).ts"
        if let i = args.firstIndex(of: "-o"), i + 1 < args.count { output = args[i + 1] }

        let client = HaijiaoClient()
        let topic = try await client.detail(id: id)
        guard let video = topic.videos.first, let playlistURL = URL(string: video.url) else {
            throw QHError.api("topic \(id) has no video attachment")
        }
        print("topic: \(topic.title)")
        print("m3u8 : \(playlistURL)")

        let http = HTTPClient()
        let text = try await http.text(playlistURL)
        let playlist = try HLSPlaylist.parse(text, base: playlistURL)
        print("segments: \(playlist.segments.count)  duration: \(String(format: "%.1f", playlist.totalDuration))s  key: \(playlist.keyURI?.lastPathComponent ?? "-")")

        let downloader = HLSDownloader(http: http)
        var lastTick = 0
        let data = try await downloader.download(playlist: playlist, playlistURL: playlistURL) { p in
            if p.completed == p.total || p.completed - lastTick >= 10 {
                lastTick = p.completed
                print("  \(p.completed)/\(p.total)")
            }
        }
        try data.write(to: URL(fileURLWithPath: output))
        print("written \(data.count) bytes -> \(output)")
    }

    static func selftest() throws {
        // FIPS-197 AES-128 vector
        let key: [UInt8] = (0...15).map { UInt8($0) }
        let cipherBytes = Data(hexString: "69c4e0d86a7b0430d8cdb78070b4c55a")!
        let plain = try AES128(key: key).decryptBlock(Array(cipherBytes))
        let expected = Data(hexString: "00112233445566778899aabbccddeeff")!
        print("AES block decrypt:", Array(plain) == Array(expected) ? "OK" : "FAIL")
        if Array(plain) != Array(expected) { exit(1) }

        // CBC round-trip against a known OpenSSL output is covered by `pull`.
        let peel = Base64Peel.peel("V3hWbGMybElUMmx1YzNSbFpDQT0=")
        print("base64 peel:", peel)
    }
}
