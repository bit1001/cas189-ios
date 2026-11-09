import Foundation
import UIKit
import CAS189Core

enum DownloadStatus: String, Codable {
    case queued, downloading, paused, completed, failed, interrupted
}

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

/// 下载管理器（半 A2 bisect：桩化 JSON/getAllDownloadTasks）
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

    func enqueue(client: Cloud189Client, fileId: String, familyId: String?,
                 fileName: String, totalBytes: Int64, destination: URL? = nil) async {}
    func pause(id: UUID) {}
    func resume(id: UUID) {}
    func cancel(id: UUID) {}
    func remove(id: UUID) {}
    func clearFinished() {}
    func retry(id: UUID) {}

    private func restart(id: UUID) {}
    private var pendingClient: Cloud189Client?

    func attach(client: Cloud189Client) {
        pendingClient = client
    }

    private func restartAsync(id: UUID) async {}

    private func removeLocalPartial(_ item: DownloadItem) {}

    private func update(id: UUID, mutate: (inout DownloadItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
        save()
    }

    private func item(forTaskIdentifier identifier: Int) -> DownloadItem? {
        items.first(where: { $0.taskIdentifier == identifier })
    }

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
    private func reattach() {
        session.getAllDownloadTasks { _ in }
    }
    private func finishBackgroundIfDone() {}
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {}
}
