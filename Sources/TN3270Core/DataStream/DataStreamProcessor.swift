/// Outcome of processing an outbound (host to terminal) 3270 record.
public struct DataStreamResult: Equatable, Sendable {
    /// The WCC requested the keyboard to be unlocked.
    public var keyboardRestore = false
    /// The WCC requested the audible alarm.
    public var soundAlarm = false
    /// Inbound records (terminal to host) that must be transmitted in reply.
    public var replies: [[UInt8]] = []
    /// The record contained an unknown command.
    public var commandRejected = false

    public init() {}
}

/// Interprets the outbound 3270 data stream and builds inbound replies.
public final class DataStreamProcessor {
    public var screen: ScreenBuffer
    /// Host code page reported in Character Sets query replies.
    public var codePage: CodePage
    /// Default (Erase/Write) screen size. Always 24x80 for 3278 models.
    public let defaultRows = 24
    public let defaultColumns = 80
    /// Alternate (Erase/Write Alternate) screen size, determined by the terminal model.
    public private(set) var alternateRows: Int
    public private(set) var alternateColumns: Int
    /// The last AID sent to the host; used to answer host initiated reads.
    public var lastAID: UInt8 = DS.AID.none

    public init(model: TerminalModel = .model2, codePage: CodePage = .default) {
        self.codePage = codePage
        alternateRows = model.rows
        alternateColumns = model.columns
        screen = ScreenBuffer(rows: 24, columns: 80)
    }

    /// Changes the terminal model and resets the screen.
    public func configure(model: TerminalModel) {
        alternateRows = model.rows
        alternateColumns = model.columns
        screen.clear(rows: defaultRows, columns: defaultColumns)
    }

    // MARK: - Outbound processing

    /// Processes one complete 3270 record (command + data).
    @discardableResult
    public func process(_ record: [UInt8]) -> DataStreamResult {
        var result = DataStreamResult()
        guard let command = record.first else { return result }
        let data = Array(record.dropFirst())
        processCommand(command, data: data, result: &result)
        return result
    }

    private func processCommand(_ command: UInt8, data: [UInt8], result: inout DataStreamResult) {
        if DS.Command.write.contains(command) {
            write(data, erase: false, alternate: false, result: &result)
        } else if DS.Command.eraseWrite.contains(command) {
            write(data, erase: true, alternate: false, result: &result)
        } else if DS.Command.eraseWriteAlternate.contains(command) {
            write(data, erase: true, alternate: true, result: &result)
        } else if DS.Command.readBuffer.contains(command) {
            result.replies.append(readBuffer(aid: lastAID))
        } else if DS.Command.readModified.contains(command) {
            result.replies.append(readModified(aid: lastAID, all: false))
        } else if DS.Command.readModifiedAll.contains(command) {
            result.replies.append(readModified(aid: lastAID, all: true))
        } else if DS.Command.eraseAllUnprotected.contains(command) {
            eraseAllUnprotected()
            result.keyboardRestore = true
        } else if DS.Command.writeStructuredField.contains(command) {
            writeStructuredField(data, result: &result)
        } else if command == DS.Command.nop {
            return
        } else {
            result.commandRejected = true
        }
    }

