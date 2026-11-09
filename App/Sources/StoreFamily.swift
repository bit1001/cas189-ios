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

    /// 任何界面要用家庭云之前调用：没取过 familyId 就先取
    func ensureFamilyReady() async {
        guard session.isLoggedIn else { return }
        if familyId.isEmpty { await loadFamilyRoot() }
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
            let n = try await client.download(fileId: entry.id, to: dst, familyId: familyId)
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
    private func parseCredentials(_ urls: [URL]) -> [(item: CasItem, kind: String, bundle: String?)] {
        var items: [(CasItem, String, String?)] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let lower = url.lastPathComponent.lowercased()
            do {
                let data = try Data(contentsOf: url)
                // zip 内的凭证统一放进「与 zip 同名」的文件夹
                let bundleName: String? = lower.hasSuffix(".zip")
                    ? zipFolderName(url.lastPathComponent) : nil
                if lower.hasSuffix(".zip") {
                    // 凭证包就是普通 .zip：里面可能装多个 .cas，也可能不带 .cas 后缀。
                    // 按「逐个条目当 .cas 解析」处理，坏的条目跳过不影响其他。
                    let entries = try CasFile.allEntries(inArchive: url)
                    var used = 0
                    for e in entries {
                        let inner = e.name.lowercased()
                        if inner.hasSuffix(".torrent") {
                            if let item = try? CasTorrent.parse(e.data) {
                                items.append((item, "torrent", bundleName)); used += 1
                            } else {
                                append("  zip 内 \(e.name) 不是合法种子，跳过")
                            }
                        } else {
                            do {
                                items.append((try CasFile.parse(data: e.data, fileName: e.name), "cas", bundleName))
                                used += 1
                            } catch {
                                append("  \(e.name)：\(error.localizedDescription)")
                            }
                        }
                    }
                    append("\(url.lastPathComponent)：\(entries.count) 个条目，认出 \(used) 个凭证")
                    if used == 0 {
                        append("  这个压缩包里没有 .cas 凭证，不能秒传")
                    }
                } else if lower.hasSuffix(".torrent") {
                    items.append((try CasTorrent.parse(data), "torrent", nil))
                } else {
                    // 没后缀 / 后缀不标准也按 .cas 试一次（选了「导入秒传」就应该当凭证处理）
                    do {
                        items.append((try CasFile.parse(data: data, fileName: url.lastPathComponent), "cas", nil))
                    } catch {
                        append("跳过 \(url.lastPathComponent)：\(error.localizedDescription)")
                    }
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
    // MARK: - 指定目标的上传 / 秒传 / 转存（导入界面用）

    func listForPicker(space: CloudSpace, folderId: String) async throws -> [CloudEntry] {
        try await client.entries(space: space.key, folderId: folderId, familyId: familyId)
    }

    /// 选择文件 → 上传（先试秒传，未命中转真实上传）
    func uploadTo(_ urls: [URL], space: CloudSpace, folderId: String) async {
        guard !urls.isEmpty else {
            append("上传：没有收到文件")
            return
        }
        append("开始上传 \(urls.count) 个文件 → \(space.rawValue) / \(folderId)")
        busy = true; errorText = nil
        defer { busy = false; uploadProgress = 0; uploadLabel = "" }
        var ok = 0
        for (index, url) in urls.enumerated() {
            uploadLabel = "[\(index + 1)/\(urls.count)] \(url.lastPathComponent)"
            do {
                let r = try await transferOne(url: url, space: space, folderId: folderId)
                if r.ok {
                    ok += 1
                    // 处理成功后清掉本地副本（系统选择器给的临时文件不在沙盒里，不会动）
                    if LocalFiles.contains(url) {
                        do { try LocalFiles.delete(url) } catch { /* 清理失败不影响结果 */ }
                    }
                }
                append("\(url.lastPathComponent) → \(r.message)")
            } catch {
                append("\(url.lastPathComponent) 失败：\(error.localizedDescription)")
                if isSessionExpired(error) { needsRelogin = true; break }
            }
        }
        uploadProgress = 0; uploadLabel = ""
        append("上传完成 \(ok)/\(urls.count)")
        await refresh(space: space, target: folderId)
    }

    /// 单个文件：先算指纹试秒传，未命中走真实上传
    private func transferOne(url: URL, space: CloudSpace, folderId: String) async throws -> (ok: Bool, message: String) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let fp = try await Task.detached(priority: .userInitiated) {
            try CryptoTool.fingerprintFile(url)
        }.value
        let item = CasItem(name: url.lastPathComponent, size: fp.size,
                           fileMd5: fp.fileMd5, sliceMd5: fp.sliceMd5,
                           sliceSize: fp.sliceSize, parts: fp.parts)

        if space == .personal {
            let rapid = try await client.rapidUpload(item, parentFolderId: folderId)
            if rapid.ok { return (true, "秒传成功") }
        } else {
            guard !familyId.isEmpty else { throw CASError.missing("未连接家庭云") }
            let rapid = try await client.familyRapidUpload(item, familyId: familyId,
                                                           parentFolderId: folderId)
            if rapid.ok { return (true, "秒传成功") }
        }
        uploadLabel = "上传 \(url.lastPathComponent)"
        let uploaded: RapidResult
        if space == .personal {
            uploaded = try await client.uploadFile(at: url, name: url.lastPathComponent,
                                                   parentFolderId: folderId) { done, total in
                Task { @MainActor [weak self] in
                    self?.uploadProgress = total > 0 ? Double(done) / Double(total) : 0
                }
            }
        } else {
            uploaded = try await client.familyUpload(at: url, familyId: familyId,
                                                     name: url.lastPathComponent,
                                                     parentFolderId: folderId) { done, total in
                Task { @MainActor [weak self] in
                    self?.uploadProgress = total > 0 ? Double(done) / Double(total) : 0
                }
            }
        }
        return (uploaded.ok, uploaded.message)
    }

    /// 凭证（.cas / .torrent / .zip）秒传到指定位置
    func importCredentialsTo(_ urls: [URL], space: CloudSpace, folderId: String) async {
        append("开始解析 \(urls.count) 个凭证文件 → \(space.rawValue) / \(folderId)")
        busy = true; errorText = nil
        defer { busy = false; uploadLabel = "" }
        let items = parseCredentials(urls)
        guard !items.isEmpty else {
            errorText = "没有可用的秒传凭证（支持 .cas / .cas.torrent / .cas.zip）"
            return
        }
        var ok = 0
        var currentFolder = folderId
        var currentBundle: String?
        for (index, pair) in items.enumerated() {
            uploadLabel = "[\(index + 1)/\(items.count)] \(pair.item.name)"
            do {
                // 换包了：在目标目录下建一个与 zip 同名的文件夹
                if pair.bundle != currentBundle {
                    currentBundle = pair.bundle
                    if let name = pair.bundle {
                        currentFolder = try await ensureFolder(named: name, space: space, parent: folderId)
                    } else {
                        currentFolder = folderId
                    }
                }
                let r: RapidResult
                if space == .personal {
                    r = try await client.rapidUpload(pair.item, parentFolderId: currentFolder)
                } else {
                    guard !familyId.isEmpty else { throw CASError.missing("未连接家庭云") }
                    r = try await client.familyRapidUpload(pair.item, familyId: familyId,
                                                           parentFolderId: currentFolder)
                }
                if r.ok { ok += 1 }
                append("\(pair.item.name)（\(pair.kind)）→ \(r.ok ? "秒传成功" : "未命中：\(r.message)")")
            } catch {
                append("\(pair.item.name) 失败：\(error.localizedDescription)")
                if isSessionExpired(error) { needsRelogin = true; break }
            }
        }
        append("凭证秒传 \(ok)/\(items.count)")
        if ok == items.count {
            var removed = 0
            for url in urls where LocalFiles.contains(url) {
                if (try? LocalFiles.delete(url)) != nil { removed += 1 }
            }
            if removed > 0 { append("已清理 App 文件夹里的 \(removed) 个本地副本") }
        }
        await refresh(space: space, target: folderId)
    }


    /// zip 文件名 → 文件夹名：`挑情丑闻.zip` → `挑情丑闻`
    private func zipFolderName(_ fileName: String) -> String {
        var name = fileName
        if name.lowercased().hasSuffix(".zip") { name = String(name.dropLast(4)) }
        if name.lowercased().hasSuffix(".cas") { name = String(name.dropLast(4)) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "秒传导入" : trimmed
    }

    /// 目标目录下按名字找文件夹，没有就建一个；返回 folderId
    private func ensureFolder(named name: String, space: CloudSpace, parent: String) async throws -> String {
        if space == .family && familyId.isEmpty { await loadFamilyRoot() }
        let siblings = try await client.entries(space: space.key, folderId: parent, familyId: familyId)
        if let hit = siblings.first(where: { $0.isFolder && $0.name == name }) {
            append("使用已有文件夹「\(name)」")
            return hit.id
        }
        let id: String
        if space == .personal {
            id = try await client.createFolder(name: name, parentId: parent)
        } else {
            guard !familyId.isEmpty else { throw CASError.missing("未连接家庭云") }
            id = try await client.familyMkdir(name: name, familyId: familyId, parentFolderId: parent)
        }
        append("已创建文件夹「\(name)」→ 秒传到该目录")
        return id
    }

    /// 分享转存到指定位置（目前仅个人云支持）
    func importShareTo(_ text: String, space: CloudSpace, folderId: String) async {
        guard space == .personal else {
            errorText = "服务端不支持把他人分享直接转存到家庭云，请先转到个人云再复制"
            return
        }
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        busy = true; errorText = nil
        defer { busy = false }
        do {
            let parsed = Cloud189Client.extractShareLink(from: raw)
            let code = parsed?.code ?? raw
            let pwd = parsed?.accessCode ?? ""
            let info = try await client.shareInfo(code: code, accessCode: pwd)
            append("分享内容：\(info.fileName) → 目录 \(folderId)")
            let r = try await client.saveShare(info: info, targetFolderId: folderId, accessCode: pwd)
            if let taskId = r["taskId"] as? String {
                append("转存任务 \(taskId) 已提交")
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                let st = try await client.checkShareSaveTask(taskId: taskId)
                append("状态 \(st["taskStatus"] ?? "?")：成功 \(st["successedCount"] ?? "0") / 失败 \(st["failedCount"] ?? "0")")
            }
            await refresh(space: space, target: folderId)
        } catch {
            errorText = error.localizedDescription
            append("转存失败：\(error.localizedDescription)")
        }
    }

    private func refresh(space: CloudSpace, target: String) async {
        switch space {
        case .personal:
            if target == folderId { await load(target) }
        case .family:
            if target == familyFolderId { await loadFamily(target) }
        }
    }
    /// 「用本 App 打开」进来的文件：复制进 Inbox，再按类型自动导入
    func importIncoming(_ urls: [URL], space: CloudSpace) async {
        let saved = LocalFiles.copyIn(urls)
        guard !saved.isEmpty else {
            append("没有收到可导入的文件")
            return
        }
        for url in saved {
            append("已接收 \(url.lastPathComponent)（\(LocalFiles.sizeText(url))）")
        }
        let supported = saved.filter { LocalFiles.isSupported($0) }
        guard !supported.isEmpty else {
            errorText = "收到的文件不是 .cas / .torrent / .zip"
            return
        }
        await importCredentialsTo(supported, space: space, folderId: "-11")
    }

    /// 直接导入 App 文件夹里的文件（LiveContainer 下选择器不可用时的主路径）
    func importLocalFiles(_ urls: [URL], space: CloudSpace, folderId: String) async {
        append("从 App 文件夹导入 \(urls.count) 个文件")
        await importCredentialsTo(urls, space: space, folderId: folderId)
    }
    /// 粘贴 .cas JSON 文本直接秒传（不依赖任何文件接口）
    func rapidFromCASJSON(_ text: String, space: CloudSpace, folderId: String) async {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        busy = true; errorText = nil
        defer { busy = false }
        do {
            let data = Data(raw.utf8)
            let item = try CasFile.parse(data: data, fileName: "pasted.cas")
            let r: RapidResult
            if space == .personal {
                r = try await client.rapidUpload(item, parentFolderId: folderId)
            } else {
                guard !familyId.isEmpty else { throw CASError.missing("未连接家庭云") }
                r = try await client.familyRapidUpload(item, familyId: familyId, parentFolderId: folderId)
            }
            append("粘贴凭证 \(item.name) → \(r.ok ? "秒传成功" : "未命中：\(r.message)")")
            await refresh(space: space, target: folderId)
        } catch {
            errorText = error.localizedDescription
            append("粘贴凭证失败：\(error.localizedDescription)")
        }
    }
    /// 从 http(s) 链接下载凭证再导入（完全绕开 iOS 文件接口）
    func importFromURL(_ text: String, space: CloudSpace, folderId: String) async {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            errorText = "链接无效，需要 http(s) 地址"
            return
        }
        busy = true; errorText = nil
        do {
            append("下载 \(raw)…")
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw CASError.api(code: "HTTP \(http.statusCode)", message: "下载失败")
            }
            LocalFiles.ensureDirs()
            let name = url.lastPathComponent.isEmpty ? "download.cas" : url.lastPathComponent
            let dst = LocalFiles.inbox.appendingPathComponent(name)
            try data.write(to: dst)
            busy = false
            append("已下载 \(name)（\(data.count) 字节）")
            await importCredentialsTo([dst], space: space, folderId: folderId)
        } catch {
            busy = false
            errorText = error.localizedDescription
            append("下载失败：\(error.localizedDescription)")
        }
    }
}
