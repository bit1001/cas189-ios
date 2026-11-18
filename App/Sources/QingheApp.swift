import SwiftUI
import QHCore

@main
struct QingheApp: App {
    @StateObject private var store = Store()
    @StateObject private var theme = ThemeStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(theme)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.colorScheme) private var systemScheme
    @State private var selection: AppTab = .home

    private var palette: GlassPalette {
        theme.palette(systemDark: systemScheme == .dark)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                GlassBackground()
                Group {
                    switch selection {
                    case .home: FeedView()
                    case .browse: BrowseView()
                    case .search: SearchView()
                    case .library: LibraryView()
                    case .settings: SettingsView()
                    }
                }
                .environment(\.palette, palette)
                DockView(selection: $selection)
                    .environment(\.palette, palette)
            }
            .navigationDestination(for: SiteVideo.self) { video in
                VideoDetailView(video: video)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { StudyView() } label: {
                        Label("青禾学堂", systemImage: "book.fill")
                            .font(.caption)
                    }
                }
            }
        }
        .environment(\.palette, palette)
        .tint(palette.accentPrimary)
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var siteID: String = "hstv"
    @Published var section: String = "hot"
    @Published var items: [SiteVideo] = []
    @Published var page = 1
    @Published var loading = false
    @Published var hasMore = true
    @Published var error: String?
    @Published var favorites: Set<String> = []

    private var loadedSites: Set<String> = []

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favs") ?? [])
    }

    var siteLabel: String {
        SiteRegistry.entries.first { $0.id == siteID }?.label ?? siteID
    }

    var sections: [SelfShotSection] { SelfShotCatalog.sections(for: siteID) }

    func switchTo(_ id: String) async {
        guard id != siteID else { return }
        siteID = id
        section = SelfShotCatalog.sections(for: id).first?.key ?? "hot"
        items = []
        page = 1
        hasMore = true
        error = nil
        await load(reset: true)
    }

    func switchSection(_ key: String) async {
        guard key != section else { return }
        section = key
        items = []
        page = 1
        hasMore = true
        error = nil
        await load(reset: true)
    }

    func load(reset: Bool = false) async {
        if loading { return }
        loading = true
        error = nil
        let target = reset ? 1 : page
        do {
            let adapter = try SiteRegistry.adapter(for: siteID)
            let result = try await adapter.feed(section: section, page: target)
            items = reset ? result.items : items + result.items
            page = target + 1
            hasMore = !result.items.isEmpty
            loadedSites.insert(siteID)
        } catch {
            self.error = "\(error)"
            hasMore = false
        }
        loading = false
    }

    func search(_ keyword: String) async {
        let text = keyword.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { await load(reset: true); return }
        loading = true
        error = nil
        do {
            let adapter = try SiteRegistry.adapter(for: siteID)
            let result = try await adapter.search(text, page: 1)
            items = result.items
            hasMore = false
        } catch {
            self.error = "\(error)"
        }
        loading = false
    }

    func toggleFavorite(_ v: SiteVideo) {
        if favorites.contains(v.uid) { favorites.remove(v.uid) } else { favorites.insert(v.uid) }
        UserDefaults.standard.set(Array(favorites), forKey: "favs")
    }
}
