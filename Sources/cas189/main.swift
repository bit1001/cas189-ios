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

func authed() async throws -> Cloud189Client {
    guard let saved = loadSession() else { die("未登录，先执行 cas189 login") }
    let c = Cloud189Client()
    await c.restore(session: saved)
    return c
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

case "rm":
    guard let id = arg("--id") else { die("用法: cas189 rm --id <fileId>") }
    let client = try await authed()
    do { try await client.deleteFiles([id]); print("✓ 已删除 \(id)") }
    catch { die(error.localizedDescription) }

case "rename":
    guard let id = arg("--id"), let name = arg("--name") else { die("用法: cas189 rename --id <fileId> --name <新名字>") }
    let client = try await authed()
    do {
        let e = try await client.rename(fileId: id, to: name)
        print("✓ 已重命名为 \(e?.name ?? name)")
    } catch { die(error.localizedDescription) }

case "mkdir":
    guard let name = arg("--name") else { die("用法: cas189 mkdir --name <名字> [--folder -11]") }
    let client = try await authed()
    do { print("✓ 已创建，folderId=\(try await client.createFolder(name: name, parentId: arg("--folder") ?? "-11"))") }
    catch { die(error.localizedDescription) }

case "search":
    guard let kw = arg("--keyword") else { die("用法: cas189 search --keyword <关键词> [--folder -11]") }
    let client = try await authed()
    let hits = await client.search(kw, folderId: arg("--folder") ?? "-11")
    print("命中 \(hits.count) 项：")
    for e in hits.prefix(50) {
        print("  \(e.isFolder ? "📁" : "📄") \(e.name)  [\(human(e.size))]  id=\(e.id)")
    }

case "share":
    guard let id = arg("--id") else { die("用法: cas189 share --id <fileId> [--type 1] [--days 7]") }
    let client = try await authed()
    do {
        let link = try await client.createShare(
            fileId: id,
            shareType: arg("--type").flatMap(Int.init),
            expireDays: arg("--days").flatMap(Int.init)
        )
        print("✓ 分享已创建")
        print("  链接: \(link.url)")
        print("  提取码: \(link.accessCode.isEmpty ? "无（公开）" : link.accessCode)")
        print("  文案: \(link.shareText)")
    } catch { die(error.localizedDescription) }

case "parse-share":
    guard let text = arg("--text") else { die("用法: cas189 parse-share --text \"<含分享链接的文本>\"") }
    if let r = Cloud189Client.extractShareLink(from: text) {
        print("shareCode: \(r.code)")
        print("accessCode: \(r.accessCode ?? "未识别")")
    } else {
        print("未识别到 189 分享链接")
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
      swift run cas189 rm --id <fileId>                    删除
      swift run cas189 rename --id <id> --name <新名>       重命名
      swift run cas189 mkdir --name <名字> [--folder -11]   新建文件夹
      swift run cas189 search --keyword <关键词>            递归搜索
      swift run cas189 share --id <fileId> [--type 1] [--days 7]  创建分享链接
      swift run cas189 parse-share --text "<文本>"          从文本提取分享链接和提取码
    """)
}
