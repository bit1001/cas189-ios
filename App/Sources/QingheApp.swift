import SwiftUI
import QHCore

@main
struct QingheApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                FeedView()
            }
            .environmentObject(store)
            .preferredColorScheme(.dark)
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var topics: [Topic] = []
    @Published var loading = false
    @Published var error: String?
    @Published var page = 1
    @Published var favorites: Set<Int> = []

    let client = HaijiaoClient()

    init() {
        favorites = Set(UserDefaults.standard.array(forKey: "favs") as? [Int] ?? [])
    }

    func load(reset: Bool = false) async {
        if loading { return }
        loading = true
        error = nil
        do {
            let result = try await client.feed(.hot, page: reset ? 1 : page)
            topics = reset ? result.topics : topics + result.topics
            page = result.page + 1
        } catch {
            self.error = "\(error)"
        }
        loading = false
    }

    func toggleFavorite(_ topic: Topic) {
        if favorites.contains(topic.id) { favorites.remove(topic.id) } else { favorites.insert(topic.id) }
        UserDefaults.standard.set(Array(favorites), forKey: "favs")
    }
}
