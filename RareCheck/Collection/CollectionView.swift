import SwiftUI
import CoreData

struct CollectionView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var appNavigation: AppNavigationState
    @StateObject private var viewModel = CollectionViewModel()
    @State private var showPaywall = false
    @State private var layout: Layout = .grid
    @State private var visibleSaveNotice: AppNavigationState.CollectionSaveNotice?
    @Environment(\.managedObjectContext) private var moc

    enum Layout { case grid, list }

    @FetchRequest private var cards: FetchedResults<SavedCard>

    init() {
        _cards = FetchRequest<SavedCard>(
            sortDescriptors: [NSSortDescriptor(key: "addedAt", ascending: false)],
            animation: .default
        )
    }

    private var filteredCards: [SavedCard] {
        cards.filter { card in
            let matchesSearch = viewModel.searchText.isEmpty ||
                (card.name ?? "").localizedCaseInsensitiveContains(viewModel.searchText) ||
                (card.setName ?? "").localizedCaseInsensitiveContains(viewModel.searchText)
            let matchesRarity = viewModel.filterRarity == nil || card.rarity == viewModel.filterRarity
            return matchesSearch && matchesRarity
        }
        .sorted { a, b in
            switch viewModel.sortOption {
            case .dateAdded:    return (a.addedAt ?? .distantPast) > (b.addedAt ?? .distantPast)
            case .name:         return (a.name ?? "") < (b.name ?? "")
            case .priceHighToLow: return a.currentPriceMarket > b.currentPriceMarket
            case .priceLowToHigh: return a.currentPriceMarket < b.currentPriceMarket
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        collectionStats
                        if layout == .grid {
                            gridView
                        } else {
                            listView
                        }
                    }
                }
            }
            .navigationTitle("Collection")
            .searchable(text: $viewModel.searchText, prompt: "Search cards…")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if subscriptionManager.isPro {
                        Button { viewModel.exportCSV() } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    layoutToggle
                    sortMenu
                }
            }
            .sheet(isPresented: $viewModel.showCSVExport) {
                ShareSheet(text: viewModel.csvContent)
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .safeAreaInset(edge: .top) {
                if let visibleSaveNotice {
                    saveNoticeBanner(visibleSaveNotice)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: appNavigation.collectionSaveNotice) { _, notice in
                guard let notice else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    visibleSaveNotice = notice
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_400_000_000)
                    guard visibleSaveNotice == notice else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        visibleSaveNotice = nil
                    }
                    if appNavigation.collectionSaveNotice == notice {
                        appNavigation.collectionSaveNotice = nil
                    }
                }
            }
        }
    }

    // MARK: - Stats Bar

    private var collectionStats: some View {
        HStack {
            statItem(title: "Cards", value: "\(filteredCards.count)")
            Divider().frame(height: 30)
            statItem(title: "Total Value", value: "$\(String(format: "%.2f", viewModel.totalValue(cards: filteredCards)))")
            Divider().frame(height: 30)
            statItem(title: "Limit",
                     value: subscriptionManager.isPro ? "Unlimited" : "\(cards.count)/\(PersistenceController.freeCollectionLimit)")
        }
        .padding(.vertical, 10)
        .padding(.horizontal)
        .background(.secondary.opacity(0.06))
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline).fontWeight(.semibold)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(filteredCards) { card in
                    NavigationLink {
                        CardDetailView(card: card.toCardMatch())
                            .environmentObject(subscriptionManager)
                    } label: {
                        CollectionCardTile(card: card)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            PersistenceController.shared.deleteCard(card)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - List View

    private var listView: some View {
        List {
            ForEach(filteredCards) { card in
                NavigationLink {
                    CardDetailView(card: card.toCardMatch())
                        .environmentObject(subscriptionManager)
                } label: {
                    CollectionListRow(card: card)
                }
            }
            .onDelete { indexSet in
                indexSet.forEach { PersistenceController.shared.deleteCard(filteredCards[$0]) }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Cards Yet", systemImage: "rectangle.stack")
        } description: {
            Text("Scan your first Pokémon card to start your collection.")
        }
    }

    private func saveNoticeBanner(_ notice: AppNavigationState.CollectionSaveNotice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: notice.outcome == .inserted ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(.white)
            Text(notice.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.green.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }

    // MARK: - Toolbar Controls

    private var layoutToggle: some View {
        Button {
            layout = layout == .grid ? .list : .grid
        } label: {
            Image(systemName: layout == .grid ? "list.bullet" : "square.grid.2x2")
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $viewModel.sortOption) {
                ForEach(CollectionViewModel.SortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }
}

// MARK: - Grid Tile

struct CollectionCardTile: View {
    let card: SavedCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: card.imageURL ?? "")) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.15))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .aspectRatio(5/7, contentMode: .fit)

            Text(card.name ?? "Unknown").font(.caption).fontWeight(.semibold).lineLimit(1)
            Text(card.setName ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text("$\(String(format: "%.2f", card.currentPriceMarket))")
                .font(.caption).foregroundStyle(.green).fontWeight(.medium)
        }
        .padding(8)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - List Row

struct CollectionListRow: View {
    let card: SavedCard

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: card.imageURL ?? "")) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.15))
            }
            .frame(width: 44, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 3) {
                Text(card.name ?? "").font(.subheadline).fontWeight(.semibold)
                Text("\(card.setName ?? "") · #\(card.collectorNumber ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
                Text(card.rarity ?? "").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Text("$\(String(format: "%.2f", card.currentPriceMarket))")
                .font(.subheadline).fontWeight(.semibold).foregroundStyle(.green)
        }
    }
}

// MARK: - CoreData → CardMatch bridge

extension SavedCard {
    func toCardMatch() -> CardMatch {
        CardMatch(
            id: cardId ?? UUID().uuidString,
            name: name ?? "",
            setName: setName ?? "",
            setCode: setCode ?? "",
            collectorNumber: collectorNumber ?? "",
            rarity: rarity ?? "",
            imageURL: imageURL ?? "",
            confidence: 1.0,
            price: PriceData(
                low: currentPriceLow, mid: currentPriceMid,
                high: currentPriceHigh, market: currentPriceMarket,
                currency: "USD", updatedAt: addedAt ?? Date()
            )
        )
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("collection_export.csv")
        try? text.write(to: tmpURL, atomically: true, encoding: .utf8)
        return UIActivityViewController(activityItems: [tmpURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
