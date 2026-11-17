import SwiftUI
import QHCore

struct DetailView: View {
    let topic: Topic
    @State private var detail: Topic?
    @State private var error: String?
    @State private var playTarget: Attachment?

    private var current: Topic { detail ?? topic }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(current.title).font(.title3.bold())

                HStack(spacing: 12) {
                    Text(current.author).font(.footnote).foregroundStyle(.secondary)
                    Text("\(current.views) 次观看").font(.footnote).foregroundStyle(.secondary)
                    Text(current.created).font(.footnote).foregroundStyle(.secondary)
                }

                if let cover = current.cover, let url = URL(string: cover) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)).frame(height: 220)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                ForEach(current.videos, id: \.id) { video in
                    Button {
                        playTarget = video
                    } label: {
                        Label("播放 \(video.durationSec.map { "\($0 / 60):\(String(format: "%02d", $0 % 60))" } ?? "")",
                              systemImage: "play.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }

                Text("来源：海角 · 附件 \(current.attachments.count) 个")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playTarget) { attachment in
            PlayerView(topicId: current.id, attachment: attachment)
        }
        .task {
            guard detail == nil else { return }
            do { detail = try await HaijiaoClient().detail(id: topic.id) }
            catch { self.error = "\(error)" }
        }
    }
}
