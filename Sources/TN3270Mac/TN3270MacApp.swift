import AppKit
import SwiftUI
import TN3270Core

@main
struct TN3270MacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("TN3270Mac", id: WindowID.terminal) {
            TerminalWindow()
                .environmentObject(model)
        }
        .commands {
            TerminalCommands(model: model)
        }

        Window("Connection Options", id: WindowID.connectionOptions) {
            ConnectionOptionsView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)

        Window("Keyboard Options", id: WindowID.keyboardOptions) {
            KeyboardOptionsView()
                .environmentObject(model)
        }
    }
}

enum WindowID {
    static let terminal = "terminal"
    static let connectionOptions = "connection-options"
    static let keyboardOptions = "keyboard-options"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched from `swift run` (no app bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// The main terminal window: 3270 screen plus an operator information area.
struct TerminalWindow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            TerminalScreenView(model: model)
                .frame(minWidth: 720, minHeight: 420)
            Divider()
            HStack {
                Text(model.statusText)
                    .lineLimit(1)
                Spacer()
                if model.blockSelection {
                    Text("BLOCK")
                }
                Text(model.settings.codePage.id)
                let screen = model.session.screen
                Text(String(format: "%03d/%03d", screen.row(of: screen.cursor) + 1, screen.column(of: screen.cursor) + 1))
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black)
            .foregroundColor(Color(red: 0.45, green: 0.6, blue: 1.0))
        }
        .background(Color.black)
        .navigationTitle(model.title)
        .toolbar {
            ToolbarItemGroup {
                if model.isConnected {
                    Button { model.disconnect() } label: {
                        Label("Disconnect", systemImage: "bolt.slash")
                    }
                } else {
                    Button {
                        if model.settings.isValid { model.connect() } else { openWindow(id: WindowID.connectionOptions) }
                    } label: {
                        Label("Connect", systemImage: "bolt")
                    }
                }
                Button { openWindow(id: WindowID.connectionOptions) } label: {
                    Label("Connection Options", systemImage: "network")
                }
                Button { openWindow(id: WindowID.keyboardOptions) } label: {
                    Label("Keyboard Options", systemImage: "keyboard")
                }
            }
        }
        .onAppear {
            if !model.settings.isValid { openWindow(id: WindowID.connectionOptions) }
        }
    }
}

/// Menu bar commands.
struct TerminalCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Toggle("Block Selection", isOn: $model.blockSelection)
                .keyboardShortcut("b", modifiers: [.command, .option])
        }
        CommandMenu("Connection") {
            ConnectMenuButton(model: model)
                .keyboardShortcut("k", modifiers: .command)
            Button("Disconnect") { model.disconnect() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!model.isConnected)
            Divider()
            OpenWindowMenuButton(title: "Connection Options…", windowID: WindowID.connectionOptions)
                .keyboardShortcut(",", modifiers: [.command, .shift])
        }
        CommandMenu("Keyboard") {
            OpenWindowMenuButton(title: "Keyboard Options…", windowID: WindowID.keyboardOptions)
                .keyboardShortcut("k", modifiers: [.command, .option])
            Divider()
            Button("Reset") { model.perform(.reset) }
            Button("Attention (ATTN)") { model.perform(.attn) }
            Button("System Request") { model.perform(.sysreq) }
            Button("Clear") { model.perform(.clear) }
            Divider()
            Button("PA1") { model.perform(.pa1) }
            Button("PA2") { model.perform(.pa2) }
            Button("PA3") { model.perform(.pa3) }
        }
    }
}

private struct ConnectMenuButton: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Connect") {
            if model.settings.isValid {
                model.connect()
            } else {
                openWindow(id: WindowID.connectionOptions)
            }
        }
        .disabled(model.isConnected)
    }
}

private struct OpenWindowMenuButton: View {
    let title: String
    let windowID: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) { openWindow(id: windowID) }
    }
}
