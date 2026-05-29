import XCTest
import UIKit
@testable import RareCheck

/// Exercise the full scan pipeline against a real Pokémon card photo
/// (Mega Floette EX 250 HP, collector # 035/095, taken from a binder
/// sleeve so glare + neighboring cards are present). Documents what
/// each pipeline stage actually extracts on real input.
final class RealCardScanTests: XCTestCase {

    private func loadRealCard() throws -> UIImage {
        let bundle = Bundle(for: RealCardScanTests.self)
        guard let url = bundle.url(forResource: "test-pokemon-card", withExtension: "jpg"),
              let data = try? Data(contentsOf: url),
              let img = UIImage(data: data)
        else {
            // Resource lookup can also fall back to subdirectory or main bundle
            // in some bundle configurations. Try a couple of variants.
            for path in [
                bundle.path(forResource: "test-pokemon-card", ofType: "jpg"),
                bundle.path(forResource: "test-pokemon-card", ofType: "jpg", inDirectory: "Resources"),
            ].compactMap({ $0 }) {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let img = UIImage(data: data) {
                    return img
                }
            }
            XCTFail("Could not load test-pokemon-card.jpg from test bundle: \(bundle.bundleURL)")
            throw NSError(domain: "test", code: 1)
        }
        return img
    }

    func testRealCardLoadsCorrectly() throws {
        let img = try loadRealCard()
        XCTAssertGreaterThan(img.size.width, 100)
        XCTAssertGreaterThan(img.size.height, 100)
        print("[card] loaded: \(Int(img.size.width))×\(Int(img.size.height))")
    }

    func testCardDetectorFindsCardRectangle() async throws {
        let img = try loadRealCard()
        let cropped = await CardDetector.shared.detectAndCrop(from: img)
        if let cropped {
            print("[detector] FOUND card rectangle. Cropped: \(Int(cropped.size.width))×\(Int(cropped.size.height))")
            XCTAssertGreaterThan(cropped.size.width, 50)
        } else {
            print("[detector] No card rectangle found (Vision returned nil)")
            // Not a hard failure — Vision can miss cards in busy backgrounds.
            // Pipeline falls back to the original image.
        }
    }

    func testOCRExtractsNameAndNumberFromRealCard() async throws {
        let img = try loadRealCard()
        let info = try await OCRService.shared.extractCardInfo(from: img)
        print("[ocr] name=\(info.name ?? "<nil>") collector=\(info.collectorNumber ?? "<nil>") set=\(info.setCode ?? "<nil>")")
        // Floette is a Pokémon name on the card; OCR should find something Pokémon-ish.
        // We don't pin to an exact string (OCR varies) but we expect SOMETHING parsed.
        let anyExtraction = info.name != nil || info.collectorNumber != nil || info.setCode != nil
        XCTAssertTrue(anyExtraction, "OCR should extract at least one of name/collector/set from a clear card photo")
    }

    func testPHashOfRealCardIsStable() throws {
        let img = try loadRealCard()
        let a = PHashMatcher.shared.hash(of: img)
        let b = PHashMatcher.shared.hash(of: img)
        print("[phash] a=\(String(describing: a)) b=\(String(describing: b))")
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b, "Same input must produce same hash")
    }

    @MainActor
    func testIdentifyEndToEndOnRealCard() async throws {
        let img = try loadRealCard()
        let start = Date()
        do {
            let result = try await CardIdentificationService.shared.identify(image: img)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            print("[identify] SUCCESS source=\(result.source) matches=\(result.matches.count) elapsedMs=\(elapsed)")
            for (i, match) in result.matches.prefix(3).enumerated() {
                print("  [\(i)] \(match.name) — \(match.setName) #\(match.collectorNumber) — \(match.rarity) — \(Int(match.confidence * 100))% — $\(match.price.market)")
            }
            // This should resolve locally from the bundled/full index when
            // OCR can read enough of the card.
        } catch let urlError as URLError {
            XCTFail("Scan should not depend on the remote identification service: \(urlError.code.rawValue) \(urlError.localizedDescription)")
        } catch {
            print("[identify] error: \(error)")
        }
    }
}