    private func write(_ data: [UInt8], erase: Bool, alternate: Bool, result: inout DataStreamResult) {
        if erase {
            if alternate {
                screen.clear(rows: alternateRows, columns: alternateColumns)
            } else {
                screen.clear(rows: defaultRows, columns: defaultColumns)
            }
        }
        guard let wcc = data.first else { return }
        if wcc & DS.WCC.resetMDT != 0 { screen.resetAllModified() }

        var address = erase ? 0 : screen.cursor
        var insertCursor: Int?
        var foreground: UInt8 = 0
        var background: UInt8 = 0
        var highlight: UInt8 = 0
        var lastWasCharacter = false
        var index = 1

        func next() -> UInt8? {
            guard index < data.count else { return nil }
            defer { index += 1 }
            return data[index]
        }

        func putCharacter(_ byte: UInt8) {
            var cell = ScreenCell()
            cell.byte = byte
            cell.foreground = foreground
            cell.background = background
            cell.highlight = highlight
            screen[address] = cell
            address = screen.wrap(address + 1)
        }

        func putAttribute(_ attribute: UInt8, foreground fg: UInt8 = 0, background bg: UInt8 = 0, highlight hl: UInt8 = 0) {
            var cell = ScreenCell()
            cell.isFieldAttribute = true
            cell.byte = attribute
            cell.foreground = fg
            cell.background = bg
            cell.highlight = hl
            screen[address] = cell
            address = screen.wrap(address + 1)
        }

        while let byte = next() {
            switch byte {
            case DS.Order.startField:
                guard let attribute = next() else { break }
                putAttribute(attribute)
                lastWasCharacter = false

            case DS.Order.startFieldExtended:
                guard let count = next() else { break }
                var attribute: UInt8 = 0
                var fg: UInt8 = 0, bg: UInt8 = 0, hl: UInt8 = 0
                for _ in 0..<Int(count) {
                    guard let type = next(), let value = next() else { break }
                    switch type {
                    case DS.ExtendedAttribute.fieldAttribute: attribute = value
                    case DS.ExtendedAttribute.foreground: fg = value
                    case DS.ExtendedAttribute.background: bg = value
                    case DS.ExtendedAttribute.highlighting: hl = value
                    default: break
                    }
                }
                putAttribute(attribute, foreground: fg, background: bg, highlight: hl)
                lastWasCharacter = false

            case DS.Order.setBufferAddress:
                guard let high = next(), let low = next() else { break }
                address = screen.wrap(DS.decodeAddress(high, low))
                lastWasCharacter = false

            case DS.Order.insertCursor:
                insertCursor = address
                lastWasCharacter = false

            case DS.Order.programTab:
                if lastWasCharacter {
                    // Null-fill the remainder of the current field.
                    while !screen[address].isFieldAttribute {
                        screen[address].byte = 0
                        address = screen.wrap(address + 1)
                        if address == 0 { break }
                    }
                }
                address = screen.nextUnprotectedField(after: address - 1) ?? 0
                lastWasCharacter = false

            case DS.Order.repeatToAddress:
                guard let high = next(), let low = next(), var character = next() else { break }
                if character == DS.Order.graphicEscape, let escaped = next() { character = escaped }
                let stop = screen.wrap(DS.decodeAddress(high, low))
                repeat {
                    putCharacter(character)
                } while address != stop
                lastWasCharacter = true

            case DS.Order.eraseUnprotectedToAddress:
                guard let high = next(), let low = next() else { break }
                let stop = screen.wrap(DS.decodeAddress(high, low))
                repeat {
                    if !screen.isProtected(address) { screen[address].byte = 0 }
                    address = screen.wrap(address + 1)
                } while address != stop
                lastWasCharacter = false

            case DS.Order.graphicEscape:
                guard let character = next() else { break }
                putCharacter(character)
                lastWasCharacter = true

            case DS.Order.setAttribute:
                guard let type = next(), let value = next() else { break }
                switch type {
                case DS.ExtendedAttribute.all:
                    foreground = 0; background = 0; highlight = 0
                case DS.ExtendedAttribute.foreground: foreground = value
                case DS.ExtendedAttribute.background: background = value
                case DS.ExtendedAttribute.highlighting: highlight = value
                default: break
                }
                lastWasCharacter = false

            case DS.Order.modifyField:
                guard let count = next() else { break }
                let isAttribute = screen[address].isFieldAttribute
                for _ in 0..<Int(count) {
                    guard let type = next(), let value = next() else { break }
                    guard isAttribute else { continue }
                    switch type {
                    case DS.ExtendedAttribute.fieldAttribute: screen[address].byte = value
                    case DS.ExtendedAttribute.foreground: screen[address].foreground = value
                    case DS.ExtendedAttribute.background: screen[address].background = value
                    case DS.ExtendedAttribute.highlighting: screen[address].highlight = value
                    default: break
                    }
                }
                if isAttribute { address = screen.wrap(address + 1) }
                lastWasCharacter = false

            default:
                putCharacter(byte)
                lastWasCharacter = true
            }
        }

        if let insertCursor {
            screen.cursor = insertCursor
        } else if erase {
            screen.cursor = 0
        }
        if wcc & DS.WCC.keyboardRestore != 0 {
            result.keyboardRestore = true
            lastAID = DS.AID.none
        }
        if wcc & DS.WCC.soundAlarm != 0 { result.soundAlarm = true }
    }

    private func eraseAllUnprotected() {
        if screen.isFormatted {
            for address in 0..<screen.size where !screen.isProtected(address) {
                screen[address].byte = 0
            }
            screen.resetAllModified()
            screen.cursor = screen.nextUnprotectedField(after: screen.size - 1) ?? 0
        } else {
            screen.clear()
        }
        lastAID = DS.AID.none
    }

    // MARK: - Structured fields

    private func writeStructuredField(_ data: [UInt8], result: inout DataStreamResult) {
        var index = 0
        while index + 3 <= data.count {
            var length = (Int(data[index]) << 8) | Int(data[index + 1])
            if length == 0 { length = data.count - index }
            guard length >= 3, index + length <= data.count else { break }
            let id = data[index + 2]
            let body = Array(data[(index + 3)..<(index + length)])
            switch id {
            case DS.StructuredField.readPartition:
                if body.count >= 2 {
                    let type = body[1]
                    if body[0] == 0xFF && (type == DS.StructuredField.readPartitionQuery
                                           || type == DS.StructuredField.readPartitionQueryList) {
                        if type == DS.StructuredField.readPartitionQuery {
                            result.replies.append(queryReply())
                        } else if body.count < 3 {
                            result.commandRejected = true
                        } else {
                            switch body[2] {
                            case 0x00:
                                result.replies.append(queryReply(requestedCodes: Array(body.dropFirst(3))))
                            case 0x40, 0x80:
                                result.replies.append(queryReply())
                            default:
                                result.commandRejected = true
                            }
                        }
                    } else if DS.Command.readBuffer.contains(type) {
                        result.replies.append(readBuffer(aid: lastAID))
                    } else if DS.Command.readModified.contains(type) {
                        result.replies.append(readModified(aid: lastAID, all: false))
                    } else if DS.Command.readModifiedAll.contains(type) {
                        result.replies.append(readModified(aid: lastAID, all: true))
                    }
                }
            case DS.StructuredField.eraseReset:
                let alternate = (body.first ?? 0) & 0x80 != 0
                if alternate {
                    screen.clear(rows: alternateRows, columns: alternateColumns)
                } else {
                    screen.clear(rows: defaultRows, columns: defaultColumns)
                }
            case DS.StructuredField.outbound3270DS:
                if body.count >= 2 {
                    processCommand(body[1], data: Array(body.dropFirst(2)), result: &result)
                }
            default:
                break
            }
            index += length
        }
    }

