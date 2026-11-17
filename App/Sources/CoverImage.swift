import SwiftUI
import UIKit
import QHCore

/// Cover loader. Most sites serve plain JPEG/PNG; 黑暗抖阴 serves RC4 ciphertext
/// and its hosts use self-signed certs, so AsyncImage cannot be used there.
struct CoverImage: View {
    let path: String?
    let rc4: Bool

    @State private var image: UIImage?
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        ZStack {
            Color.white.opacity(0.06)
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            }
        }
        .clipped()
        .task(id: path) { await load() }
    }

    private func load() async {
        guard let path, let url = URL(string: path) else { return }
        if let hit = Self.cache.object(forKey: path as NSString) {
            image = hit
            return
        }
        do {
            let (data, _) = try await HTTPClient(insecureTLS: true).data(url)
            let bytes = rc4 ? DouyinCrypto.decodeCover(data) : data
            guard let img = UIImage(data: bytes) else { return }
            Self.cache.setObject(img, forKey: path as NSString)
            image = img
        } catch {
            // keep placeholder; a failed cover must not break the row
        }
    }
}
