import AppKit
import SwiftData
import SwiftUI

@main
struct MachiaiApp: App {
    @State private var model: AppModel

    init() {
        let paths = MachiaiPaths()
        let container: ModelContainer
        do {
            container = try AppModel.makeContainer(paths: paths)
        } catch {
            fatalError("Could not open the Machiai store at \(paths.store.path): \(error)")
        }
        let model = AppModel(paths: paths, container: container)
        model.installer.syncInstalledHooks(into: paths.installedHooks)
        model.markRunning()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { model.clearRunning() }
        }
        _model = State(initialValue: model)
    }

    var body: some Scene {
        Window("Machiai", id: "main") {
            ContentView()
                .environment(model)
                .onAppear { model.startWatching() }
        }
        .modelContainer(model.container)
        .defaultSize(width: 1040, height: 680)
        .windowResizability(.contentMinSize)
        .commands { MachiaiCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct MachiaiCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Toggle("Capture Prompts", isOn: Binding(
                get: { model.preferences.isCaptureEnabled },
                set: { model.preferences.isCaptureEnabled = $0 }
            ))
        }

        CommandMenu("Entry") {
            let entry = model.selectedEntry
            Button("Mark as Read") { entry.map(model.markRead) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(entry == nil || entry?.isRead == true)
            Button("Mark as Unread") { entry.map(model.markUnread) }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(entry == nil || entry?.isRead == false)
            Divider()
            Button((entry?.isFavorite == true ? "Remove from Favorites" : "Add to Favorites") as LocalizedStringKey) {
                entry.map(model.toggleFavorite)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(entry == nil)
            Button("Copy Translation") { entry.map(model.copyTranslation) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(entry?.translation == nil)
            Divider()
            Button("Delete") { entry.map(model.delete) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(entry == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Bigger Text") { model.adjustFontSize(by: 2) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller Text") { model.adjustFontSize(by: -2) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Default Text Size") { model.resetFontSize() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
        }
    }
}
