import UIKit
import UniformTypeIdentifiers

/// 文件浏览器（进程内 UI，不是跨进程的 document picker）。
///
/// LiveContainer 下 `UIDocumentPickerViewController` 会「弹出 → 关闭 → 0 个文件」，
/// 说明跨进程取结果那条链断了。`UIDocumentBrowserViewController` 的界面和选择逻辑
/// 都在本进程内，只把文件系统访问交给 document provider，兼容性通常更好。
final class DocumentBrowserCoordinator: NSObject, UIDocumentBrowserViewControllerDelegate {

    static var shared: DocumentBrowserCoordinator?

    private var completion: (([URL]) -> Void)?
    private var logger: ((String) -> Void)?
    private var finished = false

    static func pick(allowsMultiple: Bool = true,
                     log: @escaping (String) -> Void,
                     completion: @escaping ([URL]) -> Void) {
        let coordinator = DocumentBrowserCoordinator()
        coordinator.completion = completion
        coordinator.logger = log
        coordinator.finished = false
        shared = coordinator

        let browser = UIDocumentBrowserViewController(forOpeningFilesWithContentTypes: [UTType.item.identifier])
        browser.allowsDocumentCreation = false
        browser.allowsPickingMultipleItems = allowsMultiple
        browser.delegate = coordinator
        browser.modalPresentationStyle = .fullScreen

        guard let host = DocumentPickerCoordinator.topViewController() else {
            log("找不到可用窗口，文件浏览器无法弹出")
            completion([])
            shared = nil
            return
        }
        log("文件浏览器已打开（进程内模式）")
        host.present(browser, animated: true)
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didPickDocumentsAt documentURLs: [URL]) {
        finish(documentURLs)
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didRequestDocumentCreationWithHandler importHandler:
                         @escaping (URL?, UIDocumentBrowserViewController.ImportMode) -> Void) {
        importHandler(nil, .none)
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didImportDocumentAt sourceURL: URL, toDestinationURL destinationURL: URL) {
        finish([destinationURL])
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         failedToImportDocumentAt documentURL: URL, error: Error?) {
        logger?("文件浏览器导入失败：\(error?.localizedDescription ?? "unknown")")
    }

    private func finish(_ urls: [URL]) {
        guard !finished else { return }
        finished = true
        logger?("文件浏览器回调：\(urls.count) 个文件")
        let callback = completion
        completion = nil
        DispatchQueue.main.async {
            callback?(urls)
            DocumentBrowserCoordinator.shared = nil
        }
    }
}
