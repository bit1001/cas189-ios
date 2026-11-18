import SwiftUI

/// Short video feed — mirrors ShortVideoFeedScreen (vertical pager + right action rail).
struct ShortVideoView: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var liked: Set<Int> = []
    @State private var playing = true

    private let total = 6
    private let likeColor = Color(hex: 0xFFFE2C55)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(colors: [Color(hex: 0xFF2A1B3D), Color.black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(0..<total, id: \.self) { i in
                    shortCard(index: i).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            topBar
            rightRail
            bottomInfo
        }
    }

    private var topBar: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("退出短视频").font(.caption)
                    }
                }
                Spacer()
                Text("短视频").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("\(index + 1) / \(total)").font(.caption2.monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.top, 8)
            Spacer()
        }
    }

    private func shortCard(index i: Int) -> some View {
        ZStack {
            Image(systemName: "play.rectangle.fill").font(.system(size: 80)).foregroundStyle(.white.opacity(0.08))
            Button {
                playing.toggle()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 40)).foregroundStyle(.white.opacity(0.85))
            }.buttonStyle(.plain)
            .onTapGesture(count: 2) {
                if liked.contains(i) { liked.remove(i) } else { liked.insert(i) }
            }
        }
    }

    private var rightRail: some View {
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(.white.opacity(0.3))
                Text("@作者").font(.caption2).foregroundStyle(.white)
            }
            VStack(spacing: 6) {
                Button {
                    if liked.contains(index) { liked.remove(index) } else { liked.insert(index) }
                } label: {
                    Image(systemName: liked.contains(index) ? "heart.fill" : "heart")
                        .font(.system(size: 40)).foregroundStyle(liked.contains(index) ? likeColor : .white)
                        .rotationEffect(.degrees(liked.contains(index) ? -14 : 0))
                }.buttonStyle(.plain)
                Text("双击收藏").font(.caption2).foregroundStyle(.white.opacity(0.8))
            }
            VStack(spacing: 6) {
                Image(systemName: "speedometer").font(.system(size: 26)).foregroundStyle(.white)
                Text("倍速").font(.caption2).foregroundStyle(.white.opacity(0.8))
            }
            Button { } label: {
                Image(systemName: "lock.open").font(.title3).foregroundStyle(.white)
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 120)
    }

    private var bottomInfo: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("@作者").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                Text("短视频列表，上下滑动切换。双击画面收藏。")
                    .font(.system(size: 15)).foregroundStyle(.white).lineLimit(2)
                ProgressView(value: 0.4).tint(.white.opacity(0.9))
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
    }
}
