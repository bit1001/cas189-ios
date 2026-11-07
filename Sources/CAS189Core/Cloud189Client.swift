import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 天翼云盘客户端。对齐 APK `com.ty189.cas.Cloud189Client` 的关键路径：
/// - Cookie 登录 → getUserBriefInfo 换 sessionKey
/// - 账号密码登录（RSA）→ getSessionForPC 换 sessionKey
/// - 目录 / 列表 / 建目录（走 web 通道，仅需 Cookie）
/// - 秒传（走 upload 通道，需要 SessionKey + 签名）
public actor Cloud189Client {

    public let transport: Transport
    public private(set) var session = Session()
    public var debugLog: (@Sendable (String) -> Void)?

    public init(transport: Transport = Transport()) {
        self.transport = transport
    }

    public func setDebugLog(_ handler: (@Sendable (String) -> Void)?) {
        debugLog = handler
    }

    /// 从已保存的状态恢复（CLI / App 冷启动用）
    public func restore(session saved: Session) {
        transport.setCookies(saved.cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "))
        session = saved
    }

    /// 导出当前状态（含 Cookie，调用方负责安全存储）
    public func snapshot() -> Session {
        var copy = session
        copy.cookies = transport.cookies
        return copy
    }

    private func log(_ message: String) { debugLog?(message) }

    // MARK: - 登录：Cookie

    /// 直接用浏览器 Cookie 登录。必须包含 COOKIE_LOGIN_USER。
    public func loginWithCookies(_ rawCookie: String) async throws -> Session {
        transport.setCookies(rawCookie)
        guard transport.cookie(named: "COOKIE_LOGIN_USER")?.isEmpty == false else {
            throw CASError.missing("Cookie 中缺少 COOKIE_LOGIN_USER（仅 apm_* 等统计 Cookie 无法登录）")
        }
        try await fetchSessionKey()
        return session
    }

    /// getUserBriefInfo：拿 sessionKey / 昵称
    private func fetchSessionKey() async throws {
        var comps = URLComponents(string: C.webURL + "/v2/getUserBriefInfo.action")!
        comps.queryItems = [URLQueryItem(name: "noCache", value: "0." + String(Int64.random(in: 0...99_999_999_999_999_999)))]
        let res = try await transport.request(comps.url!, headers: [
            "Accept": "application/json;charset=UTF-8",
            "Referer": C.referer
        ])
        let json = try res.json()
        let key = (json["sessionKey"] as? String) ?? ""
        guard !key.isEmpty else {
            throw CASError.missing("getUserBriefInfo 未返回 sessionKey（Cookie 可能已失效）")
        }
        let name = (json["userAccount"] as? String) ?? (json["nickname"] as? String) ?? ""
        let deviceId = (json["deviceId"] as? String) ?? ""
        session = Session(sessionKey: key, loginName: name, deviceId: deviceId, cookies: transport.cookies)
        log("登录成功(Web) name=\(name)")
    }

    // MARK: - 登录：账号密码（RSA）

    /// 密码登录：prepareLogin → 验证码 → submitLogin → getSessionForPC。
    /// 注意：RSA 加密依赖 Security.framework，Linux 上会抛 unsupported。
    public func loginWithPassword(username: String, password: String,
                                  captcha: String?, onCaptcha: ((Data) async -> String?)? = nil) async throws -> Session {
        // 1) unifyLoginForPC 拿 lt
        var comps = URLComponents(string: C.webURL + "/api/portal/unifyLoginForPC.action")!
        comps.queryItems = [
            .init(name: "appId", value: C.appId),
            .init(name: "clientType", value: C.clientType),
            .init(name: "returnURL", value: C.returnURL),
            .init(name: "timeStamp", value: String(Int(Date().timeIntervalSince1970 * 1000)))
        ]
        let first = try await transport.request(comps.url!, headers: ["Referer": C.referer])
        guard let redirect = first.location, let lt = URLComponents(string: redirect)?
            .queryItems?.first(where: { $0.name == "lt" })?.value, !lt.isEmpty else {
            throw CASError.missing("未取得 lt（unifyLoginForPC 未跳转）")
        }

        // 2) encryptConf 拿登录用 RSA 公钥
        let confBody = "appId=\(C.appId)".data(using: .utf8)!
        let conf = try await transport.request(URL(string: C.authURL + "/api/logbox/config/encryptConf.do")!,
                                               method: "POST",
                                               headers: ["Content-Type": "application/x-www-form-urlencoded"],
                                               body: confBody).json()
        guard let pubKey = conf["pubKey"] as? String else {
            throw CASError.missing("登录公钥")
        }
        let rsaUser = try CryptoTool.rsaEncryptBase64(x509PubKeyB64: pubKey, plaintext: username)
        let rsaPass = try CryptoTool.rsaEncryptBase64(x509PubKeyB64: pubKey, plaintext: password)

        // 3) 验证码
        var code = captcha
        if code == nil {
            var needComps = URLComponents(string: C.authURL + "/api/logbox/oauth2/needcaptcha.do")!
            needComps.queryItems = nil
            let needBody = "appKey=\(C.appId)&accountType=\(C.accountType)&userName=\(rsaUser)".data(using: .utf8)!
            let need = try await transport.request(needComps.url!, method: "POST",
                                                   headers: ["Content-Type": "application/x-www-form-urlencoded"],
                                                   body: needBody)
            let needText = need.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if needText == "1" || needText.contains("true") {
                var capComps = URLComponents(string: C.authURL + "/api/logbox/oauth2/picCaptcha.do")!
                capComps.queryItems = [
                    .init(name: "token", value: ""),
                    .init(name: "REQID", value: UUID().uuidString),
                    .init(name: "rnd", value: String(Int(Date().timeIntervalSince1970 * 1000)))
                ]
                let cap = try await transport.request(capComps.url!)
                guard let onCaptcha, let input = await onCaptcha(cap.body), !input.isEmpty else {
                    throw CASError.missing("需要图形验证码，但未提供输入")
                }
                code = input
            }
        }

        // 4) 登录提交
        var fields: [(String, String)] = [
            ("version", "v2.0"), ("apToken", ""), ("appKey", C.appId), ("pageKey", "normal"),
            ("accountType", C.accountType), ("userName", rsaUser), ("password", rsaPass),
            ("epd", rsaPass), ("validateCode", code ?? ""), ("captchaToken", ""),
            ("returnUrl", C.returnURL), ("dynamicCheck", "FALSE"), ("clientType", C.clientType),
            ("cb_SaveName", "1"), ("isOauth2", "false"), ("state", ""), ("paramId", lt)
        ]
        fields = fields.filter { !$0.1.isEmpty }
        let body = Signer.paramsString(fields).data(using: .utf8)!
        let submit = try await transport.request(URL(string: C.authURL + "/api/logbox/oauth2/loginSubmit.do")!,
                                                 method: "POST",
                                                 headers: [
                                                    "Content-Type": "application/x-www-form-urlencoded",
                                                    "Referer": C.authURL + "/api/logbox/separate/web/index.html?appId=\(C.appId)&lt=\(lt)"
                                                 ],
                                                 body: body)
        let submitJSON = try submit.json()
        if let msg = submitJSON["msg"] as? String, let result = submitJSON["result"] as? Int, result != 0 {
            throw CASError.api(code: String(result), message: msg)
        }
        guard let toUrl = (submitJSON["toUrl"] as? String) ?? submit.location else {
            throw CASError.missing("登录成功但未返回跳转地址")
        }

        // 5) 用跳转地址换会话
        try await sessionFromRedirect(toUrl)
        return session
    }

    /// getSessionForPC：redirectURL → sessionKey/sessionSecret/accessToken
    private func sessionFromRedirect(_ redirect: String) async throws {
        var comps = URLComponents(string: C.apiURL + "/getSessionForPC.action")!
        comps.queryItems = [
            .init(name: "clientType", value: C.pc),
            .init(name: "version", value: C.version),
            .init(name: "channelId", value: C.channelId),
            .init(name: "rand", value: String(Int.random(in: 100000...999999))),
            .init(name: "redirectURL", value: redirect),
            .init(name: "returnType", value: "JSON")
        ]
        let res = try await transport.request(comps.url!, method: "POST",
                                              headers: ["X-Request-ID": UUID().uuidString,
                                                        "Content-Type": "application/x-www-form-urlencoded"],
                                              body: Data())
        let json = try res.json()
        let key = (json["sessionKey"] as? String) ?? ""
        guard !key.isEmpty else { throw CASError.missing("getSessionForPC 未返回 sessionKey") }
        session = Session(
            sessionKey: key,
            sessionSecret: (json["sessionSecret"] as? String) ?? "",
            loginName: (json["loginName"] as? String) ?? "",
            deviceId: session.deviceId,
            cookies: transport.cookies
        )
        log("登录成功(PC) name=\(session.loginName)")
    }

    // MARK: - 业务请求：web（Cookie）

    public func webGet(_ path: String, _ query: [(String, String)]) async throws -> [String: Any] {
        var comps = URLComponents(string: C.webURL + path)!
        comps.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        let res = try await transport.request(comps.url!, headers: [
            "Accept": "application/json;charset=UTF-8",
            "Referer": C.referer
        ])
        let json = try res.json()
        if let code = json["res_code"] as? Int, code != 0 {
            throw CASError.api(code: String(code), message: (json["res_message"] as? String) ?? "")
        }
        return json
    }

    // MARK: - 目录 / 列表

    public func rootFolderId(isFamily: Bool = false) -> String { isFamily ? "-11" : "-11" }

    public func listEntries(folderId: String = "-11", pageSize: Int = 200) async throws -> [CloudEntry] {
        let path = "/api/open/file/listFiles.action"
        let json = try await webGet(path, [
            ("pageSize", String(pageSize)),
            ("pageNum", "1"),
            ("folderId", folderId),
            ("mediaType", "0")
        ])
        let arr = (json["fileListAO"] as? [String: Any])?["fileList"] as? [[String: Any]] ?? []
        return arr.compactMap { item in
            guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
            let size = (item["size"] as? NSNumber)?.int64Value ?? 0
            let isFolder = (item["isFolder"] as? Bool) ?? ((item["fileType"] as? Int) == 1)
            return CloudEntry(id: id, name: name, size: size, isFolder: isFolder,
                              md5: item["md5"] as? String, parentId: folderId)
        }
    }

    public func createFolder(name: String, parentId: String = "-11") async throws -> String {
        var comps = URLComponents(string: C.webURL + "/api/open/file/createFolder.action")!
        comps.queryItems = [
            .init(name: "folderName", value: name),
            .init(name: "parentFolderId", value: parentId)
        ]
        let res = try await transport.request(comps.url!, method: "POST",
                                              headers: ["Referer": C.referer],
                                              body: Data())
        let json = try res.json()
        if let code = json["res_code"] as? Int, code != 0 {
            throw CASError.api(code: String(code), message: (json["res_message"] as? String) ?? "")
        }
        return (json["id"] as? String) ?? ""
    }

    // MARK: - 秒传（签名通道）

    /// 确保拿到签名用的 RSA 公钥（有效期由服务端给）
    public func ensureSigningKey(force: Bool = false) async throws {
        if !force, !session.rsaPubKey.isEmpty { return }
        for url in [C.apiURL + "/security/generateRsaKey.action",
                    C.webURL + "/api/security/generateRsaKey.action"] {
            let res = try? await transport.request(URL(string: url)!, headers: [
                "Referer": C.referer,
                "X-Request-ID": UUID().uuidString
            ])
            guard let res, let json = try? res.json() else { continue }
            if let pub = json["pubKey"] as? String, let pk = json["pkId"] as? String,
               CryptoTool.isUsableRSAPubKey(pub) {
                session.rsaPubKey = pub
                session.rsaPkId = pk
                log("取得签名公钥 pkId=\(pk)")
                return
            }
        }
        throw CASError.missing("签名公钥（generateRsaKey 两次都失败）")
    }

    /// 调用 upload 通道的签名接口，返回解析后的 JSON
    public func signedRequest(uri: String, params: [(String, String)],
                              method: String = "POST") async throws -> [String: Any] {
        try await ensureSigningKey()
        let signed = try Signer.build(.init(uri: uri, params: params,
                                            sessionKey: session.sessionKey,
                                            method: method,
                                            baseURL: C.uploadURL,
                                            rsaPubKeyB64: session.rsaPubKey,
                                            rsaPkId: session.rsaPkId))
        let res: Transport.Response
        if method == "POST" {
            res = try await transport.request(signed.url, method: "POST",
                                              headers: signed.headers.merging(
                                                ["Content-Type": "application/x-www-form-urlencoded"]) { $1 },
                                              body: "params=\(signed.paramsHex)".data(using: .utf8))
        } else {
            var comps = URLComponents(url: signed.url, resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "params", value: signed.paramsHex)]
            res = try await transport.request(comps.url!, method: "GET", headers: signed.headers)
        }
        let json = try res.json()
        let code = (json["code"] as? String) ?? ""
        if code == "SUCCESS" || code == "0" { return json }
        let message = (json["message"] as? String) ?? ""
        if Self.isSessionError(code: code, message: message) {
            throw CASError.sessionExpired(message)
        }
        if Self.isSecurityReject(code: code, message: message) {
            throw CASError.securityRejected(message)
        }
        throw CASError.api(code: code, message: message)
    }

    static func isSessionError(code: String, message: String) -> Bool {
        let text = code + message
        return text.contains("SessionKey") || text.contains("session")
            || text.contains("登录") || code == "-1"
    }

    static func isSecurityReject(code: String, message: String) -> Bool {
        let text = code + message
        return text.contains("安全") || text.contains("违规") || text.contains("审查")
    }
}
