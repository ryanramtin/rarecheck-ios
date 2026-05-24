import UIKit
import Accelerate

// MARK: - Perceptual Hash (pHash) Image Matcher
//
// pHash steps:
//  1. Resize image to 32x32 grayscale
//  2. Apply DCT (discrete cosine transform)
//  3. Take top-left 8x8 of DCT (low frequencies)
//  4. Compute mean of those 64 values
//  5. Build 64-bit hash: each bit = (pixel > mean)
//  6. Hamming distance between two hashes = dissimilarity
//
// Similarity score = 1 - (hammingDistance / 64)
// Threshold: >= 0.85 = strong visual match

final class PHashMatcher {
    static let shared = PHashMatcher()

    private let hashSize = 8          // 8x8 final DCT block
    private let dctSize = 32          // 32x32 intermediate size

    // MARK: - Hash Computation

    func hash(of image: UIImage) -> UInt64? {
        guard let gray = toGrayscale(image, size: CGSize(width: dctSize, height: dctSize)),
              let pixels = pixelValues(from: gray) else { return nil }

        let dctBlock = dct2D(pixels, size: dctSize)
        let topLeft = extract8x8(dctBlock, fullSize: dctSize)

        let mean = topLeft.reduce(0, +) / Float(topLeft.count)

        var hash: UInt64 = 0
        for (i, val) in topLeft.enumerated() {
            if val > mean { hash |= 1 << i }
        }
        return hash
    }

    // MARK: - Similarity

    /// Returns 0.0 (no match) to 1.0 (identical)
    func similarity(between a: UInt64, and b: UInt64) -> Double {
        let xor = a ^ b
        let distance = xor.nonzeroBitCount
        return 1.0 - Double(distance) / 64.0
    }

    func similarity(between imageA: UIImage, and imageB: UIImage) -> Double? {
        guard let hashA = hash(of: imageA), let hashB = hash(of: imageB) else { return nil }
        return similarity(between: hashA, and: hashB)
    }

    // MARK: - Image → Grayscale Float Pixels

    private func toGrayscale(_ image: UIImage, size: CGSize) -> UIImage? {
        UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size)
            image.draw(in: rect)
        }.applying(CIFilter(name: "CIColorMonochrome", parameters: [
            kCIInputColorKey: CIColor.gray,
            kCIInputIntensityKey: 1.0
        ]))
    }

    private func pixelValues(from image: UIImage) -> [Float]? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let ctx = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        // vDSP DCT works with Float; convert from UInt8 pixel bytes
        return pixels.map { Float($0) }
    }

    // MARK: - 2D DCT (separable, using vDSP — Float only)

    private func dct2D(_ pixels: [Float], size: Int) -> [Float] {
        var result = pixels
        let n = vDSP_Length(size)
        guard let setup = vDSP_DCT_CreateSetup(nil, n, .II) else { return result }
        defer { vDSP_DFT_DestroySetup(setup) }

        // Row-wise DCT (separate input/output buffers — vDSP requires exclusive access)
        result.withUnsafeMutableBufferPointer { buf in
            for row in 0..<size {
                let input = Array(buf[row * size ..< (row + 1) * size])
                var output = [Float](repeating: 0, count: size)
                vDSP_DCT_Execute(setup, input, &output)
                for col in 0..<size { buf[row * size + col] = output[col] }
            }
        }

        // Column-wise DCT
        result.withUnsafeMutableBufferPointer { buf in
            for col in 0..<size {
                let input = (0..<size).map { buf[$0 * size + col] }
                var output = [Float](repeating: 0, count: size)
                vDSP_DCT_Execute(setup, input, &output)
                for row in 0..<size { buf[row * size + col] = output[row] }
            }
        }

        return result
    }

    private func extract8x8(_ block: [Float], fullSize: Int) -> [Float] {
        var result = [Float]()
        result.reserveCapacity(hashSize * hashSize)
        for row in 0..<hashSize {
            for col in 0..<hashSize {
                result.append(block[row * fullSize + col])
            }
        }
        return result
    }
}

extension UIImage {
    func applying(_ filter: CIFilter?) -> UIImage? {
        guard let filter else { return self }
        guard let ciImage = CIImage(image: self) else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        guard let output = filter.outputImage else { return nil }
        return UIImage(ciImage: output)
    }
}
