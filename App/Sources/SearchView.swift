import SwiftUI
import QHCore

/// Search — mirrors SearchScreen + SearchControls + VideoResultsFeed from the APK.
struct SearchView: View {
    @Environment(\.palette) private var p
    @State private var query = ""
    @State private var showFilters = false
    @State private var history: [String] = ["极限与连续", "turn right 的意思", "看懂网页请求", "借阅期限"]
    @State private var isGrid = false
    @State private var site = "全部平台"
    @State private var sort = "最新"
    @State private var partition = "全部"
    @State private var duration = "不限"
    @State private var matchAll = false
    @State private var hasSearched = false

    private let sites = ["全部平台", "海角", "探花", "51视频", "JAVHD", "黑暗抖阴", "糖心Vlog"]
    private let sorts = ["最新", "最热", "播放次数", "发布时间"]
    private let partitions = ["全部", "推荐", "原创", "无码", "高清", "动漫", "欧美", "日本"]
    private let durations = ["不限", ">10 分钟", ">30 分钟", ">60 分钟"]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                searchBar
                platformStrip
                if hasSearched {
                    activeFilters
                    results
                } else {
                    historyPanel
                }
            }
            .padding(.bottom, 100)
        }
        .sheet(isPresented: $showFilters) { filterSheet }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(p.textTertiary)
                TextField("标题、作者或标签", text: $query).foregroundStyle(p.textPrimary)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(p.textTertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().fill(p.cardSurface))
            .overlay(Capsule().stroke(p.cardBorder, lineWidth: 0.6))
            Button {
                let q = query.trimmingCharacters(in: .whitespaces)
                if !q.isEmpty, !history.contains(q) { history.insert(q, at: 0) }
                withAnimation { hasSearched = true }
            } label: {
                Text("搜索").font(.subheadline.weight(.semibold)).foregroundStyle(p.badgeText)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(p.accentPrimary))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    private var platformStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sites, id: \.self) { s in
                    PillButton(label: s, selected: s == site) { site = s }
                }
            }.padding(.horizontal, 20)
        }
    }

    private var activeFilters: some View {
        HStack(spacing: 8) {
            Button {
                showFilters = true
            } label: {
                Label("筛选 · \(sort) / \(partition)", systemImage: "slider.horizontal.3")
                    .font(.caption).foregroundStyle(p.accentPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(p.cardSurface))
            }.buttonStyle(.plain)
            Spacer()
            Button { isGrid.toggle() } label: {
                Image(systemName: isGrid ? "rectangle.grid.2x2" : "square.grid.2x2")
                    .foregroundStyle(p.textSecondary)
            }.buttonStyle(.plain)
        }.padding(.horizontal, 20)
    }

    private var results: some View {
        let items = demoVideos(prefix: "search", count: 12)
        return Group {
            if items.isEmpty {
                EmptyState(icon: "magnifyingglass", text: "没有匹配结果")
            } else if isGrid {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(items) { v in VideoCard(video: v) }
                }.padding(.horizontal, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { v in SearchResultRow(video: v) }
                }.padding(.horizontal, 20)
            }
        }
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近搜索").font(.headline).foregroundStyle(p.textPrimary)
                Spacer()
                Button("清空搜索历史") { history = [] }.font(.caption).foregroundStyle(p.accentPrimary)
            }
            if history.isEmpty {
                EmptyState(icon: "clock", text: "暂无搜索记录")
            } else {
                ForEach(history, id: \.self) { h in
                    HStack {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(p.textTertiary)
                        Text(h).font(.subheadline).foregroundStyle(p.textPrimary)
                        Spacer()
                        Button { history.removeAll { $0 == h } } label: {
                            Image(systemName: "xmark").foregroundStyle(p.textTertiary)
                        }.buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                }
                Text("相关搜索记录").font(.caption).foregroundStyle(p.textTertiary)
            }
        }
        .padding(16).glassCard(corner: 16).padding(.horizontal, 20)
    }

    private var filterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    filterGroup("排序", sorts, $sort)
                    filterGroup("分区", partitions, $partition)
                    filterGroup("视频时长", durations, $duration)
                    Toggle("匹配全部关键词", isOn: $matchAll)
                        .foregroundStyle(p.textPrimary)
                    HStack(spacing: 12) {
                        Button("重置") {
                            sort = "最新"; partition = "全部"; duration = "不限"; matchAll = false
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(p.cardSurface, in: RoundedRectangle(cornerRadius: 10))
                        Button("应用") { showFilters = false }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(p.badgeText)
                        .background(p.accentPrimary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }.padding(20)
            }
            .navigationTitle("筛选").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func filterGroup(_ title: String, _ options: [String], _ sel: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(p.textPrimary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                ForEach(options, id: \.self) { o in
                    PillButton(label: o, selected: sel.wrappedValue == o) { sel.wrappedValue = o }
                }
            }
        }
    }
}

struct SearchResultRow: View {
    let video: SiteVideo
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 12) {
            CoverImage(path: video.cover, rc4: false)
                .frame(width: 116, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(video.title).font(.subheadline).lineLimit(2).foregroundStyle(p.textPrimary)
                HStack(spacing: 8) {
                    Text("\(video.views) 次观看").font(.caption2).foregroundStyle(p.textTertiary)
                    if let d = video.durationText { Text(d).font(.caption2).foregroundStyle(p.textTertiary) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10).glassCard(corner: 14)
    }
}
