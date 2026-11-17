import SwiftUI
import AVKit
import QHCore

@MainActor
final class PlayerModel: ObservableObject {
    enum Phase {
        case loading(done: Int, total: Int)
        case ready(URL)
        case failed(String)
    }

    @Published var phase: Phase = .loading(done: 0, total: 0)
    @Published var player: AVPlayer?

    private let topicId: Int
    private let attachment: Attachment
    private var started = false

    init(topicId: Int, attachment: Attachment) {
        self.topicId = topicId
        self.attachment = attachment
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        Task { await load() }
    }

    func stop() {
        player?.pause()
    }

    private func load() async {
        do {
            guard let playlistURL = URL(string: attachment.url) else {
                throw QHError.api("bad playlist url")
            }
            let http = HTTPClient()
            let text = try await http.text(playlistURL)
            let playlist = try HLSPlaylist.parse(text, base: playlistURL)
            let data = try await HLSDownloader(http: http).download(
                playlist: playlist,
                playlistURL: playlistURL
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.phase = .loading(done: progress.completed, total: progress.total)
                }
            }
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("qh-\(topicId)-\(attachment.id).ts")
            try data.write(to: file, options: .atomic)
            let item = AVPlayerItem(url: file)
            let p = AVPlayer(playerItem: item)
            p.play()
            player = p
            phase = .ready(file)
        } catch {
            phase = .failed("\(error)")
        }
    }
}

/// v1 playback strategy: download + decrypt the HLS stream with QHCore, then hand
/// the resulting local MPEG-TS file to AVPlayer. This sidesteps AVPlayer's inability
/// to apply Haijiao's key transform (raw key XOR jpg material) during streaming.
/// A later version can serve a rewritten playlist from a local HTTP proxy.
struct PlayerView: View {
    @StateObject private var model: PlayerModel
    @Environment(\.dismiss) private var dismiss

    init(topicId: Int, attachment: Attachment) {
        _model = StateObject(wrappedValue: PlayerModel(topicId: topicId, attachment: attachment))
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
                    PlayerSurface(player: player)
                        .ignoresSafeArea()
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
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.player = player
    }
}
