import SwiftUI
import UniformTypeIdentifiers
import CAS189Core

/// 导入界面：上传 / 秒传凭证 / 转存分享，统一选目标空间与目标目录。
struct TransferView: View {
    @EnvironmentObject private var store: Store

    @State private var targetSpace: CloudSpace = .personal
    @State private var targetFolderId = "-11"
    @State private var targetFolderName = "根目录"
    @State private var showFolderPicker = false
    @State private var shareText = ""
    @State private var casText = ""
    @State private var localFiles: [URL] = []
    @State private var remoteURL = ""


    enum ImporterMode: Int, Identifiable {
        case upload = 0
        case credentials = 1
        var id: Int { rawValue }
    }

    /// 走 UIKit 原生选择器：SwiftUI 的 .fileImporter 在这台设备上完全不回调
    private func pickFiles(mode chosen: ImporterMode) {
        store.append("正在打开文件选择器…")
        DocumentPickerCoordinator.pickFiles(
            allowsMultiple: true,
            log: { message in Task { @MainActor in store.append(message) } }
        ) { urls in
            Task { @MainActor in
                guard !urls.isEmpty else {
                    store.append("已取消选择")
                    return
                }
                store.append("已选择 \(urls.count) 个文件：\(urls.prefix(3).map(\.lastPathComponent).joined(separator: ", "))")
                switch chosen {
                case .upload:
                    await store.uploadTo(urls, space: targetSpace, folderId: targetFolderId)
                case .credentials:
                    await store.importCredentialsTo(urls, space: targetSpace, folderId: targetFolderId)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("目标位置") {
                    Picker("空间", selection: Binding(
                        get: { targetSpace },
                        set: { newValue in
                            targetSpace = newValue
                            targetFolderId = "-11"
                            targetFolderName = "根目录"
                        }
                    )) {
                        ForEach(CloudSpace.allCases) { space in
                            Text(space.rawValue).tag(space)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack {
                            Text("目录")
                            Spacer()
                            Text(targetFolderName).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Button {
                        pickFiles(mode: .upload)
                    } label: {
                        Label("选择文件上传（先试秒传，未命中转真实上传）", systemImage: "doc.badge.plus")
                    }
                    Button {
                        pickFiles(mode: .credentials)
                    } label: {
                        Label("导入秒传凭证（.cas / .torrent / .zip）", systemImage: "shippingbox")
                    }
                } header: {
                    Text("上传 / 秒传")
                } footer: {
                    Text("凭证导入只读指纹，不需要原文件。选 .zip 会自动解包里面的所有 .cas / .torrent 批量秒传。")
                }

                Section {
                    TextField("https://cloud.189.cn/t/xxxx 提取码：abcd",
                              text: $shareText, axis: .vertical)
                        .lineLimit(2...4)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("转存到上面的目录") {
                        let text = shareText
                        Task { await store.importShareTo(text, space: targetSpace, folderId: targetFolderId) }
                    }
                    .disabled(shareText.isEmpty || store.busy)
                } header: {
                    Text("转存别人的分享")
                } footer: {
                    if targetSpace == .family {
                        Text("服务端不支持把他人分享直接转存到家庭云：请先转到个人云，再在文件界面长按「转存到个人云」的反向操作。")
                            .foregroundStyle(.orange)
                    } else {
                        Text("粘贴整段分享文案即可，会自动识别提取码。")
                    }
                }

                Section {
                    Button {
                        localFiles = LocalFiles.list()
                        store.append("App 文件夹里 \(localFiles.count) 个文件")
                    } label: {
                        Label("刷新 App 文件夹", systemImage: "arrow.clockwise")
                    }
                    if localFiles.isEmpty {
                        Text("还没有文件").foregroundStyle(.secondary).font(.caption)
                    }
                    ForEach(localFiles, id: \.self) { url in
                        Button {
                            Task {
                                await store.importCredentialsTo([url], space: targetSpace, folderId: targetFolderId)
                            }
                        } label: {
                            HStack {
                                Text(url.lastPathComponent).lineLimit(1)
                                Spacer()
                                Text(LocalFiles.sizeText(url)).font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("App 文件夹")
                } footer: {
                    Text("把 .cas / .torrent / .zip 放进「文件」App 的「我的 iPhone / 189秒传」，或长按文件 → 共享 →「用 189秒传 打开」。LiveContainer 里系统选择器回调拿不到结果，这条路最稳。")
                }

                Section {
                    TextField("https://example.com/xxx.cas.zip", text: $remoteURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Button("下载并导入") {
                        let link = remoteURL
                        Task { await store.importFromURL(link, space: targetSpace, folderId: targetFolderId) }
                    }
                    .disabled(remoteURL.isEmpty || store.busy)
                } header: {
                    Text("从链接导入")
                } footer: {
                    Text("把 .cas / .torrent / .zip 放到任意 http 直链（NAS、VPS、网盘直链都行），这里下载后直接秒传。不依赖任何系统文件接口。")
                }

                Section {
                    TextEditor(text: $casText)
                        .frame(minHeight: 80)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("秒传这段 .cas 内容") {
                        let text = casText
                        Task { await store.rapidFromCASJSON(text, space: targetSpace, folderId: targetFolderId) }
                    }
                    .disabled(casText.isEmpty || store.busy)
                } header: {
                    Text("粘贴 .cas 内容")
                } footer: {
                    Text(".cas 是 JSON 文本，直接粘进来即可，完全不需要文件接口。")
                }

                if store.busy || !store.uploadLabel.isEmpty {
                    Section("进行中") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.uploadLabel).font(.caption)
                            if store.uploadProgress > 0 {
                                ProgressView(value: store.uploadProgress)
                            }
                        }
                    }
                }

                Section("最近日志") {
                    let recent = Array(store.logs.suffix(6))
                    if recent.isEmpty {
                        Text("暂无").foregroundStyle(.secondary)
                    }
                    ForEach(Array(recent.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2.monospaced())
                    }
                }
            }
            .navigationTitle("导入")
            .alert("出错了", isPresented: Binding(
                get: { store.errorText != nil },
                set: { if !$0 { store.errorText = nil } }
            )) {
                Button("知道了") { store.errorText = nil }
            } message: {
                Text(store.errorText ?? "")
            }
            .onAppear {
                localFiles = LocalFiles.list()
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView(space: targetSpace) { id, name in
                    targetFolderId = id
                    targetFolderName = name
                }
            }
        }
    }
}

/// 目录选择器：只在目录间走，选中后回传给导入界面
struct FolderPickerView: View {
    @EnvironmentObject private var store: Store
    let space: CloudSpace
    var onPick: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var folderId = "-11"
    @State private var folderName = "根目录"
    @State private var entries: [CloudEntry] = []
    @State private var stack: [FolderCrumb] = []
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onPick(folderId, folderName)
                        dismiss()
                    } label: {
                        Label("选这个目录", systemImage: "checkmark.circle")
                    }
                } header: {
                    Text("当前：\(folderName)")
                }

                Section("子目录") {
                    let folders = entries.filter { $0.isFolder }
                    if folders.isEmpty {
                        Text(loading ? "加载中…" : "没有子目录").foregroundStyle(.secondary)
                    }
                    ForEach(folders) { entry in
                        Button {
                            stack.append(FolderCrumb(id: folderId, name: folderName))
                            folderId = entry.id
                            folderName = entry.name
                            Task { await load() }
                        } label: {
                            HStack {
                                Label(entry.name, systemImage: "folder")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("选择目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        guard let prev = stack.popLast() else { return }
                        folderId = prev.id
                        folderName = prev.name
                        Task { await load() }
                    } label: { Image(systemName: "chevron.backward") }
                        .disabled(stack.isEmpty)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            entries = try await store.listForPicker(space: space, folderId: folderId)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
