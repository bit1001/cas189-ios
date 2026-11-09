import SwiftUI

/// 收到「用本 App 打开」的文件后弹出：选处理方式（文件上传 / cas 凭证秒传）+
/// 目标空间 + 目标目录，再开始处理。
/// 文件已经复制进 Inbox，关闭界面后仍可从「导入」Tab 的 App 文件夹里处理。
struct IncomingImportView: View {
    @EnvironmentObject private var store: Store
    let files: [URL]
    var onDone: () -> Void

    private enum Mode: String, CaseIterable {
        case upload = "文件上传"
        case credentials = "cas 秒传"
    }

    @State private var mode: Mode = .credentials
    @State private var space: CloudSpace = .personal
    @State private var folderId = "-11"
    @State private var folderName = "根目录"
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(files, id: \.self) { url in
                        HStack {
                            Image(systemName: LocalFiles.isSupported(url) ? "shippingbox" : "doc")
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent).lineLimit(2)
                            Spacer()
                            Text(LocalFiles.sizeText(url))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if files.count > 1 {
                        Text("\(files.count) 个文件")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("已接收文件")
                }

                Section {
                    Picker("处理方式", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("处理方式")
                } footer: {
                    Text(mode == .upload
                        ? "把文件本身上传到云盘（先试秒传，未命中再真实上传）。"
                        : "把文件当作 .cas / .torrent / .zip 凭证秒传，不上传文件内容。zip 会自动建同名文件夹。")
                }

                Section {
                    Picker("目标空间", selection: $space) {
                        Text("个人云").tag(CloudSpace.personal)
                        Text("家庭云").tag(CloudSpace.family)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: space) { newValue in
                        folderId = "-11"
                        folderName = "根目录"
                        if newValue == .family {
                            Task { await store.ensureFamilyReady() }
                        }
                    }
                    Button {
                        showFolderPicker = true
                    } label: {
                        LabeledContent("目标目录", value: folderName)
                    }
                } header: {
                    Text("目标位置")
                }

                Section {
                    Button {
                        start()
                    } label: {
                        Label(startTitle, systemImage: mode == .upload ? "arrow.up.doc" : "shippingbox")
                    }
                    .disabled(store.busy || files.isEmpty)
                }
            }
            .navigationTitle("处理接收到的文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onDone() }
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView(space: space) { id, name in
                    folderId = id
                    folderName = name
                }
            }
        }
    }

    private var startTitle: String {
        switch (mode, space) {
        case (.upload, .personal): return "上传到个人云"
        case (.upload, .family): return "上传到家庭云"
        case (.credentials, .personal): return "秒传到个人云"
        case (.credentials, .family): return "秒传到家庭云"
        }
    }

    private func start() {
        let urls = files
        let target = folderId
        let mode = self.mode
        let space = self.space
        onDone()
        Task { @MainActor in
            switch mode {
            case .upload:
                await store.uploadTo(urls, space: space, folderId: target)
            case .credentials:
                await store.importCredentialsTo(urls, space: space, folderId: target)
            }
        }
    }
}
