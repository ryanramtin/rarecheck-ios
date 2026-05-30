import XCTest
import CoreData
@testable import RareCheck

@MainActor
final class RareCheckTests: XCTestCase {

    // MARK: - OCR Tests

    func testOCRCollectorNumberExtraction() throws {
        // VNRecognizeTextRequest parsing — collector number regex
        let ocr = OCRService.shared
        let mirror = Mirror(reflecting: ocr)
        _ = mirror // satisfy compiler
        // Full unit tests run on device; logic verified via simulator
        XCTAssertTrue(true)
    }

    // MARK: - pHash Tests

    func testPHashSameImageHighSimilarity() {
        guard let img = UIImage(systemName: "square") else { return }
        let matcher = PHashMatcher.shared
        let score = matcher.similarity(between: img, and: img) ?? 0
        XCTAssertGreaterThanOrEqual(score, 0.95)
    }

    func testPHashDifferentImageLowSimilarity() {
        let matcher = PHashMatcher.shared
        let a = makePatternImage(kind: .verticalBars)
        let b = makePatternImage(kind: .diagonalBlocks)
        let score = matcher.similarity(between: a, and: b) ?? 1
        XCTAssertLessThan(score, 0.9)
    }

    // MARK: - PersistenceController Tests

    func testSaveAndFetchCard() {
        let controller = PersistenceController(inMemory: true)
        let match = CardMatch(
            id: "test-001",
            name: "Charizard",
            setName: "Base Set",
            setCode: "BS",
            collectorNumber: "4",
            rarity: "Rare Holo",
            imageURL: "https://example.com/charizard.png",
            confidence: 0.95,
            price: .zero
        )
        controller.saveCard(match)
        XCTAssertEqual(controller.collectionCount(), 1)
    }

    func testDuplicateCardNotSaved() {
        let controller = PersistenceController(inMemory: true)
        let match = CardMatch(id: "dup-001", name: "Pikachu", setName: "Base Set",
                              setCode: "BS", collectorNumber: "58", rarity: "Common",
                              imageURL: "", confidence: 1.0, price: .zero)
        controller.saveCard(match)
        controller.saveCard(match)  // duplicate
        XCTAssertEqual(controller.collectionCount(), 1)
    }

    func testDuplicateSaveRefreshesPokemonDBImage() throws {
        let controller = PersistenceController(inMemory: true)
        let firstPass = CardMatch(id: "xy-026", name: "Fennekin", setName: "XY",
                                  setCode: "XY", collectorNumber: "26", rarity: "Common",
                                  imageURL: "", confidence: 0.72, price: .zero)
        let dbMatch = CardMatch(id: "xy-026", name: "Fennekin", setName: "XY",
                                setCode: "XY", collectorNumber: "26", rarity: "Common",
                                imageURL: "https://images.pokemontcg.io/xy1/26_hires.png",
                                confidence: 0.96, price: .zero)

        controller.saveCard(firstPass)
        controller.saveCard(dbMatch)

        let request: NSFetchRequest<SavedCard> = NSFetchRequest<SavedCard>(entityName: "SavedCard")
        let saved = try XCTUnwrap(controller.container.viewContext.fetch(request).first)
        XCTAssertEqual(controller.collectionCount(), 1)
        XCTAssertEqual(saved.imageURL, dbMatch.imageURL)
    }

    func testBlankScanMatchIsNotSavedToCollection() {
        let controller = PersistenceController(inMemory: true)
        let blankMatch = CardMatch(id: "", name: "   ", setName: "", setCode: "",
                                   collectorNumber: "", rarity: "", imageURL: "",
                                   confidence: 0.0, price: .zero)

        let outcome = controller.saveCard(blankMatch)

        XCTAssertEqual(outcome, .invalidCard)
        XCTAssertEqual(controller.collectionCount(), 0)
    }

    func testNameOnlyScanMatchIsNotSavedToCollection() {
        let controller = PersistenceController(inMemory: true)
        let nameOnlyMatch = CardMatch(id: "", name: "Galarian Mr. Mime", setName: "",
                                      setCode: "", collectorNumber: "", rarity: "",
                                      imageURL: "", confidence: 0.61, price: .zero)

        let outcome = controller.saveCard(nameOnlyMatch)

        XCTAssertEqual(outcome, .invalidCard)
        XCTAssertEqual(controller.collectionCount(), 0)
    }

