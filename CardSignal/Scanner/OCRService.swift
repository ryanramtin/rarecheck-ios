import Vision
import UIKit

// MARK: - OCR Service
// Uses VNRecognizeTextRequest to extract card name, collector number, and set code

final class OCRService {
    static let shared = OCRService()

    func extractCardInfo(from image: UIImage) async throws -> OCRCardInfo {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: OCRCardInfo(name: nil, collectorNumber: nil, setCode: nil, rawText: ""))
                    return
                }
                let info = self.parseObservations(observations)
                continuation.resume(returning: info)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false          // raw text for card names
            request.minimumTextHeight = 0.02                // filter tiny noise
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Parsing

    private func parseObservations(_ observations: [VNRecognizedTextObservation]) -> OCRCardInfo {
        // Sort top-to-bottom by bounding box y position (Vision uses bottom-left origin)
        let sorted = observations.sorted { $0.boundingBox.minY > $1.boundingBox.minY }
        let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
        let rawText = lines.joined(separator: "\n")

        // Card name is usually the first prominent line
        let name = extractCardName(from: lines)
        let collectorNumber = extractCollectorNumber(from: lines)
        let setCode = extractSetCode(from: lines)

        return OCRCardInfo(
            name: name,
            collectorNumber: collectorNumber,
            setCode: setCode,
            rawText: rawText
        )
    }

    /// Card name is typically the first non-HP, non-numeric line near the top
    private func extractCardName(from lines: [String]) -> String? {
        // Skip common non-name lines
        let skipPatterns = [
            #"^\d+$"#,                  // pure numbers
            #"^HP\s*\d+"#,              // HP 120
            #"^\d+/\d+"#,               // collector number
            #"^[A-Z]{2,4}-\d+"#,        // set code
            #"^(Basic|Stage \d+|VMAX|V-UNION|ex|GX|EX|☆)"#  // stage/suffix
        ]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.count >= 3 else { continue }
            let shouldSkip = skipPatterns.contains { pattern in
                trimmed.range(of: pattern, options: .regularExpression) != nil
            }
            if !shouldSkip { return trimmed }
        }
        return nil
    }

    /// Collector number format: "042/165" or "042"
    private func extractCollectorNumber(from lines: [String]) -> String? {
        let pattern = #"(\d{1,3})/(\d{1,3})"#
        for line in lines {
            if let range = line.range(of: pattern, options: .regularExpression) {
                let match = String(line[range])
                return match.components(separatedBy: "/").first
            }
        }
        return nil
    }

    /// Set code format: "SVI", "OBF", "MEW", "BRS", etc. — 2–4 uppercase letters
    private func extractSetCode(from lines: [String]) -> String? {
        let pattern = #"^[A-Z]{2,4}$"#
        return lines.first { $0.range(of: pattern, options: .regularExpression) != nil }
    }
}

enum OCRError: LocalizedError {
    case invalidImage
    var errorDescription: String? { "Could not process image for text recognition." }
}
