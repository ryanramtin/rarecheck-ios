import SwiftUI
import RevenueCat

@main
struct RareCheckApp: App {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var persistenceController = PersistenceController.shared
    @StateObject private var appNavigation = AppNavigationState()

    init() {
        configureRevenueCat()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(subscriptionManager)
                .environmentObject(appNavigation)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }

    private func configureRevenueCat() {
        // Replace with your actual RevenueCat API key from dashboard
        Purchases.configure(withAPIKey: "appl_REPLACE_WITH_YOUR_REVENUECAT_KEY")
        Purchases.logLevel = .debug
    }
}
