import Foundation

/// Pure functions of time (seconds since start, clamped to 0...duration) returning a pose.
/// Ported from the original index.html (three.js); times converted from ms to s.

private func progress(_ t: Double, _ duration: Double) -> Double {
    min(max(t / duration, 0), 1)
}

/// Cover flip around the Y axis (original lines 4080-4100).
struct FlipMotion {
    static let duration = 0.9
    let center: Point2

    func frame(at t: Double) -> (pose: CoverPose, showsNewAlbum: Bool) {
        let angle = Easing.inOutSine(progress(t, Self.duration)) * Double.pi
        var pose = CoverPose.resting(at: center)
        if angle > Double.pi / 2 {
            pose.rotY = angle - Double.pi
            return (pose, true)
        }
        pose.rotY = angle
        return (pose, false)
    }
}

/// Cover falls off the wall (original lines 4130-4290), originalZ = 0.
struct DropMotion {
    static let duration = 2.2
    private static let gravity = 9.8
    private static let airResistance = 0.02
    private static let baseTiltX = 0.25
    private static let initialRotationSpeed = 0.5
    private static let rotationAcceleration = 2.5
    private static let zClearance = 0.08

    let origin: Point2
    let coverSize: Double
    let yawTarget: Double
    let rollWobble: Double
    let spin: Double

    init(origin: Point2, coverSize: Double, yawTarget: Double, rollWobble: Double, spin: Double) {
        self.origin = origin
        self.coverSize = coverSize
        self.yawTarget = yawTarget
        self.rollWobble = rollWobble
        self.spin = spin
    }

    static func random(origin: Point2, coverSize: Double, using rng: inout SplitMix64) -> DropMotion {
        let yaw = Double.random(in: -0.4..<0.4, using: &rng)
        let wobble = Double.random(in: -0.15..<0.15, using: &rng)
        let spin: Double = Bool.random(using: &rng) ? 1 : -1
        return DropMotion(origin: origin, coverSize: coverSize, yawTarget: yaw, rollWobble: wobble, spin: spin)
    }

    func pose(at t: Double) -> CoverPose {
        let all = progress(t, Self.duration)
        let half = coverSize / 2
        var pose = CoverPose.resting(at: origin)
        if all <= 0.2 {
            let p = all / 0.2
            let tilt = p * Self.baseTiltX
            pose.rotX = tilt * Easing.outQuart(p)
            pose.rotY = yawTarget * (0.3 * Easing.inOutCubic(p))
            pose.rotZ = rollWobble * 0.2 * sin(p * Double.pi)
            pose.y = origin.y + sin(p * Double.pi) * 0.1
            pose.z = max(p * 0.2, Self.zClearance + half * abs(sin(tilt)))
            return pose
        }
        let p = (all - 0.2) / 0.8
        let fall = p * (Self.duration * 0.8)
        let finalPivotY = -10 - coverSize
        pose.rotX = Self.baseTiltX
            + (Self.initialRotationSpeed * fall + 0.5 * Self.rotationAcceleration * fall * fall) * spin
        pose.rotY = yawTarget * (0.3 + 0.7 * Easing.inOutCubic(min(p * 1.5, 1)))
        let turbulence = sin(fall * 8) * cos(fall * 3) * 0.1
        pose.rotZ = rollWobble * (sin(p * Double.pi * 2) + turbulence) * min(p * 2, 1)
        let distance = 0.5 * Self.gravity * fall * fall * (1 - min(Self.airResistance * fall, 0.3))
        pose.y = origin.y - distance * (abs(origin.y - finalPivotY) / 10)
        let zForward = max(0.8, coverSize * 0.5)
        pose.z = max(0.2 + Easing.inQuart(p) * zForward,
                     Self.zClearance + half * abs(sin(pose.rotX)))
        if p > 0.6 {
            pose.opacity = max(0, 1 - Easing.inQuart((p - 0.6) / 0.4))
        }
        pose.scale = 1 + Easing.inQuart(p) * 0.15
        return pose
    }
}

/// One step of the roll animation (original lines 4522-4572).
struct RollStepMotion {
    static let duration = 0.3
    let from: Point2
    let to: Point2
    let startRotZ: Double
    let increment: Double
    let coverSize: Double

    init(from: Point2, to: Point2, startRotZ: Double, increment: Double, coverSize: Double) {
        self.from = from
        self.to = to
        self.startRotZ = startRotZ
        self.increment = increment
        self.coverSize = coverSize
    }

    func pose(at t: Double) -> CoverPose {
        let e = Easing.inOutQuad(progress(t, Self.duration))
        let arc = coverSize * 0.1 * sin(e * Double.pi)
        var pose = CoverPose.resting(at: Point2(x: from.x + (to.x - from.x) * e,
                                                 y: from.y + (to.y - from.y) * e + arc),
                                     z: 0.1 + arc * 0.5)
        pose.rotZ = startRotZ + increment * e
        pose.scale = 1 + arc / coverSize * 0.5
        return pose
    }
}

/// One tumble step downward by one cover (original lines 4733-4770).
struct TumbleStepMotion {
    static let duration = 0.35
    static let pause = 0.08
    let from: Point2
    let coverSize: Double
    let startRotX: Double

    init(from: Point2, coverSize: Double, startRotX: Double) {
        self.from = from
        self.coverSize = coverSize
        self.startRotX = startRotX
    }

    var to: Point2 { Point2(x: from.x, y: from.y - coverSize) }

    func pose(at t: Double) -> CoverPose {
        let angle = Easing.inOutQuad(progress(t, Self.duration)) * Double.pi
        let radius = coverSize / 2
        let centerY = (from.y + to.y) / 2
        var pose = CoverPose.resting(at: Point2(x: from.x, y: centerY + radius * cos(angle)),
                                     z: max(0.2 + radius * sin(angle), 0.1))
        pose.rotX = startRotX + angle
        pose.scale = 1 + sin(angle) * 0.05
        return pose
    }
}

/// Cover swings half a turn around a pin (original lines 5128-5196), linear.
struct PinSwingMotion {
    static let duration = 0.8
    static let swapProgress = 0.4
    let pin: Point2
    private let radius: Double
    private let startAngle: Double

    init(pin: Point2, from: Point2) {
        self.pin = pin
        let dx = from.x - pin.x, dy = from.y - pin.y
        radius = (dx * dx + dy * dy).squareRoot()
        startAngle = atan2(dy, dx)
    }

    func pose(at t: Double) -> CoverPose {
        let p = progress(t, Self.duration)
        let a = startAngle + Double.pi * p
        var pose = CoverPose.resting(at: Point2(x: pin.x + radius * cos(a), y: pin.y + radius * sin(a)),
                                     z: (p < 0.3 || p > 0.7) ? 0.001 : -0.001)
        pose.rotZ = Double.pi * p - (p > Self.swapProgress ? Double.pi : 0)
        pose.scale = 1 + sin(2 * Double.pi * p) * 0.03
        return pose
    }

    func hasSwapped(at t: Double) -> Bool {
        progress(t, Self.duration) > Self.swapProgress
    }
}
