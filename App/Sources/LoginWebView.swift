import SwiftUI
import WebKit
import CAS189Core

/// 内嵌官方登录页：用户扫码或输账号密码，成功后从 WKHTTPCookieStore 直接读会话 cookie。
/// 不需要抓包、不需要装证书、不需要代理。
struct LoginWebView: UIViewRepresentable {
    var onLogin: (String) -> Void
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.customUserAgent = Self.desktopUA   // 用 PC 版页面，避免被引导到 h5
        var request = URLRequest(url: URL(string: C.loginEntryURL)!)
        request.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        web.load(request)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: LoginWebView
        private var finished = false

        init(_ parent: LoginWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            harvest(from: webView)
        }

        private func harvest(from webView: WKWebView) {
            guard !finished else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.finished else { return }
                var dict: [String: String] = [:]
                for c in cookies where c.domain.hasSuffix("189.cn") {
                    if (dict[c.name]?.count ?? 0) < c.value.count { dict[c.name] = c.value }
                }
                guard dict["COOKIE_LOGIN_USER"] != nil else { return }
                self.finished = true
                let cookieHeader = dict
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "; ")
                DispatchQueue.main.async { self.parent.onLogin(cookieHeader) }
            }
        }
    }
}

struct LoginSheet: View {
    var onLogin: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoginWebView(
                onLogin: { cookie in
                    onLogin(cookie)
                    dismiss()
                },
                onClose: { dismiss() }
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("登录天翼云盘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
