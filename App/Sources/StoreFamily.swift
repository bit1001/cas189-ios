import Foundation
import SwiftUI
import CAS189Core

// MARK: - 家庭云 + 分享转存 + 凭证导入
// 这些能力原先只在 CLI 里，这里接进 App。
// 注意：@Published 只能在 Store 类本体声明，本文件只放方法。

@MainActor
extension Store {

    // MARK: 家庭云

    /// 首次进入家庭云：先取 familyId，再列根目录
    func loadFamilyRoot() async {
        guard session.isLoggedIn else { return }
        if !familyId.isEmpty {
            await loadFamily(familyFolderId)
            return
        }
        familyBusy = true; errorText = nil
        defer { familyBusy = false }
        do {
            let infos = try await client.familyInfo()
            guard let first = infos.first else {
                errorText = "该账号没有家庭云空间"
                return
            }
            familyId = first.id
            append("家庭云：\(first.name)（\(first.id)）")
            familyEntries = try await client.familyList(folderId: "-11", familyId: familyId)
            familyFolderId = "-11"
            append("家庭云根目录 \(familyEntries.count) 项")
        } catch {
            errorText = error.localizedDescription
            append("家庭云加载失败：\(error.localizedDescription)")
        }
    }

    func loadFamily(_ folder: String) async {
        guard !familyId.isEmpty else {
            await loadFamilyRoot()
            return
        }
        familyBusy = true; errorText = nil
        defer { familyBusy = false }
        do {
            familyEntries = try await client.familyList(folderId: folder, familyId: familyId)
            familyFolderId = folder
            append("家庭云列出 \(familyEntries.count) 项")
        } catch {
            errorText = error.localizedDescription
            append("家庭云列目录失败：\(error.localizedDescription)")
        }
    }

    func familyMakeFolder(_ name: String) async {
        guard !familyId.isEmpty else { return }
        familyBusy = true; errorText = nil
        defer { familyBusy = false }
        do {
            let id = try await client.familyMkdir(name: name, familyId: familyId,
                                                  parentFolderId: familyFolderId)
            append("家庭云新建文件夹 \(name)（\(id)）")
            await loadFamily(familyFolderId)
        } catch {
            errorText = error.localizedDescription
            append("家庭云建文件夹失败：\(error.localizedDescription)")
        }
    }

