import SwiftUI

@MainActor
final class AppNavigationState: ObservableObject {
    enum Tab {
        case scanner
        case search
        case collection
        case settings
    }

    struct CollectionSaveNotice: Equatable {
        let cardName: String
        let outcome: PersistenceController.SaveOutcome

        var message: String {
            switch outcome {
            case .inserted:
                return "\(cardName) added to your collection"
            case .updated:
                return "\(cardName) refreshed in your collection"
            case .limitReached:
                return "Upgrade to Pro to save more than \(PersistenceController.freeCollectionLimit) cards"
            }
        }
    }

    @Published var selectedTab: Tab = .scanner
    @Published var collectionSaveNotice: CollectionSaveNotice?

    func showCollection(for cardName: String, outcome: PersistenceController.SaveOutcome) {
        collectionSaveNotice = CollectionSaveNotice(cardName: cardName, outcome: outcome)
        selectedTab = .collection
    }
}

struct ContentView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var appNavigation: AppNavigationState

    var body: some View {
        TabView(selection: $appNavigation.selectedTab) {
            ScannerContainerView()
                .tabItem {
                    Label("Scan", systemImage: "viewfinder")
                }
                .tag(AppNavigationState.Tab.scanner)

            CardSearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(AppNavigationState.Tab.search)

            CollectionView()
                .tabItem {
                    Label("Collection", systemImage: "rectangle.stack")
                }
                .tag(AppNavigationState.Tab.collection)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppNavigationState.Tab.settings)
        }
        .tint(.red)
    }
}

struct CardSearchView: View {
    @State private var query = ""
    @State private var results: [CardMatch] = []
    @State private var isRefreshing = false
    @State private var recordCount = LocalCardIndex.shared.recordCount

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView {
                        Label("Search Pokemon DB", systemImage: "magnifyingglass")
                    } description: {
                        Text(searchEmptyStateText)
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { card in
                        NavigationLink {
                            CardDetailView(card: card)
                        } label: {
                            CardSearchResultRow(card: card)
                        }
                    }
                }
            }
            .navigationTitle("Pokemon DB")
            .searchable(text: $query, prompt: "Name, set, or number")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshIndex(allowSeededRefresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isRefreshing {
                    ProgressView("Updating Pokemon DB")
                        .font(.caption)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
            }
            .onAppear(perform: updateResults)
            .onChange(of: query) { _, _ in updateResults() }
            .task {
                await refreshIndex(allowSeededRefresh: true)
            }
        }
    }

    private func refreshIndex(allowSeededRefresh: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await LocalCardIndex.shared.refreshFromPokemonTCGIfNeeded(allowSeededRefresh: allowSeededRefresh)
        recordCount = LocalCardIndex.shared.recordCount
        updateResults()
        isRefreshing = false
    }

    private func updateResults() {
        results = LocalCardIndex.shared.searchCards(matching: query)
        recordCount = LocalCardIndex.shared.recordCount
    }

    private var searchEmptyStateText: String {
        if recordCount == 0 {
            return "Tap refresh to download the Pokemon DB for fast local search."
        }

        if LocalCardIndex.shared.isUsingBundledSeed {
            if isRefreshing {
                return "\(recordCount) starter cards cached. Downloading the larger Pokemon DB for fast local search."
            }
            return "\(recordCount) starter cards cached. Tap refresh to retry the larger Pokemon DB download."
        }

        return "\(recordCount) cards cached for fast local search."
    }
}

struct CardSearchResultRow: View {
    let card: CardMatch

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: card.preferredDisplayImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.secondary.opacity(0.15))
                        .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 48, height: 67)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(.headline)
                    .lineLimit(1)
                Text([card.setName, "#\(card.collectorNumber)", card.rarity]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if card.price.market > 0 {
                    Text(card.price.formattedMarket)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings View (inline, lightweight)
struct SettingsView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(subscriptionManager.isPro ? "Pro ⚡" : "Free")
                            .foregroundStyle(subscriptionManager.isPro ? .yellow : .secondary)
                            .fontWeight(.semibold)
                    }
                    if !subscriptionManager.isPro {
                        Button("Upgrade to Pro") { showPaywall = true }
                            .foregroundStyle(.red)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                    LabeledContent("Build", value: Bundle.main.buildNumber)
                    Link("Privacy Policy", destination: URL(string: "https://pokerarecheck.com/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://pokerarecheck.com/terms")!)
                }

                Section {
                    Button("Restore Purchases") {
                        Task { await subscriptionManager.restorePurchases() }
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }
}

extension Bundle {
    var appVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    var buildNumber: String { infoDictionary?["CFBundleVersion"] as? String ?? "1" }
}
