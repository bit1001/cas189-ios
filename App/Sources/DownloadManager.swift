import Foundation
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

/// 下载管理器（骨架版，用于定位编译问题）
final class DownloadManager: NSObject, ObservableObject {

    static let shared = DownloadManager()

    @Published var items: [DownloadItem] = []

    private override init() {
        super.init()
    }
}
