import Foundation

/// File locations shared with the hook. See docs/SPEC.md §4.1.
struct MachiaiPaths: Sendable {
    let home: URL

    init(home: URL? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let home {
            self.home = home
        } else if let override = environment["MACHIAI_HOME"], !override.isEmpty {
            self.home = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.home = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/Machiai", directoryHint: .isDirectory)
        }
    }

    var inbox: URL { home.appending(path: "inbox", directoryHint: .isDirectory) }
    var enabledFlag: URL { home.appending(path: "enabled") }
    var configFile: URL { home.appending(path: "config.env") }
    var installedHooks: URL { home.appending(path: "hooks", directoryHint: .isDirectory) }
    /// The running app's pid. The hook translates only while this process is alive (by default).
    var appPID: URL { home.appending(path: "app.pid") }
    /// Where the app keeps its SwiftData store.
    var store: URL { home.appending(path: "Machiai.store") }
}