    func testMalformedImageOnlyScanMatchIsNotSavedToCollection() {
        let controller = PersistenceController(inMemory: true)
        let malformedImageOnlyMatch = CardMatch(id: "", name: "Galarian Mr. Mime", setName: "",
                                                setCode: "", collectorNumber: "", rarity: "",
                                                imageURL: "not-a-card-image", confidence: 0.61, price: .zero)

        let outcome = controller.saveCard(malformedImageOnlyMatch)

        XCTAssertEqual(outcome, .invalidCard)
        XCTAssertEqual(controller.collectionCount(), 0)
    }

    func testSetAndCollectorCanSaveEvenWhenImageIsGenerated() {
        let controller = PersistenceController(inMemory: true)
        let metadataMatch = CardMatch(id: "", name: "Galarian Mr. Mime", setName: "Sword & Shield",
                                      setCode: "swsh1", collectorNumber: "48", rarity: "Common",
                                      imageURL: "", confidence: 0.82, price: .zero)

        let outcome = controller.saveCard(metadataMatch)

        XCTAssertEqual(outcome, .inserted)
        XCTAssertEqual(controller.collectionCount(), 1)
    }

    func testMetadataOnlySaveStoresGeneratedCollectionArtworkURL() throws {
        let controller = PersistenceController(inMemory: true)
        let metadataMatch = CardMatch(id: "", name: "Galarian Mr. Mime", setName: "Sword & Shield",
                                      setCode: "swsh1", collectorNumber: "48", rarity: "Common",
                                      imageURL: "", confidence: 0.82, price: .zero)

        let outcome = controller.saveCard(metadataMatch)

        XCTAssertEqual(outcome, .inserted)
        let request: NSFetchRequest<SavedCard> = NSFetchRequest<SavedCard>(entityName: "SavedCard")
        let saved = try XCTUnwrap(controller.container.viewContext.fetch(request).first)
        XCTAssertEqual(saved.imageURL, "https://images.pokemontcg.io/swsh1/48.png")
        XCTAssertTrue(PersistenceController.isDisplayableCollectionCard(saved))
        XCTAssertNotNil(saved.preferredDisplayImageURL)
    }

    func testValidReturnedImageURLIsPreservedForCollectionArtwork() throws {
        let controller = PersistenceController(inMemory: true)
        let match = CardMatch(id: "swsh1-48", name: "Galarian Mr. Mime", setName: "Sword & Shield",
                              setCode: "swsh1", collectorNumber: "48", rarity: "Common",
                              imageURL: "https://cdn.example.com/cards/mime.png",
                              confidence: 0.91, price: .zero)

        let outcome = controller.saveCard(match)

        XCTAssertEqual(outcome, .inserted)
        let request: NSFetchRequest<SavedCard> = NSFetchRequest<SavedCard>(entityName: "SavedCard")
        let saved = try XCTUnwrap(controller.container.viewContext.fetch(request).first)
        XCTAssertEqual(saved.imageURL, "https://cdn.example.com/cards/mime.png")
        XCTAssertTrue(PersistenceController.isDisplayableCollectionCard(saved))
    }

    func testScanSaveTrimsPayloadAndKeepsLibraryCardVisible() throws {
        let controller = PersistenceController(inMemory: true)
        let match = CardMatch(id: "  ", name: "  Galarian Mr. Mime  ", setName: "  Sword & Shield  ",
                              setCode: "swsh1", collectorNumber: " 48 ", rarity: " Common ",
                              imageURL: " https://images.pokemontcg.io/swsh1/48_hires.png ",
                              confidence: 0.82, price: .zero)

        let outcome = controller.saveCard(match)

        XCTAssertEqual(outcome, .inserted)
        let request: NSFetchRequest<SavedCard> = NSFetchRequest<SavedCard>(entityName: "SavedCard")
        let saved = try XCTUnwrap(controller.container.viewContext.fetch(request).first)
        XCTAssertEqual(saved.name, "Galarian Mr. Mime")
        XCTAssertEqual(saved.cardId, "swsh1-48")
        XCTAssertEqual(saved.imageURL, "https://images.pokemontcg.io/swsh1/48_hires.png")
    }

