import SwiftUI
import AVKit
import QHCore

@MainActor
final class PlayerModel: ObservableObject {
    enum Phase {
        case loading(done: Int, total: Int)
        case ready
        case failed(String)
    }

    @Published var phase: Phase = .loading(done: 0, total: 0)
    @Published var player: AVPlayer?

    private let video: SiteVideo
    private var started = false

    init(video: SiteVideo) {
        self.video = video
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        Task { await load() }
    }

    func stop() { player?.pause() }

    private func load() async {
        do {
            let adapter = try SiteRegistry.adapter(for: video.site)
            let url = try await adapter.playURL(videoID: video.id)

            if !SiteRegistry.requiresLocalDecrypt(video.site) {
                // Plain HLS (PornShop family / THDH / JAVHD): AVPlayer streams it directly.
                let p = AVPlayer(url: url)
                p.play()
                player = p
                phase = .ready
                return
            }

            // Encrypted-with-custom-key sources: download, decrypt, then play locally.
            let http = HTTPClient(insecureTLS: true)
            let text = try await http.text(url)
            let playlist = try HLSPlaylist.parse(text, base: url)
            let data = try await HLSDownloader(http: http).download(
                playlist: playlist,
                playlistURL: url,
                applyJpegXor: video.site == "haijiao"
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.phase = .loading(done: progress.completed, total: progress.total)
                }
            }
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("qh-\(video.site)-\(video.id).ts")
            try data.write(to: file, options: .atomic)
            let p = AVPlayer(url: file)
            p.play()
            player = p
            phase = .ready
        } catch {
            phase = .failed("\(error)")
        }
    }
}

struct PlayerView: View {
    @StateObject private var model: PlayerModel
    @Environment(\.dismiss) private var dismiss

    init(video: SiteVideo) {
        _model = StateObject(wrappedValue: PlayerModel(video: video))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.phase {
            case .loading(let done, let total):
                VStack(spacing: 14) {
                    ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                        .tint(.orange)
                        .frame(width: 220)
                    Text(total > 0 ? "缓存中 \(done)/\(total)" : "解析视频…")
                        .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    Button("取消") { dismiss() }.tint(.orange)
                }
            case .ready:
                if let player = model.player {
                    PlayerSurface(player: player).ignoresSafeArea()
                }
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text(message).font(.footnote).multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.75)).padding(.horizontal, 24)
                    Button("关闭") { dismiss() }.tint(.orange)
                }
            }
        }
        .onAppear { model.startIfNeeded() }
        .onDisappear { model.stop() }
    }
}

struct PlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.player = player
    }
}
