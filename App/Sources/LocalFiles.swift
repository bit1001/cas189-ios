import Foundation
import UIKit

/// App 自己的文件目录。
///
/// LiveContainer 环境下 UIDocumentPicker 的回调不返回结果，所以再给一条路：
/// 把文件放进 App 的 Documents（Info.plist 开了 UIFileSharingEnabled 后，
/// 「文件」App 里能看到「我的 iPhone / 189秒传」），或者从「文件」用
/// 「共享 → 用 189秒传 打开」送进来。
enum LocalFiles {

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var inbox: URL {
        documents.appendingPathComponent("Inbox", isDirectory: true)
    }

    static func ensureDirs() {
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    }

    /// Documents 和 Inbox 下的文件（不含目录）
    static func list() -> [URL] {
        ensureDirs()
        var out: [URL] = []
        for dir in [documents, inbox] {
            let items = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in items {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                    out.append(url)
                }
            }
        }
        return out.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func isSupported(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".cas") || name.hasSuffix(".torrent") || name.hasSuffix(".zip")
    }

    /// 把外部（共享/打开方式）进来的 URL 复制进 Inbox，返回本地副本
    @discardableResult
    static func copyIn(_ urls: [URL]) -> [URL] {
        ensureDirs()
        var saved: [URL] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let dst = inbox.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: dst.path) {
                    try FileManager.default.removeItem(at: dst)
                }
                try FileManager.default.copyItem(at: url, to: dst)
                saved.append(dst)
            } catch {
                // 有些源直接就在容器内，不需要复制
                if FileManager.default.fileExists(atPath: url.path) {
                    saved.append(url)
                }
            }
        }
        return saved
    }

    static func sizeText(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
