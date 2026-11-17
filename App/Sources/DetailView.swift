import SwiftUI
import QHCore

struct VideoDetailView: View {
    let video: SiteVideo
    @State private var playing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(video.title).font(.title3.bold())

                HStack(spacing: 12) {
                    if !video.author.isEmpty {
                        Text(video.author).font(.footnote).foregroundStyle(.secondary)
                    }
                    if video.views > 0 {
                        Text("\(video.views) 次观看").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let d = video.durationText {
                        Text(d).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if let cover = video.cover, let url = URL(string: cover) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)).frame(height: 220)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    playing = true
                } label: {
                    Label("播放", systemImage: "play.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Text("来源：\(video.site)  ·  id \(video.id)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $playing) {
            PlayerView(video: video)
        }
    }
}
