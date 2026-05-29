import XCTest
import UIKit
@testable import RareCheck

/// Internal smoke test exercising the full identification pipeline with a
/// dummy image (solid-color UIImage, no real card). Documents what happens
/// in each stage on a cold install before the full local card index downloads.
final class ScanFlowSmokeTests: XCTestCase {

    /// Build a solid-color UIImage of the given size — stand-in for a captured photo.
    private func dummyImage(color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        color.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return img
    }

    func testCardDetectorAcceptsButFindsNothingInFlatImage() async {
        let detector = CardDetector.shared
        let img = dummyImage(color: .systemBlue, size: CGSize(width: 1024, height: 1024))
        let cropped = await detector.detectAndCrop(from: img)
        // Vision's rectangle detector should NOT find a card in a uniform image —
        // function returns nil and the pipeline falls back to the original image.
        XCTAssertNil(cropped, "Vision should not detect a card in a flat-color image")
    }

    func testOCRReturnsEmptyForFlatImage() async {
        let ocr = OCRService.shared
        let img = dummyImage(color: .systemRed, size: CGSize(width: 1024, height: 1024))
        let info = try? await ocr.extractCardInfo(from: img)
        XCTAssertNil(info?.name, "Flat image yields no OCR name")
        XCTAssertNil(info?.collectorNumber, "Flat image yields no collector number")
        XCTAssertNil(info?.setCode, "Flat image yields no set code")
    }

    func testPHashIsDeterministicForSameImage() {
        let matcher = PHashMatcher.shared
        let img = dummyImage(color: .systemGreen, size: CGSize(width: 256, height: 256))
        let a = matcher.hash(of: img)
        let b = matcher.hash(of: img)
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b, "Same image must produce same hash")
    }

    func testLocalCardIndexLoadsBundledSeedOnFreshInstall() {
        // Cold installs ship a bundled Pokemon TCG index so local lookup has
        // immediate coverage before any cache refresh runs.
        let index = LocalCardIndex.shared.index
        XCTAssertNotNil(index, "Index should be loaded on first call")
        XCTAssertGreaterThanOrEqual(index?.count ?? 0, 1_000, "Cold install should start with a broad bundled card database")
        XCTAssertTrue(index?.contains { $0.id == "det1-1" && $0.name == "Bulbasaur" } ?? false)
    }

    func testBundledCardIndexSeedIsPresentAndDecodable() throws {
        let bundles = [Bundle.main, Bundle(for: Self.self)] + Bundle.allBundles
        let seedURL = bundles
            .lazy
            .compactMap { $0.url(forResource: "rarecheck_card_index_seed", withExtension: "json") }
            .first
        let url = try XCTUnwrap(seedURL, "Seed card index should be copied into a test-visible bundle")
        let records = try JSONDecoder().decode([LocalCardRecord].self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(records.count, 1_000)
        XCTAssertTrue(records.contains { $0.id == "det1-1" && $0.name == "Bulbasaur" })
    }

    /// End-to-end: cold install + dummy image. Confirms the pipeline runs
    /// without crashing and does not depend on the remote identification API
    /// when the bundled local Pokemon DB is available.
    @MainActor
    func testIdentifyEndToEndWithDummyImageStaysLocalWhenDBIsBundled() async {
        let service = CardIdentificationService.shared
        let img = dummyImage(color: .systemYellow, size: CGSize(width: 1024, height: 1024))

        do {
            let result = try await service.identify(image: img)
            // Seed data is present on cold install, but a flat dummy image
            // should not produce a confident card match.
            XCTFail("Unexpected success — got \(result.matches.count) matches from \(result.source).")
        } catch let scanError as CardIdentificationError {
            XCTAssertNotNil(scanError.errorDescription)
        } catch let urlError as URLError {
            XCTFail("Bundled local DB scans should not surface remote service failures, got \(urlError)")
        } catch {
            XCTFail("Expected a local scan gate error, got \(error)")
        }
    }
}
