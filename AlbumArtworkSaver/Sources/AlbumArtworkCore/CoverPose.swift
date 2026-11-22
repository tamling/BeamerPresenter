import Foundation

/// Position (world units), rotation (radians), scale and opacity of one cover.
struct CoverPose: Equatable {
    var x: Double
    var y: Double
    var z: Double
    var rotX: Double
    var rotY: Double
    var rotZ: Double
    var scale: Double
    var opacity: Double

    static func resting(at p: Point2, z: Double = 0) -> CoverPose {
        CoverPose(x: p.x, y: p.y, z: z, rotX: 0, rotY: 0, rotZ: 0, scale: 1, opacity: 1)
    }
}
