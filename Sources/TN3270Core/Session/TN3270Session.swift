/// A TN3270 terminal session: combines telnet/TN3270E negotiation, the 3270
/// data stream processor and local keyboard handling.
///
/// The session is transport agnostic. Use `connect(using:)` with a
/// `TN3270Transport` (e.g. `NetworkTransport`) or drive it directly with
/// `receive(_:)` and the `send` closure in tests.
public final class TN3270Session {
    public enum State: Equatable, Sendable {
        case disconnected
        case connecting
        case negotiating
        case connected(TelnetMode)
        case failed(String)
    }

    public private(set) var settings: ConnectionSettings
    public let negotiator: TelnetNegotiator
    public let processor: DataStreamProcessor
    public private(set) var codePage: CodePage

    public private(set) var state: State = .disconnected { didSet { notify() } }
    public private(set) var keyboardLocked = false
    public private(set) var insertMode = false
    /// True between BIND and UNBIND in TN3270E mode (or always in TN3270 mode).
    public private(set) var isBound = false
    /// TN3270E: last data was SSCP-LU data (e.g. a USS logon screen).
    public private(set) var isSSCPMode = false
    /// Text received while in NVT (non-3270) mode, typically server error messages.
    public private(set) var nvtText = ""

    /// Called after the screen or session status changes.
    public var onUpdate: (() -> Void)?
    /// Called when the host or an operator error requests the audible alarm.
    public var onAlarm: (() -> Void)?
    /// Raw bytes to be written to the server. Set automatically by `connect(using:)`.
    public var send: ([UInt8]) -> Void = { _ in }

    private var transport: TN3270Transport?

