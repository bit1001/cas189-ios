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

/// Several target sites serve broken certificate chains; the Android app disables
/// verification outright (its OkHttp builders install a trust-all manager).
final class InsecureTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        #if canImport(Security)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        #endif
        completionHandler(.performDefaultHandling, nil)
    }
}

/// Minimal async HTTP client with per-site header injection.
public struct HTTPClient {
    public var userAgent: String
    public var defaultHeaders: [String: String]
    private let session: URLSession
    private let trustDelegate: InsecureTrustDelegate?
    private let insecureTLS: Bool

    /// Foundation on Linux cannot accept untrusted server certificates at all, so the
    /// CLI (test harness) falls back to `curl -k` there. iOS/macOS use URLSession.
    static var hasSecureTransport: Bool {
        #if canImport(Security)
        return true
        #else
        return false
        #endif
    }

    public init(userAgent: String = UA.androidChrome,
                defaultHeaders: [String: String] = [:],
                insecureTLS: Bool = false) {
        self.userAgent = userAgent
        self.defaultHeaders = defaultHeaders
        self.insecureTLS = insecureTLS
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        cfg.httpMaximumConnectionsPerHost = 8
        if insecureTLS {
            let delegate = InsecureTrustDelegate()
            self.trustDelegate = delegate
            self.session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        } else {
            self.trustDelegate = nil
            self.session = URLSession(configuration: cfg)
        }
    }

    public func data(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        if insecureTLS && !Self.hasSecureTransport {
            return try curlData(url, method: method, headers: headers, body: body)
        }
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

    /// Linux-only test path: shell out to curl so self-signed sites can be exercised.
    private func curlData(_ url: URL, method: String, headers: [String: String], body: Data?) throws -> (Data, HTTPURLResponse) {
        let jar = NSTemporaryDirectory() + "qh-curl-cookies-\(getpid()).txt"
        var args = ["-skL", "-m", "60", "-c", jar, "-b", jar, "-X", method, "-w", "\n%{http_code}"]
        for (k, v) in defaultHeaders { args += ["-H", "\(k): \(v)"] }
        for (k, v) in headers { args += ["-H", "\(k): \(v)"] }
        args += ["-H", "User-Agent: \(userAgent)"]
        if body != nil { args += ["--data-binary", "@-"] }
        args.append(url.absoluteString)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = args
        let out = Pipe(), err = Pipe(), stdin = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = stdin
        try proc.run()
        if let body { stdin.fileHandleForWriting.write(body) }
        try? stdin.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw QHError.http(-1, String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        // strip trailing "\n<code>"
        guard let nl = data.lastIndex(of: 0x0A),
              let code = Int(String(decoding: data[(nl + 1)...], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw QHError.decode("curl output without status")
        }
        let payload = data[..<nl]
        guard (200..<300).contains(code) else {
            throw QHError.http(code, String(decoding: payload, as: UTF8.self))
        }
        let resp = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
        return (Data(payload), resp)
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