    /// 家庭云上传：先试秒传，未命中再真实上传
    func familyRapidOrUpload(url: URL, familyFolder: String? = nil) async {
        guard !familyId.isEmpty else { return }
        let folder = familyFolder ?? familyFolderId
        familyBusy = true; errorText = nil
        uploadProgress = 0
        uploadLabel = "家庭云：\(url.lastPathComponent)"
        defer {
            familyBusy = false
            uploadProgress = 0
            uploadLabel = ""
        }
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let fp = try await Task.detached(priority: .userInitiated) {
                try CryptoTool.fingerprintFile(url)
            }.value
            let item = CasItem(name: url.lastPathComponent,
                               size: fp.size,
                               fileMd5: fp.fileMd5,
                               sliceMd5: fp.sliceMd5,
                               sliceSize: fp.sliceSize,
                               parts: fp.parts)

            let rapid = try await client.familyRapidUpload(item, familyId: familyId,
                                                           parentFolderId: folder)
            if rapid.ok {
                append("家庭云秒传成功：\(url.lastPathComponent)")
                await loadFamily(folder)
                return
            }
            append("家庭云秒传未命中，改为真实上传…")
            let r = try await client.familyUpload(at: url, familyId: familyId,
                                                  name: url.lastPathComponent,
                                                  parentFolderId: folder) { done, total in
                Task { @MainActor [weak self] in
                    self?.uploadProgress = total > 0 ? Double(done) / Double(total) : 0
                }
            }
            append("家庭云上传：\(r.message)")
            await loadFamily(folder)
        } catch {
            errorText = error.localizedDescription
            append("家庭云上传失败：\(error.localizedDescription)")
        }
    }

    func downloadFamily(_ entry: CloudEntry) async {
        guard !entry.isFolder else { return }
        busy = true; errorText = nil
        downloadLabel = "下载 \(entry.name)"
        defer { busy = false; downloadLabel = "" }
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dst = dir.appendingPathComponent(entry.name)
            let n = try await client.download(fileId: entry.id, to: dst)
            downloadedFile = dst
            append("已下载 \(entry.name)（\(ByteCountFormatter.string(fromByteCount: n, countStyle: .file))）")
        } catch {
            errorText = error.localizedDescription
            append("下载失败：\(error.localizedDescription)")
        }
    }

    // MARK: 分享转存

    /// 输入分享链接/分享码（可带「提取码：xxxx」）→ 转存到指定目录
    func importShare(_ text: String, to targetFolder: String? = nil) async {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        busy = true; errorText = nil
        defer { busy = false }
        do {
            let parsed = Cloud189Client.extractShareLink(from: raw)
            let code = parsed?.code ?? raw
            let pwd = parsed?.accessCode ?? ""
            append("解析分享 \(code)…")

            let info = try await client.shareInfo(code: code, accessCode: pwd)
            append("分享内容：\(info.fileName)")

            let target = targetFolder ?? folderId
            let r = try await client.saveShare(info: info, targetFolderId: target, accessCode: pwd)
            if let taskId = r["taskId"] as? String {
                append("已提交转存任务 \(taskId)，等待完成…")
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                let st = try await client.checkShareSaveTask(taskId: taskId)
                append("转存状态：\(st["taskStatus"] ?? "?")（成功 \(st["successedCount"] ?? "0") / 失败 \(st["failedCount"] ?? "0")）")
            } else {
                append("已提交转存")
            }
            await load(target)
        } catch {
            errorText = error.localizedDescription
            append("转存失败：\(error.localizedDescription)")
        }
    }

    // MARK: 凭证导入（.cas / .cas.torrent / .cas.zip）

    /// 从本地凭证文件秒传，不需要文件本身
    func importCredentials(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        busy = true; errorText = nil
        defer { busy = false }
        var items: [(CasItem, String)] = []

        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let name = url.lastPathComponent.lowercased()
                if name.hasSuffix(".torrent") {
                    items.append((try CasTorrent.parse(data), "torrent"))
                } else if name.hasSuffix(".cas") {
                    items.append((try CasFile.parse(data: data, fileName: url.lastPathComponent), "cas"))
                } else if name.hasSuffix(".zip") {
                    let entries = try CasFile.entries(inArchive: url)
                    for e in entries {
                        if e.name.lowercased().hasSuffix(".torrent") {
                            items.append((try CasTorrent.parse(e.data), "torrent"))
                        } else {
                            items.append((try CasFile.parse(data: e.data, fileName: e.name), "cas"))
                        }
                    }
                } else {
                    append("跳过 \(url.lastPathComponent)（不是 .cas / .torrent / .zip）")
                }
            } catch {
                append("\(url.lastPathComponent) 读取失败：\(error.localizedDescription)")
            }
        }

        guard !items.isEmpty else {
            if errorText == nil { errorText = "没有可用的秒传凭证" }
            return
        }

        var ok = 0
        for (index, pair) in items.enumerated() {
            uploadLabel = "[\(index + 1)/\(items.count)] \(pair.0.name)"
            do {
                let r = try await client.rapidUpload(pair.0, parentFolderId: folderId)
                if r.ok { ok += 1 }
                append("\(pair.0.name)（\(pair.1)）→ \(r.ok ? "秒传成功" : "未命中：\(r.message)")")
            } catch {
                append("\(pair.0.name) 秒传失败：\(error.localizedDescription)")
                if isSessionExpired(error) { needsRelogin = true; break }
            }
        }
        uploadLabel = ""
        append("凭证导入完成 \(ok)/\(items.count)")
        await load(folderId)
    }
    // MARK: 家庭云导航

    func familyOpen(_ entry: CloudEntry) async {
        familyCrumbs.append(FolderCrumb(id: familyFolderId, name: familyFolderName))
        familyFolderName = entry.name
        await loadFamily(entry.id)
    }

    func familyGoBack() async {
        guard let prev = familyCrumbs.popLast() else { return }
        familyFolderName = prev.name
        await loadFamily(prev.id)
    }

    func familyGoRoot() async {
        familyCrumbs = []
        familyFolderName = "根目录"
        await loadFamily("-11")
    }

    // MARK: 家庭云秒传（凭证导入）

    /// 解析 .cas / .cas.torrent / .cas.zip → CasItem
    private func parseCredentials(_ urls: [URL]) -> [(item: CasItem, kind: String)] {
        var items: [(CasItem, String)] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let name = url.lastPathComponent.lowercased()
                if name.hasSuffix(".torrent") {
                    items.append((try CasTorrent.parse(data), "torrent"))
                } else if name.hasSuffix(".cas") {
                    items.append((try CasFile.parse(data: data, fileName: url.lastPathComponent), "cas"))
                } else if name.hasSuffix(".zip") {
                    for e in try CasFile.entries(inArchive: url) {
                        if e.name.lowercased().hasSuffix(".torrent") {
                            items.append((try CasTorrent.parse(e.data), "torrent"))
                        } else {
                            items.append((try CasFile.parse(data: e.data, fileName: e.name), "cas"))
                        }
                    }
                } else {
                    append("跳过 \(url.lastPathComponent)（不是 .cas / .torrent / .zip）")
                }
            } catch {
                append("\(url.lastPathComponent) 读取失败：\(error.localizedDescription)")
            }
        }
        return items
    }

    /// 家庭云秒传：只凭凭证，不上传文件
    func familyImportCredentials(_ urls: [URL]) async {
        guard !familyId.isEmpty else {
            errorText = "请先连接家庭云"
            return
        }
        familyBusy = true; errorText = nil
        defer { familyBusy = false }
        let items = parseCredentials(urls)
        guard !items.isEmpty else {
            errorText = "没有可用的秒传凭证"
            return
        }
        var ok = 0
        for (index, pair) in items.enumerated() {
            uploadLabel = "家庭云 [\(index + 1)/\(items.count)] \(pair.item.name)"
            do {
                let r = try await client.familyRapidUpload(pair.item, familyId: familyId,
                                                           parentFolderId: familyFolderId)
                if r.ok { ok += 1 }
                append("\(pair.item.name)（\(pair.kind)）→ \(r.ok ? "秒传成功" : "未命中：\(r.message)")")
            } catch {
                append("\(pair.item.name) 秒传失败：\(error.localizedDescription)")
            }
        }
        uploadLabel = ""
        append("家庭云凭证导入 \(ok)/\(items.count)")
        await loadFamily(familyFolderId)
    }

    /// 家庭云文件 → 个人云
    func familyTransferToPersonal(_ entry: CloudEntry) async {
        guard !familyId.isEmpty, !entry.isFolder else { return }
        familyBusy = true; errorText = nil
        defer { familyBusy = false }
        do {
            append("转存 \(entry.name) → 个人云…")
            let taskId = try await client.familyCopyToPersonal(fileId: entry.id,
                                                              fileName: entry.name,
                                                              familyId: familyId,
                                                              targetFolderId: "-11")
            let st = try await client.familyWaitTask(type: "COPY", taskId: taskId, familyId: familyId)
            let okCount = (st["successedCount"] as? NSNumber)?.intValue ?? 0
            append("转存完成：成功 \(okCount) 个（taskStatus \(st["taskStatus"] ?? "?"))")
            await load("-11")
        } catch {
            errorText = error.localizedDescription
            append("转存失败：\(error.localizedDescription)")
        }
    }
}
