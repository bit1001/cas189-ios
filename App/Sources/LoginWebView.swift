import SwiftUI
import WebKit
import CAS189Core

/// 内嵌官方登录页：用户扫码或输账号密码，成功后从 WKHTTPCookieStore 直接读会话 cookie。
/// 不需要抓包、不需要装证书、不需要代理。
struct LoginWebView: UIViewRepresentable {
    var useDesktopUA: Bool
    var onLogin: (String) -> Void
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        // 拼图验证码是 PC 版组件，只监听 mousedown/mousemove/mouseup。
        // WKWebView 的触摸拖动不会合成这些事件，所以手指滑不动 —— 这里做事件桥。
        config.userContentController.addUserScript(
            WKUserScript(source: Self.touchToMouseBridge,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: false)
        )

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.customUserAgent = useDesktopUA ? Self.desktopUA : Self.mobileUA

        var request = URLRequest(url: URL(string: C.loginEntryURL)!)
        request.setValue(web.customUserAgent, forHTTPHeaderField: "User-Agent")
        web.load(request)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// 把触摸拖动翻译成鼠标拖动。只在「滑块/验证码/canvas」区域生效，
    /// 其余区域保持原生滚动，不影响页面其他交互。
    static let touchToMouseBridge = """
    (function () {
      if (window.__casTouchMouseBridge) { return; }
      window.__casTouchMouseBridge = true;
      var active = false, lastX = 0, lastY = 0;

      function isSliderArea(t) {
        if (!t || t.nodeType !== 1) { return false; }
        var sel = '[class*="slider"],[class*="Slider"],[class*="captcha"],[class*="Captcha"],'
                + '[class*="verify"],[class*="Verify"],[class*="drag"],[class*="Drag"],'
                + '[class*="yidun"],[class*="geetest"],[class*="nc_"],'
                + '[id*="slider"],[id*="captcha"],[id*="verify"]';
        try { if (t.closest && t.closest(sel)) { return true; } } catch (e) {}
        if (t.tagName === 'CANVAS') { return true; }
        var p = t.parentElement;
        for (var i = 0; i < 4 && p; i++, p = p.parentElement) {
          if (p.tagName === 'CANVAS') { return true; }
        }
        return false;
      }

      function fire(type, t, target) {
        var opts = {
          bubbles: true, cancelable: true, view: window,
          clientX: t.clientX, clientY: t.clientY,
          screenX: t.screenX || t.clientX, screenY: t.screenY || t.clientY,
          button: 0, buttons: (type === 'mouseup' ? 0 : 1)
        };
        (target || document).dispatchEvent(new MouseEvent(type, opts));
      }

      document.addEventListener('touchstart', function (ev) {
        if (!isSliderArea(ev.target)) { return; }
        active = true;
        var t = ev.touches[0];
        lastX = t.clientX; lastY = t.clientY;
        fire('mousedown', t, ev.target);
      }, { capture: true, passive: true });

      document.addEventListener('touchmove', function (ev) {
        if (!active) { return; }
        ev.preventDefault();
        var t = ev.touches[0];
        lastX = t.clientX; lastY = t.clientY;
        fire('mousemove', t, document);
        fire('mousemove', t, window);
      }, { capture: true, passive: false });

      function finish(ev) {
        if (!active) { return; }
        active = false;
        var t = (ev.changedTouches && ev.changedTouches[0]) || { clientX: lastX, clientY: lastY };
        fire('mouseup', t, document);
      }
      document.addEventListener('touchend', finish, { capture: true, passive: true });
      document.addEventListener('touchcancel', finish, { capture: true, passive: true });
    })();
    """

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
    @State private var useDesktopUA = true

    var body: some View {
        NavigationStack {
            LoginWebView(
                useDesktopUA: useDesktopUA,
                onLogin: { cookie in
                    onLogin(cookie)
                    dismiss()
                },
                onClose: { dismiss() }
            )
            .id(useDesktopUA)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("登录天翼云盘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            useDesktopUA = true
                        } label: {
                            Label("桌面版页面", systemImage: useDesktopUA ? "checkmark" : "desktopcomputer")
                        }
                        Button {
                            useDesktopUA = false
                        } label: {
                            Label("手机版页面", systemImage: useDesktopUA ? "iphone" : "checkmark")
                        }
                    } label: {
                        Image(systemName: "globe")
                    }
                }
            }
        }
    }
}
