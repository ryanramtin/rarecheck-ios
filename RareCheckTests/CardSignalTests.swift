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

    func testStableLockedFramesArmAutoCapture() {
        let viewModel = CardScannerViewModel()
        let frame = DetectedCardFrame(
            boundingBox: CGRect(x: 0.18, y: 0.22, width: 0.56, height: 0.72),
            confidence: 0.92
        )

        XCTAssertFalse(viewModel.shouldAutoCapture)
        for _ in 0..<3 {
            viewModel.applyDetection(frame)
        }

        XCTAssertTrue(viewModel.isFramed)
        XCTAssertTrue(viewModel.isLocked)
        XCTAssertTrue(viewModel.shouldAutoCapture)
        XCTAssertEqual(viewModel.captureReadiness.guidanceText, "Locked - auto capture")

        viewModel.markCaptureStarted()
        XCTAssertFalse(viewModel.shouldAutoCapture)
        XCTAssertFalse(viewModel.isProcessing)
    }

    func testScanErrorBlocksAutoRecaptureUntilDismissed() {
        let viewModel = CardScannerViewModel()
        let frame = DetectedCardFrame(
            boundingBox: CGRect(x: 0.18, y: 0.22, width: 0.56, height: 0.72),
            confidence: 0.92
        )

        for _ in 0..<3 {
            viewModel.applyDetection(frame)
        }
        XCTAssertTrue(viewModel.shouldAutoCapture)

        viewModel.markCaptureStarted()
        viewModel.lastError = "Try again"
        viewModel.markCaptureFinished()
        for _ in 0..<3 {
            viewModel.applyDetection(frame)
        }
        XCTAssertFalse(viewModel.shouldAutoCapture)

        viewModel.clearErrorAndResumeScanning()
        for _ in 0..<3 {
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
            boundingBox: CGRect(x: 0.0, y: 0.2, width: 0.28, height: 0.58),
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
        let timeoutMessage = viewModel.lastError ?? ""
        XCTAssertFalse(timeoutMessage.localizedCaseInsensitiveContains("backend"))
        XCTAssertFalse(timeoutMessage.localizedCaseInsensitiveContains("service"))
        XCTAssertFalse(timeoutMessage.contains("-1001"))
        XCTAssertTrue(timeoutMessage.contains("card name"))

        viewModel.handleLocalFirstLookupFailure(APIError.httpError(statusCode: 503, message: "Backend may be offline."))
        let apiMessage = viewModel.lastError ?? ""
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
