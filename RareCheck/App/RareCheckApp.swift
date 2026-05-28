import SwiftUI

@main
struct RareCheckApp: App {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var persistenceController = PersistenceController.shared
    @StateObject private var appNavigation = AppNavigationState()

    init() {
        configurePurchases()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(subscriptionManager)
                .environmentObject(appNavigation)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .task {
                    await LocalCardIndex.shared.refreshFromPokemonTCGIfNeeded()
                }
        }
    }

    private func configurePurchases() {
        let apiKey = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String
        subscriptionManager.configure(apiKey: apiKey)
    }
}
