import Foundation

/// A command the remote (iPhone) sends to the presenter (iPad).
enum RemoteCommand: String, Codable {
    case previous, next, blackout, toggleTimer, resetTimer
}

/// A snapshot the presenter pushes to the remote so it can mirror the talk.
struct PresenterState: Codable, Equatable {
    var title: String
    var index: Int
    var pageCount: Int
    var note: String
    var blackout: Bool
    var timerRunning: Bool
    var elapsed: Int
}

/// The wire packet exchanged over the session (Codable is synthesised for the
/// enum's associated values).
enum RemotePacket: Codable {
    case command(RemoteCommand)
    case state(PresenterState)
}
