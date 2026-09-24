import Foundation
import Observation

/// Detects and installs the Claude Code hook by running the bundled `hooks/install.sh`.
@MainActor
@Observable
final class HookInstaller {
    private(set) var isInstalled = false
    private(set) var isRunning = false
    private(set) var lastOutput = ""

    private let settingsURL: URL
    private let bundledScript: URL?

    init(
        settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json"),
        bundledScript: URL? = Bundle.main.resourceURL?.appending(path: "hooks/install.sh")
    ) {
        self.settingsURL = settingsURL
        self.bundledScript = bundledScript
        refresh()
    }

    /// A command users can paste into a terminal instead of pressing the button.
    var installCommand: String {
        let path = bundledScript?.path ?? "/Applications/Machiai.app/Contents/Resources/hooks/install.sh"
        return "\"\(path)\""
    }

    func refresh() {
        isInstalled = Self.settingsReferenceHook(at: settingsURL)
    }

    /// True if any `UserPromptSubmit` command hook in the settings file points at machiai-hook.sh.
    /// `Data(contentsOf:)` follows symlinks, so dotfiles-managed settings work.
    nonisolated static func settingsReferenceHook(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any],
              let groups = hooks["UserPromptSubmit"] as? [[String: Any]]
        else { return false }
        return groups
            .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .contains { (($0["command"] as? String) ?? "").contains("machiai-hook.sh") }
    }

    /// After an app update, the copies installed under `MACHIAI_HOME/hooks` are stale. Refresh them
    /// from the bundle, but only when the hook is installed (never install behind the user's back).
    func syncInstalledHooks(into directory: URL) {
        guard let bundledDir = bundledScript?.deletingLastPathComponent() else { return }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.appending(path: "machiai-hook.sh").path) else { return }
        for name in ["machiai-hook.sh", "translate.sh"] {
            let source = bundledDir.appending(path: name)
            let destination = directory.appending(path: name)
            guard let fresh = try? Data(contentsOf: source),
                  (try? Data(contentsOf: destination)) != fresh
            else { continue }
            let temporary = directory.appending(path: ".\(name).tmp")
            do {
                try fresh.write(to: temporary)
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
                // replaceItemAt keeps the old file's attributes; the hook must be executable.
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            } catch {
                try? fileManager.removeItem(at: temporary)
            }
        }
    }

    func install() async {
        await run(arguments: [])
    }

    func uninstall() async {
        await run(arguments: ["--uninstall"])
    }

    private func run(arguments: [String]) async {
        guard let script = bundledScript, FileManager.default.fileExists(atPath: script.path) else {
            lastOutput = String(localized: "The installer is missing from the app bundle.")
            return
        }
        isRunning = true
        defer { isRunning = false }

        let result = await Task.detached { () -> (Int32, String) in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path] + arguments
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return (-1, error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value

        lastOutput = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
        refresh()
    }
}