    /// Builds the Query Reply sent in response to Read Partition (Query).
    public func queryReply(requestedCodes: [UInt8]? = nil) -> [UInt8] {
        func field(_ code: UInt8, _ body: [UInt8]) -> [UInt8] {
            if let requestedCodes, !requestedCodes.contains(code) { return [] }
            let length = body.count + 4
            return [UInt8(length >> 8), UInt8(length & 0xFF), DS.StructuredField.queryReply, code] + body
        }
        func be16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }

        let codes: [UInt8] = [
            DS.QueryCode.summary, DS.QueryCode.usableArea, DS.QueryCode.characterSets, DS.QueryCode.color,
            DS.QueryCode.highlighting, DS.QueryCode.replyModes, DS.QueryCode.implicitPartition,
        ]
        var reply: [UInt8] = [DS.AID.structuredField]
        reply += field(DS.QueryCode.summary, codes)
        var usableArea: [UInt8] = [0x01, 0x00]
        usableArea += be16(alternateColumns)
        usableArea += be16(alternateRows)
        usableArea += [0x01, 0x00, 0x0A, 0x02, 0xE5, 0x00, 0x02, 0x00, 0x6F, 0x09, 0x0C]
        usableArea += be16(alternateColumns * alternateRows)
        reply += field(DS.QueryCode.usableArea, usableArea)
        // One non-loadable SBCS set (LCID 0), with a four-byte CGCSGID.
        let cgcsgid = codePage.cgcsgid
        reply += field(DS.QueryCode.characterSets,
                       [0x02, 0x00, 0x09, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x07,
                        0x00, 0x10, 0x00,
                        UInt8(truncatingIfNeeded: cgcsgid >> 24), UInt8(truncatingIfNeeded: cgcsgid >> 16),
                        UInt8(truncatingIfNeeded: cgcsgid >> 8), UInt8(truncatingIfNeeded: cgcsgid)])
        var colors: [UInt8] = [0x00, 0x10, 0x00, HostColor.green.rawValue]
        for color in UInt8(0xF1)...UInt8(0xFF) { colors += [color, color] }
        reply += field(DS.QueryCode.color, colors)
        reply += field(DS.QueryCode.highlighting,
                       [0x04, 0x00, 0xF0, 0xF1, 0xF1, 0xF2, 0xF2, 0xF4, 0xF4])
        reply += field(DS.QueryCode.replyModes, [0x00])
        reply += field(DS.QueryCode.implicitPartition,
                       [0x00, 0x00, 0x0B, 0x01, 0x00] + be16(defaultColumns) + be16(defaultRows)
                       + be16(alternateColumns) + be16(alternateRows))
        if reply.count == 1 {
            reply += [0x00, 0x04, DS.StructuredField.queryReply, DS.QueryCode.null]
        }
        return reply
    }

    // MARK: - Inbound records

    /// Builds the inbound record for Read Modified / Read Modified All or an AID key.
    public func readModified(aid: UInt8, all: Bool) -> [UInt8] {
        var out: [UInt8] = [aid]
        if DS.AID.isShortRead(aid) && !all { return out }
        out += DS.encodeAddress(screen.cursor, bufferSize: screen.size)

        if screen.isFormatted {
            for fa in 0..<screen.size where screen[fa].isFieldAttribute {
                guard screen[fa].byte & DS.FieldAttribute.modified != 0 else { continue }
                let start = screen.wrap(fa + 1)
                out.append(DS.Order.setBufferAddress)
                out += DS.encodeAddress(start, bufferSize: screen.size)
                var address = start
                while !screen[address].isFieldAttribute {
                    let byte = screen[address].byte
                    if byte != 0 { out.append(byte) }
                    address = screen.wrap(address + 1)
                }
            }
        } else {
            for cell in screen.cells where cell.byte != 0 {
                out.append(cell.byte)
            }
        }
        return out
    }

    /// Builds the inbound record for Read Buffer.
    public func readBuffer(aid: UInt8) -> [UInt8] {
        var out: [UInt8] = [aid]
        out += DS.encodeAddress(screen.cursor, bufferSize: screen.size)
        for cell in screen.cells {
            if cell.isFieldAttribute {
                out.append(DS.Order.startField)
                out.append(DS.codeTable[Int(cell.byte & 0x3F)])
            } else {
                out.append(cell.byte)
            }
        }
        return out
    }
}
