import Foundation
import SwiftUI
import CAS189Core

enum CloudSpace: String, CaseIterable, Identifiable {
    case personal = "个人云"
    case family = "家庭云"
    var id: String { rawValue }
    var key: String { self == .personal ? "personal" : "family" }
}

struct FolderCrumb: Hashable {
    let id: String
    let name: String
}

@MainActor
final class Store: ObservableObject {
    @Published var session: Session = Session()
    @Published var logs: [String] = []
    @Published var entries: [CloudEntry] = []
    @Published var folderId: String = "-11"
    @Published var busy = false
    @Published var uploadProgress: Double = 0
    @Published var uploadLabel: String = ""
    @Published var searchText: String = ""
    @Published var searchResults: [CloudEntry] = []
    @Published var isSearching = false
    @Published var errorText: String?
    @Published var lastShareText: String?
    @Published var downloadLabel = ""
    @Published var downloadedFile: URL?
    @Published var needsRelogin = false
    // 家庭云
    @Published var familyId = ""
    @Published var familyEntries: [CloudEntry] = []
    @Published var familyFolderId = "-11"
    @Published var familyBusy = false
    // 目录导航历史（用于返回上一级）
    @Published var crumbs: [FolderCrumb] = []
    @Published var currentFolderName = "根目录"
    @Published var familyCrumbs: [FolderCrumb] = []
    @Published var familyFolderName = "根目录"
    /// 当前浏览的空间
    @Published var space: CloudSpace = .personal

    let client: Cloud189Client

