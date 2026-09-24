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
