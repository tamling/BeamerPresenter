import QuartzCore

/// The wall on screen: a black layer filling the host layer, with the camera's
/// perspective, and one layer per engine sprite, posed from the engine on
/// every `apply`. Removing the wall (releasing it) takes its layers along.
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

    init(hostLayer: CALayer, layout: GridLayout, images: CoverImageStore) {
        self.images = images
        let bounds = hostLayer.bounds
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
                let layer = makeLayer(showing: sprite.album)
                layers[id] = layer
                wallLayer.addSublayer(layer)
            case let .removed(id):
                layers.removeValue(forKey: id)?.removeFromSuperlayer()
                shownPoses[id] = nil
            case let .albumChanged(id):
                // The engine only picks ready albums; should the cache have
                // dropped this one since, the cover keeps its old image.
                guard let album = engine.sprites[id]?.album, let image = images.image(for: album) else { continue }
                layers[id]?.contents = image
            }
        }
        for (id, layer) in layers {
            guard let pose = engine.sprites[id]?.pose, pose != shownPoses[id] else { continue }
            place(layer, at: pose)
            shownPoses[id] = pose
        }
        CATransaction.commit()
    }

    private func makeLayer(showing album: AlbumID) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: coverEdge, height: coverEdge)
        layer.contents = images.image(for: album)
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
