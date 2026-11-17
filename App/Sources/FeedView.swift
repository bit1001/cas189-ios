import SwiftUI
import QHCore

struct FeedView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        List {
            ForEach(store.topics) { topic in
                NavigationLink(value: topic) {
                    TopicRow(topic: topic)
                }
                .listRowBackground(Color.clear)
                .onAppear {
                    if topic.id == store.topics.last?.id {
                        Task { await store.load() }
                    }
                }
            }
            if store.loading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            }
            if let error = store.error {
                Text(error).font(.footnote).foregroundStyle(.red)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .navigationTitle("热门")
        .navigationDestination(for: Topic.self) { topic in
            DetailView(topic: topic)
        }
        .refreshable { await store.load(reset: true) }
        .task {
            if store.topics.isEmpty { await store.load(reset: true) }
        }
    }
}

struct TopicRow: View {
    let topic: Topic
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: topic.cover.flatMap(URL.init)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.white.opacity(0.06)
            }
            .frame(width: 108, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(topic.title).font(.subheadline).lineLimit(2)
                HStack(spacing: 8) {
                    Text(topic.author).font(.caption).foregroundStyle(.secondary)
                    Text("\(topic.views) 次").font(.caption).foregroundStyle(.secondary)
                    if !topic.videos.isEmpty {
                        Label("视频", systemImage: "play.rectangle")
                            .font(.caption2).labelStyle(.titleAndIcon)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                store.toggleFavorite(topic)
            } label: {
                Image(systemName: store.favorites.contains(topic.id) ? "heart.fill" : "heart")
                    .foregroundStyle(store.favorites.contains(topic.id) ? .pink : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}
