import Foundation

public struct HLSPlaylist: Sendable {
    public let segments: [URL]
    public let keyURI: URL?
    public let iv: [UInt8]?
    public let totalDuration: Double

    public init(segments: [URL], keyURI: URL?, iv: [UInt8]?, totalDuration: Double) {
        self.segments = segments
        self.keyURI = keyURI
        self.iv = iv
        self.totalDuration = totalDuration
    }

    public static func parse(_ text: String, base: URL) throws -> HLSPlaylist {
        var segments: [URL] = []
        var keyURI: URL?
        var iv: [UInt8]?
        var duration: Double = 0

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#EXT-X-KEY") {
                if let range = line.range(of: "URI=\"") {
                    let rest = line[range.upperBound...]
                    if let end = rest.firstIndex(of: "\"") {
                        keyURI = URL(string: String(rest[..<end]), relativeTo: base)?.absoluteURL
                    }
                }
                if let range = line.range(of: "IV=0x") {
                    let hex = line[range.upperBound...].prefix { $0.isHexDigit }
                    iv = Data(hexString: String(hex)).map { Array($0) }
                }
            } else if line.hasPrefix("#EXTINF:") {
                let value = line.dropFirst("#EXTINF:".count).split(separator: ",").first ?? ""
                duration += Double(value) ?? 0
            } else if !line.hasPrefix("#") {
                if let url = URL(string: line, relativeTo: base)?.absoluteURL {
                    segments.append(url)
                }
            }
        }
        guard !segments.isEmpty else { throw QHError.decode("playlist has no segments") }
        return HLSPlaylist(segments: segments, keyURI: keyURI, iv: iv, totalDuration: duration)
    }
}

public extension Data {
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let b = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(b)
            index = next
        }
        self = Data(bytes)
    }
}

/// Downloads an AES-128 HLS stream and returns the decrypted MPEG-TS payload.
///
/// Haijiao quirk (verified live): the AES key is not used raw. It is XORed with a
/// per-video "material" blob that is served as Base64 text at the playlist URL with
/// `.m3u8` replaced by `.jpg`. Without that step the first TS byte is never 0x47.
public struct HLSDownloader {
    public struct Progress: Sendable {
        public let completed: Int
        public let total: Int
    }

    private let http: HTTPClient
    private let concurrency: Int

    public init(http: HTTPClient = HTTPClient(), concurrency: Int = 6) {
        self.http = http
        self.concurrency = max(1, concurrency)
    }

    public func resolveKey(playlistURL: URL, keyURL: URL) async throws -> [UInt8] {
        let (keyData, _) = try await http.data(keyURL)
        guard keyData.count == 16 else { throw QHError.crypto("key is \(keyData.count) bytes") }

        // material: same path, .m3u8 -> .jpg, body is Base64 text
        let jpgURL = playlistURL.deletingPathExtension().appendingPathExtension("jpg")
        let materialText: String
        do {
            materialText = try await http.text(jpgURL)
        } catch {
            return Array(keyData) // some videos serve a plain key
        }
        let compact = materialText.filter { !$0.isWhitespace }
        guard let material = Data(base64Encoded: compact), !material.isEmpty else {
            return Array(keyData)
        }
        var key = Array(keyData)
        let m = Array(material)
        for i in key.indices { key[i] ^= m[i % m.count] }
        return key
    }

    public func download(
        playlist: HLSPlaylist,
        playlistURL: URL,
        progress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Data {
        // Keyless playlists (PornShop family) are plain MPEG-TS: no decryption step.
        let cipher: AES? = try await {
            guard let keyURL = playlist.keyURI else { return nil }
            let key = try await resolveKey(playlistURL: playlistURL, keyURL: keyURL)
            return try AES(key: key)
        }()
        let iv = playlist.iv ?? [UInt8](repeating: 0, count: 16)

        var buffers = [Data?](repeating: nil, count: playlist.segments.count)
        var done = 0
        let total = playlist.segments.count

        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            var next = 0
            let initial = min(concurrency, total)
            while next < initial {
                let idx = next
                group.addTask { (idx, try await self.fetchSegment(playlist.segments[idx], cipher: cipher, iv: iv)) }
                next += 1
            }
            while let (idx, data) = try await group.next() {
                buffers[idx] = data
                done += 1
                progress?(Progress(completed: done, total: total))
                if next < total {
                    let idx = next
                    group.addTask { (idx, try await self.fetchSegment(playlist.segments[idx], cipher: cipher, iv: iv)) }
                    next += 1
                }
            }
        }

        var out = Data()
        out.reserveCapacity(buffers.reduce(0) { $0 + ($1?.count ?? 0) })
        for b in buffers { if let b { out.append(b) } }
        guard out.count > 376, out[0] == 0x47, out[188] == 0x47 else {
            throw QHError.crypto("decrypted stream is not MPEG-TS (bad key/iv)")
        }
        return out
    }

    private func fetchSegment(_ url: URL, cipher: AES?, iv: [UInt8]) async throws -> Data {
        let (enc, _) = try await http.data(url)
        guard let cipher else { return enc }
        let plain = try cipher.decryptCBC([UInt8](enc), iv: iv)
        return Data(plain)
    }
}
