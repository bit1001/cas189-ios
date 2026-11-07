import UIKit
import UniformTypeIdentifiers

/// 原生文档选择器。
///
/// SwiftUI 的 `.fileImporter` 在这个 App 里始终不回调（点了「打开」毫无反应，
/// 连错误都没有）。直接拿 UIDocumentPickerViewController 从 keyWindow 的
/// topViewController 上 present，绕开 SwiftUI 的弹窗管理。
final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {

    /// 需要强引用：picker 只弱引用 delegate
    static var shared: DocumentPickerCoordinator?

    private var completion: (([URL]) -> Void)?
    private var finished = false

    /// 选择文件（异步回主线程回调；取消时回调空数组）
    static func pickFiles(allowsMultiple: Bool = true,
                          completion: @escaping ([URL]) -> Void) {
        let coordinator = DocumentPickerCoordinator()
        coordinator.completion = completion
        coordinator.finished = false
        shared = coordinator

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        picker.delegate = coordinator

        guard let host = topViewController() else {
            completion([])
            shared = nil
            return
        }
        host.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        finish(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish([])
    }

    private func finish(_ urls: [URL]) {
        guard !finished else { return }
        finished = true
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
