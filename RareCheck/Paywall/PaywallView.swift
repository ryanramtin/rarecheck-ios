import SwiftUI
import RevenueCat

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPackage: Package?
    @State private var isPurchasing = false
    @State private var showError = false

    private var monthlyPackage: Package? {
        subscriptionManager.offerings?.current?.monthly
    }
    private var annualPackage: Package? {
        subscriptionManager.offerings?.current?.annual
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroSection
                    featureList
                    if subscriptionManager.isLoading {
                        ProgressView().padding()
                    } else {
                        pricingCards
                        purchaseButton
                        footerLinks
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not Now") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
            .task { await subscriptionManager.loadOfferings() }
            .alert("Purchase Failed", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(subscriptionManager.errorMessage ?? "An error occurred.")
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(.red.opacity(0.1)).frame(width: 80, height: 80)
                Image(systemName: "bolt.fill")
                    .font(.largeTitle).foregroundStyle(.red)
            }
            .padding(.top, 20)

            Text("RareCheck Pro")
                .font(.system(size: 32, weight: .black, design: .rounded))

            Text("Unlock the full power of your collection")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Feature List

    private let features: [(icon: String, title: String, subtitle: String)] = [
        ("infinity", "Unlimited Collection", "Save as many cards as you want"),
        ("chart.line.uptrend.xyaxis", "30-Day Price History", "Track value trends over time"),
        ("rectangle.stack.badge.plus", "Bulk Scan Mode", "Scan multiple cards at once"),
        ("square.and.arrow.up", "CSV Export", "Export your full collection to spreadsheet"),
        ("arrow.clockwise", "Auto Price Refresh", "Prices updated every 6 hours")
    ]

    private var featureList: some View {
        VStack(spacing: 14) {
            ForEach(features, id: \.title) { feature in
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(.red.opacity(0.1)).frame(width: 36, height: 36)
                        Image(systemName: feature.icon)
                            .font(.callout).foregroundStyle(.red)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title).font(.subheadline).fontWeight(.semibold)
                        Text(feature.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark").foregroundStyle(.green).fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Pricing Cards

    private var pricingCards: some View {
        VStack(spacing: 12) {
            if let annual = annualPackage {
                PricingCard(
                    package: annual,
                    badge: "Best Value",
                    isSelected: selectedPackage?.identifier == annual.identifier,
                    savingsText: savingsText(for: annual)
                )
                .onTapGesture { selectedPackage = annual }
            }

            if let monthly = monthlyPackage {
                PricingCard(
                    package: monthly,
                    badge: nil,
                    isSelected: selectedPackage?.identifier == monthly.identifier,
                    savingsText: nil
                )
                .onTapGesture { selectedPackage = monthly }
            }
        }
        .onAppear {
            // Default to annual
            selectedPackage = annualPackage ?? monthlyPackage
        }
    }

    private func savingsText(for package: Package) -> String? {
        guard let monthly = monthlyPackage else { return nil }
        let monthlyYearly = monthly.storeProduct.price * 12
        let annualPrice = package.storeProduct.price
        let savings = NSDecimalNumber(decimal: (monthlyYearly - annualPrice) / monthlyYearly * 100)
        let pct = Int(savings.doubleValue.rounded())
        return pct > 0 ? "Save \(pct)%" : nil
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        Button {
            guard let pkg = selectedPackage else { return }
            Task {
                isPurchasing = true
                defer { isPurchasing = false }
                do {
                    try await subscriptionManager.purchase(package: pkg)
                    dismiss()
                } catch {
                    subscriptionManager.errorMessage = error.localizedDescription
                    showError = true
                }
            }
        } label: {
            HStack {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text("Start Pro")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.red, in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(selectedPackage == nil || isPurchasing)
    }

    // MARK: - Footer

    private var footerLinks: some View {
        VStack(spacing: 6) {
            Button("Restore Purchases") {
                Task { await subscriptionManager.restorePurchases() }
            }
            .font(.footnote).foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Link("Privacy Policy", destination: URL(string: "https://rarecheck.app/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://rarecheck.app/terms")!)
            }
            .font(.caption).foregroundStyle(.tertiary)

            Text("Subscription auto-renews. Cancel anytime in App Store settings.")
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Pricing Card

struct PricingCard: View {
    let package: Package
    let badge: String?
    let isSelected: Bool
    let savingsText: String?

    private var priceString: String { package.storeProduct.localizedPriceString }
    private var period: String {
        switch package.packageType {
        case .monthly: return "/ month"
        case .annual:  return "/ year"
        default:       return ""
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(package.storeProduct.localizedTitle)
                        .font(.subheadline).fontWeight(.semibold)
                    if let badge {
                        Text(badge)
                            .font(.caption2).fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.red, in: Capsule())
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(priceString).font(.headline).fontWeight(.bold)
                    Text(period).font(.caption).foregroundStyle(.secondary)
                }
                if let savings = savingsText {
                    Text(savings).font(.caption).foregroundStyle(.green)
                }
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? .red : .secondary.opacity(0.4))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? .red : .secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .background(.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
