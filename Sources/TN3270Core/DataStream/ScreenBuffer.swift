/// 3270 colors, using the host color identifiers.
public enum HostColor: UInt8, Sendable, CaseIterable {
    case `default` = 0x00
    case blue = 0xF1
    case red = 0xF2
    case pink = 0xF3
    case green = 0xF4
    case turquoise = 0xF5
    case yellow = 0xF6
    case white = 0xF7
}

/// Extended highlighting values.
public enum Highlight: UInt8, Sendable {
    case `default` = 0x00
    case normal = 0xF0
    case blink = 0xF1
    case reverse = 0xF2
    case underscore = 0xF4
}

/// One position of the 3270 presentation space.
public struct ScreenCell: Equatable, Sendable {
    /// EBCDIC character (or the field attribute byte when `isFieldAttribute`).
    public var byte: UInt8 = 0x00
    /// Whether this position holds a field attribute.
    public var isFieldAttribute = false
    /// Extended attributes (from SFE/SA/MF).
    public var foreground: UInt8 = 0
    public var background: UInt8 = 0
    public var highlight: UInt8 = 0

    public init() {}
}

/// Resolved visual attributes for rendering a cell.
public struct CellAppearance: Equatable, Sendable {
    public var foreground: HostColor
    public var background: HostColor
    public var intensified: Bool
    public var hidden: Bool
    public var reverse: Bool
    public var underscore: Bool
    public var blink: Bool
}

/// The 3270 presentation space (character buffer plus fields).
public struct ScreenBuffer: Sendable {
    public private(set) var rows: Int
    public private(set) var columns: Int
    public private(set) var cells: [ScreenCell]
    public var cursor: Int = 0

    public var size: Int { rows * columns }

    public init(rows: Int = 24, columns: Int = 80) {
        self.rows = rows
        self.columns = columns
        self.cells = Array(repeating: ScreenCell(), count: rows * columns)
    }

    /// Clears the buffer and optionally changes its dimensions.
    public mutating func clear(rows: Int? = nil, columns: Int? = nil) {
        if let rows { self.rows = rows }
        if let columns { self.columns = columns }
        cells = Array(repeating: ScreenCell(), count: self.rows * self.columns)
        cursor = 0
    }

    public subscript(address: Int) -> ScreenCell {
        get { cells[wrap(address)] }
        set { cells[wrap(address)] = newValue }
    }

    public func wrap(_ address: Int) -> Int {
        let size = self.size
        return ((address % size) + size) % size
    }

    public func row(of address: Int) -> Int { wrap(address) / columns }
    public func column(of address: Int) -> Int { wrap(address) % columns }
    public func address(row: Int, column: Int) -> Int { wrap(row * columns + column) }

    /// True when the buffer contains at least one field attribute.
    public var isFormatted: Bool { cells.contains { $0.isFieldAttribute } }

    // MARK: - Fields

    /// Address of the field attribute governing `address`, or nil if the
    /// screen is unformatted.
    public func fieldAttributeAddress(for address: Int) -> Int? {
        var current = wrap(address)
        for _ in 0..<size {
            if cells[current].isFieldAttribute { return current }
            current = wrap(current - 1)
        }
        return nil
    }

    /// The field attribute byte governing `address` (nil if unformatted).
    public func fieldAttribute(for address: Int) -> UInt8? {
        fieldAttributeAddress(for: address).map { cells[$0].byte }
    }

    /// Whether input is prohibited at the given position.
    public func isProtected(_ address: Int) -> Bool {
        if cells[wrap(address)].isFieldAttribute { return true }
        guard let attribute = fieldAttribute(for: address) else { return false }
        return attribute & DS.FieldAttribute.protected != 0
    }

    /// Whether the field at `address` only accepts numeric input.
    public func isNumeric(_ address: Int) -> Bool {
        guard let attribute = fieldAttribute(for: address) else { return false }
        return attribute & DS.FieldAttribute.numeric != 0
    }

    /// Address of the next field attribute after `address` (exclusive), wrapping.
    public func nextFieldAttributeAddress(after address: Int) -> Int? {
        var current = wrap(address + 1)
        for _ in 0..<size {
            if cells[current].isFieldAttribute { return current }
            current = wrap(current + 1)
        }
        return nil
    }

