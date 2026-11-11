import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 极简 HTTP 传输层：自管 Cookie、可拦截 302（登录流程需要读 Location）
public final class Transport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    public private(set) var cookies: [String: String] = [:]
    public var userAgent: String = C.defaultUA
    /// 记录最近一次被拦截的跳转目标
    private var lastLocation: String?
    private let lock = NSLock()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    public override init() { super.init() }

    public func setCookies(_ raw: String) {
        lock.lock(); defer { lock.unlock() }
        for part in raw.split(separator: ";") {
            let item = part.trimmingCharacters(in: .whitespaces)
            guard let eq = item.firstIndex(of: "=") else { continue }
            let key = String(item[item.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(item[item.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            cookies[key] = value
        }
    }

    public var cookieHeader: String {
        lock.lock(); defer { lock.unlock() }
        return cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    public func cookie(named name: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return cookies[name]
    }

    public func removeCookie(named name: String) {
        lock.lock(); defer { lock.unlock() }
        cookies.removeValue(forKey: name)
    }

    public func clearSessionCookies() {
        lock.lock(); defer { lock.unlock() }
        cookies.removeValue(forKey: "JSESSIONID")
    }

    private func absorb(_ response: HTTPURLResponse) {
        let fields = response.allHeaderFields
        var headerMap: [String: String] = [:]
        for (k, v) in fields {
            headerMap[String(describing: k)] = String(describing: v)
        }
        let url = response.url ?? URL(string: "https://cloud.189.cn")!
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: headerMap, for: url)
        if !parsed.isEmpty {
            lock.lock(); defer { lock.unlock() }
            for c in parsed {
                cookies[c.name] = c.value
            }
            return
        }

        var raw: [String] = []
        for (k, v) in fields where String(describing: k).lowercased() == "set-cookie" {
            raw.append(String(describing: v))
        }
        guard !raw.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        for line in raw {
            // 只取 name=value 部分，忽略属性
            let head = line.split(separator: ";").first.map(String.init) ?? line
            guard let eq = head.firstIndex(of: "=") else { continue }
            let key = String(head[head.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(head[head.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { cookies[key] = value }
        }
    }

    public struct Response {
        public let status: Int
        public let headers: [String: String]
        public let body: Data
        public let location: String?
        public var text: String { String(data: body, encoding: .utf8) ?? "" }
        public func json() throws -> [String: Any] {
            guard !body.isEmpty else { return [:] }
            let obj = try JSONSerialization.jsonObject(with: body)
            return (obj as? [String: Any]) ?? [:]
        }
    }

    public func request(_ url: URL,
                        method: String = "GET",
                        headers: [String: String] = [:],
                        body: Data? = nil,
                        followRedirects: Bool = false) async throws -> Response {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let cookie = cookieHeader
        if !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if let body { req.httpBody = body }

        lock.withLock { lastLocation = nil }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CASError.http(-1, "非 HTTP 响应")
        }
        absorb(http)
        var headerMap: [String: String] = [:]
        for (k, v) in http.allHeaderFields { headerMap[String(describing: k)] = String(describing: v) }
        let location = http.value(forHTTPHeaderField: "Location") ?? lastLocation

        if (300...399).contains(http.statusCode), followRedirects, let location,
           let next = URL(string: location, relativeTo: url) {
            return try await request(next, method: "GET", headers: headers, body: nil, followRedirects: true)
        }
        return Response(status: http.statusCode, headers: headerMap, body: data, location: location)
    }

    // MARK: - URLSessionTaskDelegate

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        lock.withLock { lastLocation = request.url?.absoluteString }
        completionHandler(nil)   // 不自动跟随，交给调用方决定
    }
}
