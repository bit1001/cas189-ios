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
    @State private var showLogin = false
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            loginTab.tabItem { Label("登录", systemImage: "person.crop.circle") }.tag(0)
            BrowserView().tabItem { Label("文件", systemImage: "folder") }.tag(1)
            TransferView().tabItem { Label("导入", systemImage: "arrow.down.doc") }.tag(2)
            logTab.tabItem { Label("日志", systemImage: "doc.text") }.tag(3)
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
                ProgressView().padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { BackgroundRefresh.schedule() }
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
                    Text("在内嵌的官方登录页里扫码或输账号密码。登录后自动读取会话 cookie。验证码拖不动时，点右上角地球图标切「手机版页面」。")
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

    // MARK: - 日志

    private var logTab: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(store.logs.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
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
