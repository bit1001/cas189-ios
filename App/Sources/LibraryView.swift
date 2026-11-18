import SwiftUI
import QHCore

/// Library — mirrors LibraryScreen + LibraryBatch + LibraryUndoBanner.
struct LibraryView: View {
    @Environment(\.palette) private var p
    @EnvironmentObject private var store: Store
    @State private var tab = 0
    @State private var manage = false
    @State private var selected: Set<String> = []
    @State private var undoText: String? = nil

    private let tabs = ["收藏", "足迹"]
    private let items = demoVideos(prefix: "lib", count: 14)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                Picker("", selection: $tab) {
                    ForEach(0..<tabs.count, id: \.self) { Text(tabs[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                statsBar
                if let u = undoText {
                    HStack {
                        Text(u).font(.caption).foregroundStyle(p.textPrimary)
                        Spacer()
                        Button("撤销") { undoText = nil }.font(.caption).foregroundStyle(p.accentPrimary)
                    }
                    .padding(10).glassCard(corner: 10)
                }
                LazyVStack(spacing: 10) {
                    ForEach(items) { v in LibraryRow(video: v, manage: manage, selected: $selected) }
                }
            }
            .padding(.bottom, 110)
        }
        .safeAreaInset(edge: .bottom) {
            if manage {
                batchBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("资料库").font(.largeTitle.bold()).foregroundStyle(p.textPrimary)
            Spacer()
            Button(manage ? "完成" : "管理") {
                withAnimation { manage.toggle(); if !manage { selected = [] } }
            }.font(.subheadline).foregroundStyle(p.accentPrimary)
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    private var statsBar: some View {
        HStack(spacing: 16) {
            if tab == 0 {
                Text("共收藏 \(items.count) 部视频").font(.caption).foregroundStyle(p.textSecondary)
                Text("显示 \(items.count) 部收藏").font(.caption).foregroundStyle(p.textTertiary)
            } else {
                Text("最近观看 \(items.count) 部视频").font(.caption).foregroundStyle(p.textSecondary)
                Text("显示 \(items.count) 条足迹").font(.caption).foregroundStyle(p.textTertiary)
            }
            Spacer()
        }.padding(.horizontal, 20)
    }

    private var batchBar: some View {
        HStack(spacing: 8) {
            Button("全选") { selected = Set(items.map { $0.uid }) }
            Button("取消全选") { selected = [] }
            Spacer()
            Button(tab == 0 ? "取消收藏 \(selected.count) 部" : "移除 \(selected.count) 部足迹") {
                undoText = "已\(tab == 0 ? "取消收藏" : "移除") \(selected.count) 部"
                selected = []
            }
            .foregroundStyle(p.badgeText)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(p.accentPrimary, in: Capsule())
        }
        .font(.caption).padding(12).glassCard(corner: 16)
    }
}

struct LibraryRow: View {
    let video: SiteVideo
    let manage: Bool
    @Binding var selected: Set<String>
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 12) {
            if manage {
                Image(systemName: selected.contains(video.uid) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(video.uid) ? p.accentPrimary : p.textTertiary)
                    .onTapGesture {
                        if selected.contains(video.uid) { selected.remove(video.uid) }
                        else { selected.insert(video.uid) }
                    }
            }
            CoverImage(path: video.cover, rc4: false)
                .frame(width: 100, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text(video.title).font(.subheadline).lineLimit(2).foregroundStyle(p.textPrimary)
                Text("\(video.views) 次观看 · \(video.durationText ?? "--:--")")
                    .font(.caption2).foregroundStyle(p.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(9).glassCard(corner: 14).padding(.horizontal, 20)
    }
}
