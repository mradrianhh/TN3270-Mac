import AppKit
import Combine
import TN3270Core

/// Application state shared by the terminal, connection options and keyboard options windows.
final class AppModel: ObservableObject {
    private enum DefaultsKey {
        static let connectionSettings = "connectionSettings"
        static let keyMap = "keyMap"
        static let blockSelection = "blockSelection"
    }

    /// Persisted connection options. Changes take effect on the next connection.
    @Published var settings: ConnectionSettings {
        didSet {
            save(settings, forKey: DefaultsKey.connectionSettings)
            session.update(settings: settings)
        }
    }

    /// Persisted client keyboard to 3270 key mapping.
    @Published var keyMap: KeyMap {
        didSet { save(keyMap, forKey: DefaultsKey.keyMap) }
    }

    /// Persisted preference for rectangular terminal selection.
    @Published var blockSelection: Bool {
        didSet { defaults.set(blockSelection, forKey: DefaultsKey.blockSelection) }
    }

    /// Incremented whenever the screen or session status changes.
    @Published private(set) var revision = 0

    let session: TN3270Session
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.blockSelection = defaults.object(forKey: DefaultsKey.blockSelection) as? Bool ?? true
        let settings = Self.load(ConnectionSettings.self, forKey: DefaultsKey.connectionSettings, from: defaults)
            ?? ConnectionSettings()
        self.settings = settings
        self.keyMap = Self.load(KeyMap.self, forKey: DefaultsKey.keyMap, from: defaults) ?? .default
        self.session = TN3270Session(settings: settings)

        session.onUpdate = { [weak self] in self?.revision &+= 1 }
        session.onAlarm = { NSSound.beep() }
    }

    // MARK: - Connection

    var isConnected: Bool {
        switch session.state {
        case .connecting, .negotiating, .connected: return true
        case .disconnected, .failed: return false
        }
    }

    var statusText: String { session.statusText }

    var title: String {
        guard isConnected else { return "TN3270Mac" }
        return "TN3270Mac – \(settings.host):\(settings.port)"
    }

    func connect() {
        guard settings.isValid else { return }
        session.update(settings: settings)
        session.connect(using: NetworkTransport(settings: settings))
    }

    func disconnect() {
        session.disconnect()
    }

    // MARK: - Keyboard

    func perform(_ action: HostAction) {
        session.perform(action)
    }

    func type(_ text: String) {
        session.type(text)
    }

    /// Pastes text, mapping line breaks to the 3270 New Line function.
    func paste(_ text: String) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            if index > 0 { session.perform(.newline) }
            session.type(String(line))
        }
    }

    func moveCursor(row: Int, column: Int) {
        let screen = session.screen
        guard (0..<screen.rows).contains(row), (0..<screen.columns).contains(column) else { return }
        session.moveCursor(to: screen.address(row: row, column: column))
    }

    /// The visible screen as plain text.
    var screenText: String {
        let screen = session.screen
        return (0..<screen.rows).map { screen.text(row: $0, codePage: session.codePage) }.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
