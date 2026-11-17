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
            case "ps":
                try await psFeed(args)
            case "pssearch":
                try await psSearch(args)
            case "psplay":
                try await psPlay(args)
            case "psdl":
                try await psDownload(args)
            case "list":
                try await anyList(args)
            case "play":
                try await anyPlay(args)
            case "sites":
                for s in PornShopClient.sites {
                    print("\(s.id)\t\(s.label)\t\(s.origin)")
                }
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
    qh — 青禾学堂 core (Haijiao + PornShop 系)
      Haijiao:
        qh hot|news|original [page]
        qh detail <topicId>
        qh pull <topicId> [-o out.ts]
      PornShop 系 (pornshop / hstv / theporny / 51porn):
        qh sites                    列出可用站点
        qh ps <site> [page]         列表
        qh pssearch <site> <kw>     搜索
        qh psplay <site> <vId>      解析 m3u8
      qh selftest                   算法自检
    """

    // MARK: - Haijiao

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

    // MARK: - PornShop family

    static func psFeed(_ args: [String]) async throws {
        guard let site = args.first else { throw QHError.api("ps <site> [page]") }
        let page = args.count > 1 ? (Int(args[1]) ?? 1) : 1
        let client = try PornShopClient(siteID: site)
        let result = try await client.feed(page: page)
        print("[\(result.site)] page \(page)  items \(result.items.count)")
        for v in result.items.prefix(15) {
            print("  \(v.id)  \(v.title)  · \(v.author) · \(v.views)")
            if let p = v.playURL { print("      \(p)") }
        }
    }

    static func psSearch(_ args: [String]) async throws {
        guard args.count >= 2 else { throw QHError.api("pssearch <site> <keyword>") }
        let client = try PornShopClient(siteID: args[0])
        let result = try await client.search(args[1], page: 1)
        print("[\(result.site)] keyword=\(args[1])  items \(result.items.count)")
        for v in result.items.prefix(15) {
            print("  \(v.id)  \(v.title)")
        }
    }

    static func psPlay(_ args: [String]) async throws {
        guard args.count >= 2 else { throw QHError.api("psplay <site> <vId>") }
        let client = try PornShopClient(siteID: args[0])
        let url = try await client.playURL(videoID: args[1])
        print(url.absoluteString)
        let text = try await HTTPClient(insecureTLS: true).text(url, headers: [
            "Referer": "https://\(client.siteID == "pornshop" ? "pornshop.one" : client.siteID).com/",
        ])
        let head = text.split(separator: "\n").prefix(4).joined(separator: " | ")
        print("playlist:", head)
    }

    /// Verify the whole chain for PornShop-family sites: resolve → playlist → segments → TS.
    static func psDownload(_ args: [String]) async throws {
        guard args.count >= 2 else { throw QHError.api("psdl <site> <vId> [--segments N] [-o out.ts]") }
        let client = try PornShopClient(siteID: args[0])
        let url = try await client.playURL(videoID: args[1])
        var limit = Int.max
        var output = "ps-\(args[1]).ts"
        if let i = args.firstIndex(of: "--segments"), i + 1 < args.count { limit = Int(args[i + 1]) ?? limit }
        if let i = args.firstIndex(of: "-o"), i + 1 < args.count { output = args[i + 1] }

        let http = HTTPClient(insecureTLS: true)
        let text = try await http.text(url)
        var playlist = try HLSPlaylist.parse(text, base: url)
        if limit < playlist.segments.count {
            playlist = HLSPlaylist(segments: Array(playlist.segments.prefix(limit)),
                                   keyURI: playlist.keyURI, iv: playlist.iv,
                                   totalDuration: playlist.totalDuration)
        }
        print("playlist: \(url.absoluteString)")
        print("segments: \(playlist.segments.count)  encrypted: \(playlist.keyURI != nil)")
        let data = try await HLSDownloader(http: http).download(playlist: playlist, playlistURL: url)
        try data.write(to: URL(fileURLWithPath: output))
        print("written \(data.count) bytes -> \(output)")
    }

    /// Any site from the registry: qh list <site> [page]
    static func anyList(_ args: [String]) async throws {
        guard let site = args.first else { throw QHError.api("list <site> [page]") }
        let page = args.count > 1 ? (Int(args[1]) ?? 1) : 1
        let adapter = try SiteRegistry.adapter(for: site)
        let result = try await adapter.feed(page: page)
        print("[\(site)] page \(page)  items \(result.items.count)")
        for v in result.items.prefix(12) {
            print("  \(v.id)  \(v.title)")
            if let a = v.author.isEmpty ? nil : v.author { print("      · \(a)") }
            if let c = v.cover { print("      cover \(c)") }
        }
    }

    /// qh play <site> <videoId> — resolve and print the playable URL, then verify it.
    static func anyPlay(_ args: [String]) async throws {
        guard args.count >= 2 else { throw QHError.api("play <site> <id>") }
        let adapter = try SiteRegistry.adapter(for: args[0])
        let url = try await adapter.playURL(videoID: args[1])
        print("playable: \(url.absoluteString)")
        let http = HTTPClient(insecureTLS: true)
        // Range request: MP4 sources are large, never pull the whole file just to verify.
        let (data, resp) = try await http.data(url, headers: [
            "Referer": "https://\(args[0]).com/",
            "Range": "bytes=0-1023",
        ])
        let head = String(decoding: data.prefix(120), as: UTF8.self)
        print("http \(resp.statusCode)  bytes \(data.count)  head: \(head.replacingOccurrences(of: "\n", with: " | "))")
    }

    static func selftest() throws {
        // FIPS-197 AES-128 vector
        let key: [UInt8] = (0...15).map { UInt8($0) }
        let cipherBytes = Data(hexString: "69c4e0d86a7b0430d8cdb78070b4c55a")!
        let plain = try AES128(key: key).decryptBlock(Array(cipherBytes))
        let expected = Data(hexString: "00112233445566778899aabbccddeeff")!
        print("AES-128 block:", Array(plain) == Array(expected) ? "OK" : "FAIL")
        if Array(plain) != Array(expected) { exit(1) }

        // AES-256 vector (FIPS-197 appendix C.3)
        let k256 = Data(hexString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")!
        let c256 = Data(hexString: "8ea2b7ca516745bfeafc49904b496089")!
        let p256 = try AES(key: Array(k256)).decryptBlock(Array(c256))
        print("AES-256 block:", Array(p256) == Array(Data(hexString: "00112233445566778899aabbccddeeff")!) ? "OK" : "FAIL")

        let peel = Base64Peel.peel("V3hWbGMybElUMmx1YzNSbFpDQT0=")
        print("base64 peel:", peel)
    }
}
