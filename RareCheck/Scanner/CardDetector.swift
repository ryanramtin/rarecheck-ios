import Vision
import CoreImage
import UIKit
import ImageIO

struct DetectedCardFrame: Equatable {
    let boundingBox: CGRect
    let confidence: Float

    var center: CGPoint {
        CGPoint(x: boundingBox.midX, y: boundingBox.midY)
    }

    var area: CGFloat {
        boundingBox.width * boundingBox.height
    }

    var aspectRatio: CGFloat {
        guard boundingBox.height > 0 else { return 0 }
        return boundingBox.width / boundingBox.height
    }

    var isUsablyFramed: Bool {
        area >= 0.25 &&
            (0.22...0.78).contains(center.x) &&
            (0.18...0.82).contains(center.y)
    }

    func isStable(comparedTo previous: DetectedCardFrame) -> Bool {
        let centerShift = hypot(center.x - previous.center.x, center.y - previous.center.y)
        let areaDelta = abs(area - previous.area)
        let aspectDelta = abs(aspectRatio - previous.aspectRatio)
        return centerShift <= 0.035 && areaDelta <= 0.08 && aspectDelta <= 0.08
    }
}

// MARK: - Card Detector
// Uses VNDetectRectanglesRequest to find the card bounding box in a frame/image

final class CardDetector {
    static let shared = CardDetector()

    // Returns the cropped, perspective-corrected card image
    func detectAndCrop(from image: UIImage) async -> UIImage? {
        let normalized = image.normalizedUp()
        guard let cgImage = normalized.cgImage else { return nil }
        return await detectAndCrop(from: cgImage, orientation: .up)
    }

    func detectAndCrop(from pixelBuffer: CVPixelBuffer) async -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return await detectAndCrop(from: cgImage, orientation: .right)
    }

    func detectFrame(in pixelBuffer: CVPixelBuffer) -> DetectedCardFrame? {
        detectRectangle(in: VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:]))
            .map { DetectedCardFrame(boundingBox: $0.boundingBox, confidence: $0.confidence) }
    }

    private func detectAndCrop(from cgImage: CGImage, orientation: CGImagePropertyOrientation) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, _ in
                guard let results = request.results as? [VNRectangleObservation],
                      let best = results.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let cropped = self.perspectiveCrop(cgImage: cgImage, observation: best)
                continuation.resume(returning: cropped)
            }

            // Tune for trading card aspect ratio (2.5 x 3.5 inches ≈ 0.714)
            request.minimumAspectRatio = 0.60
            request.maximumAspectRatio = 0.80
            request.minimumSize = 0.3          // card must fill ≥30% of frame
            request.minimumConfidence = 0.7
            request.maximumObservations = 1

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            try? handler.perform([request])
        }
    }

    private func detectRectangle(in handler: VNImageRequestHandler) -> VNRectangleObservation? {
        var result: VNRectangleObservation?
        let request = VNDetectRectanglesRequest { req, _ in
            result = (req.results as? [VNRectangleObservation])?.first
        }
        request.minimumAspectRatio = 0.60
        request.maximumAspectRatio = 0.80
        request.minimumSize = 0.25
        request.minimumConfidence = 0.65
        request.maximumObservations = 1
        try? handler.perform([request])
        return result
    }

    // MARK: - Perspective Correction (four-point transform)

    private func perspectiveCrop(cgImage: CGImage, observation: VNRectangleObservation) -> UIImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        // Vision coordinates: bottom-left origin → flip Y
        func toImagePoint(_ normalized: CGPoint) -> CIVector {
            CIVector(x: normalized.x * width, y: normalized.y * height)
        }

        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(toImagePoint(observation.topLeft),     forKey: "inputTopLeft")
        filter.setValue(toImagePoint(observation.topRight),    forKey: "inputTopRight")
        filter.setValue(toImagePoint(observation.bottomLeft),  forKey: "inputBottomLeft")
        filter.setValue(toImagePoint(observation.bottomRight), forKey: "inputBottomRight")
        filter.setValue(ciImage, forKey: kCIInputImageKey)

        guard let output = filter.outputImage else { return nil }

        let context = CIContext()
        guard let finalCG = context.createCGImage(output, from: output.extent) else { return nil }

        // Normalize to standard size (600×840 ≈ 2.5x3.5 at 240dpi)
        return resized(UIImage(cgImage: finalCG), to: CGSize(width: 600, height: 840))
    }

    private func resized(_ image: UIImage, to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Live Frame Detection (returns bool for overlay highlight)

    func hasCard(in pixelBuffer: CVPixelBuffer) -> Bool {
        detectFrame(in: pixelBuffer) != nil
    }
}

private extension UIImage {
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
