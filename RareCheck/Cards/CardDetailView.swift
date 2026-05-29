import SwiftUI

struct CardDetailView: View {
    let card: CardMatch
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var priceHistory: [PriceHistoryPoint] = []
    @State private var isLoadingHistory = false
    @State private var showPaywall = false
    @State private var isSaved = false
    @Environment(\.managedObjectContext) private var moc

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                cardImageSection
                priceSection
                priceHistorySection
                metadataSection
                Spacer(minLength: 30)
            }
            .padding()
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveCard()
                } label: {
                    Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                        .foregroundStyle(isSaved ? .green : .red)
                }
                .disabled(isSaved)
            }
        }
        .task { await loadPriceHistory() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Card Image

    private var cardImageSection: some View {
        AsyncImage(url: card.preferredDisplayImageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 12, y: 6)
            case .failure:
                RoundedRectangle(cornerRadius: 12)
                    .fill(.secondary.opacity(0.15))
                    .frame(width: 280, height: 390)
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            default:
                RoundedRectangle(cornerRadius: 12)
                    .fill(.secondary.opacity(0.1))
                    .frame(width: 280, height: 390)
                    .overlay { ProgressView() }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Price Section

    private var priceSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Market Price")
                        .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                    Text(card.price.formattedMarket)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Range").font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                    Text(card.price.formattedRange)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                priceLabel("Low", value: card.price.low)
                Divider().frame(height: 40)
                priceLabel("Mid", value: card.price.mid)
                Divider().frame(height: 40)
                priceLabel("High", value: card.price.high)
            }
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func priceLabel(_ title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("$\(String(format: "%.2f", value))").font(.subheadline).fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    // MARK: - Price History Chart

    private var priceHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("30-Day Price History")
                    .font(.headline)
                Spacer()
                if !subscriptionManager.isPro {
                    ProBadge()
                }
            }

            if subscriptionManager.isPro {
                if isLoadingHistory {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                } else if priceHistory.isEmpty {
                    Text("No history available yet.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    PriceHistoryChart(history: priceHistory)
                        .frame(height: 160)
                }
            } else {
                ProLockedChart()
                    .onTapGesture { showPaywall = true }
            }
        }
        .padding()
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(spacing: 0) {
            metaRow("Set", value: card.setName)
            Divider().padding(.leading)
            metaRow("Set Code", value: card.setCode)
            Divider().padding(.leading)
            metaRow("Collector #", value: card.collectorNumber)
            Divider().padding(.leading)
            metaRow("Rarity", value: card.rarity)
            Divider().padding(.leading)
            metaRow("Match Confidence", value: "\(card.confidencePercent)%")
        }
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func metaRow(_ key: String, value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func saveCard() {
        let outcome = PersistenceController.shared.saveCard(card, isPro: subscriptionManager.isPro)
        guard outcome != .limitReached else {
            showPaywall = true
            return
        }
        isSaved = true
    }

    private func loadPriceHistory() async {
        guard subscriptionManager.isPro else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let response = try await APIClient.shared.priceHistory(cardId: card.id)
            priceHistory = response.history
        } catch {
            print("[RareCheck] Price history error: \(error)")
        }
    }
}

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2).fontWeight(.heavy)
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.yellow, in: Capsule())
    }
}

struct ProLockedChart: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.secondary.opacity(0.1))
                .frame(height: 120)
            VStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.title2).foregroundStyle(.secondary)
                Text("Upgrade to Pro to unlock price history")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }
}
