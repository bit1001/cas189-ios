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
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var cookieInput = ""
    @State private var showImporter = false
    @State private var tab = 0
    @State private var showLogin = false

    var body: some View {
        TabView(selection: $tab) {
            loginTab.tabItem { Label("登录", systemImage: "person.crop.circle") }.tag(0)
            browserTab.tabItem { Label("云盘", systemImage: "cloud") }.tag(1)
            logTab.tabItem { Label("日志", systemImage: "doc.text") }.tag(2)
        }
        .overlay(alignment: .top) {
            if store.busy {
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

                Section("目录（\(store.folderId)）") {
                    ForEach(store.entries) { entry in
                        HStack {
                            Image(systemName: entry.isFolder ? "folder" : "doc")
                                .foregroundStyle(entry.isFolder ? .blue : .secondary)
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
                    }
                }
            }
            .navigationTitle("云盘")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await store.load("-11") }
                    } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .refreshable { await store.load(store.folderId) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            switch result {
            case let .success(url):
                Task { await store.rapidUpload(url: url) }
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
