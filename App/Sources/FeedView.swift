import SwiftUI
import QHCore

/// Home feed — mirrors VideoFeedCards + HomeMediaHub + ShelfRow from the APK.
/// Apple-Glass shelf layout: top title + search, category chips, horizontal
/// scrolling card shelves with glass cards. Uses real items when present,
/// otherwise placeholder cards so the visual design is fully visible offline.
struct FeedView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.palette) private var p
    @State private var query = ""
    @State private var isGrid = false
    @State private var selectedCategory = "推荐"

    private let categories = ["推荐", "最新", "最热", "热门", "排行", "精华", "动漫", "欧美", "日本"]
    private let shelves: [(String, String)] = [
        ("每日精选", "sparkles"), ("热门推荐", "flame"), ("最新上架", "clock"),
        ("高清专区", "tv"), ("追更榜单", "chart.bar.fill")
    ]

    private var items: [SiteVideo] { store.items }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                categoryChips
                if items.isEmpty {
                    ForEach(shelves, id: \.0) { shelf in
                        ShelfSection(title: shelf.0, icon: shelf.1, items: placeholderVideos(seed: shelf.0), isGrid: isGrid)
                    }
                } else {
                    ShelfSection(title: "全部视频", icon: "square.grid.2x2", items: items, isGrid: isGrid)
                }
                if store.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }
                if let error = store.error {
                    Text(error).font(.footnote).foregroundStyle(.red).padding()
                }
            }
            .padding(.bottom, 100)
        }
        .navigationDestination(for: SiteVideo.self) { video in
            VideoDetailView(video: video)
        }
        .searchable(text: $query, prompt: "搜索片名或标签")
        .onSubmit(of: .search) { Task { await store.search(query) } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button { isGrid.toggle() } label: {
                        Image(systemName: isGrid ? "square.grid.2x2" : "rectangle.grid.2x2")
                    }
                    Menu {
                        ForEach(SiteRegistry.entries, id: \.id) { entry in
                            Button {
                                Task { await store.switchTo(entry.id) }
                            } label: {
                                if entry.id == store.siteID {
                                    Label(entry.label, systemImage: "checkmark")
                                } else { Text(entry.label) }
                            }
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
            }
        }
        .task { if store.items.isEmpty { await store.load(reset: true) } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline) {
                Text("青禾学堂").font(.largeTitle.bold()).foregroundStyle(p.textPrimary)
                Spacer()
                Text("v1.9.5").font(.caption).foregroundStyle(p.textTertiary)
            }
            Text("发现好内容，学习新知识").font(.subheadline).foregroundStyle(p.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories, id: \.self) { cat in
                    Button {
                        withAnimation { selectedCategory = cat }
                    } label: {
                        Text(cat).font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .foregroundStyle(selectedCategory == cat ? p.badgeText : p.textSecondary)
                            .background(
                                Capsule().fill(selectedCategory == cat ? p.accentPrimary.opacity(0.85) : p.cardSurface)
                            )
                            .overlay(Capsule().stroke(p.cardBorder, lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func placeholderVideos(seed: String) -> [SiteVideo] {
        let titles = ["深入解析极限与连续", "从零开始的网页请求", "第一天：认识函数", "路线表达与方向词", "借阅场景常用表达", "常见状态码详解", "直观理解变化与趋近", "课后复习步骤"]
        return (0..<8).map { i in
            SiteVideo(site: "demo", id: "\(seed)-\(i)",
                      title: titles[i % titles.count],
                      cover: nil, views: (i + 1) * 1234,
                      durationText: String(format: "%02d:%02d", 8 + i, (i * 7) % 60))
        }
    }
}

/// A shelf = section title row + horizontal scrolling cards (or grid).
struct ShelfSection: View {
    let title: String
    let icon: String
    let items: [SiteVideo]
    let isGrid: Bool
    @EnvironmentObject private var store: Store
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline).foregroundStyle(p.textPrimary)
                Spacer()
                Button("查看全部") {}.font(.caption).foregroundStyle(p.accentPrimary)
            }
            .padding(.horizontal, 20)

            if isGrid {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(items) { v in VideoCard(video: v) }
                }
                .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(items) { v in VideoCard(video: v).frame(width: 190) }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

/// Apple-glass video card: cover 16:9, duration badge, title, views, favorite.
struct VideoCard: View {
    let video: SiteVideo
    @EnvironmentObject private var store: Store
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                CoverImage(path: video.cover, rc4: video.site == "douyin")
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if let d = video.durationText {
                    Text(d).font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(p.cardSurface.opacity(0.9))
                        .clipShape(Capsule())
                        .padding(8)
                }
            }
            HStack(alignment: .top) {
                Text(video.title).font(.subheadline).lineLimit(2)
                    .foregroundStyle(p.textPrimary)
                Spacer(minLength: 0)
                Button { store.toggleFavorite(video) } label: {
                    Image(systemName: store.favorites.contains(video.uid) ? "heart.fill" : "heart")
                        .font(.caption)
                        .foregroundStyle(store.favorites.contains(video.uid) ? .pink : p.textTertiary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Image(systemName: "play.circle").font(.caption2)
                Text(formatViews(video.views)).font(.caption2)
            }
            .foregroundStyle(p.textTertiary)
        }
        .padding(10)
        .glassCard(corner: 16)
    }

    private func formatViews(_ n: Int) -> String {
        if n >= 100_000_000 { return String(format: "%.1f 亿次观看", Double(n)/100_000_000) }
        if n >= 10_000 { return String(format: "%.1f 万次观看", Double(n)/10_000) }
        return "\(n) 次观看"
    }
}
