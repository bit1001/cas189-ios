import SwiftUI
import QHCore

/// Download — mirrors DownloadPane + DownloadRow + DownloadViewFilter.
struct DownloadView: View {
    @Environment(\.palette) private var p
    @State private var filter = 0
    @State private var wifiOnly = true
    private let filters = ["全部", "进行中", "已完成", "需处理"]
    private let items = demoVideos(prefix: "dl", count: 8)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .lastTextBaseline) {
                    Text("下载").font(.largeTitle.bold()).foregroundStyle(p.textPrimary)
                    Spacer()
                    Menu {
                        Button("入队顺序") {}
                        Button("最近添加") {}
                    } label: {
                        Image(systemName: "arrow.up.arrow.down").foregroundStyle(p.textSecondary)
                    }
                }.padding(.horizontal, 20).padding(.top, 8)

                HStack {
                    ForEach(0..<filters.count, id: \.self) { i in
                        PillButton(label: filters[i], selected: filter == i) { filter = i }
                    }
                    Spacer()
                }.padding(.horizontal, 20)

                ToggleRow("仅 Wi-Fi 下载", isOn: $wifiOnly)
                    .padding(12).glassCard(corner: 12).padding(.horizontal, 20)

                let shown = filteredItems
                if shown.isEmpty {
                    EmptyState(icon: "tray", text: emptyText)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(shown.enumerated()), id: \.element.uid) { idx, v in
                            DownloadRowView(video: v, progress: Double(idx + 1) / Double(shown.count + 1))
                        }
                    }.padding(.horizontal, 20)
                }

                HStack {
                    Button("导出 MP4") {}.font(.caption)
                    Spacer()
                    Text("保存到 下载/青禾学堂").font(.caption2).foregroundStyle(p.textTertiary)
                }.padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)
        }
    }

    private var filteredItems: [SiteVideo] {
        switch filter {
        case 0: return items
        case 1: return Array(items.prefix(3))
        case 2: return Array(items.suffix(2))
        default: return Array(items.dropFirst(5).prefix(2))
        }
    }

    private var emptyText: String {
        switch filter {
        case 1: return "没有正在进行的任务"
        case 2: return "还没有已完成的下载"
        case 3: return "没有需要处理的任务"
        default: return "还没有下载"
        }
    }
}

struct DownloadRowView: View {
    let video: SiteVideo
    let progress: Double
    @Environment(\.palette) private var p
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CoverImage(path: video.cover, rc4: false)
                    .frame(width: 96, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 5) {
                    Text(video.title).font(.subheadline).lineLimit(2).foregroundStyle(p.textPrimary)
                    Text("大小还在估算").font(.caption2).foregroundStyle(p.textTertiary)
                }
                Spacer(minLength: 0)
            }
            ProgressView(value: progress)
                .tint(p.progressColor)
            HStack(spacing: 12) {
                Button("暂停") {}.font(.caption).foregroundStyle(p.accentPrimary)
                Button("重试") {}.font(.caption).foregroundStyle(p.textSecondary)
                Button("继续") {}.font(.caption).foregroundStyle(p.textSecondary)
                Spacer()
                Text("\(Int(progress * 100))%").font(.caption2).foregroundStyle(p.textTertiary)
            }
        }
        .padding(12).glassCard(corner: 14)
    }
}