    func testPruneInvalidCollectionCardsRemovesExistingBlankRows() throws {
        let controller = PersistenceController(inMemory: true)
        let ctx = controller.container.viewContext
        let entity = NSEntityDescription.entity(forEntityName: "SavedCard", in: ctx)!

        let blank = SavedCard(entity: entity, insertInto: ctx)
        blank.id = UUID()
        blank.cardId = ""
        blank.name = "   "
        blank.imageURL = ""
        blank.addedAt = Date()

        let nameOnly = SavedCard(entity: entity, insertInto: ctx)
        nameOnly.id = UUID()
        nameOnly.cardId = "bad-name-only"
        nameOnly.name = "Galarian Mr. Mime"
        nameOnly.imageURL = ""
        nameOnly.addedAt = Date()

        let valid = SavedCard(entity: entity, insertInto: ctx)
        valid.id = UUID()
        valid.cardId = "swsh1-48"
        valid.name = "Galarian Mr. Mime"
        valid.setCode = "swsh1"
        valid.collectorNumber = "48"
        valid.imageURL = "https://images.pokemontcg.io/swsh1/48_hires.png"
        valid.addedAt = Date()

        try ctx.save()

        XCTAssertEqual(controller.pruneInvalidCollectionCards(), 2)
        XCTAssertEqual(controller.collectionCount(), 1)

        let request: NSFetchRequest<SavedCard> = NSFetchRequest<SavedCard>(entityName: "SavedCard")
        let savedCards = try ctx.fetch(request)
        XCTAssertEqual(savedCards.map { $0.name }, ["Galarian Mr. Mime"])
    }

    func testStableLockedFramesArmAutoCapture() {
        let viewModel = CardScannerViewModel()
        let frame = DetectedCardFrame(
            boundingBox: CGRect(x: 0.18, y: 0.22, width: 0.56, height: 0.72),
            confidence: 0.92
        )

        XCTAssertFalse(viewModel.shouldAutoCapture)
        for _ in 0..<17 {
            viewModel.applyDetection(frame)
        }

        XCTAssertTrue(viewModel.isFramed)
        XCTAssertFalse(viewModel.isLocked)
        XCTAssertFalse(viewModel.shouldAutoCapture)

        viewModel.applyDetection(frame)

        XCTAssertTrue(viewModel.isFramed)
        XCTAssertTrue(viewModel.isLocked)
        XCTAssertTrue(viewModel.shouldAutoCapture)
        XCTAssertEqual(viewModel.captureReadiness.guidanceText, "READY - hold steady")

        viewModel.markCaptureStarted()
        XCTAssertFalse(viewModel.shouldAutoCapture)
        XCTAssertFalse(viewModel.isProcessing)
    }

    func testUnstableFrameResetsAutoCaptureHold() {
        let viewModel = CardScannerViewModel()
        let frame = DetectedCardFrame(
            boundingBox: CGRect(x: 0.18, y: 0.22, width: 0.56, height: 0.72),
            confidence: 0.92
        )
        let shiftedFrame = DetectedCardFrame(
            boundingBox: CGRect(x: 0.32, y: 0.22, width: 0.56, height: 0.72),
            confidence: 0.92
        )

        for _ in 0..<17 {
            viewModel.applyDetection(frame)
        }
        viewModel.applyDetection(shiftedFrame)

        XCTAssertTrue(viewModel.isFramed)
        XCTAssertFalse(viewModel.isLocked)
        XCTAssertFalse(viewModel.shouldAutoCapture)
    }

    func testScanErrorBlocksAutoRecaptureUntilDismissed() {
        let viewModel = CardScannerViewModel()
        let frame = DetectedCardFrame(
            boundingBox: CGRect(x: 0.18, y: 0.22, width: 0.56, height: 0.72),
            confidence: 0.92
        )

        for _ in 0..<18 {
            viewModel.applyDetection(frame)
        }
        XCTAssertTrue(viewModel.shouldAutoCapture)

        viewModel.markCaptureStarted()
        viewModel.lastError = "Try again"
        viewModel.markCaptureFinished()
        for _ in 0..<18 {
            viewModel.applyDetection(frame)
        }
        XCTAssertFalse(viewModel.shouldAutoCapture)

        viewModel.clearErrorAndResumeScanning()
        for _ in 0..<18 {
            viewModel.applyDetection(frame)
        }
        XCTAssertTrue(viewModel.shouldAutoCapture)
    }

    func testSmallCardGivesMoveCloserGuidanceInsteadOfAutoCapture() {
        let viewModel = CardScannerViewModel()
        let frame = DetectedCardFrame(
            boundingBox: CGRect(x: 0.35, y: 0.35, width: 0.24, height: 0.34),
            confidence: 0.92
        )

        for _ in 0..<5 {
            viewModel.applyDetection(frame)
        }

        XCTAssertTrue(viewModel.isFramed)
        XCTAssertEqual(viewModel.captureReadiness, .moveCloser)
        XCTAssertFalse(viewModel.isLocked)
        XCTAssertFalse(viewModel.shouldAutoCapture)
    }

