import SwiftUI

/// 下载管理页面：后台下载（可切走、锁屏）+ 进度 + 目标目录选择
struct DownloadView: View {
    @ObservedObject var manager = DownloadManager.shared
    @AppStorage("dl.destination") private var destination = ""
    @State private var newFolderName = ""
    @State private var showNewFolder = false
    @State private var showFolderPicker = false

    private var directories: [(String, String)] {
        // (显示名, Documents 下的相对路径 "" = 根)
        var out: [(String, String)] = [("App 文件夹", "")]
        out.append(("Inbox", "Inbox"))
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let items = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for url in items {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                   isDir.boolValue, url.lastPathComponent != "Inbox" {
                    out.append((url.lastPathComponent, url.lastPathComponent))
                }
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack {
                            Label("保存到", systemImage: "folder")
                            Spacer()
                            Text(DownloadManager.destinationName)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("下载在后台进行，切到其他页面或锁屏都会继续；文件落到这个目录（在「文件」App 里也能看到）。")
                }

                if manager.items.isEmpty {
                    Section {
                        Text("还没有下载任务。在「文件」里长按一个文件 → 下载，会加进来。")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                } else {
                    Section {
                        ForEach(manager.items) { item in
                            row(for: item)
                        }
                    } header: {
                        Text("任务（\(manager.items.filter { $0.status == .downloading || $0.status == .queued }.count) 个进行中）")
                    }
                }
            }
            .navigationTitle("下载管理")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("清空已完成/失败") { manager.clearFinished() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showFolderPicker) { folderPicker }
            .sheet(isPresented: $showNewFolder) { newFolderSheet }
        }
    }

    // MARK: - 任务行

    private func row(for item: DownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: statusIcon(for: item))
                    .foregroundStyle(statusColor(for: item))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(statusText(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                actions(for: item)
            }
            if item.status == .downloading || item.status == .paused || item.status == .interrupted {
                ProgressView(value: item.progress)
            }
            if let err = item.errorMessage, item.status == .failed {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusIcon(for item: DownloadItem) -> String {
        switch item.status {
        case .downloading: return "arrow.down.circle.fill"
        case .queued: return "clock"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .interrupted: return "arrow.triangle.2.circlepath"
        }
    }

    private func statusColor(for item: DownloadItem) -> Color {
        switch item.status {
        case .completed: return .green
        case .failed: return .red
        case .downloading: return .blue
        default: return .secondary
        }
    }

    private func statusText(for item: DownloadItem) -> String {
        let size = ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file)
        switch item.status {
        case .downloading:
            let done = ByteCountFormatter.string(fromByteCount: item.downloadedBytes, countStyle: .file)
            return "下载中 \(done) / \(size)（\(Int(item.progress * 100))%）"
        case .queued: return "排队中 \(size)"
        case .paused: return "已暂停"
        case .completed: return "完成 \(size)"
        case .failed: return "失败"
        case .interrupted: return "中断（可重试）"
        }
    }

    @ViewBuilder
    private func actions(for item: DownloadItem) -> some View {
        switch item.status {
        case .downloading:
            HStack(spacing: 14) {
                Button { manager.pause(id: item.id) } label: {
                    Image(systemName: "pause.fill").font(.title3)
                }
                Button { manager.cancel(id: item.id) } label: {
                    Image(systemName: "xmark").font(.title3)
                }
            }
            .foregroundStyle(.secondary)
        case .paused, .interrupted, .failed:
            HStack(spacing: 14) {
                Button { manager.resume(id: item.id) } label: {
                    Image(systemName: "play.fill").font(.title3)
                }
                Button { manager.remove(id: item.id) } label: {
                    Image(systemName: "trash").font(.title3)
                }
            }
            .foregroundStyle(.secondary)
        case .queued, .completed:
            Button { manager.remove(id: item.id) } label: {
                Image(systemName: "trash").font(.title3)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - 目录选择

    private var folderPicker: some View {
        NavigationStack {
            List {
                ForEach(directories, id: \.1) { name, rel in
                    Button {
                        destination = rel
                        showFolderPicker = false
                    } label: {
                        HStack {
                            Label(name, systemImage: "folder")
                            Spacer()
                            if destination == rel {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Button {
                    showFolderPicker = false
                    showNewFolder = true
                } label: {
                    Label("新建文件夹…", systemImage: "folder.fill.badge.plus")
                }
            }
            .navigationTitle("保存到")
        }
    }

    private var newFolderSheet: some View {
        NavigationStack {
            Form {
                TextField("文件夹名称", text: $newFolderName)
                Button("创建并保存到这里") {
                    let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    try? FileManager.default.createDirectory(
                        at: base.appendingPathComponent(name, isDirectory: true),
                        withIntermediateDirectories: true)
                    destination = name
                    newFolderName = ""
                    showNewFolder = false
                }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("新建文件夹")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
