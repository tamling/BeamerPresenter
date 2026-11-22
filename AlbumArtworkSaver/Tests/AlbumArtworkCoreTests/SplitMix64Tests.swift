import XCTest
@testable import AlbumArtworkCore

final class SplitMix64Tests: XCTestCase {
    func testSplitMixSeedZero() {
        var r = SplitMix64(seed: 0)
        XCTAssertEqual(r.next(), 0xE220A8397B1DCDAF)
    }

    func testDeterministic() {
        var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42)
        for _ in 0..<10 { XCTAssertEqual(a.next(), b.next()) }
    }
}
