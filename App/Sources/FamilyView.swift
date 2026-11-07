import SwiftUI
import CAS189Core

/// 家庭云：独立一屏（与个人云是两套接口，分开展示更清楚）
struct FamilyView: View {
    @EnvironmentObject private var store: Store

    @State private var showFolderPrompt = false
    @State private var folderName = ""
    @State private var showUploader = false
    @State private var showCredentialImporter = false

    var body: some View {
        NavigationStack {
            List {
                if store.familyId.isEmpty {
                    Section {
                        Button {
                            Task { await store.loadFamilyRoot() }
                        } label: {
                            Label("连接家庭云", systemImage: "person.2.badge.gearshape")
                        }
                        .disabled(store.familyBusy)
                    } footer: {
                        Text("家庭云用 AccessToken + 签名鉴权，和个人云的 Cookie 通道不同。")
                    }
                } else {
                    Section {
                        Text("空间 ID：\(store.familyId)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Section("目录（\(store.familyFolderId)）") {
                        ForEach(store.familyEntries) { entry in
                            HStack(spacing: 10) {
                                Image(systemName: entry.isFolder ? "folder" : "doc")
                                    .foregroundStyle(entry.isFolder ? .blue : .secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name).lineLimit(1)
                                    if !entry.isFolder {
                                        Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if entry.isFolder {
                                    Button {
                                        Task { await store.familyOpen(entry) }
                                    } label: { Image(systemName: "chevron.right") }
                                        .buttonStyle(.plain)
                                }
                            }
                            .contentShape(Rectangle())
                            .contextMenu {
                                if !entry.isFolder {
                                    Button {
                                        Task { await store.downloadFamily(entry) }
                                    } label: { Label("下载", systemImage: "arrow.down.circle") }
                                    Button {
                                        Task { await store.familyTransferToPersonal(entry) }
                                    } label: { Label("转存到个人云", systemImage: "arrow.uturn.left.circle") }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("家庭云 · \(store.familyFolderName)")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await store.familyGoBack() }
                    } label: { Image(systemName: "chevron.backward") }
                        .disabled(store.familyCrumbs.isEmpty || store.familyBusy)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await store.familyGoRoot() }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(store.familyBusy || store.familyId.isEmpty)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        folderName = ""
                        showFolderPrompt = true
                    } label: { Image(systemName: "folder.badge.plus") }
                        .disabled(store.familyId.isEmpty)
                    Button {
                        showUploader = true
                    } label: { Image(systemName: "square.and.arrow.up") }
                        .disabled(store.familyId.isEmpty)
                    Menu {
                        Button {
                            showCredentialImporter = true
                        } label: { Label("导入秒传凭证", systemImage: "doc.badge.arrow.up") }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .disabled(store.familyId.isEmpty)
                }
            }
            .refreshable { await store.loadFamily(store.familyFolderId) }
            .fileImporter(isPresented: $showCredentialImporter,
                          allowedContentTypes: [.item],
                          allowsMultipleSelection: true) { result in
                if case let .success(urls) = result, !urls.isEmpty {
                    Task { await store.familyImportCredentials(urls) }
                }
            }
            .alert("新建文件夹", isPresented: $showFolderPrompt) {
                TextField("名字", text: $folderName)
                Button("取消", role: .cancel) { }
                Button("创建") { Task { await store.familyMakeFolder(folderName) } }
            }
            .fileImporter(isPresented: $showUploader,
                          allowedContentTypes: [.item],
                          allowsMultipleSelection: true) { result in
                if case let .success(urls) = result, !urls.isEmpty {
                    Task {
                        for url in urls {
                            await store.familyRapidOrUpload(url: url)
                        }
                    }
                }
            }
            .overlay {
                if store.familyBusy {
                    ProgressView().padding(12).background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
    }
}
