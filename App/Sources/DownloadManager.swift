import Foundation
import UIKit
import CAS189Core

/// 下载任务状态
enum DownloadStatus: String, Codable {
    case queued, downloading, paused, completed, failed, interrupted

    var label: String {
        switch self {
        case .queued: return "排队中"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .completed: return "完成"
        case .failed: return "失败"
        case .interrupted: return "已中断"
        }
    }
}

/// 一个下载任务
struct DownloadItem: Identifiable, Codable, Equatable {
    var id: UUID
    var fileId: String
    var familyId: String?
    var fileName: String
    var totalBytes: Int64
    var downloadedBytes: Int64
    var status: DownloadStatus
    var destinationPath: String
    var errorMessage: String?
    var taskIdentifier: Int = 0

    var progress: Double {
        totalBytes > 0 ? min(max(Double(downloadedBytes) / Double(totalBytes), 0), 1) : 0
    }

    var destinationURL: URL { URL(fileURLWithPath: destinationPath) }
}

/// 下载管理器：后台 URLSession，App 切到后台/锁屏后继续下载。
/// 任务元数据持久化到 UserDefaults，重启后列表不丢。
/// 注：getAllDownloadTasks 在最新 Xcode 下编不过，任务用内存表登记即可。
final class DownloadManager: NSObject, ObservableObject {

    static let shared = DownloadManager()

    @Published var items: [DownloadItem] = []

    /// AppDelegate 转交的后台会话完成回调
    var backgroundCompletionHandler: (() -> Void)?

    /// 完成/失败时写日志（Store 接）
    var logHandler: ((String) -> Void)?

