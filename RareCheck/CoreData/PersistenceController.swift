import CoreData
import SwiftUI

// MARK: - Persistence Controller

@MainActor
final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    enum SaveOutcome {
        case inserted
        case updated
        case limitReached
    }

    let container: NSPersistentContainer

    // Free tier limit
    nonisolated static let freeCollectionLimit = 20

    init(inMemory: Bool = false) {
        // Load the managed object model explicitly from the main bundle so
        // CoreData doesn't auto-scan all loaded bundles and find duplicate
        // entity definitions (which logs "Failed to find a unique match for
        // an NSEntityDescription to a managed object subclass" warnings
        // when both the app and test bundles are loaded together).
        let model: NSManagedObjectModel = {
            guard let url = Bundle.main.url(forResource: "RareCheck", withExtension: "momd"),
                  let m = NSManagedObjectModel(contentsOf: url) else {
                // Fallback: merged model from all bundles (legacy behavior).
                return NSManagedObjectModel.mergedModel(from: nil) ?? NSManagedObjectModel()
            }
            return m
        }()
        container = NSPersistentContainer(name: "RareCheck", managedObjectModel: model)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error {
                assertionFailure("CoreData load failed: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Save Card

    @discardableResult
    func saveCard(_ card: CardMatch, isPro: Bool = false) -> SaveOutcome {
        let ctx = container.viewContext

        // Existing saves should be refreshed when the database returns better
        // metadata later, especially imageURL after an initial fuzzy match.
        let fetchRequest: NSFetchRequest<SavedCard> = NSFetchRequest<SavedCard>(entityName: "SavedCard")
        fetchRequest.predicate = NSPredicate(format: "cardId == %@", card.id)
        if let existing = try? ctx.fetch(fetchRequest), let saved = existing.first {
            apply(card, to: saved, preserveAddedAt: false)
            try? ctx.save()
            return .updated
        }

        guard isPro || !isAtFreeLimit() else {
            return .limitReached
        }

        // Use the entity from our container's model explicitly, so we don't
        // hit "Failed to find a unique match" warnings if multiple bundles
        // (app + tests) each register the same model.
        let entity = NSEntityDescription.entity(forEntityName: "SavedCard", in: ctx)!
        let saved = SavedCard(entity: entity, insertInto: ctx)
        apply(card, to: saved, preserveAddedAt: false)
        saved.addedAt = Date()

        try? ctx.save()
        return .inserted
    }

    private func apply(_ card: CardMatch, to saved: SavedCard, preserveAddedAt: Bool) {
        if saved.id == nil {
            saved.id = UUID()
        }
        saved.cardId = card.id
        saved.name = card.name
        saved.setName = card.setName
        saved.setCode = card.setCode
        saved.collectorNumber = card.collectorNumber
        saved.rarity = card.rarity
        let preferredImageURL = card.preferredCollectionImageURL
        if !preferredImageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saved.imageURL = preferredImageURL
        }
        saved.currentPriceLow = card.price.low
        saved.currentPriceMid = card.price.mid
        saved.currentPriceHigh = card.price.high
        saved.currentPriceMarket = card.price.market
        if !preserveAddedAt || saved.addedAt == nil {
            saved.addedAt = Date()
        }
    }

    // MARK: - Delete Card

    func deleteCard(_ savedCard: SavedCard) {
        container.viewContext.delete(savedCard)
        try? container.viewContext.save()
    }

    // MARK: - Collection Count

    func collectionCount() -> Int {
        let req: NSFetchRequest<SavedCard> = NSFetchRequest<SavedCard>(entityName: "SavedCard")
        return (try? container.viewContext.count(for: req)) ?? 0
    }

    func isAtFreeLimit() -> Bool {
        collectionCount() >= Self.freeCollectionLimit
    }

    // MARK: - CSV Export (Pro)

    func exportCSV() -> String {
        let req: NSFetchRequest<SavedCard> = NSFetchRequest<SavedCard>(entityName: "SavedCard")
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
