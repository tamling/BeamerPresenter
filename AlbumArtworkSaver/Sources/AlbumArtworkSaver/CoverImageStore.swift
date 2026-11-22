import CoreGraphics
import Foundation
import ImageIO

/// The wall's cover images, keyed by album. `prefetch` decodes on a serial
/// background queue, never on the main thread: an ImageIO thumbnail whose short
/// side is at least `pixelEdge` (where the file is that large), cut to a square
/// from its middle. The result goes into an `NSCache` on the main thread; an
/// album is ready while its image is in the cache.
///
/// Used from the main thread only; just the decoding runs elsewhere.
final class CoverImageStore: ArtworkSource {
    /// Caps the cache at a few hundred covers; layers keep the images they show.
    private static let cacheBytes = 256 << 20

    var pool: [AlbumID] = []
    /// Short side to decode to, in pixels: a cover's edge on screen. Set it
    /// before prefetching; images already decoded keep their size.
    var pixelEdge = 640

    private let imageURL: (AlbumID) -> URL?
    private let cache = NSCache<NSString, CGImage>()
    private let queue = DispatchQueue(label: "app.beamerpresenter.AlbumArtworkSaver.covers",
                                      qos: .userInitiated, autoreleaseFrequency: .workItem)
    private var decoding: Set<AlbumID> = []
    /// Albums without a readable image; they are not asked for again.
    private var failed: Set<AlbumID> = []

    init(imageURL: @escaping (AlbumID) -> URL?) {
        self.imageURL = imageURL
        cache.totalCostLimit = Self.cacheBytes
    }

    func image(for album: AlbumID) -> CGImage? {
        cache.object(forKey: album as NSString)
    }

    func isReady(_ album: AlbumID) -> Bool {
        image(for: album) != nil
    }

    /// True once decoding `album` failed: it will never be ready.
    func hasFailed(_ album: AlbumID) -> Bool {
        failed.contains(album)
    }

    /// Starts decoding every album that is not ready, not decoding and not failed.
    func prefetch(_ albums: [AlbumID]) {
        let edge = pixelEdge
        for album in albums where !decoding.contains(album) && !failed.contains(album) && !isReady(album) {
            guard let url = imageURL(album) else {
                failed.insert(album)
                continue
            }
            decoding.insert(album)
            queue.async { [weak self] in
                let image = Self.squareImage(at: url, edge: edge)
                DispatchQueue.main.async { self?.finishDecoding(album, image) }
            }
        }
    }

    private func finishDecoding(_ album: AlbumID, _ image: CGImage?) {
        decoding.remove(album)
        guard let image else {
            failed.insert(album)
            return
        }
        cache.setObject(image, forKey: album as NSString, cost: image.bytesPerRow * image.height)
    }

    // MARK: - Decoding (background queue)

    /// The middle square of the image at `url`, its edge at least `edge` pixels
    /// unless the file is smaller (never scaled up); nil if ImageIO cannot read it.
    private static func squareImage(at url: URL, edge: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        // The thumbnail's size limit applies to its long side.
        let longSide = (Double(max(edge, 1)) * Double(max(width, height)) / Double(min(width, height))).rounded(.up)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(longSide),
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        else { return nil }
        return middleSquare(of: thumbnail)
    }

    /// Draws the middle square into a fresh bitmap, so the pixels are decoded
    /// here and Core Animation gets an image it can use as it is.
    private static func middleSquare(of image: CGImage) -> CGImage? {
        let side = min(image.width, image.height)
        guard side > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: (side - image.width) / 2, y: (side - image.height) / 2,
                                       width: image.width, height: image.height))
        return context.makeImage()
    }
}
