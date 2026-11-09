import UIKit
import UniformTypeIdentifiers

/// 打开系统文件选择器（打开模式）。
///
/// 关键点（踩过的坑）：
/// - **用独立 UIWindow 呈现**。`UIDocumentPickerViewController` 在呈现 VC 处于复杂层级时
///   会出现「弹出 → 点文件 → 关闭，但 delegate 永不触发」的静默失败（已知 UIKit 行为，
///   直接安装也会复现，与 LiveContainer 等宿主环境无关）。SwiftUI 的托管根视图 +
///   `presentedViewController` 链正是复杂层级。社区验证过的绕行：建一个专用的
///   `UIWindow(windowLevel: .alert)`，用空白 UIViewController 呈现选择器。
/// - **用 asCopy: false（打开模式）**：直接返回 security-scoped URL，不复制到 TMPDIR，
///   不依赖宿主环境改过的临时目录；本 App 只读文件，不需要回写。
/// - picker 的 delegate 是弱引用，必须强引用 coordinator；专用窗口同样强引用，
///   在结果回调后拆掉并把 key 恢复给主窗口。
/// - 用 KVO 监听 `picker.view.window` 判断「面板关了但没回调」（安全网，避免界面卡住），
///   因此不再需要子类化选择器。
final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {

    static var current: DocumentPickerCoordinator?

    private var completion: (([URL]) -> Void)?
    private var logger: ((String) -> Void)?
    private var window: UIWindow?
    private var windowObservation: NSKeyValueObservation?
    private var finished = false

    static func pickFiles(allowsMultiple: Bool = true,
                          log: @escaping (String) -> Void,
                          completion: @escaping ([URL]) -> Void) {
        let coordinator = DocumentPickerCoordinator()
        coordinator.completion = completion
        coordinator.logger = log
        current = coordinator

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        picker.delegate = coordinator

        // 独立窗口呈现，避开复杂层级。
        // 构造时必须带上当前 scene，否则 iOS 13+ 下窗口不挂在任何 scene 上，
        // 不渲染，picker 根本不出现。
        let scene = (UIApplication.shared.connectedScenes.first {
            $0.activationState == .foregroundActive
        } ?? UIApplication.shared.connectedScenes.first) as? UIWindowScene
        let window: UIWindow
        if let scene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        let host = UIViewController()
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.windowLevel = .alert
        coordinator.window = window
        window.makeKeyAndVisible()

        // 面板关闭但没有 delegate 回调时兜底
        coordinator.windowObservation = picker.view.observe(\.window) { [weak coordinator] view, _ in
            if view.window == nil {
                coordinator?.pickerVanished()
            }
        }

        let hasScene = window.windowScene != nil
        let isKey = window.isKeyWindow
        logger?("专用窗口已挂载：有scene=\(hasScene)，isKeyWindow=\(isKey)")
        log("选择器已弹出（独立窗口，打开模式，可多选）")
        host.present(picker, animated: false)
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
        logger?("选择器已关闭，但系统没返回文件（面板关闭但 delegate 未触发）")
    }

    private func finish(_ urls: [URL], reason: String) {
        guard !finished else { return }
        finished = true
        logger?("选择器回调：\(reason)，\(urls.count) 个文件")
        let callback = completion
        completion = nil
        DispatchQueue.main.async {
            callback?(urls)
            DocumentPickerCoordinator.current?.tearDown()
            DocumentPickerCoordinator.current = nil
        }
    }

    /// 拆掉专用窗口，把 key 恢复给主窗口
    private func tearDown() {
        windowObservation?.invalidate()
        windowObservation = nil
        if let ownWindow = window {
            let scene = ownWindow.windowScene
            let others = (scene?.windows ?? UIApplication.shared.windows).filter { $0 !== ownWindow }
            (others.first(where: { $0.isKeyWindow }) ?? others.first)?.makeKey()
            window = nil
        }
    }
}
