import XCTest
@testable import AlbumArtworkCore

final class MotionsTests: XCTestCase {
    private let s = 20.0 / 6.0
    private let acc = 1e-5

    func testEasing() {
        let fs: [(Double) -> Double] = [Easing.inOutSine, Easing.outQuart, Easing.inQuart, Easing.inOutCubic, Easing.inOutQuad]
        for f in fs {
            XCTAssertEqual(f(0), 0, accuracy: acc)
            XCTAssertEqual(f(1), 1, accuracy: acc)
        }
        XCTAssertEqual(Easing.inOutQuad(0.25), 0.125, accuracy: acc)
        XCTAssertEqual(Easing.inOutCubic(0.25), 0.0625, accuracy: acc)
        XCTAssertEqual(Easing.outQuart(0.5), 0.9375, accuracy: acc)
    }

    func testFlip() {
        let m = FlipMotion(center: Point2(x: 1, y: 2))
        let a = m.frame(at: 0)
        XCTAssertEqual(a.pose.rotY, 0, accuracy: acc); XCTAssertFalse(a.showsNewAlbum)
        XCTAssertEqual(a.pose.x, 1, accuracy: acc); XCTAssertEqual(a.pose.y, 2, accuracy: acc)
        let b = m.frame(at: 0.45)
        XCTAssertEqual(b.pose.rotY, Double.pi / 2, accuracy: acc); XCTAssertFalse(b.showsNewAlbum)
        let c = m.frame(at: 0.6)
        XCTAssertEqual(c.pose.rotY, -Double.pi / 4, accuracy: acc); XCTAssertTrue(c.showsNewAlbum)
        let d = m.frame(at: 0.9)
        XCTAssertEqual(d.pose.rotY, 0, accuracy: acc); XCTAssertTrue(d.showsNewAlbum)
    }

    func testDropTopRow() {
        let m = DropMotion(origin: Point2(x: -16.666667, y: 8.333333), coverSize: s, yawTarget: 0.3, rollWobble: 0.1, spin: 1)
        var p = m.pose(at: 0)
        XCTAssertEqual(p.y, 8.333333, accuracy: acc); XCTAssertEqual(p.z, 0.08, accuracy: acc); XCTAssertEqual(p.rotX, 0, accuracy: acc)
        p = m.pose(at: 0.22)
        XCTAssertEqual(p.y, 8.433333, accuracy: acc); XCTAssertEqual(p.z, 0.287791, accuracy: acc)
        XCTAssertEqual(p.rotX, 0.117187, accuracy: acc); XCTAssertEqual(p.rotY, 0.045, accuracy: acc); XCTAssertEqual(p.rotZ, 0.02, accuracy: acc)
        p = m.pose(at: 0.44)
        XCTAssertEqual(p.z, 0.492340, accuracy: acc); XCTAssertEqual(p.rotX, 0.25, accuracy: acc); XCTAssertEqual(p.rotY, 0.09, accuracy: acc)
        p = m.pose(at: 1.32)
        XCTAssertEqual(p.y, 0.256486, accuracy: acc); XCTAssertEqual(p.z, 1.740334, accuracy: acc)
        XCTAssertEqual(p.rotX, 1.658, accuracy: acc); XCTAssertEqual(p.rotY, 0.286875, accuracy: acc)
        XCTAssertEqual(p.rotZ, -0.006020, accuracy: acc); XCTAssertEqual(p.scale, 1.009375, accuracy: acc)
        p = m.pose(at: 2.2)
        XCTAssertEqual(p.y, -23.395260, accuracy: acc); XCTAssertEqual(p.z, 1.866667, accuracy: acc)
        XCTAssertEqual(p.rotX, 5.002, accuracy: acc); XCTAssertEqual(p.scale, 1.15, accuracy: acc); XCTAssertEqual(p.opacity, 0, accuracy: acc)
    }

    func testDropBottomRowLeavesScreen() {
        let m = DropMotion(origin: Point2(x: 16.666667, y: -8.333333), coverSize: s, yawTarget: 0.3, rollWobble: 0.1, spin: 1)
        XCTAssertEqual(m.pose(at: 2.2).y, -15.655316, accuracy: acc)
    }

