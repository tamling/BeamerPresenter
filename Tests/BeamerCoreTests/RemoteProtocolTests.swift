import XCTest
@testable import BeamerCore

final class RemoteProtocolTests: XCTestCase {

    private func state(title: String = "Talk", index: Int = 2, pageCount: Int = 10,
                       note: String = "Say hello", elapsed: Int = 65) -> PresenterState {
        PresenterState(title: title, index: index, pageCount: pageCount, note: note,
                       blackout: false, timerRunning: true, elapsed: elapsed)
    }

    func testOversizedDataIsRejected() throws {
        // A syntactically valid packet, padded with whitespace past the cap.
        var data = try XCTUnwrap(RemotePacket.command(.next).encoded())
        data.append(Data(repeating: 0x20, count: RemotePacket.maxPacketBytes))
        XCTAssertGreaterThan(data.count, RemotePacket.maxPacketBytes)
        XCTAssertNil(RemotePacket.decode(data))
    }

    func testSanitizedClampsNumbersAndTruncatesText() {
        let s = state(title: String(repeating: "T", count: 10_000), index: Int.max, pageCount: -5,
                      note: String(repeating: "ü", count: 100_000), elapsed: -1).sanitized()
        XCTAssertEqual(s.pageCount, 0)
        XCTAssertEqual(s.index, 0)
        XCTAssertEqual(s.elapsed, 0)
        XCTAssertEqual(s.title.count, PresenterState.maxTitleLength)
        XCTAssertLessThanOrEqual(s.note.count, PresenterState.maxNoteLength)
        XCTAssertLessThanOrEqual(s.note.utf8.count, PresenterState.maxNoteBytes)

        let big = state(index: Int.max, pageCount: Int.max, elapsed: Int.max).sanitized()
        XCTAssertEqual(big.pageCount, PresenterState.maxPageCount)
        XCTAssertEqual(big.index, PresenterState.maxPageCount - 1)
        XCTAssertEqual(big.elapsed, PresenterState.maxElapsed)
    }

    func testDecodedStateIsSanitized() throws {
        let raw = try JSONEncoder().encode(RemotePacket.state(state(index: Int.max)))
        guard case .state(let s)? = RemotePacket.decode(raw) else { return XCTFail("not a state") }
        XCTAssertEqual(s.index, 9)
    }

    func testStateRoundTrips() throws {
        let original = state()
        let data = try XCTUnwrap(RemotePacket.state(original).encoded())
        guard case .state(let decoded)? = RemotePacket.decode(data) else { return XCTFail("not a state") }
        XCTAssertEqual(decoded, original)
    }

    func testCommandRoundTrips() throws {
        let data = try XCTUnwrap(RemotePacket.command(.toggleTimer).encoded())
        guard case .command(let c)? = RemotePacket.decode(data) else { return XCTFail("not a command") }
        XCTAssertEqual(c, .toggleTimer)
    }

    func testTruncatedKeepsWholeCharacters() {
        XCTAssertEqual(PresenterState.truncated("aü", maxBytes: 2), "a")
        XCTAssertEqual(PresenterState.truncated("abc", maxBytes: 10), "abc")
    }

    func testPairingCode() {
        let code = PairingCode.make()
        XCTAssertTrue(PairingCode.isWellFormed(code))
        XCTAssertTrue(PairingCode.matches(code, code))
        XCTAssertFalse(PairingCode.matches("123456", "123457"))
        XCTAssertFalse(PairingCode.matches("123456", "12345"))
        XCTAssertFalse(PairingCode.isWellFormed("12a456"))
    }
}
