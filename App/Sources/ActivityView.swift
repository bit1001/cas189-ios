import SwiftUI
import UIKit

/// 系统分享面板（下载完保存到「文件」/ AirDrop / 发微信）
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 包一层，方便 .sheet(item:) 使用
struct ShareSheetItem: Identifiable {
    let id = UUID()
    let url: URL
}
