import CoreData
import SwiftUI
import Combine

@MainActor
final class CollectionViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var sortOption: SortOption = .dateAdded
    @Published var filterRarity: String? = nil
    @Published var showCSVExport = false
    @Published var csvContent = ""

    enum SortOption: String, CaseIterable, Identifiable {
        case dateAdded = "Date Added"
        case name = "Name"
        case priceHighToLow = "Price ↓"
        case priceLowToHigh = "Price ↑"
        var id: String { rawValue }
    }

    var sortDescriptors: [NSSortDescriptor] {
        switch sortOption {
        case .dateAdded: return [NSSortDescriptor(key: "addedAt", ascending: false)]
        case .name:      return [NSSortDescriptor(key: "name", ascending: true)]
        case .priceHighToLow: return [NSSortDescriptor(key: "currentPriceMarket", ascending: false)]
        case .priceLowToHigh: return [NSSortDescriptor(key: "currentPriceMarket", ascending: true)]
        }
    }

    var predicate: NSPredicate? {
        var predicates: [NSPredicate] = []
        if !searchText.isEmpty {
            predicates.append(NSPredicate(format: "name CONTAINS[cd] %@ OR setName CONTAINS[cd] %@",
                                          searchText, searchText))
        }
        if let rarity = filterRarity {
            predicates.append(NSPredicate(format: "rarity == %@", rarity))
        }
        return predicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    func exportCSV() {
        csvContent = PersistenceController.shared.exportCSV()
        showCSVExport = true
    }

    func totalValue(cards: [SavedCard]) -> Double {
        cards.reduce(0) { $0 + $1.currentPriceMarket }
    }
}