    private var session: URLSession!
    private let storeKey = "cas189.downloadItems.v1"
    private var lastProgressUpdate: [Int: Date] = [:]
    /// item.id -> 任务（创建时登记，供暂停/继续/取消）
    private var tasks: [UUID: URLSessionDownloadTask] = [:]

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.local.cas189.downloads")
        // 注意：不要给 background 配置赋值 discretionary，最新 Xcode 会编不过；
        // 后台会话默认就是非 discretionary
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        restore()
        reattach()
    }

    // MARK: - 目录

    /// 当前选定的落盘目录（UserDefaults 里存 Documents 下的相对路径）
    static func targetDirectory() -> URL {
        let rel = UserDefaults.standard.string(forKey: "dl.destination") ?? ""
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if rel.isEmpty { return base }
        let url = base.appendingPathComponent(rel, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var destinationName: String {
        let rel = UserDefaults.standard.string(forKey: "dl.destination") ?? ""
        return rel.isEmpty ? "App 文件夹" : rel
    }

    // MARK: - 增删

    func enqueue(client: Cloud189Client,
                 fileId: String,
                 familyId: String?,
                 fileName: String,
                 totalBytes: Int64,
                 destination: URL? = nil) async {
        let dir = destination ?? Self.targetDirectory()
        do {
            let url = try await client.downloadURL(fileId: fileId, familyId: familyId)
            let request = URLRequest(url: url)
            let task = session.downloadTask(with: request)
            var item = DownloadItem(
                id: UUID(),
                fileId: fileId,
                familyId: familyId,
                fileName: fileName,
                totalBytes: totalBytes,
                downloadedBytes: 0,
                status: .downloading,
                destinationPath: dir.path,
                errorMessage: nil
            )
            item.taskIdentifier = task.taskIdentifier
            items.insert(item, at: 0)
            tasks[item.id] = task
            save()
            task.resume()
            logHandler?("开始下载：\(fileName)（→ \(Self.destinationName)）")
        } catch {
            let item = DownloadItem(
                id: UUID(), fileId: fileId, familyId: familyId, fileName: fileName,
                totalBytes: totalBytes, downloadedBytes: 0, status: .failed,
                destinationPath: dir.path,
                errorMessage: error.localizedDescription
            )
            items.insert(item, at: 0)
            save()
            logHandler?("下载失败：\(fileName)（\(error.localizedDescription)）")
        }
    }

    func pause(id: UUID) {
        tasks[id]?.suspend()
        update(id: id) { $0.status = .paused }
    }

    func resume(id: UUID) {
        if let task = tasks[id] {
            task.resume()
            update(id: id) { $0.status = .downloading }
        } else {
            // 任务已不存在（App 重启等）：重新下载
            restart(id: id)
        }
    }

    func cancel(id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        update(id: id) { $0.status = .paused; $0.errorMessage = "已取消" }
    }

    /// 从列表移除（不删已落盘文件）
    func remove(id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        items.removeAll { $0.id == id }
        save()
    }

    /// 清掉已完成/失败/中断的记录
    func clearFinished() {
        items.removeAll { $0.status == .completed || $0.status == .failed || $0.status == .interrupted }
        save()
    }

    /// 重试失败任务
    func retry(id: UUID) {
        restart(id: id)
    }

    // MARK: - 内部

    private var pendingClient: Cloud189Client?

    /// Store 在构造时把自己的 client 挂上来，供重新取直链用
    func attach(client: Cloud189Client) {
        pendingClient = client
    }

    private func restart(id: UUID) {
        update(id: id) {
            $0.status = .queued
            $0.downloadedBytes = 0
            $0.errorMessage = nil
        }
        Task { @MainActor in
            await restartAsync(id: id)
        }
    }

    private func restartAsync(id: UUID) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        guard let client = pendingClient else {
            update(id: id) { $0.status = .failed; $0.errorMessage = "无可用会话，请重新登录后点重试" }
            return
        }
        do {
            let url = try await client.downloadURL(fileId: item.fileId, familyId: item.familyId)
            let task = session.downloadTask(with: URLRequest(url: url))
            update(id: id) {
                $0.status = .downloading
                $0.taskIdentifier = task.taskIdentifier
                $0.downloadedBytes = 0
            }
            tasks[id] = task
            task.resume()
            logHandler?("重新下载：\(item.fileName)")
        } catch {
            update(id: id) { $0.status = .failed; $0.errorMessage = error.localizedDescription }
            logHandler?("下载失败：\(item.fileName)（\(error.localizedDescription)）")
        }
    }

    private func update(id: UUID, mutate: (inout DownloadItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
        save()
    }

    private func item(forTaskIdentifier identifier: Int) -> DownloadItem? {
        items.first(where: { $0.taskIdentifier == identifier })
    }

    // MARK: - 持久化

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return }
        items = decoded
    }

    /// App 重启后，之前 downloading 的任务肯定已经中断（内存表为空）
    private func reattach() {
        var changed = false
        for i in items.indices where items[i].status == .downloading {
            items[i].status = .interrupted
            items[i].errorMessage = "App 重启后中断，可重试"
            changed = true
        }
        if changed { save() }
    }

    private func finishBackgroundIfDone() {
        if tasks.isEmpty {
            backgroundCompletionHandler?()
            backgroundCompletionHandler = nil
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        let now = Date()
        if let last = lastProgressUpdate[id], now.timeIntervalSince(last) < 0.3 { return }
        lastProgressUpdate[id] = now
        DispatchQueue.main.async { [weak self] in
            guard let item = self?.item(forTaskIdentifier: id) else { return }
            self?.update(id: item.id) {
                $0.downloadedBytes = totalBytesWritten
                if totalBytesExpectedToWrite > 0 { $0.totalBytes = totalBytesExpectedToWrite }
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // 关键：临时文件只在 delegate 方法返回前有效，必须同步落盘，
        // 异步跳到别的队列再 move，文件已被系统删掉（“couldn't be moved，
        // either the former doesn't exist”）。
        let id = downloadTask.taskIdentifier
        let http = downloadTask.response as? HTTPURLResponse

        guard let item = item(forTaskIdentifier: id) else { return }

        if let http, http.statusCode == 200 || http.statusCode == 206 {
            // 文件名冲突自动改名
            var dest = item.destinationURL.appendingPathComponent(item.fileName)
            if FileManager.default.fileExists(atPath: dest.path) {
                let base = (item.fileName as NSString).deletingPathExtension
                let ext = (item.fileName as NSString).pathExtension
                var n = 1
                repeat {
                    let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
                    dest = item.destinationURL.appendingPathComponent(name)
                    n += 1
                } while FileManager.default.fileExists(atPath: dest.path)
            }

            var size: Int64 = item.downloadedBytes
            var moveError: Error?
            do {
                try FileManager.default.createDirectory(at: item.destinationURL, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: location, to: dest)
                let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
                size = (attrs?[.size] as? NSNumber)?.int64Value ?? size
            } catch {
                moveError = error
                // 兜底：move 不行试 copy（跨卷时 move 会失败）
                do {
                    try FileManager.default.copyItem(at: location, to: dest)
                    try? FileManager.default.removeItem(at: location)
                    let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
                    size = (attrs?[.size] as? NSNumber)?.int64Value ?? size
                    moveError = nil
                } catch {
                    moveError = error
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.tasks[item.id] = nil
                if let moveError {
                    self.update(id: item.id) {
                        $0.status = .failed
                        $0.errorMessage = "落盘失败：\(moveError.localizedDescription)"
                    }
                    self.logHandler?("落盘失败：\(item.fileName)（\(moveError.localizedDescription)）")
                } else {
                    self.update(id: item.id) {
                        $0.status = .completed
                        $0.downloadedBytes = size
                        if size > 0 { $0.totalBytes = size }
                        $0.errorMessage = nil
                    }
                    self.logHandler?("已下载 \(item.fileName)（\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))）→ \(dest.lastPathComponent)")
                }
                self.finishBackgroundIfDone()
            }
        } else {
            try? FileManager.default.removeItem(at: location)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.tasks[item.id] = nil
                self.update(id: item.id) {
                    $0.status = .failed
                    $0.errorMessage = "HTTP\(http?.statusCode ?? -1)"
                }
                self.logHandler?("下载失败：\(item.fileName)（HTTP\(http?.statusCode ?? -1)）")
                self.finishBackgroundIfDone()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let id = task.taskIdentifier
        DispatchQueue.main.async { [weak self] in
            guard let self, let item = self.item(forTaskIdentifier: id) else { return }
            self.tasks[item.id] = nil
            guard item.status != .completed else { return }
            if (error as NSError).code == NSURLErrorCancelled {
                self.update(id: item.id) { $0.status = .paused; $0.errorMessage = "已取消" }
                return
            }
            self.update(id: item.id) {
                $0.status = .failed
                $0.errorMessage = error.localizedDescription
            }
            self.logHandler?("下载失败：\(item.fileName)（\(error.localizedDescription)）")
            self.finishBackgroundIfDone()
        }
    }
}
