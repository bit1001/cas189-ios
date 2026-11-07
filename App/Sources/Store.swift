import Foundation
import SwiftUI
import CAS189Core

@MainActor
final class Store: ObservableObject {
    @Published var session: Session = Session()
    @Published var logs: [String] = []
    @Published var entries: [CloudEntry] = []
    @Published var folderId: String = "-11"
    @Published var busy = false
    @Published var errorText: String?

    let client: Cloud189Client

    init(client: Cloud189Client = Cloud189Client()) {
        self.client = client
        Task {
            await client.setDebugLog { [weak self] message in
                Task { @MainActor in self?.append(message) }
            }
        }
        // 冷启动：从 Keychain 恢复会话，直接尝试拉目录
        if let saved = SessionStore.load() {
            session = saved
            append("已恢复上次会话：\(saved.loginName)")
            Task {
                await client.restore(session: saved)
                await load("-11")
            }
        }
    }

    func logout() {
        SessionStore.clear()
        session = Session()
        entries = []
        append("已退出登录")
    }

    func append(_ text: String) {
        logs.append("\(Self.time()) \(text)")
        if logs.count > 400 { logs.removeFirst(logs.count - 400) }
    }

    static func time() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    func login(cookie: String) async {
        busy = true; errorText = nil
        defer { busy = false }
        do {
            session = try await client.loginWithCookies(cookie)
            SessionStore.save(session)
            append("已登录：\(session.loginName)")
            await load(folderId)
        } catch {
            errorText = error.localizedDescription
            append("登录失败：\(error.localizedDescription)")
        }
    }

    func load(_ folder: String) async {
        busy = true; errorText = nil
        defer { busy = false }
        do {
            entries = try await client.listEntries(folderId: folder)
            folderId = folder
            append("列出 \(entries.count) 项")
        } catch {
            errorText = error.localizedDescription
            append("列目录失败：\(error.localizedDescription)")
        }
    }

    /// 对本地文件做指纹（10MB 切片）并秒传
    func rapidUpload(url: URL) async {
        busy = true; errorText = nil
        defer { busy = false }
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            append("计算指纹：\(url.lastPathComponent)")
            let fp = try await Task.detached(priority: .userInitiated) {
                try CryptoTool.fingerprintFile(url)
            }.value
            let item = CasItem(name: url.lastPathComponent,
                               size: fp.size,
                               fileMd5: fp.fileMd5,
                               sliceMd5: fp.sliceMd5,
                               sliceSize: fp.sliceSize,
                               parts: fp.parts)
            append("md5=\(fp.fileMd5.prefix(10))… slice=\(fp.sliceMd5.prefix(10))… 分片 \(fp.parts.count)")

            let result = try await client.rapidUpload(item, parentFolderId: folderId)
            append("秒传结果：\(result.ok ? "成功" : "未命中") — \(result.message)")
            if result.ok { await load(folderId) }
        } catch {
            errorText = error.localizedDescription
            append("秒传失败：\(error.localizedDescription)")
        }
    }
}
