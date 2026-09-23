import Foundation
import Observation

/// User settings. Capture state and translator options live in files the hook reads
/// (`enabled`, `config.env`); reading preferences live in UserDefaults.
@MainActor
@Observable
final class Preferences {
    static let defaultModel = "sonnet"
    static let defaultTargetLanguage = "English"
    static let defaultFontSize: Double = 24
    static let fontSizeRange: ClosedRange<Double> = 16...40

    private let paths: MachiaiPaths
    private let defaults: UserDefaults
    private let fileManager = FileManager.default

    var isCaptureEnabled: Bool {
        didSet { writeEnabledFlag() }
    }

    var model: String {
        didSet { writeConfig() }
    }

    var targetLanguage: String {
        didSet { writeConfig() }
    }

    var readingFontSize: Double {
        didSet {
            let clamped = min(max(readingFontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
            if clamped != readingFontSize { readingFontSize = clamped }
            defaults.set(readingFontSize, forKey: Keys.readingFontSize)
        }
    }

    var hidesWhenInboxEmpty: Bool {
        didSet { defaults.set(hidesWhenInboxEmpty, forKey: Keys.hidesWhenInboxEmpty) }
    }

    private enum Keys {
        static let readingFontSize = "readingFontSize"
        static let hidesWhenInboxEmpty = "hidesWhenInboxEmpty"
    }

    init(paths: MachiaiPaths, defaults: UserDefaults = .standard) {
        self.paths = paths
        self.defaults = defaults

        isCaptureEnabled = FileManager.default.fileExists(atPath: paths.enabledFlag.path)

        let config = (try? String(contentsOf: paths.configFile, encoding: .utf8)) ?? ""
        let values = Self.parseConfig(config)
        model = values["MACHIAI_MODEL"] ?? Self.defaultModel
        targetLanguage = values["MACHIAI_TARGET_LANG"] ?? Self.defaultTargetLanguage

        let storedSize = defaults.double(forKey: Keys.readingFontSize)
        readingFontSize = storedSize == 0 ? Self.defaultFontSize : storedSize
        hidesWhenInboxEmpty = defaults.object(forKey: Keys.hidesWhenInboxEmpty) as? Bool ?? true
    }

    /// Re-reads the `enabled` flag (the installer may have created it).
    func reloadCaptureState() {
        let exists = fileManager.fileExists(atPath: paths.enabledFlag.path)
        if exists != isCaptureEnabled { isCaptureEnabled = exists }
    }

    // MARK: - Files shared with the hook

    private func writeEnabledFlag() {
        try? fileManager.createDirectory(at: paths.home, withIntermediateDirectories: true)
        if isCaptureEnabled {
            if !fileManager.fileExists(atPath: paths.enabledFlag.path) {
                fileManager.createFile(atPath: paths.enabledFlag.path, contents: Data())
            }
        } else {
            try? fileManager.removeItem(at: paths.enabledFlag)
        }
    }

    private func writeConfig() {
        try? fileManager.createDirectory(at: paths.home, withIntermediateDirectories: true)
        var values = Self.parseConfig((try? String(contentsOf: paths.configFile, encoding: .utf8)) ?? "")
        values["MACHIAI_MODEL"] = model.trimmingCharacters(in: .whitespaces)
        values["MACHIAI_TARGET_LANG"] = targetLanguage.trimmingCharacters(in: .whitespaces)
        let text = values.keys.sorted()
            .map { "\($0)=\(Self.shellQuote(values[$0] ?? ""))" }
            .joined(separator: "\n") + "\n"
        try? text.write(to: paths.configFile, atomically: true, encoding: .utf8)
    }

    /// Parses `KEY=value` lines, accepting single-quoted values written by `shellQuote`.
    static func parseConfig(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq])
            var value = String(trimmed[trimmed.index(after: eq)...])
            if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
            }
            result[key] = value
        }
        return result
    }

    /// Quotes a value so `. config.env` in bash yields it verbatim.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
