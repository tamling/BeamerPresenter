import Foundation

/// Easing curves, `t` in 0...1 (original index.html lines 4084, 4212-4214, 4537-4539).
enum Easing {
    static func inOutSine(_ t: Double) -> Double { 0.5 - 0.5 * cos(Double.pi * t) }
    static func outQuart(_ t: Double) -> Double { 1 - pow(1 - t, 4) }
    static func inQuart(_ t: Double) -> Double { t * t * t * t }
    static func inOutCubic(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    static func inOutQuad(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
}
