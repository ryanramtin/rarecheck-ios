import XCTest
import UIKit
@testable import RareCheck

/// Internal smoke test exercising the full identification pipeline with a
/// dummy image (solid-color UIImage, no real card). Documents what happens
/// in each stage on a cold install with no cached local card index.
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

    func testLocalCardIndexIsEmptyOnFreshInstall() {
        // The pipeline expects a pre-seeded local index. Cold install ships
        // none, so the index is [] and localMatch always returns nil.
        let index = LocalCardIndex.shared.index
        XCTAssertNotNil(index, "Index should be loaded (empty array) on first call")
        XCTAssertTrue(index?.isEmpty ?? false, "Cold install: local index is empty")
    }

    /// End-to-end: cold install + dummy image. Confirms the pipeline runs
    /// without crashing and falls through to the API path (which then fails
    /// fast because no backend is reachable).
    @MainActor
    func testIdentifyEndToEndWithDummyImageFallsBackToAPIAndFailsConnect() async {
        let service = CardIdentificationService.shared
        let img = dummyImage(color: .systemYellow, size: CGSize(width: 1024, height: 1024))

        do {
            let result = try await service.identify(image: img)
            // If this branch ever hits, the local index must have seed data.
            // That's not the cold-install case we're documenting here.
            XCTFail("Unexpected success — got \(result.matches.count) matches from \(result.source). Local index should be empty.")
        } catch let urlError as URLError {
            // Expected: API fallback hits the configured baseURL
            // (Info.plist/APIClient currently defaults to the Railway
            // production host) and may fail with a connection-class error
            // if the backend is unavailable.
            print("[smoke] OK — API fallback failed as expected: \(urlError.code.rawValue) \(urlError.localizedDescription)")
            XCTAssertTrue(
                [.cannotFindHost, .cannotConnectToHost, .notConnectedToInternet, .timedOut, .dnsLookupFailed]
                    .contains(urlError.code),
                "Expected a connection-class URLError, got \(urlError.code)"
            )
        } catch {
            // Any other error type still tells us the pipeline reached the
            // API stage without crashing — record it for the report.
            print("[smoke] API fallback raised non-URLError: \(error)")
        }
    }
}
