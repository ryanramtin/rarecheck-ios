import RevenueCat
import SwiftUI
import Combine

// MARK: - Subscription Manager
// Single source of truth for Pro entitlement state via RevenueCat

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var isPro = false
    @Published private(set) var offerings: Offerings?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    // RevenueCat entitlement ID — set in RC dashboard
    static let proEntitlementID = "pro"

    private init() {
        Task { await refreshStatus() }
    }

    // MARK: - Status Check

    func refreshStatus() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            isPro = info.entitlements[Self.proEntitlementID]?.isActive == true
        } catch {
            print("[RevenueCat] Status check failed: \(error)")
        }
    }

    // MARK: - Load Offerings

    func loadOfferings() async {
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
        isLoading = true
        defer { isLoading = false }
        let result = try await Purchases.shared.purchase(package: package)
        isPro = result.customerInfo.entitlements[Self.proEntitlementID]?.isActive == true
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            isPro = info.entitlements[Self.proEntitlementID]?.isActive == true
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
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
