import RevenueCat
import SwiftUI
import Combine

private let purchaseUnavailableMessage = "Purchases are unavailable in this build. Configure REVENUECAT_API_KEY for App Store or TestFlight purchase testing."

// MARK: - Subscription Manager
// Single source of truth for Pro entitlement state via RevenueCat

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var isPro = false
    @Published private(set) var offerings: Offerings?
    @Published private(set) var isLoading = false
    @Published private(set) var isConfigured = false
    @Published var errorMessage: String?

    // RevenueCat entitlement ID — set in RC dashboard
    static let proEntitlementID = "pro"

    private init() {}

    func configure(apiKey rawAPIKey: String?) {
        let apiKey = rawAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard isUsableRevenueCatKey(apiKey) else {
            errorMessage = purchaseUnavailableMessage
            return
        }

        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: apiKey)
        isConfigured = true
        errorMessage = nil

        Task { await refreshStatus() }
    }

    // MARK: - Status Check

    func refreshStatus() async {
        guard isConfigured else { return }

        do {
            let info = try await Purchases.shared.customerInfo()
            isPro = info.entitlements[Self.proEntitlementID]?.isActive == true
        } catch {
            print("[RevenueCat] Status check failed: \(error)")
        }
    }

    // MARK: - Load Offerings

    func loadOfferings() async {
        guard isConfigured else {
            errorMessage = purchaseUnavailableMessage
            return
        }

        guard offerings == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            errorMessage = "Failed to load subscription options."
        }
    }

    // MARK: - Purchase

    func purchase(package: Package) async throws {
        guard isConfigured else {
            errorMessage = purchaseUnavailableMessage
            throw SubscriptionError.purchasesUnavailable
        }

        isLoading = true
        defer { isLoading = false }
        let result = try await Purchases.shared.purchase(package: package)
        isPro = result.customerInfo.entitlements[Self.proEntitlementID]?.isActive == true
    }

    // MARK: - Restore

    func restorePurchases() async {
        guard isConfigured else {
            errorMessage = purchaseUnavailableMessage
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            isPro = info.entitlements[Self.proEntitlementID]?.isActive == true
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func isUsableRevenueCatKey(_ apiKey: String) -> Bool {
        !apiKey.isEmpty &&
        !apiKey.contains("REPLACE") &&
        !apiKey.contains("$(")
    }
}

private enum SubscriptionError: LocalizedError {
    case purchasesUnavailable

    var errorDescription: String? {
        purchaseUnavailableMessage
    }
}

// MARK: - Pro Gate Modifier

extension View {
    /// Shows paywall sheet if user is not Pro
    func requiresPro(subscriptionManager: SubscriptionManager, showPaywall: Binding<Bool>) -> some View {
        modifier(ProGateModifier(subscriptionManager: subscriptionManager, showPaywall: showPaywall))
    }
}

struct ProGateModifier: ViewModifier {
    @ObservedObject var subscriptionManager: SubscriptionManager
    @Binding var showPaywall: Bool

    func body(content: Content) -> some View {
        content
            .disabled(!subscriptionManager.isPro)
            .overlay {
                if !subscriptionManager.isPro {
                    Button { showPaywall = true } label: {
                        ZStack {
                            Color.clear
                            VStack {
                                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                                Text("Pro feature").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
    }
}