    func testDropRandomRanges() {
        var rng = SplitMix64(seed: 42)
        for _ in 0..<1000 {
            let m = DropMotion.random(origin: Point2(x: 0, y: 0), coverSize: s, using: &rng)
            XCTAssertTrue(m.yawTarget >= -0.4 && m.yawTarget < 0.4)
            XCTAssertTrue(m.rollWobble >= -0.15 && m.rollWobble < 0.15)
            XCTAssertTrue(m.spin == 1 || m.spin == -1)
        }
    }

    func testRollStep() {
        let m = RollStepMotion(from: Point2(x: 0, y: 0), to: Point2(x: s, y: 0), startRotZ: 0, increment: -Double.pi / 2, coverSize: s)
        var p = m.pose(at: 0.15)
        XCTAssertEqual(p.x, 1.666667, accuracy: acc); XCTAssertEqual(p.y, 0.333333, accuracy: acc)
        XCTAssertEqual(p.z, 0.266667, accuracy: acc); XCTAssertEqual(p.rotZ, -0.785398, accuracy: acc); XCTAssertEqual(p.scale, 1.05, accuracy: acc)
        p = m.pose(at: 0.3)
        XCTAssertEqual(p.x, 3.333333, accuracy: acc); XCTAssertEqual(p.y, 0, accuracy: acc); XCTAssertEqual(p.z, 0.1, accuracy: acc)
        XCTAssertEqual(p.rotZ, -Double.pi / 2, accuracy: acc); XCTAssertEqual(p.scale, 1, accuracy: acc)
    }

    func testTumbleStep() {
        let m = TumbleStepMotion(from: Point2(x: 0, y: 0), coverSize: s, startRotX: 0)
        XCTAssertEqual(m.to.y, -s, accuracy: acc)
        var p = m.pose(at: 0.175)
        XCTAssertEqual(p.y, -1.666667, accuracy: acc); XCTAssertEqual(p.z, 1.866667, accuracy: acc)
        XCTAssertEqual(p.rotX, Double.pi / 2, accuracy: acc); XCTAssertEqual(p.scale, 1.05, accuracy: acc)
        p = m.pose(at: 0.35)
        XCTAssertEqual(p.y, -3.333333, accuracy: acc); XCTAssertEqual(p.z, 0.2, accuracy: acc); XCTAssertEqual(p.rotX, Double.pi, accuracy: acc)
    }

    func testPinSwing() {
        let m = PinSwingMotion(pin: Point2(x: 0, y: 0), from: Point2(x: -s / 2, y: s / 2))
        var p = m.pose(at: 0.2)
        XCTAssertEqual(p.x, -2.357023, accuracy: acc); XCTAssertEqual(p.y, 0, accuracy: acc); XCTAssertEqual(p.z, 0.001, accuracy: acc)
        XCTAssertEqual(p.rotZ, Double.pi / 4, accuracy: acc); XCTAssertEqual(p.scale, 1.03, accuracy: acc)
        XCTAssertFalse(m.hasSwapped(at: 0.3))
        p = m.pose(at: 0.4)
        XCTAssertEqual(p.x, -1.666667, accuracy: acc); XCTAssertEqual(p.y, -1.666667, accuracy: acc)
        XCTAssertEqual(p.z, -0.001, accuracy: acc); XCTAssertEqual(p.rotZ, -Double.pi / 2, accuracy: acc)
        XCTAssertTrue(m.hasSwapped(at: 0.4))
        p = m.pose(at: 0.8)
        XCTAssertEqual(p.x, 1.666667, accuracy: acc); XCTAssertEqual(p.y, -1.666667, accuracy: acc)
        XCTAssertEqual(p.z, 0.001, accuracy: acc); XCTAssertEqual(cos(p.rotZ), 1, accuracy: acc); XCTAssertEqual(p.scale, 1, accuracy: acc)
    }
}
