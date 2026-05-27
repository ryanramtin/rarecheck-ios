import SwiftUI

@MainActor
final class AppNavigationState: ObservableObject {
    enum Tab {
        case scanner
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
                    Label("Scan", systemImage: "camera.viewfinder")
                }
                .tag(AppNavigationState.Tab.scanner)

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
