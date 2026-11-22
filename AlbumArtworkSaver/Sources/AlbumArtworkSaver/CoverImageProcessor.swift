import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns an embedded cover picture into the cache's image: the middle square,
/// scaled down to `edge` pixels (never up), as a JPEG.
enum CoverImageProcessor {
    static let edge = 640
    static let jpegQuality = 0.85

    /// `nil` when ImageIO cannot read `data` as an image.
    static func makeSquareJPEG(from data: Data, edge: Int = CoverImageProcessor.edge) -> Data? {
        guard edge > 0,
              let source = CGImageSourceCreateWithData(data as CFData,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        // The thumbnail's size limit applies to its long side; one pixel more,
        // so its short side cannot round to less than `edge`. ImageIO never
        // scales up, and also applies the EXIF orientation here.
        let longSide = (Double(edge) * Double(max(width, height)) / Double(min(width, height))).rounded(.up) + 1
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(longSide),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let shortSide = min(image.width, image.height)
        let side = min(edge, shortSide)
        guard side > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        // Transparent parts turn black, like the wall behind the covers.
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high
        let scale = CGFloat(side) / CGFloat(shortSide)
        let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.draw(image, in: CGRect(x: (CGFloat(side) - drawn.width) / 2, y: (CGFloat(side) - drawn.height) / 2,
                                       width: drawn.width, height: drawn.height))
        guard let square = context.makeImage() else { return nil }

        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg as CFMutableData,
                                                                 UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, square,
                                   [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return jpeg as Data
    }
}
