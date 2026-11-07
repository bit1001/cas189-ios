import UIKit
import SwiftUI
import UniformTypeIdentifiers
import CAS189Core

@main
struct CAS189App: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskID)) {
            await store.backgroundRefresh()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.scenePhase) private var scenePhase
    @State private var cookieInput = ""
    @State private var showImporter = false
    @State private var tab = 0
    @State private var showLogin = false
    @State private var renameTarget: CloudEntry?
    @State private var renameText = ""
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    var body: some View {
        TabView(selection: $tab) {
            loginTab.tabItem { Label("登录", systemImage: "person.crop.circle") }.tag(0)
            browserTab.tabItem { Label("云盘", systemImage: "cloud") }.tag(1)
            logTab.tabItem { Label("日志", systemImage: "doc.text") }.tag(2)
        }
        .overlay(alignment: .top) {
            if store.uploadProgress > 0 || !store.uploadLabel.isEmpty {
                VStack(spacing: 6) {
                    Text("\(store.uploadLabel)  \(Int(store.uploadProgress * 100))%")
                        .font(.caption)
                    ProgressView(value: store.uploadProgress)
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            } else if store.busy {
                ProgressView().padding(6).background(.ultraThinMaterial, in: Capsule()).padding(.top, 8)
            }
        }
    }

    // MARK: - 登录

    private var loginTab: some View {
        NavigationStack {
            Form {
                Section {
                    if store.session.isLoggedIn {
                        LabeledContent("账号", value: store.session.loginName)
                        LabeledContent("会话", value: "有效")
                    } else {
                        Text("未登录").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("状态")
                }

                Section {
                    Button {
                        showLogin = true
                    } label: {
                        Label("通过网页登录（推荐）", systemImage: "safari")
                    }
                    .disabled(store.busy)
                } footer: {
                    Text("在内嵌的官方登录页里扫码或输账号密码。登录成功后自动读取会话 cookie，不需要抓包、不需要装证书。")
                }

                if store.session.isLoggedIn {
                    Section {
                        Button("退出登录", role: .destructive) { store.logout() }
                    }
                }

                Section {
                    DisclosureGroup("高级：手动粘贴 Cookie") {
                        TextEditor(text: $cookieInput)
                            .frame(minHeight: 100)
                            .font(.footnote.monospaced())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button("使用 Cookie 登录") {
                            Task { await store.login(cookie: cookieInput) }
                        }
                        .disabled(cookieInput.isEmpty || store.busy)
                    }
                } footer: {
                    Text("只在网页登录不可用时使用。需要包含 COOKIE_LOGIN_USER。")
                }

                if let error = store.errorText {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("189 秒传")
            .sheet(isPresented: $showLogin) {
                LoginSheet { cookie in
                    Task { await store.login(cookie: cookie) }
                }
            }
        }
    }

    // MARK: - 云盘

    private var browserTab: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("选择本地文件秒传", systemImage: "arrow.up.doc")
                    }
                    .disabled(!store.session.isLoggedIn || store.busy)
                } footer: {
                    Text("会对文件做 10MB 分片 MD5，再用 initMultiUpload / commitMultiUploadFile 判定秒传。")
                }

                Section(store.searchText.isEmpty ? "目录（\(store.folderId)）" : "搜索结果（\(store.searchResults.count)）") {
                    ForEach(store.searchText.isEmpty ? store.entries : store.searchResults) { entry in
                        HStack {
                            if let icon = entry.iconURL, let url = URL(string: icon) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case let .success(img):
                                        img.resizable().scaledToFill()
                                    default:
                                        Color.secondary.opacity(0.15)
                                    }
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: entry.isFolder ? "folder" : "doc")
                                    .foregroundStyle(entry.isFolder ? .blue : .secondary)
                            }
                            VStack(alignment: .leading) {
                                Text(entry.name).lineLimit(1)
                                if !entry.isFolder {
                                    Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if entry.isFolder {
                                Button {
                                    Task { await store.load(entry.id) }
                                } label: { Image(systemName: "chevron.right") }
                                    .buttonStyle(.plain)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if !entry.isFolder {
                                Button {
                                    Task { await store.download(entry) }
                                } label: { Label("下载", systemImage: "arrow.down.circle") }
                            }
                            Button {
                                Task { await store.createShare(for: entry) }
                            } label: { Label("创建分享链接", systemImage: "square.and.arrow.up") }
                            Button(role: .destructive) {
                                Task { await store.delete(entry) }
                            } label: { Label("删除", systemImage: "trash") }
                        }
                        .contextMenu {
                            Button {
                                renameTarget = entry
                                renameText = entry.name
                            } label: { Label("重命名", systemImage: "pencil") }
                            Button {
                                Task { await store.createShare(for: entry) }
                            } label: { Label("创建分享链接", systemImage: "square.and.arrow.up") }
                            Button(role: .destructive) {
                                Task { await store.delete(entry) }
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
            }
            .navigationTitle(store.downloadLabel.isEmpty ? "云盘" : store.downloadLabel)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await store.load("-11") }
                    } label: { Image(systemName: "arrow.clockwise") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newFolderName = ""
                        showNewFolder = true
                    } label: { Image(systemName: "folder.badge.plus") }
                }
            }
            .refreshable { await store.load(store.folderId) }
            .searchable(text: $store.searchText, prompt: "搜索云盘（递归 3 层）")
            .onSubmit(of: .search) {
                Task { await store.search(store.searchText) }
            }
            .onChange(of: store.searchText) { newValue in
                if newValue.isEmpty { store.searchResults = [] }
            }
            .alert("重命名", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("新名字", text: $renameText)
                Button("取消", role: .cancel) { renameTarget = nil }
                Button("确定") {
                    if let target = renameTarget {
                        Task { await store.rename(target, to: renameText) }
                    }
                    renameTarget = nil
                }
            }
            .sheet(item: Binding(
                get: { store.downloadedFile.map { ShareSheetItem(url: $0) } },
                set: { if $0 == nil { store.clearDownload() } }
            )) { item in
                ActivityView(items: [item.url])
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background { BackgroundRefresh.schedule() }
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
            .alert("登录已过期", isPresented: $store.needsRelogin) {
                Button("重新登录") {
                    store.relogin()
                    showLogin = true
                }
                Button("稍后", role: .cancel) { store.needsRelogin = false }
            } message: {
                Text("天翼云盘会话失效，请重新登录后重试。")
            }
            .alert("新建文件夹", isPresented: $showNewFolder) {
                TextField("名字", text: $newFolderName)
                Button("取消", role: .cancel) { }
                Button("创建") {
                    Task { await store.makeFolder(newFolderName) }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case let .success(urls):
                if urls.count == 1 {
                    Task { await store.rapidUpload(url: urls[0]) }
                } else if !urls.isEmpty {
                    Task { await store.uploadMany(urls) }
                }
            case let .failure(error):
                store.errorText = error.localizedDescription
            }
        }
    }

    // MARK: - 日志

    private var logTab: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(store.logs.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .navigationTitle("日志")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空") { store.logs.removeAll() }
                }
            }
        }
    }
}
