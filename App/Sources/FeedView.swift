import SwiftUI
import QHCore

struct FeedView: View {
    @EnvironmentObject private var store: Store
    @State private var query = ""

    var body: some View {
        List {
            ForEach(store.items) { video in
                NavigationLink(value: video) {
                    VideoRow(video: video)
                }
                .listRowBackground(Color.clear)
                .onAppear {
                    if video.uid == store.items.last?.uid, store.hasMore {
                        Task { await store.load() }
                    }
                }
            }
            if store.loading {
                HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
            }
            if let error = store.error {
                Text(error).font(.footnote).foregroundStyle(.red)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .navigationTitle(store.siteLabel)
        .navigationDestination(for: SiteVideo.self) { video in
            VideoDetailView(video: video)
        }
        .refreshable { await store.load(reset: true) }
        .searchable(text: $query, prompt: "搜索 \(store.siteLabel)")
        .onSubmit(of: .search) { Task { await store.search(query) } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(SiteRegistry.entries, id: \.id) { entry in
                        Button {
                            Task { await store.switchTo(entry.id) }
                        } label: {
                            if entry.id == store.siteID {
                                Label(entry.label, systemImage: "checkmark")
                            } else {
                                Text(entry.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
            }
        }
        .task {
            if store.items.isEmpty { await store.load(reset: true) }
        }
    }
}

struct VideoRow: View {
    let video: SiteVideo
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(path: video.cover, rc4: video.site == "douyin")
            .frame(width: 108, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(video.title).font(.subheadline).lineLimit(2)
                HStack(spacing: 8) {
                    if !video.author.isEmpty {
                        Text(video.author).font(.caption).foregroundStyle(.secondary)
                    }
                    if video.views > 0 {
                        Text("\(video.views)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let d = video.durationText {
                        Text(d).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                store.toggleFavorite(video)
            } label: {
                Image(systemName: store.favorites.contains(video.uid) ? "heart.fill" : "heart")
                    .foregroundStyle(store.favorites.contains(video.uid) ? .pink : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}
