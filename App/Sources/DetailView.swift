import SwiftUI
import QHCore

struct VideoDetailView: View {
    let video: SiteVideo
    @Environment(\.palette) private var p
    @State private var playing = false
    @State private var shortFeed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CoverImage(path: video.cover, rc4: video.site == "douyin")
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(video.title).font(.title3.bold()).foregroundStyle(p.textPrimary)

                HStack(spacing: 12) {
                    if !video.author.isEmpty {
                        Text(video.author).font(.footnote).foregroundStyle(p.textSecondary)
                    }
                    if video.views > 0 {
                        Text("\(video.views) 次观看").font(.footnote).foregroundStyle(p.textSecondary)
                    }
                    if let d = video.durationText {
                        Text(d).font(.footnote).foregroundStyle(p.textSecondary)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        playing = true
                    } label: {
                        Label("播放", systemImage: "play.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(p.badgeText)
                            .background(p.accentPrimary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        shortFeed = true
                    } label: {
                        Label("短视频", systemImage: "mobile.view")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(p.textPrimary)
                            .background(p.cardSurface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("简介").font(.headline).foregroundStyle(p.textPrimary)
                    Text("这是一段用于界面演示的占位简介。原 App 的详情与播放功能在纯 UI 复刻中以占位数据呈现。")
                        .font(.footnote).foregroundStyle(p.textSecondary)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(corner: 14)

                Text("来源：\(video.site)  ·  id \(video.id)")
                    .font(.caption2).foregroundStyle(p.textTertiary)
            }
            .padding(16)
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $playing) {
            PlayerScreen(title: video.title)
        }
        .fullScreenCover(isPresented: $shortFeed) {
            ShortVideoView()
        }
    }
}
