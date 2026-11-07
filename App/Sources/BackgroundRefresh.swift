import Foundation
import BackgroundTasks

/// 后台刷新：iOS 会在合适时机唤起 App（频率由系统决定，不保证 30 分钟一次）。
enum BackgroundRefresh {

    /// 必须和 Info.plist 的 BGTaskSchedulerPermittedIdentifiers 完全一致
    static let taskID = "com.local.cas189.refresh"

    static func schedule(earliest: TimeInterval = 30 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliest)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // 模拟器 / 未授权时为正常现象，不打扰用户
            #if DEBUG
            print("[bg] 提交失败：\(error.localizedDescription)")
            #endif
        }
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
    }
}
