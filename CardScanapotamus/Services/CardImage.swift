import UIKit
import ImageIO
import SwiftData

/// Memory-conscious handling of card photos.
///
/// Stored images are normalized once (landscape, bounded size) when saved, and
/// decoded for display through ImageIO at a bounded pixel size so a full
/// camera-resolution bitmap never has to sit in memory just to draw a row.
enum CardImage {
    /// Longest side of a stored card image, in pixels.
    static let maxStoredDimension: CGFloat = 1600

    /// Encode an image for storage: rotated to landscape, downscaled, JPEG.
    static func storageData(from image: UIImage) -> Data? {
        image.normalizedForCard(maxDimension: maxStoredDimension)
            .jpegData(compressionQuality: 0.7)
    }

    /// Decode stored data no larger than `maxPixel` on its longest side.
    /// EXIF orientation is applied so the result is upright.
    static func decode(_ data: Data?, maxPixel: CGFloat) -> UIImage? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel)
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// True when stored data is portrait or larger than the storage bound.
    /// Reads only the header, no pixel decode.
    static func needsNormalizing(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat else { return false }
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let rotated = (5...8).contains(orientation)
        let (dispW, dispH) = rotated ? (h, w) : (w, h)
        return dispH > dispW || max(dispW, dispH) > maxStoredDimension
    }

    /// Re-encode existing stored data into normalized form.
    static func renormalize(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return storageData(from: image)
    }

    /// One-time pass over saved cards so images stored before normalization
    /// existed are brought in line. Runs sequentially to keep peak memory low.
    @MainActor
    static func migrateStoredImagesIfNeeded(context: ModelContext) async {
        let key = "cardImagesNormalized.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let cards = (try? context.fetch(FetchDescriptor<ScannedCard>())) ?? []
        for card in cards {
            if let d = card.imageData, needsNormalizing(d),
               let fixed = await Task.detached(priority: .utility, operation: { renormalize(d) }).value {
                card.imageData = fixed
            }
            if let d = card.backImageData, needsNormalizing(d),
               let fixed = await Task.detached(priority: .utility, operation: { renormalize(d) }).value {
                card.backImageData = fixed
            }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}

extension UIImage {
    /// Rotate to landscape if needed and scale so the longest side is at most
    /// `maxDimension`, in a single render pass.
    func normalizedForCard(maxDimension: CGFloat) -> UIImage {
        let portrait = size.height > size.width
        let longSide = max(size.width, size.height)
        let scaleFactor = min(1, maxDimension / longSide)

        guard portrait || scaleFactor < 1 else { return self }

        let drawSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let outSize = portrait
            ? CGSize(width: drawSize.height, height: drawSize.width)
            : drawSize

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: outSize, format: format).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: outSize.width / 2, y: outSize.height / 2)
            if portrait { c.rotate(by: -.pi / 2) }
            draw(in: CGRect(x: -drawSize.width / 2, y: -drawSize.height / 2,
                            width: drawSize.width, height: drawSize.height))
        }
    }
}
