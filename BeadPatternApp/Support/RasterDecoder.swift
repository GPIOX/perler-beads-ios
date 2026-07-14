import BeadPatternCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum RasterDecoder {
    static func decode(data: Data, maximumDimension: Int = 4096) throws -> RasterImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw PatternCoreError.invalidRaster
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // CGContext stores premultiplied channels. Canvas getImageData, used by the Web baseline,
        // exposes straight alpha, so restore the channels before sampling.
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Int(bytes[offset + 3])
            guard alpha > 0, alpha < 255 else { continue }
            bytes[offset] = UInt8(min(255, Int(bytes[offset]) * 255 / alpha))
            bytes[offset + 1] = UInt8(min(255, Int(bytes[offset + 1]) * 255 / alpha))
            bytes[offset + 2] = UInt8(min(255, Int(bytes[offset + 2]) * 255 / alpha))
        }
        return try RasterImage(width: width, height: height, rgba: bytes)
    }

    static func preferredFilename(for url: URL?) -> String {
        let ext = url?.pathExtension.lowercased()
        let supported = ["png", "jpg", "jpeg", "heic", "gif"]
        return "source.\(supported.contains(ext ?? "") ? ext! : "image")"
    }
}