    init(client: Cloud189Client = Cloud189Client()) {
        self.client = client
        // 下载完成的日志写到日志页
        DownloadManager.shared.logHandler = { [weak self] message in
            Task { @MainActor in self?.append(message) }
        }
        DownloadManager.shared.attach(client: client)
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

    /// 进入子目录（记录历史，可返回）
    func openFolder(_ entry: CloudEntry) async {
        crumbs.append(FolderCrumb(id: folderId, name: currentFolderName))
        currentFolderName = entry.name
        await load(entry.id)
    }

    /// 返回上一级
    func goBack() async {
        guard let prev = crumbs.popLast() else { return }
        currentFolderName = prev.name
        await load(prev.id)
    }

    /// 回到根目录并清空历史
    func goRoot() async {
        crumbs = []
        currentFolderName = "根目录"
        await load("-11")
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

            if result.ok {
                await load(folderId)
                return
            }

            // 未命中：自动转真实分片上传
            append("转为真实上传…")
            uploadLabel = "上传 \(url.lastPathComponent)"
            uploadProgress = 0
            defer { uploadProgress = 0; uploadLabel = "" }
            let uploaded = try await client.uploadFile(
                at: url, name: url.lastPathComponent, parentFolderId: folderId
            ) { done, total in
                Task { @MainActor [weak self] in
                    self?.uploadProgress = total > 0 ? Double(done) / Double(total) : 0
                }
            }
            append("上传结果：\(uploaded.message)")
            await load(folderId)
        } catch {
            errorText = error.localizedDescription
            append("秒传失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 当前空间

    var activeEntries: [CloudEntry] { space == .personal ? entries : familyEntries }
    var activeFolderId: String { space == .personal ? folderId : familyFolderId }
    var activeFolderName: String { space == .personal ? currentFolderName : familyFolderName }
    var activeCrumbs: [FolderCrumb] { space == .personal ? crumbs : familyCrumbs }
    var activeBusy: Bool { space == .personal ? busy : familyBusy }

    func switchSpace(_ new: CloudSpace) async {
        space = new
        if new == .personal {
            if entries.isEmpty { await load("-11") }
        } else {
            if familyId.isEmpty { await loadFamilyRoot() }
            else if familyEntries.isEmpty { await loadFamily(familyFolderId) }
        }
    }

    /// 进目录（自动分派到当前空间，并记录历史）
    func openEntry(_ entry: CloudEntry) async {
        guard entry.isFolder else { return }
        switch space {
        case .personal: await openFolder(entry)
        case .family: await familyOpen(entry)
        }
    }

    func navBack() async {
        switch space {
        case .personal: await goBack()
        case .family: await familyGoBack()
        }
    }

    func navRoot() async {
        switch space {
        case .personal: await goRoot()
        case .family: await familyGoRoot()
        }
    }

    func refreshActive() async {
        switch space {
        case .personal: await load(folderId)
        case .family: await loadFamily(familyFolderId)
        }
    }

    func deleteEntry(_ entry: CloudEntry) async {
        switch space {
        case .personal:
            await delete(entry)
        case .family:
            guard !familyId.isEmpty else { return }
            familyBusy = true; errorText = nil
            defer { familyBusy = false }
            do {
                try await client.familyDelete(fileId: entry.id, familyId: familyId)
                append("家庭云已删除 \(entry.name)")
                await loadFamily(familyFolderId)
            } catch {
                errorText = error.localizedDescription
                append("删除失败：\(error.localizedDescription)")
            }
        }
    }

    func renameEntry(_ entry: CloudEntry, to newName: String) async {
        switch space {
        case .personal:
            await rename(entry, to: newName)
        case .family:
            guard !familyId.isEmpty else { return }
            familyBusy = true; errorText = nil
            defer { familyBusy = false }
            do {
                try await client.familyRename(fileId: entry.id, to: newName, familyId: familyId)
                append("家庭云已重命名 \(entry.name) → \(newName)")
                await loadFamily(familyFolderId)
            } catch {
                errorText = error.localizedDescription
                append("重命名失败：\(error.localizedDescription)")
            }
        }
    }

    func makeFolderInActive(_ name: String) async {
        switch space {
        case .personal: await makeFolder(name)
        case .family: await familyMakeFolder(name)
        }
    }

    func downloadEntry(_ entry: CloudEntry) async {
        switch space {
        case .personal: await download(entry)
        case .family: await downloadFamily(entry)
        }
    }

    // MARK: - 文件管理

    func delete(_ entry: CloudEntry) async {
        busy = true; errorText = nil
        defer { busy = false }
        do {
            try await client.deleteFiles([entry.id])
            append("已删除 \(entry.name)")
            await load(folderId)
        } catch {
            errorText = error.localizedDescription
            append("删除失败：\(error.localizedDescription)")
        }
    }

    func rename(_ entry: CloudEntry, to newName: String) async {
        busy = true; errorText = nil
        defer { busy = false }
        do {
            try await client.rename(fileId: entry.id, to: newName)
            append("已重命名 \(entry.name) → \(newName)")
            await load(folderId)
        } catch {
            errorText = error.localizedDescription
            append("重命名失败：\(error.localizedDescription)")
        }
    }

    func makeFolder(_ name: String) async {
        busy = true; errorText = nil
        defer { busy = false }
        do {
            let id = try await client.createFolder(name: name, parentId: folderId)
            append("新建文件夹 \(name)（\(id)）")
            await load(folderId)
        } catch {
            errorText = error.localizedDescription
            append("新建失败：\(error.localizedDescription)")
        }
    }

    func search(_ keyword: String) async {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        let hits = await client.search(kw, folderId: folderId)
        searchResults = hits
        append("搜索「\(kw)」命中 \(hits.count) 项")
    }

    // MARK: - 分享（用 String 而非 ShareLink，避免 iOS target 引用问题）

    func createShare(for entry: CloudEntry) async {
        busy = true; errorText = nil
        defer { busy = false }
        do {
            let link = try await client.createShare(fileId: entry.id)
            lastShareText = link.shareText
            append("已创建分享：\(link.url) 提取码 \(link.accessCode)")
        } catch {
            errorText = error.localizedDescription
            append("创建分享失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 批量上传

    func uploadMany(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        busy = true; errorText = nil
        defer { busy = false; uploadProgress = 0; uploadLabel = "" }
        var ok = 0
        for (index, url) in urls.enumerated() {
            uploadLabel = "[\(index + 1)/\(urls.count)] \(url.lastPathComponent)"
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let r = try await client.uploadFile(at: url,
                                                   name: url.lastPathComponent,
                                                   parentFolderId: folderId)
                if r.ok { ok += 1 }
                append("\(url.lastPathComponent) → \(r.ok ? "成功" : "失败")")
            } catch {
                append("\(url.lastPathComponent) 失败：\(error.localizedDescription)")
                if isSessionExpired(error) { needsRelogin = true; break }
            }
        }
        append("批量完成 \(ok)/\(urls.count)")
        await load(folderId)
    }

    func isSessionExpired(_ error: Error) -> Bool {
        if case CASError.sessionExpired = error { return true }
        let text = error.localizedDescription
        return text.contains("登录") || text.contains("session") || text.contains("SessionKey")
    }

    func relogin() {
        needsRelogin = false
        SessionStore.clear()
        session = Session()
        entries = []
    }

    func clearShare() { lastShareText = nil }

    // MARK: - 下载

    func download(_ entry: CloudEntry) async {
        guard !entry.isFolder else { return }
        errorText = nil
        DownloadManager.shared.attach(client: client)
        await DownloadManager.shared.enqueue(
            client: client, fileId: entry.id, familyId: nil,
            fileName: entry.name, totalBytes: entry.size)
        append("已加入下载队列：\(entry.name)")
    }

    /// 后台刷新：重拉当前目录，让下次打开 App 时列表是新的
    func backgroundRefresh() async {
        BackgroundRefresh.schedule()
        guard !session.cookies.isEmpty else { return }
        await load(folderId)
    }

    func clearDownload() { downloadedFile = nil }
}