    /// First data position of the next unprotected field strictly after `address`.
    public func nextUnprotectedField(after address: Int) -> Int? {
        var current = wrap(address)
        for _ in 0..<size {
            current = wrap(current + 1)
            if cells[current].isFieldAttribute,
               cells[current].byte & DS.FieldAttribute.protected == 0,
               !cells[wrap(current + 1)].isFieldAttribute {
                return wrap(current + 1)
            }
        }
        return nil
    }

    /// Sets the Modified Data Tag of the field containing `address`.
    public mutating func setModified(at address: Int) {
        if let fa = fieldAttributeAddress(for: address) {
            cells[fa].byte |= DS.FieldAttribute.modified
        }
    }

    /// Resets all MDTs.
    public mutating func resetAllModified() {
        for index in cells.indices where cells[index].isFieldAttribute {
            cells[index].byte &= ~DS.FieldAttribute.modified
        }
    }

    // MARK: - Rendering helpers

    /// Display attributes for a position, combining field and character attributes.
    public func appearance(at address: Int) -> CellAppearance {
        let field = fieldAttributeAddress(for: address).map { cells[$0] }
        return appearance(of: cells[wrap(address)], field: field)
    }

    /// Display attributes for every position, computed in a single pass.
    public func appearances() -> [CellAppearance] {
        var field: ScreenCell? = cells.last(where: { $0.isFieldAttribute })
        var result: [CellAppearance] = []
        result.reserveCapacity(cells.count)
        for cell in cells {
            if cell.isFieldAttribute { field = cell }
            result.append(appearance(of: cell, field: field))
        }
        return result
    }

    private func appearance(of cell: ScreenCell, field: ScreenCell?) -> CellAppearance {
        let fa = field?.byte ?? 0
        let isProtected = fa & DS.FieldAttribute.protected != 0
        let display = fa & DS.FieldAttribute.displayMask
        let intensified = display == DS.FieldAttribute.intensified
        let hidden = field != nil && display == DS.FieldAttribute.nonDisplay

        // Base (4-color) mapping used by 3279 terminals when no explicit color is set.
        let baseColor: HostColor
        if field == nil {
            baseColor = .green
        } else if isProtected {
            baseColor = intensified ? .white : .blue
        } else {
            baseColor = intensified ? .red : .green
        }

        let fgByte = cell.foreground != 0 ? cell.foreground : (field?.foreground ?? 0)
        let bgByte = cell.background != 0 ? cell.background : (field?.background ?? 0)
        let hlByte = cell.highlight != 0 ? cell.highlight : (field?.highlight ?? 0)

        var foreground = HostColor(rawValue: fgByte) ?? baseColor
        if foreground == .default { foreground = baseColor }
        let background = HostColor(rawValue: bgByte) ?? .default

        return CellAppearance(
            foreground: foreground,
            background: cell.isFieldAttribute ? .default : background,
            intensified: intensified,
            hidden: hidden || cell.isFieldAttribute,
            reverse: !cell.isFieldAttribute && hlByte == Highlight.reverse.rawValue,
            underscore: !cell.isFieldAttribute && hlByte == Highlight.underscore.rawValue,
            blink: hlByte == Highlight.blink.rawValue
        )
    }

    /// Returns the text of a row, using the given code page. Attribute and
    /// null positions are rendered as spaces, non-display fields are blanked.
    public func text(row: Int, codePage: CodePage) -> String {
        var line = ""
        for column in 0..<columns {
            line.append(displayCharacter(at: row * columns + column, codePage: codePage))
        }
        return line
    }

    /// The character to display at an address.
    public func displayCharacter(at address: Int, codePage: CodePage) -> Character {
        let cell = cells[wrap(address)]
        if cell.isFieldAttribute || cell.byte == 0x00 { return " " }
        if let fa = fieldAttribute(for: address), fa & DS.FieldAttribute.displayMask == DS.FieldAttribute.nonDisplay {
            return " "
        }
        let character = codePage.character(for: cell.byte)
        if let scalar = character.unicodeScalars.first, scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value) {
            return " "
        }
        return character
    }
}
