import SwiftUI
import QHCore

/// Home feed — self-shot (自拍) sections of the three sites, Apple-Glass style.
/// Real data from the live sites (direct connection, no proxy). Section chips
/// switch the per-site 自拍 sub-section; cards navigate to detail/player.
struct FeedView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.palette) private var p
    @State private var query = ""
    @State private var isGrid = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                sectionChips
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)
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
        .refreshable { await store.load(reset: true) }
        .task {
            if store.items.isEmpty { await store.load(reset: true) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.loading && store.items.isEmpty {
            VStack(spacing: 12) {
                ProgressView().frame(maxWidth: .infinity)
                Text("正在查找视频…").font(.caption).foregroundStyle(p.textTertiary)
            }
            .frame(minHeight: 240)
        } else if store.items.isEmpty {
            EmptyState(icon: "photo", text: store.error.map { "加载失败：\($0)" } ?? "本页没有视频")
        } else if isGrid {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(store.items) { v in cardCell(v) }
            }
            .padding(.horizontal, 20)
            loadMoreRow
        } else {
            VStack(spacing: 14) {
                ForEach(store.items) { v in cardCell(v) }
            }
            .padding(.horizontal, 20)
            loadMoreRow
        }
    }

    @ViewBuilder
    private func cardCell(_ v: SiteVideo) -> some View {
        NavigationLink(value: v) { VideoCard(video: v) }
            .buttonStyle(.plain)
            .onAppear {
                if v.uid == store.items.last?.uid, store.hasMore {
                    Task { await store.load() }
                }
            }
    }

    private var loadMoreRow: some View {
        Group {
            if store.loading {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if let e = store.error {
                VStack(spacing: 8) {
                    Text(e).font(.caption).foregroundStyle(.red)
                    Button("重试") { Task { await store.load(reset: true) } }
                        .font(.caption).foregroundStyle(p.accentPrimary)
                }.padding()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline) {
                Text(store.siteLabel).font(.largeTitle.bold()).foregroundStyle(p.textPrimary)
                Spacer()
                Text("自拍专区").font(.caption.weight(.medium)).foregroundStyle(p.accentPrimary)
            }
            Text("共 \(store.sections.count) 个分区 · 当前「\(currentSectionLabel)」")
                .font(.subheadline).foregroundStyle(p.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var currentSectionLabel: String {
        store.sections.first { $0.key == store.section }?.label ?? store.section
    }

    private var sectionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.sections) { sec in
                    Button {
                        Task { await store.switchSection(sec.key) }
                    } label: {
                        Text(sec.label).font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(sec.key == store.section ? p.badgeText : p.textSecondary)
                            .background(
                                Capsule().fill(sec.key == store.section ? p.accentPrimary.opacity(0.85) : p.cardSurface)
                            )
                            .overlay(Capsule().stroke(p.cardBorder, lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                // Use `.fit` with an explicit width: in a vertical ScrollView the
                // height proposal is .infinity, so `.fill` makes the cover grow to
                // fill the whole screen. `.fit` derives height from the finite width.
                CoverImage(path: video.cover, rc4: video.site == "douyin")
                    .aspectRatio(16/9, contentMode: .fit)
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
