import SwiftUI

/// Player UI — mirrors VideoPlayerScreen HUD (no real playback; visual replica).
/// iOS 16 compatible. Overlay HUD with top bar, center controls, bottom footer.
struct PlayerScreen: View {
    let title: String
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = true
    @State private var playing = false
    @State private var progress: Double = 0.32
    @State private var showDetails = false
    @State private var showCast = false
    @State private var locked = false
    @State private var speed = 1.0

    private let accentPink = Color(hex: 0xFFFF2D55)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(colors: [Color(hex: 0xFF1A1A2E), Color.black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Image(systemName: "film").font(.system(size: 64)).foregroundStyle(.white.opacity(0.12))

            if showControls {
                VStack {
                    topBar
                    Spacer()
                    centerRow
                    Spacer()
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .transition(.opacity)
            }

            if !showControls {
                Button { withAnimation { showControls = true } } label: {
                    Color.clear.contentShape(Rectangle())
                }
            }
        }
        .ignoresSafeArea()
        .onTapGesture { withAnimation { showControls.toggle() } }
        .sheet(isPresented: $showDetails) { WatchDetailsSheet() }
        .sheet(isPresented: $showCast) { CastSheet() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.title3) }
            Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Spacer()
            Group {
                Button { locked.toggle() } label: {
                    Image(systemName: locked ? "lock" : "lock.open")
                }
                Button { showCast = true } label: { Image(systemName: "airplayvideo") }
                Button { showDetails = true } label: { Image(systemName: "ellipsis") }
            }
            .font(.title3)
        }
        .foregroundStyle(.white)
    }

    private var centerRow: some View {
        HStack(spacing: 12) {
            Button { } label: { Image(systemName: "backward.end.fill").font(.title2) }
            Button { } label: { Image(systemName: "gobackward.10").font(.title).foregroundStyle(.white) }
            Button { playing.toggle() } label: {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(hex: 0xFFFF6EC7), Color(hex: 0xFFFF2D55)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.title2).foregroundStyle(.white)
                }
            }
            Button { } label: { Image(systemName: "goforward.10").font(.title).foregroundStyle(.white) }
            Button { } label: { Image(systemName: "forward.end.fill").font(.title2) }
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                Text("00:32").font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                Slider(value: $progress, in: 0...1)
                    .tint(accentPink)
                Text("01:40").font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
            }
            HStack(spacing: 20) {
                Button { } label: { Image(systemName: "speaker.wave.2.fill") }
                Menu {
                    ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { s in
                        Button { speed = s } label: { Text("\(s, specifier: "%.1f")x") }
                    }
                } label: { Text("\(speed, specifier: "%.1f")x").font(.caption) }
                Spacer()
                Text("高清").font(.caption2).foregroundStyle(.white.opacity(0.7))
                Button { } label: { Image(systemName: "rectangle.fill.on.rectangle.fill") }
            }
            .foregroundStyle(.white)
        }
    }
}

private struct WatchDetailsSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("简介").font(.headline).foregroundStyle(p.textPrimary)
                    Text("这是一段用于界面演示的占位简介。播放器支持单击显隐控制、双击快退/播放/快进、横滑调节进度。")
                        .font(.subheadline).foregroundStyle(p.textSecondary)
                    HStack {
                        Button("上一条") {}.font(.caption)
                        Spacer()
                        Button("下一条") {}.font(.caption)
                    }
                }.padding(20)
            }
            .navigationTitle("观看详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }
}

private struct CastSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "airplayvideo").font(.system(size: 44)).foregroundStyle(p.accentPrimary)
                Text("选择投屏设备").font(.headline).foregroundStyle(p.textPrimary)
                Text("通过手机的无线投屏连接电视。可用设备由系统提供。")
                    .font(.caption).foregroundStyle(p.textSecondary).multilineTextAlignment(.center)
            }.padding(30)
            .navigationTitle("TV 投屏").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }
}
