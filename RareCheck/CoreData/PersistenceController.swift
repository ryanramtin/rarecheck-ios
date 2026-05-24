import CoreData
import SwiftUI

// MARK: - Persistence Controller

@MainActor
final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    // Free tier limit
    static let freeCollectionLimit = 20

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "RareCheck")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error { fatalError("CoreData load failed: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Save Card

    func saveCard(_ card: CardMatch) {
        let ctx = container.viewContext

        // Check for duplicate
        let fetchRequest: NSFetchRequest<SavedCard> = SavedCard.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "cardId == %@", card.id)
        if let existing = try? ctx.fetch(fetchRequest), !existing.isEmpty { return }

        let saved = SavedCard(context: ctx)
        saved.id = UUID()
        saved.cardId = card.id
        saved.name = card.name
        saved.setName = card.setName
        saved.setCode = card.setCode
        saved.collectorNumber = card.collectorNumber
        saved.rarity = card.rarity
        saved.imageURL = card.imageURL
        saved.currentPriceLow = card.price.low
        saved.currentPriceMid = card.price.mid
        saved.currentPriceHigh = card.price.high
        saved.currentPriceMarket = card.price.market
        saved.addedAt = Date()

        try? ctx.save()
    }

    // MARK: - Delete Card

    func deleteCard(_ savedCard: SavedCard) {
        container.viewContext.delete(savedCard)
        try? container.viewContext.save()
    }

    // MARK: - Collection Count

    func collectionCount() -> Int {
        let req: NSFetchRequest<SavedCard> = SavedCard.fetchRequest()
        return (try? container.viewContext.count(for: req)) ?? 0
    }

    func isAtFreeLimit() -> Bool {
        collectionCount() >= Self.freeCollectionLimit
    }

    // MARK: - CSV Export (Pro)

    func exportCSV() -> String {
        let req: NSFetchRequest<SavedCard> = SavedCard.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        let cards = (try? container.viewContext.fetch(req)) ?? []

        var csv = "Name,Set,Set Code,Collector #,Rarity,Market Price,Low,Mid,High,Added\n"
        let df = ISO8601DateFormatter()
        for card in cards {
            csv += "\"\(card.name ?? "")\",\"\(card.setName ?? "")\",\(card.setCode ?? ""),\(card.collectorNumber ?? ""),\"\(card.rarity ?? "")\",\(card.currentPriceMarket),\(card.currentPriceLow),\(card.currentPriceMid),\(card.currentPriceHigh),\(df.string(from: card.addedAt ?? Date()))\n"
        }
        return csv
    }

    // MARK: - Preview helper

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        return controller
    }()
}
