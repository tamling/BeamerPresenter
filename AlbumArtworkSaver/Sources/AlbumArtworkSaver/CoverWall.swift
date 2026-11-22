import os
import QuartzCore

extension Logger {
    /// The wall's log: subsystem = bundle ID, category `wall`.
    static let wall = Logger(subsystem: "app.beamerpresenter.AlbumArtworkSaver", category: "wall")
}

/// The wall on screen: a black layer filling `bounds` of the host layer, with
/// the camera's perspective, and one layer per engine sprite, posed from the
/// engine on every `apply`. Removing the wall (releasing it) takes its layers
/// along. A wall is laid out once; another size needs another wall.
///
/// World units map to points as `pointsPerUnit` (the screen is
/// `GridLayout.worldHeight` units tall); y points up in both.
final class CoverWall {
    let pointsPerUnit: CGFloat
    /// A cover's edge in points.
    let coverEdge: CGFloat

    private let wallLayer = CALayer()
    private let center: CGPoint
    private let images: CoverImageStore
    private var layers: [SpriteID: CALayer] = [:]
    /// The pose each layer was last given, so resting covers are not set again every frame.
    private var shownPoses: [SpriteID: CoverPose] = [:]
    /// Layers whose album's image the store did not have yet, with that album.
    private var waiting: [SpriteID: AlbumID] = [:]

    /// `bounds` is the view's: the host layer may not have caught up with a
    /// size the view was just given.
    init(hostLayer: CALayer, bounds: CGRect, layout: GridLayout, images: CoverImageStore) {
        self.images = images
        pointsPerUnit = bounds.height / CGFloat(GridLayout.worldHeight)
        coverEdge = CGFloat(layout.coverSize) * pointsPerUnit
        center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / (CGFloat(GridLayout.cameraDistance) * pointsPerUnit)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wallLayer.frame = bounds
        wallLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        wallLayer.sublayerTransform = perspective
        hostLayer.addSublayer(wallLayer)
        CATransaction.commit()
    }

    deinit {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wallLayer.removeFromSuperlayer()
        CATransaction.commit()
    }

    /// Mirrors `changes` (in order), then poses every layer like its sprite.
    func apply(_ changes: [WallChange], engine: WallEngine) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for change in changes {
            switch change {
            case let .added(id):
                guard let sprite = engine.sprites[id] else { continue }
                let layer = makeLayer()
                layers[id] = layer
                wallLayer.addSublayer(layer)
                show(sprite.album, id: id, on: layer)
            case let .removed(id):
                layers.removeValue(forKey: id)?.removeFromSuperlayer()
                shownPoses[id] = nil
                waiting[id] = nil
            case let .albumChanged(id):
                guard let album = engine.sprites[id]?.album, let layer = layers[id] else { continue }
                show(album, id: id, on: layer)
            }
        }
        if !waiting.isEmpty { fillWaitingLayers() }
        for (id, layer) in layers {
            guard let pose = engine.sprites[id]?.pose, pose != shownPoses[id] else { continue }
            place(layer, at: pose)
            shownPoses[id] = pose
        }
        CATransaction.commit()
    }

    /// Puts `album`'s image on the layer. The engine only picks ready albums,
    /// but the cache may have dropped one since: then the layer keeps what it
    /// shows and waits while the store decodes the image again.
    private func show(_ album: AlbumID, id: SpriteID, on layer: CALayer) {
        if let image = images.image(for: album) {
            layer.contents = image
            waiting[id] = nil
            return
        }
        waiting[id] = album
        images.prefetch([album])
        Logger.wall.notice("cover \(id.raw, privacy: .public) waits for its image to be decoded again")
    }

    private func fillWaitingLayers() {
        for (id, album) in waiting {
            guard let layer = layers[id] else {
                waiting[id] = nil
                continue
            }
            if let image = images.image(for: album) {
                layer.contents = image
                waiting[id] = nil
            } else if images.hasFailed(album) {
                // The image cannot be read any more: any cover beats a hole.
                if layer.contents == nil { layer.contents = anyImage() }
                guard layer.contents != nil else { continue }
                waiting[id] = nil
                Logger.wall.error("cover \(id.raw, privacy: .public): its image cannot be read, showing another")
            } else {
                // Nothing while it decodes; asks again if the cache dropped it on arrival.
                images.prefetch([album])
            }
        }
    }

    private func anyImage() -> CGImage? {
        let images = self.images
        return images.pool.lazy.compactMap { images.image(for: $0) }.first
    }

    private func makeLayer() -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: coverEdge, height: coverEdge)
        layer.contentsGravity = .resizeAspectFill
        layer.masksToBounds = true
        layer.isDoubleSided = true
        return layer
    }

    private func place(_ layer: CALayer, at pose: CoverPose) {
        layer.position = CGPoint(x: center.x + CGFloat(pose.x) * pointsPerUnit,
                                 y: center.y + CGFloat(pose.y) * pointsPerUnit)
        // Moves the cover towards the camera and orders it among its siblings.
        layer.zPosition = CGFloat(pose.z) * pointsPerUnit
        // Rotation about Z first, then Y, then X (three.js's XYZ order), then the
        // scale. Core Animation multiplies row vectors, so a·b applies a first.
        var transform = CATransform3DMakeRotation(CGFloat(pose.rotZ), 0, 0, 1)
        transform = CATransform3DConcat(transform, CATransform3DMakeRotation(CGFloat(pose.rotY), 0, 1, 0))
        transform = CATransform3DConcat(transform, CATransform3DMakeRotation(CGFloat(pose.rotX), 1, 0, 0))
        let scale = CGFloat(pose.scale)
        layer.transform = CATransform3DConcat(transform, CATransform3DMakeScale(scale, scale, scale))
        layer.opacity = Float(pose.opacity)
    }
}
