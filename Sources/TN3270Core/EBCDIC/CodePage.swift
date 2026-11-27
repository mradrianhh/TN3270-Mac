/// An EBCDIC code page (CECP / CCSID) used to translate between host bytes and
/// Unicode characters shown on the client.
public struct CodePage: Identifiable, Hashable, Sendable {
    /// The CCSID / code page number, e.g. "037" or "1047".
    public let id: String
    /// Human readable description.
    public let name: String

    /// Combined graphic character set and code page ID for 3270 Character Sets queries.
    public var cgcsgid: UInt32 {
        guard let configuredNumber = UInt16(id) else {
            preconditionFailure("Code page IDs must be numeric 16-bit identifiers")
        }
        // Advertise the Euro-capable Denmark/Norway set without changing translation.
        let number: UInt16 = configuredNumber == 277 ? 1142 : configuredNumber
        let characterSet: UInt32 = (1140...1148).contains(number) ? 695 : 697
        return characterSet << 16 | UInt32(number)
    }

    private let toUnicode: [UInt16]
    private let fromUnicode: [UInt16: UInt8]

    init(id: String, name: String, table: [UInt16]) {
        precondition(table.count == 256, "EBCDIC table must contain 256 entries")
        self.id = id
        self.name = name
        self.toUnicode = table
        var reverse: [UInt16: UInt8] = [:]
        for (index, scalar) in table.enumerated() where reverse[scalar] == nil {
            reverse[scalar] = UInt8(index)
        }
        self.fromUnicode = reverse
    }

    public static func == (lhs: CodePage, rhs: CodePage) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// All code pages bundled with the emulator.
    public static var all: [CodePage] { builtIn }

    /// The default code page (CECP 037, USA/Canada).
    public static var `default`: CodePage { builtIn[0] }

    /// Looks up a code page by its identifier (e.g. "037", "CP1047", "1140").
    public static func named(_ identifier: String) -> CodePage? {
        var key = identifier.uppercased()
        for prefix in ["CP", "IBM-", "IBM", "CCSID"] where key.hasPrefix(prefix) {
            key = String(key.dropFirst(prefix.count))
        }
        if let page = builtIn.first(where: { $0.id == key }) { return page }
        if let number = Int(key) {
            return builtIn.first(where: { Int($0.id) == number })
        }
        return nil
    }

    /// Converts a single EBCDIC byte to a Unicode character.
    public func character(for byte: UInt8) -> Character {
        let value = toUnicode[Int(byte)]
        guard let scalar = Unicode.Scalar(value) else { return " " }
        return Character(scalar)
    }

    /// Converts a Unicode character to its EBCDIC byte, or `nil` if the
    /// character cannot be represented in this code page.
    public func ebcdic(for character: Character) -> UInt8? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.value <= UInt32(UInt16.max) else { return nil }
        return fromUnicode[UInt16(scalar.value)]
    }

    /// Decodes a buffer of EBCDIC bytes into a string.
    public func decode<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        var result = ""
        for byte in bytes { result.append(character(for: byte)) }
        return result
    }

    /// Encodes a string into EBCDIC, replacing unmappable characters with
    /// the EBCDIC substitute character (0x3F).
    public func encode(_ string: String) -> [UInt8] {
        string.map { ebcdic(for: $0) ?? 0x3F }
    }
}
