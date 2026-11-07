import Foundation
import CAS189Core

// 极简 CLI：在没有 iOS 设备的情况下验证 189 接口
//   swift run cas189 fingerprint --file ~/a.mp4
//   swift run cas189 login --cookie "COOKIE_LOGIN_USER=...; ..."
//   swift run cas189 ls [--folder -11]
//   swift run cas189 rapid --file ~/a.mp4 [--folder -11] [--overwrite]

let storePath = ("~/.cas189/session.json" as NSString).expandingTildeInPath

func loadSession() -> Session? {
    guard let data = FileManager.default.contents(atPath: storePath) else { return nil }
    return try? JSONDecoder().decode(Session.self, from: data)
}

func saveSession(_ session: Session) throws {
    let dir = (storePath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(session)
    try data.write(to: URL(fileURLWithPath: storePath))
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storePath)
}

func arg(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func flag(_ name: String) -> Bool { CommandLine.arguments.contains(name) }

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("✗ " + message + "\n").utf8))
    exit(1)
}

func human(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

let command = CommandLine.arguments.dropFirst().first ?? "help"

switch command {
case "fingerprint":
    guard let path = arg("--file") else { die("用法: cas189 fingerprint --file <路径>") }
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let started = Date()
    do {
        let fp = try CryptoTool.fingerprintFile(url, progress: { done, total in
            FileHandle.standardError.write(Data("\r  分片 \(done)/\(total)".utf8))
            return true
        })
        FileHandle.standardError.write(Data("\r".utf8))
        print("文件: \(url.lastPathComponent)")
        print("大小: \(human(fp.size)) (\(fp.size) 字节)")
        print("fileMd5:  \(fp.fileMd5)")
        print("sliceMd5: \(fp.sliceMd5)")
        print("分片数:  \(fp.parts.count)  片大小: \(fp.sliceSize)")
        print(String(format: "耗时: %.2fs", Date().timeIntervalSince(started)))
    } catch {
        die(error.localizedDescription)
    }

case "login":
    guard let cookie = arg("--cookie") else {
        die("用法: cas189 login --cookie \"COOKIE_LOGIN_USER=...; ...\"\n提示: 浏览器登录 cloud.189.cn 后从任意请求复制整段 Cookie")
    }
    let client = Cloud189Client()
    await client.setDebugLog { msg in FileHandle.standardError.write(Data(("  · " + msg + "\n").utf8)) }
    do {
        let session = try await client.loginWithCookies(cookie)
        let saved = await client.snapshot()
        try saveSession(saved)
        print("✓ 登录成功: \(session.loginName)  sessionKey=\(session.sessionKey.prefix(8))…")
        print("  会话已保存到 \(storePath)")
    } catch {
        die(error.localizedDescription)
    }

case "ls":
    guard let saved = loadSession() else { die("未登录，先执行 cas189 login --cookie ...") }
    let client = Cloud189Client()
    await client.restore(session: saved)
    let folder = arg("--folder") ?? "-11"
    do {
        let entries = try await client.listEntries(folderId: folder)
        print("目录 \(folder) 共 \(entries.count) 项：")
        for e in entries.prefix(100) {
            let kind = e.isFolder ? "📁" : "📄"
            print("  \(kind) \(e.name)  [\(human(e.size))]  id=\(e.id)")
        }
    } catch {
        die(error.localizedDescription)
    }

case "upload":
    guard let path = arg("--file") else { die("用法: cas189 upload --file <路径> [--folder -11] [--overwrite]") }
    guard let saved = loadSession() else { die("未登录，先执行 cas189 login") }
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let folder = arg("--folder") ?? "-11"
    let client = Cloud189Client()
    await client.restore(session: saved)
    await client.setDebugLog { msg in FileHandle.standardError.write(Data(("  · " + msg + "\n").utf8)) }
    do {
        print("上传 \(url.lastPathComponent) → 目录 \(folder)")
        let result = try await client.uploadFile(at: url, parentFolderId: folder,
                                                 overwrite: flag("--overwrite")) { done, total in
            let pct = total > 0 ? Double(done) / Double(total) * 100 : 0
            FileHandle.standardError.write(Data(String(format: "\r  分片 %d/%d (%.0f%%)", done, total, pct).utf8))
            if done == total { FileHandle.standardError.write(Data("\n".utf8)) }
        }
        print(result.ok ? "✓ \(result.message)" : "✗ \(result.message)")
    } catch {
        die(error.localizedDescription)
    }

case "raw":
    // 调试用：直接打一个签名接口，把原始 JSON 打出来
    guard let uri = arg("--uri") else { die("用法: cas189 raw --uri /person/xxx [--params a=1&b=2]") }
    guard let saved = loadSession() else { die("未登录") }
    let client = Cloud189Client()
    await client.restore(session: saved)
    await client.setDebugLog { msg in FileHandle.standardError.write(Data(("  · " + msg + "\n").utf8)) }
    var params: [(String, String)] = []
    if let p = arg("--params"), !p.isEmpty {
        for pair in p.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { params.append((String(kv[0]), String(kv[1]))) }
        }
    }
    do {
        let json = try await client.signedRequest(uri: uri, params: params)
        let out = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        print(String(data: out, encoding: .utf8) ?? "")
    } catch {
        die(error.localizedDescription)
    }

case "rapid":
    guard let path = arg("--file") else { die("用法: cas189 rapid --file <路径> [--folder -11] [--overwrite]") }
    guard let saved = loadSession() else { die("未登录，先执行 cas189 login --cookie ...") }
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let folder = arg("--folder") ?? "-11"
    let client = Cloud189Client()
    await client.restore(session: saved)
    await client.setDebugLog { msg in FileHandle.standardError.write(Data(("  · " + msg + "\n").utf8)) }
    do {
        print("计算指纹…")
        let fp = try CryptoTool.fingerprintFile(url)
        print("  md5=\(fp.fileMd5)  slice=\(fp.sliceMd5)  分片=\(fp.parts.count)")
        let item = CasItem(name: url.lastPathComponent, size: fp.size,
                           fileMd5: fp.fileMd5, sliceMd5: fp.sliceMd5,
                           sliceSize: fp.sliceSize, parts: fp.parts)
        let result = try await client.rapidUpload(item, parentFolderId: folder, overwrite: flag("--overwrite"))
        print(result.ok ? "✓ 秒传成功: \(result.message)" : "✗ 未命中: \(result.message)")
    } catch {
        die(error.localizedDescription)
    }

default:
    print("""
    cas189 — 天翼云盘秒传 CLI

      swift run cas189 fingerprint --file <路径>            只算指纹（离线，不需要账号）
      swift run cas189 login --cookie "COOKIE_LOGIN_USER=…" 用浏览器 Cookie 登录并保存会话
      swift run cas189 ls [--folder -11]                    列目录
      swift run cas189 rapid --file <路径> [--folder -11]   秒传本地文件
      swift run cas189 upload --file <路径> [--folder -11]  真实分片上传（秒传未命中时的兜底）
      swift run cas189 raw --uri /person/xxx [--params a=1&b=2]  调试：直接打签名接口
    """)
}
