import Foundation
import Testing
@testable import Machiai

@MainActor
struct PreferencesTests {
    let home = FileManager.default.temporaryDirectory.appending(path: "machiai-prefs-\(UUID().uuidString)")
    var paths: MachiaiPaths { MachiaiPaths(home: home) }

    func makePreferences() throws -> Preferences {
        let defaults = try #require(UserDefaults(suiteName: "machiai-prefs-\(UUID().uuidString)"))
        return Preferences(paths: paths, defaults: defaults)
    }

    @Test func captureToggleWritesAndRemovesFlag() throws {
        let preferences = try makePreferences()
        #expect(!preferences.isCaptureEnabled)
        preferences.isCaptureEnabled = true
        #expect(FileManager.default.fileExists(atPath: paths.enabledFlag.path))
        preferences.isCaptureEnabled = false
        #expect(!FileManager.default.fileExists(atPath: paths.enabledFlag.path))
    }

    @Test func configRoundTripsThroughShellQuoting() throws {
        let preferences = try makePreferences()
        preferences.model = "claude-sonnet-5"
        preferences.targetLanguage = "English (it's casual)"

        let text = try String(contentsOf: paths.configFile, encoding: .utf8)
        #expect(text.contains("MACHIAI_MODEL='claude-sonnet-5'"))
        #expect(text.contains(#"MACHIAI_TARGET_LANG='English (it'\''s casual)'"#))

        let reloaded = try makePreferences()
        #expect(reloaded.model == "claude-sonnet-5")
        #expect(reloaded.targetLanguage == "English (it's casual)")
    }

    @Test func translatesOnlyWhileOpenDefaultsOnAndRoundTrips() throws {
        let preferences = try makePreferences()
        #expect(preferences.translatesOnlyWhileOpen)
        preferences.translatesOnlyWhileOpen = false
        #expect(Preferences.parseConfig(try String(contentsOf: paths.configFile, encoding: .utf8))["MACHIAI_REQUIRE_APP"] == "0")
        #expect(try makePreferences().translatesOnlyWhileOpen == false)
        preferences.translatesOnlyWhileOpen = true
        #expect(Preferences.parseConfig(try String(contentsOf: paths.configFile, encoding: .utf8))["MACHIAI_REQUIRE_APP"] == "1")
    }

    @Test func configKeepsKeysItDoesNotManage() throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try "MACHIAI_TRANSLATE_CMD='ollama run llama3.2'\n".write(to: paths.configFile, atomically: true, encoding: .utf8)
        let preferences = try makePreferences()
        preferences.model = "haiku"
        let values = Preferences.parseConfig(try String(contentsOf: paths.configFile, encoding: .utf8))
        #expect(values["MACHIAI_TRANSLATE_CMD"] == "ollama run llama3.2")
        #expect(values["MACHIAI_MODEL"] == "haiku")
    }

    /// The shell must read back exactly what the app wrote.
    @Test func bashSourcesConfigVerbatim() throws {
        let preferences = try makePreferences()
        preferences.targetLanguage = #"Eng'lish "$HOME" `x`"#
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", ". \"$1\"; printf '%s' \"$MACHIAI_TARGET_LANG\"", "_", paths.configFile.path]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(output == #"Eng'lish "$HOME" `x`"#)
    }
}

struct HookInstallerDetectionTests {
    func settings(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func detectsMachiaiHook() throws {
        let url = try settings(#"""
        {"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"\"/x/Machiai/hooks/machiai-hook.sh\""}]}]}}
        """#)
        #expect(HookInstaller.settingsReferenceHook(at: url))
    }

    @Test func ignoresOtherHooksAndMissingFiles() throws {
        let url = try settings(#"{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"other.sh"}]}]}}"#)
        #expect(!HookInstaller.settingsReferenceHook(at: url))
        #expect(!HookInstaller.settingsReferenceHook(at: URL(fileURLWithPath: "/nonexistent/settings.json")))
        #expect(!HookInstaller.settingsReferenceHook(at: try settings("not json")))
    }

    @Test func followsSymlinks() throws {
        let target = try settings(#"{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"machiai-hook.sh"}]}]}}"#)
        let link = FileManager.default.temporaryDirectory.appending(path: "link-\(UUID().uuidString).json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(HookInstaller.settingsReferenceHook(at: link))
    }
}

@MainActor
struct HookSyncTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "machiai-sync-\(UUID().uuidString)")
    var bundle: URL { root.appending(path: "bundle") }
    var installed: URL { root.appending(path: "installed") }

    func installer() throws -> HookInstaller {
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try "new hook".write(to: bundle.appending(path: "machiai-hook.sh"), atomically: true, encoding: .utf8)
        try "new translate".write(to: bundle.appending(path: "translate.sh"), atomically: true, encoding: .utf8)
        return HookInstaller(settingsURL: root.appending(path: "settings.json"),
                             bundledScript: bundle.appending(path: "install.sh"))
    }

    @Test func refreshesStaleInstalledHooks() throws {
        let installer = try installer()
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try "old hook".write(to: installed.appending(path: "machiai-hook.sh"), atomically: true, encoding: .utf8)
        installer.syncInstalledHooks(into: installed)
        #expect(try String(contentsOf: installed.appending(path: "machiai-hook.sh"), encoding: .utf8) == "new hook")
        #expect(try String(contentsOf: installed.appending(path: "translate.sh"), encoding: .utf8) == "new translate")
        let mode = try FileManager.default.attributesOfItem(atPath: installed.appending(path: "machiai-hook.sh").path)[.posixPermissions] as? Int
        #expect(mode == 0o755)
    }

    @Test func doesNotInstallWhenNotInstalled() throws {
        let installer = try installer()
        installer.syncInstalledHooks(into: installed)
        #expect(!FileManager.default.fileExists(atPath: installed.path))
    }
}

struct PathsTests {
    @Test func honorsMachiaiHomeOverride() {
        let paths = MachiaiPaths(environment: ["MACHIAI_HOME": "/tmp/mh"])
        #expect(paths.inbox.path == "/tmp/mh/inbox")
        #expect(paths.enabledFlag.path == "/tmp/mh/enabled")
        #expect(paths.configFile.path == "/tmp/mh/config.env")
    }

    @Test func defaultsToApplicationSupport() {
        let paths = MachiaiPaths(environment: [:])
        #expect(paths.home.path.hasSuffix("Library/Application Support/Machiai"))
    }
}
