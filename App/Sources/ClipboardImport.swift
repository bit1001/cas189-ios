import UIKit
import UniformTypeIdentifiers

/// 从剪贴板取文件。
///
/// 用法：在「文件」App 里长按文件 → 拷贝，回到本 App 点「从剪贴板导入」。
/// 文件 App 会把文件 URL 放进 UIPasteboard 的 itemProviders；
/// `loadFileRepresentation` 在**回调期间**给出一个临时 URL，必须当场复制走。
/// 全程不走 document picker，所以在 LiveContainer 里也能用。
enum ClipboardImport {

    static func takeFiles(completion: @escaping ([URL]) -> Void) {
        let board = UIPasteboard.general

        // 有些情况下剪贴板里是纯 file URL（比如从别的 App 复制路径）
        if let direct = board.url, direct.isFileURL,
           FileManager.default.fileExists(atPath: direct.path) {
            LocalFiles.ensureDirs()
            let dst = LocalFiles.inbox.appendingPathComponent(direct.lastPathComponent)
            try? FileManager.default.removeItem(at: dst)
            if (try? FileManager.default.copyItem(at: direct, to: dst)) != nil {
                completion([dst])
                return
            }
        }

        let providers = board.itemProviders
        guard !providers.isEmpty else {
            completion([])
            return
        }

        LocalFiles.ensureDirs()
        let group = DispatchGroup()
        let lock = NSLock()
        var saved: [URL] = []

        for provider in providers {
            let types = provider.registeredTypeIdentifiers
            guard let type = types.first(where: {
                $0 == UTType.data.identifier
                    || $0 == UTType.item.identifier
                    || $0 == UTType.zip.identifier
                    || $0.contains("cas")
                    || $0.contains("torrent")
            }) ?? types.first else { continue }

            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                let dst = LocalFiles.inbox.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: dst)
                if (try? FileManager.default.copyItem(at: url, to: dst)) != nil {
                    lock.lock()
                    saved.append(dst)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            completion(saved)
        }
    }
}
