import SwiftUI
import QHCore

/// Browse (片库) — mirrors BrowseControls + catalog chips + video feed.
struct BrowseView: View {
    @Environment(\.palette) private var p
    @State private var platform = "海角"
    @State private var category = "推荐"
    @State private var isGrid = false
    private let platforms = ["海角", "探花", "51视频", "JAVHD", "黑暗抖阴", "糖心Vlog", "台湾SWAG"]
    private let categories = ["推荐", "最新", "最热", "热门", "排行", "精华", "新闻", "动漫", "原创", "高清", "欧美", "日本"]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .lastTextBaseline) {
                    Text("片库").font(.largeTitle.bold()).foregroundStyle(p.textPrimary)
                    Spacer()
                    Button { isGrid.toggle() } label: {
                        Image(systemName: isGrid ? "rectangle.grid.2x2" : "square.grid.2x2")
                            .foregroundStyle(p.textSecondary)
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 20).padding(.top, 8)

                HStack {
                    Menu {
                        ForEach(platforms, id: \.self) { x in
                            Button { platform = x } label: {
                                if x == platform { Label(x, systemImage: "checkmark") } else { Text(x) }
                            }
                        }
                    } label: {
                        Label("筛选片库平台 · \(platform)", systemImage: "square.stack.3d.up")
                            .font(.caption).foregroundStyle(p.accentPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(p.cardSurface))
                    }
                    Spacer()
                }.padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { c in
                            PillButton(label: c, selected: c == category) { category = c }
                        }
                    }.padding(.horizontal, 20)
                }

                let items = demoVideos(prefix: "browse-\(category)", count: 16)
                if isGrid {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(items) { v in VideoCard(video: v) }
                    }.padding(.horizontal, 20)
                } else {
                    VStack(spacing: 12) {
                        ForEach(items) { v in VideoCard(video: v) }
                    }.padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 100)
        }
    }
}
