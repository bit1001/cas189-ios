import Foundation
import UIKit
import CAS189Core

/// 下载任务状态
enum DownloadStatus: String, Codable {
    case queued, downloading, paused, completed, failed, interrupted
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

/// 下载管理器（骨架版 3，用于定位编译问题）
final class DownloadManager: NSObject, ObservableObject {

    static let shared = DownloadManager()

    @Published var items: [DownloadItem] = []

    var backgroundCompletionHandler: (() -> Void)?
    var logHandler: ((String) -> Void)?

    private var session: URLSession!
    private let storeKey = "cas189.downloadItems.v1"
    private var lastProgressUpdate: [Int: Date] = [:]

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.local.cas189.downloads")
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        restore()
        reattach()
    }

    static func targetDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var destinationName: String { "App 文件夹" }

    func attach(client: Cloud189Client) {}

    private func restore() {}
    private func reattach() {}
    private func save() {}

    func enqueue(client: Cloud189Client, fileId: String, familyId: String?,
                 fileName: String, totalBytes: Int64, destination: URL? = nil) async {}
    func pause(id: UUID) {}
    func resume(id: UUID) {}
    func cancel(id: UUID) {}
    func remove(id: UUID) {}
    func clearFinished() {}
    func retry(id: UUID) {}
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        let now = Date()
        // 节流：同一任务 0.3s 内最多刷一次 UI
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
        let id = downloadTask.taskIdentifier
        DispatchQueue.main.async { [weak self] in
            guard let self, var item = self.item(forTaskIdentifier: id) else { return }
            let http = downloadTask.response as? HTTPURLResponse

            guard let http, http.statusCode == 200 || http.statusCode == 206 else {
                self.update(id: item.id) {
                    $0.status = .failed
                    $0.errorMessage = "HTTP\(http?.statusCode ?? -1)"
                }
                self.logHandler?("下载失败：\(item.fileName)（HTTP\(http?.statusCode ?? -1)）")
                try? FileManager.default.removeItem(at: location)
                self.finishBackgroundIfDone()
                return
            }

            // 落盘（同名文件加序号，不覆盖）
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
            do {
                try FileManager.default.createDirectory(at: item.destinationURL, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: location, to: dest)
                let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? item.downloadedBytes
                self.update(id: item.id) {
                    $0.status = .completed
                    $0.downloadedBytes = size
                    if size > 0 { $0.totalBytes = size }
                    $0.errorMessage = nil
                }
                self.logHandler?("已下载 \(item.fileName)（\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))）→ \(dest.lastPathComponent)")
                _ = item
            } catch {
                self.update(id: item.id) {
                    $0.status = .failed
                    $0.errorMessage = "落盘失败：\(error.localizedDescription)"
                }
                self.logHandler?("落盘失败：\(item.fileName)（\(error.localizedDescription)）")
            }
            self.finishBackgroundIfDone()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let id = task.taskIdentifier
        DispatchQueue.main.async { [weak self] in
            guard let self, let item = self.item(forTaskIdentifier: id) else { return }
            // 已完成的不再覆盖（didFinishDownloadingTo 先到）
            guard item.status != .completed else { return }
            // 用户主动取消的不算失败
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
