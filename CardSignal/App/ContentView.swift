import SwiftUI

struct ContentView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var selectedTab: Tab = .scanner

    enum Tab {
        case scanner, collection, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ScannerContainerView()
                .tabItem {
                    Label("Scan", systemImage: "camera.viewfinder")
                }
                .tag(Tab.scanner)

            CollectionView()
                .tabItem {
                    Label("Collection", systemImage: "rectangle.stack")
                }
                .tag(Tab.collection)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
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
                    Link("Privacy Policy", destination: URL(string: "https://cardsignal.app/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://cardsignal.app/terms")!)
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
