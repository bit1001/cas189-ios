import SwiftUI
import CAS189Core

/// 文件浏览与管理：个人云 / 家庭云共用一个界面，顶部切换空间。
/// 整行可点（点名字就进目录），左滑删除，长按更多。
struct BrowserView: View {
    @EnvironmentObject private var store: Store

    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renameTarget: CloudEntry?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("空间", selection: Binding(
                        get: { store.space },
                        set: { newValue in Task { await store.switchSpace(newValue) } }
                    )) {
                        ForEach(CloudSpace.allCases) { space in
                            Text(space.rawValue).tag(space)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(store.searchText.isEmpty
                        ? "目录（\(store.activeFolderName)）"
                        : "搜索结果（\(displayed.count)）") {
                    if displayed.isEmpty {
                        Text(store.activeBusy ? "加载中…" : "这里还没有文件")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(displayed) { entry in
                        row(entry)
                    }
                }
            }
            .navigationTitle("文件 · \(store.activeFolderName)")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await store.navBack() }
                    } label: { Image(systemName: "chevron.backward") }
                        .disabled(store.activeCrumbs.isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await store.navRoot() }
                    } label: { Image(systemName: "arrow.clockwise") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newFolderName = ""
                        showNewFolder = true
                    } label: { Image(systemName: "folder.badge.plus") }
                }
            }
            .refreshable { await store.refreshActive() }
            .searchable(text: $store.searchText,
                        prompt: store.space == .personal ? "搜索云盘（递归 3 层）" : "在当前目录里筛选")
            .onSubmit(of: .search) {
                if store.space == .personal {
                    Task { await store.search(store.searchText) }
                }
            }
            .overlay(alignment: .top) {
                if store.activeBusy {
                    ProgressView().padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 6)
                }
            }
            .alert("新建文件夹", isPresented: $showNewFolder) {
                TextField("名字", text: $newFolderName)
                Button("取消", role: .cancel) { }
                Button("创建") { Task { await store.makeFolderInActive(newFolderName) } }
            }
            .alert("重命名", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("新名字", text: $renameText)
                Button("取消", role: .cancel) { renameTarget = nil }
                Button("确定") {
                    if let target = renameTarget {
                        Task { await store.renameEntry(target, to: renameText) }
                    }
                    renameTarget = nil
                }
            }
            .alert("分享链接", isPresented: Binding(
                get: { store.lastShareText != nil },
                set: { if !$0 { store.clearShare() } }
            )) {
                Button("复制") {
                    UIPasteboard.general.string = store.lastShareText ?? ""
                    store.clearShare()
                }
                Button("关闭", role: .cancel) { store.clearShare() }
            } message: {
                Text(store.lastShareText ?? "")
            }
            .sheet(item: Binding(
                get: { store.downloadedFile.map { ShareSheetItem(url: $0) } },
                set: { if $0 == nil { store.clearDownload() } }
            )) { item in
                ActivityView(items: [item.url])
            }
            .alert("登录已过期", isPresented: $store.needsRelogin) {
                Button("知道了") { store.needsRelogin = false }
            } message: {
                Text("请到「登录」页重新登录。")
            }
        }
    }

    /// 搜索时显示的结果：个人云走服务端递归，家庭云只做本地筛选
    private var displayed: [CloudEntry] {
        guard !store.searchText.isEmpty else { return store.activeEntries }
        if store.space == .family {
            return store.activeEntries.filter {
                $0.name.localizedCaseInsensitiveContains(store.searchText)
            }
        }
        return store.searchResults
    }

    // MARK: - 单行

    @ViewBuilder
    private func row(_ entry: CloudEntry) -> some View {
        HStack(spacing: 10) {
            thumbnail(entry)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).lineLimit(1)
                if !entry.isFolder {
                    Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if entry.isFolder {
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.isFolder {
                Task { await store.openEntry(entry) }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await store.deleteEntry(entry) }
            } label: { Label("删除", systemImage: "trash") }
        }
        .contextMenu {
            if !entry.isFolder {
                Button {
                    Task { await store.downloadEntry(entry) }
                } label: { Label("下载", systemImage: "arrow.down.circle") }

                if store.space == .personal {
                    Button {
                        Task { await store.createShare(for: entry) }
                    } label: { Label("创建分享链接", systemImage: "square.and.arrow.up") }
                } else {
                    Button {
                        Task { await store.familyTransferToPersonal(entry) }
                    } label: { Label("转存到个人云", systemImage: "arrow.uturn.left.circle") }
                }
            }
            Button {
                renameText = entry.name
                renameTarget = entry
            } label: { Label("重命名", systemImage: "pencil") }
            Button(role: .destructive) {
                Task { await store.deleteEntry(entry) }
            } label: { Label("删除", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private func thumbnail(_ entry: CloudEntry) -> some View {
        if let icon = entry.iconURL, let url = URL(string: icon) {
            AsyncImage(url: url) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: entry.isFolder ? "folder" : "doc")
                .foregroundStyle(entry.isFolder ? .blue : .secondary)
                .frame(width: 40, height: 40)
        }
    }
}