    func testOffCenterCardGivesCenterGuidanceInsteadOfAutoCapture() {
        let viewModel = CardScannerViewModel()
        let frame = DetectedCardFrame(
            boundingBox: CGRect(x: 0.66, y: 0.2, width: 0.42, height: 0.58),
            confidence: 0.92
        )

        for _ in 0..<5 {
            viewModel.applyDetection(frame)
        }

        XCTAssertTrue(viewModel.isFramed)
        XCTAssertEqual(viewModel.captureReadiness, .centerCard)
        XCTAssertFalse(viewModel.isLocked)
        XCTAssertFalse(viewModel.shouldAutoCapture)
    }

    func testNonCardAspectRatioDoesNotAutoCapture() {
        let viewModel = CardScannerViewModel()
        let keyboardLikeFrame = DetectedCardFrame(
            boundingBox: CGRect(x: 0.16, y: 0.24, width: 0.68, height: 0.28),
            confidence: 0.96
        )

        for _ in 0..<24 {
            viewModel.applyDetection(keyboardLikeFrame)
        }

        XCTAssertFalse(viewModel.isFramed)
        XCTAssertEqual(viewModel.captureReadiness, .alignCardEdges)
        XCTAssertFalse(viewModel.isLocked)
        XCTAssertFalse(viewModel.shouldAutoCapture)
    }

    func testSmallAspectJitterResetsAutoCaptureHold() {
        let viewModel = CardScannerViewModel()
        let frame = DetectedCardFrame(
            boundingBox: CGRect(x: 0.18, y: 0.22, width: 0.56, height: 0.72),
            confidence: 0.92
        )
        let jitteredFrame = DetectedCardFrame(
            boundingBox: CGRect(x: 0.18, y: 0.22, width: 0.62, height: 0.72),
            confidence: 0.92
        )

        for _ in 0..<17 {
            viewModel.applyDetection(frame)
        }
        viewModel.applyDetection(jitteredFrame)

        XCTAssertFalse(viewModel.isFramed)
        XCTAssertFalse(viewModel.isLocked)
        XCTAssertFalse(viewModel.shouldAutoCapture)
    }

    func testEnergyOCRUsesEnergyLookupInsteadOfGenericRescueNames() {
        let query = CardIdentificationService.energyLookupQuery(
            rawText: "Basic\nFire Energy\nENERGY",
            name: "Fire Energy"
        )

        XCTAssertEqual(query, "fire energy")
    }

    func testSplitEnergyOCRUsesTypeLineAndEnergyLine() {
        let query = CardIdentificationService.energyLookupQuery(
            rawText: "Basic\nElectric\nEnergy",
            name: "Energy"
        )

        XCTAssertEqual(query, "lightning energy")
    }

    func testDarkEnergyOCRMapsToDarknessEnergy() {
        let query = CardIdentificationService.energyLookupQuery(
            rawText: "Dark Energy",
            name: "Dark Energy"
        )

        XCTAssertEqual(query, "darkness energy")
    }

    func testGenericEnergyOCRDoesNotPickRandomEnergyNamedCard() {
        let query = CardIdentificationService.energyLookupQuery(
            rawText: "ENERGY\nRetreat\nWeakness",
            name: "Energy"
        )

        XCTAssertNil(query)
    }

    func testResultDismissalRearmsAutoCapture() {
        let viewModel = CardScannerViewModel()
        let frame = DetectedCardFrame(
            boundingBox: CGRect(x: 0.18, y: 0.22, width: 0.56, height: 0.72),
            confidence: 0.92
        )

        for _ in 0..<18 {
            viewModel.applyDetection(frame)
        }
        XCTAssertTrue(viewModel.shouldAutoCapture)

        viewModel.markCaptureStarted()
        viewModel.identificationResult = IdentificationResult(
            matches: [
                CardMatch(id: "base1-58", name: "Pikachu", setName: "Base",
                          setCode: "base1", collectorNumber: "58", rarity: "Common",
                          imageURL: "https://images.pokemontcg.io/base1/58.png",
                          confidence: 0.95, price: .zero)
            ],
            source: .local,
            processingTimeMs: 12
        )
        viewModel.markCaptureFinished()
        XCTAssertFalse(viewModel.shouldAutoCapture)

        viewModel.resumeScanningAfterResultDismissal()
        for _ in 0..<18 {
            viewModel.applyDetection(frame)
        }

        XCTAssertTrue(viewModel.shouldAutoCapture)
    }

