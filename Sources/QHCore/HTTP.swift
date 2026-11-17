import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum QHError: Error, CustomStringConvertible {
    case http(Int, String)
    case decode(String)
    case crypto(String)
    case api(String)

    public var description: String {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .decode(let m): return "decode failed: \(m)"
        case .crypto(let m): return "crypto failed: \(m)"
        case .api(let m): return "api error: \(m)"
        }
    }
}

/// Minimal async HTTP client with per-site header injection.
public struct HTTPClient {
    public var userAgent: String
    public var defaultHeaders: [String: String]
    private let session: URLSession

    public init(userAgent: String = UA.androidChrome, defaultHeaders: [String: String] = [:]) {
        self.userAgent = userAgent
        self.defaultHeaders = defaultHeaders
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        cfg.httpMaximumConnectionsPerHost = 8
        self.session = URLSession(configuration: cfg)
    }

    public func data(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in defaultHeaders { req.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw QHError.decode("non-http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw QHError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        return (data, http)
    }

    public func text(_ url: URL, headers: [String: String] = [:]) async throws -> String {
        let (data, _) = try await data(url, headers: headers)
        return String(decoding: data, as: UTF8.self)
    }
}

public enum UA {
    public static let androidChrome =
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
}
