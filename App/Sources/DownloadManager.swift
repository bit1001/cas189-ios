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

/// 下载管理器（骨架版，用于定位编译问题）
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
        config.discretionary = false
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 0
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

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {}
}
