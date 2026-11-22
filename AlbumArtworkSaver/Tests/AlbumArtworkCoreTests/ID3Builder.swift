import Foundation

/// Test helper that assembles ID3v2.2/2.3/2.4 tags.
struct ID3Builder {
    let version: UInt8
    var unsynchronised = false
    var extendedHeader = false
    private var frames: [(id: String, flags: [UInt8], body: Data, sizeOverride: UInt32?)] = []

    init(version: UInt8) { self.version = version }

    static func encode(_ string: String, encoding: UInt8, terminated: Bool) -> Data {
        var out = Data()
        switch encoding {
        case 1:
            out.append(contentsOf: [0xFF, 0xFE])
            for unit in string.utf16 { out.append(contentsOf: [UInt8(unit & 0xFF), UInt8(unit >> 8)]) }
        case 2:
            for unit in string.utf16 { out.append(contentsOf: [UInt8(unit >> 8), UInt8(unit & 0xFF)]) }
        case 3:
            out.append(contentsOf: Array(string.utf8))
        default:
            out.append(string.data(using: .isoLatin1, allowLossyConversion: true) ?? Data())
        }
        if terminated { out.append(contentsOf: [UInt8](repeating: 0, count: (encoding == 1 || encoding == 2) ? 2 : 1)) }
        return out
    }

    mutating func text(_ id: String, _ value: String, encoding: UInt8) {
        var body = Data([encoding])
        body.append(ID3Builder.encode(value, encoding: encoding, terminated: false))
        rawFrame(id: id, flags: [0, 0], body: body)
    }

    mutating func picture(type: UInt8, mime: String, description: String, data: Data, encoding: UInt8) {
        var body = Data([encoding])
        if version == 2 {
            body.append(mime.data(using: .isoLatin1) ?? Data())
        } else {
            body.append(mime.data(using: .isoLatin1) ?? Data())
            body.append(0)
        }
        body.append(type)
        body.append(ID3Builder.encode(description, encoding: encoding, terminated: true))
        body.append(data)
        rawFrame(id: version == 2 ? "PIC" : "APIC", flags: [0, 0], body: body)
    }

    mutating func rawFrame(id: String, flags: [UInt8], body: Data, sizeOverride: UInt32? = nil) {
        frames.append((id, flags, body, sizeOverride))
    }

    private static func unsync(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        for byte in bytes {
            out.append(byte)
            if byte == 0xFF { out.append(0) }
        }
        return out
    }

    private static func syncSafe(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    func build() -> Data {
        var payload: [UInt8] = []
        if extendedHeader && version == 3 { payload += [0, 0, 0, 6, 0, 0, 0, 0, 0, 0] }
        if extendedHeader && version == 4 { payload += [0, 0, 0, 6, 1, 0] }
        for frame in frames {
            var body = [UInt8](frame.body)
            if version == 4 && unsynchronised { body = ID3Builder.unsync(body) }
            let size = frame.sizeOverride ?? UInt32(body.count)
            payload += Array(frame.id.utf8)
            switch version {
            case 2: payload += [UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)]
            case 3: payload += ID3Builder.bigEndian(size) + frame.flags
            default: payload += ID3Builder.syncSafe(Int(size)) + frame.flags
            }
            payload += body
        }
        if version != 4 && unsynchronised { payload = ID3Builder.unsync(payload) }
        var flags: UInt8 = 0
        if unsynchronised { flags |= 0x80 }
        if extendedHeader && version != 2 { flags |= 0x40 }
        var out: [UInt8] = [0x49, 0x44, 0x33, version, 0, flags]
        out += ID3Builder.syncSafe(payload.count)
        out += payload
        return Data(out)
    }
}