    public init(settings: ConnectionSettings) {
        self.settings = settings
        self.codePage = settings.codePage
        self.negotiator = TelnetNegotiator(terminalType: settings.model.terminalType,
                                           allowTN3270E: settings.useTN3270E,
                                           luName: settings.luName.isEmpty ? nil : settings.luName)
        self.processor = DataStreamProcessor(model: settings.model, codePage: settings.codePage)

        negotiator.send = { [weak self] bytes in self?.send(bytes) }
        negotiator.onRecord = { [weak self] record in self?.handleRecord(record) }
        negotiator.onModeChange = { [weak self] mode in self?.modeChanged(mode) }
        negotiator.onNVTData = { [weak self] bytes in
            guard let self else { return }
            self.nvtText += String(decoding: bytes.filter { $0 == 0x0A || $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self)
            self.notify()
        }
    }

    public var screen: ScreenBuffer { processor.screen }

    /// Applies new settings. Takes effect on the next connection.
    public func update(settings: ConnectionSettings) {
        self.settings = settings
        self.codePage = settings.codePage
        processor.codePage = settings.codePage
        negotiator.terminalType = settings.model.terminalType
        negotiator.allowTN3270E = settings.useTN3270E
        negotiator.luName = settings.luName.isEmpty ? nil : settings.luName
        if transport == nil {
            processor.configure(model: settings.model)
        }
        notify()
    }

    // MARK: - Connection

    /// Connects using the supplied transport.
    public func connect(using transport: TN3270Transport) {
        disconnect()
        resetForConnection()
        self.transport = transport
        send = { [weak transport] bytes in transport?.send(bytes) }
        transport.onReceive = { [weak self] bytes in self?.receive(bytes) }
        transport.onStateChange = { [weak self] transportState in
            self?.transportStateChanged(transportState)
        }
        state = .connecting
        transport.connect()
    }

    /// Closes the connection.
    public func disconnect() {
        guard let transport else { return }
        self.transport = nil
        transport.onReceive = nil
        transport.onStateChange = nil
        transport.disconnect()
        send = { _ in }
        state = .disconnected
    }

    /// Prepares state for a new connection (also used by tests without a transport).
    public func resetForConnection() {
        negotiator.reset()
        processor.configure(model: settings.model)
        processor.lastAID = DS.AID.none
        keyboardLocked = false
        insertMode = false
        isBound = false
        isSSCPMode = false
        nvtText = ""
        state = .negotiating
    }

    private func transportStateChanged(_ transportState: TransportState) {
        switch transportState {
        case .connecting:
            state = .connecting
        case .connected:
            state = .negotiating
        case .disconnected:
            if case .failed = state { return }
            transport = nil
            send = { _ in }
            state = .disconnected
        case .failed(let message):
            transport = nil
            send = { _ in }
            state = .failed(message)
        }
    }

    /// Feeds bytes received from the server into the session.
    public func receive(_ bytes: [UInt8]) {
        negotiator.receive(bytes)
    }

    private func modeChanged(_ mode: TelnetMode) {
        switch mode {
        case .tn3270:
            isBound = true
            state = .connected(mode)
        case .tn3270e:
            state = .connected(mode)
        case .nvt:
            state = .connected(mode)
        case .negotiating:
            state = .negotiating
        }
    }

    // MARK: - Inbound records

    private func handleRecord(_ record: [UInt8]) {
        guard negotiator.mode == .tn3270e else {
            apply(processor.process(record))
            return
        }
        guard record.count >= TN3270E.headerLength else { return }
        let responseFlag = record[2]
        let sequence = Array(record[3...4])
        let payload = Array(record.dropFirst(TN3270E.headerLength))

        switch TN3270E.DataType(rawValue: record[0]) {
        case .data3270?:
            isSSCPMode = false
            let result = processor.process(payload)
            apply(result)
            sendResponseIfNeeded(flag: responseFlag, sequence: sequence, rejected: result.commandRejected)
        case .sscpLUData?:
            isSSCPMode = true
            let result = processor.process(payload)
            apply(result)
            keyboardLocked = false
            notify()
        case .bindImage?:
            isBound = true
            isSSCPMode = false
            notify()
        case .unbind?:
            isBound = false
            processor.configure(model: settings.model)
            notify()
        default:
            break
        }
    }

    private func apply(_ result: DataStreamResult) {
        if result.keyboardRestore { keyboardLocked = false }
        if result.soundAlarm { onAlarm?() }
        for reply in result.replies { sendData(reply) }
        notify()
    }

    private func sendResponseIfNeeded(flag: UInt8, sequence: [UInt8], rejected: Bool) {
        guard negotiator.negotiatedFunctions.contains(.responses) else { return }
        let positive: Bool
        switch flag {
        case TN3270E.ResponseFlag.alwaysResponse: positive = !rejected
        case TN3270E.ResponseFlag.errorResponse where rejected: positive = false
        default: return
        }
        let header: [UInt8] = [
            TN3270E.DataType.response.rawValue, 0x00,
            positive ? TN3270E.ResponseFlag.positiveResponse : TN3270E.ResponseFlag.negativeResponse,
        ] + sequence
        // 0x00 = DEVICE-END (positive) or COMMAND-REJECT (negative).
        negotiator.sendRecord(header + [0x00])
    }

    /// Sends an inbound 3270 record, adding the TN3270E header when required.
    private func sendData(_ data: [UInt8], type: TN3270E.DataType = .data3270) {
        if negotiator.mode == .tn3270e {
            negotiator.sendRecord([type.rawValue, 0x00, 0x00, 0x00, 0x00] + data)
        } else {
            negotiator.sendRecord(data)
        }
    }

    private func notify() { onUpdate?() }

    // MARK: - Keyboard

    /// True when the session can exchange 3270 data.
    public var is3270Connected: Bool {
        negotiator.mode == .tn3270 || negotiator.mode == .tn3270e
    }

    /// Performs a 3270 keyboard function.
    public func perform(_ action: HostAction) {
        if action == .reset {
            keyboardLocked = false
            insertMode = false
            notify()
            return
        }
        if keyboardLocked && action != .attn && action != .sysreq {
            onAlarm?()
            return
        }

        switch action {
        case .enter: sendAID(DS.AID.enter)
        case .clear:
            processor.screen.clear(rows: processor.defaultRows, columns: processor.defaultColumns)
            sendAID(DS.AID.clear)
        case .pa1: sendAID(DS.AID.pa1)
        case .pa2: sendAID(DS.AID.pa2)
        case .pa3: sendAID(DS.AID.pa3)
        case .attn:
            guard is3270Connected else { return }
            negotiator.sendCommand(negotiator.mode == .tn3270e ? Telnet.IP : Telnet.BREAK)
        case .sysreq:
            guard is3270Connected else { return }
            if negotiator.mode == .tn3270e && negotiator.negotiatedFunctions.contains(.sysreq) {
                negotiator.sendCommand(Telnet.AO)
            } else {
                sendAID(DS.AID.sysreq)
            }
        case .reset: break
        case .tab: processor.screen.cursor = nextFieldPosition(after: screen.cursor)
        case .backtab: processor.screen.cursor = previousFieldPosition(before: screen.cursor)
        case .home: processor.screen.cursor = homePosition()
        case .newline:
            let next = screen.address(row: screen.row(of: screen.cursor) + 1, column: 0)
            if !screen.isFormatted || !screen.isProtected(next) {
                processor.screen.cursor = next
            } else {
                // Include a field attribute at the start of the target row.
                processor.screen.cursor = nextFieldPosition(after: screen.wrap(next - 1))
            }
        case .cursorUp: processor.screen.cursor = screen.wrap(screen.cursor - screen.columns)
        case .cursorDown: processor.screen.cursor = screen.wrap(screen.cursor + screen.columns)
        case .cursorLeft: processor.screen.cursor = screen.wrap(screen.cursor - 1)
        case .cursorRight: processor.screen.cursor = screen.wrap(screen.cursor + 1)
        case .backspace:
            let previous = screen.wrap(screen.cursor - 1)
            processor.screen.cursor = previous
            if !screen.isProtected(previous) { deleteCharacter() }
        case .delete: deleteCharacter()
        case .eraseEOF: eraseToEndOfField()
        case .eraseInput: eraseInput()
        case .insert: insertMode.toggle()
        case .dup:
            if enter(byte: 0x1C) { processor.screen.cursor = nextFieldPosition(after: screen.cursor) }
        case .fieldMark: _ = enter(byte: 0x1E)
        default:
            if let number = action.pfNumber { sendAID(DS.AID.pf[number - 1]) }
        }
        notify()
    }

    /// Types text at the cursor position.
    public func type(_ text: String) {
        for character in text {
            if keyboardLocked { onAlarm?(); break }
            guard let byte = codePage.ebcdic(for: character), byte >= 0x40 else {
                onAlarm?()
                break
            }
            if !enter(byte: byte) { break }
        }
        notify()
    }

    /// Moves the cursor (e.g. after a mouse click).
    public func moveCursor(to address: Int) {
        processor.screen.cursor = screen.wrap(address)
        notify()
    }

    private func sendAID(_ aid: UInt8) {
        guard is3270Connected else { return }
        processor.lastAID = aid
        if isSSCPMode {
            // SSCP-LU data has no AID or cursor address, only the field text.
            if aid == DS.AID.enter {
                let record = processor.readModified(aid: aid, all: false)
                sendData(Array(record.dropFirst(3)), type: .sscpLUData)
            } else {
                sendData([aid], type: .sscpLUData)
            }
        } else {
            sendData(processor.readModified(aid: aid, all: false))
        }
        keyboardLocked = true
        insertMode = false
    }

    /// Writes a byte at the cursor, honouring protection, numeric and insert mode.
    @discardableResult
    private func enter(byte: UInt8) -> Bool {
        let address = screen.cursor
        if screen.isFormatted {
            if screen.isProtected(address) {
                onAlarm?()
                return false
            }
            if screen.isNumeric(address) && byte != 0x1C {
                let character = codePage.character(for: byte)
                guard character.isNumber || character == "." || character == "-" else {
                    onAlarm?()
                    return false
                }
            }
        }

        let positions = fieldPositions(from: address)
        if insertMode {
            guard let last = positions.last, screen[last].byte == 0x00 || screen[last].byte == 0x40 else {
                onAlarm?()
                return false
            }
            for index in stride(from: positions.count - 1, to: 0, by: -1) {
                processor.screen[positions[index]].byte = screen[positions[index - 1]].byte
            }
        }
        processor.screen[address].byte = byte
        processor.screen.setModified(at: address)

        let next = screen.wrap(address + 1)
        if screen.isFormatted && screen[next].isFieldAttribute {
            let attribute = screen[next].byte
            let autoskip = attribute & DS.FieldAttribute.protected != 0 && attribute & DS.FieldAttribute.numeric != 0
            processor.screen.cursor = autoskip ? (screen.nextUnprotectedField(after: next) ?? screen.wrap(next + 1))
                                               : screen.wrap(next + 1)
        } else {
            processor.screen.cursor = next
        }
        return true
    }

    /// Data positions from `address` to the end of its field (or of the buffer when unformatted).
    private func fieldPositions(from address: Int) -> [Int] {
        var positions: [Int] = []
        if !screen.isFormatted {
            return Array(screen.wrap(address)..<screen.size)
        }
        var current = screen.wrap(address)
        while !screen[current].isFieldAttribute && positions.count < screen.size {
            positions.append(current)
            current = screen.wrap(current + 1)
        }
        return positions
    }

    private func deleteCharacter() {
        let address = screen.cursor
        guard !screen.isProtected(address) || !screen.isFormatted else {
            onAlarm?()
            return
        }
        let positions = fieldPositions(from: address)
        guard !positions.isEmpty else { return }
        for index in 0..<(positions.count - 1) {
            processor.screen[positions[index]].byte = screen[positions[index + 1]].byte
        }
        processor.screen[positions[positions.count - 1]].byte = 0
        processor.screen.setModified(at: address)
    }

    private func eraseToEndOfField() {
        let address = screen.cursor
        if screen.isFormatted && screen.isProtected(address) {
            onAlarm?()
            return
        }
        for position in fieldPositions(from: address) {
            processor.screen[position].byte = 0
        }
        processor.screen.setModified(at: address)
    }

    private func eraseInput() {
        if screen.isFormatted {
            for address in 0..<screen.size where !screen.isProtected(address) {
                processor.screen[address].byte = 0
            }
            processor.screen.resetAllModified()
        } else {
            processor.screen.clear()
        }
        processor.screen.cursor = homePosition()
    }

    private func homePosition() -> Int {
        guard screen.isFormatted else { return 0 }
        return screen.nextUnprotectedField(after: screen.size - 1) ?? 0
    }

    private func nextFieldPosition(after address: Int) -> Int {
        guard screen.isFormatted else { return 0 }
        return screen.nextUnprotectedField(after: address) ?? 0
    }

    private func previousFieldPosition(before address: Int) -> Int {
        guard screen.isFormatted else { return 0 }
        var current = screen.wrap(address)
        for _ in 0..<screen.size {
            current = screen.wrap(current - 1)
            let start = screen.wrap(current + 1)
            if screen[current].isFieldAttribute,
               screen[current].byte & DS.FieldAttribute.protected == 0,
               !screen[start].isFieldAttribute,
               start != screen.wrap(address) {
                return start
            }
        }
        return homePosition()
    }

    // MARK: - Status

    /// A short operator information area (OIA) status text.
    public var statusText: String {
        switch state {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting to \(settings.host):\(settings.port)…"
        case .negotiating: return "Negotiating…"
        case .failed(let message): return "Connection failed: \(message)"
        case .connected(let mode):
            var parts: [String] = []
            switch mode {
            case .tn3270e: parts.append("TN3270E")
            case .tn3270: parts.append("TN3270")
            case .nvt: parts.append("NVT")
            case .negotiating: parts.append("…")
            }
            if settings.useTLS { parts.append("TLS") }
            if let lu = negotiator.connectedLU, !lu.isEmpty { parts.append(lu) }
            if isSSCPMode { parts.append("SSCP") }
            if keyboardLocked { parts.append("X SYSTEM") }
            if insertMode { parts.append("INSERT") }
            return parts.joined(separator: "  ")
        }
    }
}
