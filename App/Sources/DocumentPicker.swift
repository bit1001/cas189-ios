import UIKit
import UniformTypeIdentifiers

/// 原生文档选择器封装。
///
/// 关键点：
/// - **用 asCopy: true（导入模式）**。`asCopy: false` 需要文件提供者返回可书签化的
///   security-scoped URL；在 LiveContainer 这类虚拟容器里这一步可能静默失败，
///   表现为面板能弹出、点「打开」后 delegate 从不触发。导入模式由系统把文件复制到
///   本 App 沙盒，不走那条链路。
/// - picker 只弱引用 delegate，必须自己强引用 coordinator。
/// - 子类监听 viewDidDisappear：面板关了却没收到任何 delegate 回调时写日志并回调空结果，
///   避免界面永远卡住，也能区分「系统没回结果」和「我们不处理」。
final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {

    static var shared: DocumentPickerCoordinator?

    private var completion: (([URL]) -> Void)?
    private var logger: ((String) -> Void)?
    private var finished = false

    static func pickFiles(allowsMultiple: Bool = true,
                          log: @escaping (String) -> Void,
                          completion: @escaping ([URL]) -> Void) {
        let coordinator = DocumentPickerCoordinator()
        coordinator.completion = completion
        coordinator.logger = log
        coordinator.finished = false
        shared = coordinator

        // asCopy: true —— 导入模式，由系统把文件复制进沙盒
        let picker = LoggingDocumentPicker(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        picker.delegate = coordinator
        picker.onDisappear = { [weak coordinator] in
            coordinator?.pickerVanished()
        }

        guard let host = topViewController() else {
            log("找不到可用窗口，选择器无法弹出")
            completion([])
            shared = nil
            return
        }
        log("选择器已弹出（导入模式，可多选）")
        host.present(picker, animated: true)
    }

    // MARK: - Delegate

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        finish(urls, reason: "didPickDocumentsAt")
    }

    /// 部分系统版本在单选时只调这个旧方法
    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentAt url: URL) {
        finish([url], reason: "didPickDocumentAt")
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish([], reason: "cancelled")
    }

    /// 面板消失但没有任何 delegate 回调
    fileprivate func pickerVanished() {
        guard !finished else { return }
        finish([], reason: "vanished")
        logger?("选择器已关闭，但系统没返回文件")
    }

    private func finish(_ urls: [URL], reason: String) {
        guard !finished else { return }
        finished = true
        logger?("选择器回调：\(reason)，\(urls.count) 个文件")
        let callback = completion
        completion = nil
        DispatchQueue.main.async {
            callback?(urls)
            DocumentPickerCoordinator.shared = nil
        }
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
            ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

private final class LoggingDocumentPicker: UIDocumentPickerViewController {
    var onDisappear: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDisappear?()
    }
}