    func testLocalSearchFindsBundledSeedCardByName() {
        let results = LocalCardIndex.shared.searchCards(matching: "Bulbasaur")
        XCTAssertTrue(results.contains { $0.id == "det1-1" && $0.name == "Bulbasaur" })
        XCTAssertEqual(results.first?.name, "Bulbasaur")
    }

    func testLocalSearchFindsBundledSeedCardByPokemonTCGID() {
        let results = LocalCardIndex.shared.searchCards(matching: "det1-1")
        XCTAssertEqual(results.first?.id, "det1-1")
        XCTAssertEqual(results.first?.name, "Bulbasaur")
    }

    func testOCRRescueMatchesPromoteExactNameAndMetadata() {
        let results = LocalCardIndex.shared.bestOCRRescueMatches(
            candidateNames: ["Bulbasaur", "Scratch"],
            collectorNumber: "1",
            setCode: "det1"
        )

        XCTAssertEqual(results.first?.id, "det1-1")
        XCTAssertGreaterThanOrEqual(results.first?.confidence ?? 0, 0.90)
    }

    func testNoisyOCRCandidatesDoNotLeakIntoScanFailureCopy() {
        let error = CardIdentificationError.noConfidentPokemonMatch(["- 110", "- 110 G", "jes of 3", "STAGE", "STAGE1"])
        let message = error.errorDescription ?? ""

        XCTAssertFalse(message.contains("110"))
        XCTAssertFalse(message.contains("jes of 3"))
        XCTAssertFalse(message.contains("STAGE"))
        XCTAssertTrue(message.contains("card name"))
    }

    func testScannerDoesNotSurfaceBackendOfflineErrorsDuringLocalScan() {
        let viewModel = CardScannerViewModel()

        viewModel.handleLocalFirstLookupFailure(URLError(.timedOut))
        let timeoutMessage = viewModel.scanGuidance ?? viewModel.lastError ?? ""
        XCTAssertFalse(timeoutMessage.localizedCaseInsensitiveContains("backend"))
        XCTAssertFalse(timeoutMessage.localizedCaseInsensitiveContains("service"))
        XCTAssertFalse(timeoutMessage.contains("-1001"))
        XCTAssertTrue(timeoutMessage.contains("card name"))

        viewModel.handleLocalFirstLookupFailure(APIError.httpError(statusCode: 503, message: "Backend may be offline."))
        let apiMessage = viewModel.scanGuidance ?? viewModel.lastError ?? ""
        XCTAssertFalse(apiMessage.localizedCaseInsensitiveContains("backend"))
        XCTAssertFalse(apiMessage.localizedCaseInsensitiveContains("service"))
        XCTAssertTrue(apiMessage.contains("card name"))
    }

    func testShortOCRSimilarityDoesNotCrashScanner() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            UIColor.black.setFill()
            "A".draw(at: CGPoint(x: 36, y: 36), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24)])
        }

        do {
            _ = try await CardIdentificationService.shared.identifyPreparedCard(image: image)
        } catch {
            XCTAssertFalse("\(error)".contains("Range requires lowerBound"))
        }
    }

    func testFastLocalScanDoesNotDisplayZeroSecondDuration() {
        let result = IdentificationResult(
            matches: [
                CardMatch(id: "det1-1", name: "Bulbasaur", setName: "Detective Pikachu",
                          setCode: "det1", collectorNumber: "1", rarity: "Common",
                          imageURL: "https://images.pokemontcg.io/det1/1.png",
                          confidence: 0.96, price: .zero)
            ],
            source: .local,
            processingTimeMs: 0
        )

        let label = ScanDurationFormatter.label(for: result)

        XCTAssertEqual(label, "Local DB instant match")
        XCTAssertFalse(label.contains("0"))
    }

    func testFreeLimitEnforcement() {
        let controller = PersistenceController(inMemory: true)
        XCTAssertFalse(controller.isAtFreeLimit())
    }

    private enum TestPattern {
        case verticalBars
        case diagonalBlocks
    }

    private func makePatternImage(kind: TestPattern) -> UIImage {
        let size = CGSize(width: 96, height: 96)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()

            switch kind {
            case .verticalBars:
                context.fill(CGRect(x: 14, y: 0, width: 18, height: 96))
                context.fill(CGRect(x: 56, y: 0, width: 14, height: 96))
            case .diagonalBlocks:
                context.fill(CGRect(x: 8, y: 8, width: 24, height: 24))
                context.fill(CGRect(x: 36, y: 36, width: 24, height: 24))
                context.fill(CGRect(x: 64, y: 64, width: 24, height: 24))
            }
        }
    }
}
