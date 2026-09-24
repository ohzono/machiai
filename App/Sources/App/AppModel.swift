import AppKit
import Foundation
import Observation
import SwiftData

enum Mailbox: String, CaseIterable, Identifiable, Sendable {
    case unread
    case favorites
    case all

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .unread: "Unread"
        case .favorites: "Favorites"
        case .all: "All"
        }
    }

    var systemImage: String {
        switch self {
        case .unread: "tray"
        case .favorites: "star"
        case .all: "clock"
        }
    }

    func includes(_ entry: Entry) -> Bool {
        switch self {
        case .unread: !entry.isRead
        case .favorites: entry.isFavorite
        case .all: true
        }
    }
}

/// App-wide state and the actions behind the toolbar, menus and shortcuts.
@MainActor
@Observable
final class AppModel {
    let paths: MachiaiPaths
    let container: ModelContainer
    let preferences: Preferences
    let installer: HookInstaller

    var mailbox: Mailbox = .unread
    var selectedEntryID: UUID?
    private(set) var unreadCount = 0

    @ObservationIgnored private var importer: InboxImporter
    @ObservationIgnored private var watcher: InboxWatcher?
    @ObservationIgnored private let hideApp: @MainActor () -> Void
    @ObservationIgnored private let setBadge: @MainActor (Int) -> Void

    init(
        paths: MachiaiPaths = MachiaiPaths(),
        container: ModelContainer,
        preferences: Preferences? = nil,
        installer: HookInstaller? = nil,
        now: @escaping () -> Date = Date.init,
        hideApp: @escaping @MainActor () -> Void = { NSApp.hide(nil) },
        setBadge: @escaping @MainActor (Int) -> Void = { count in
            NSApp.dockTile.badgeLabel = count == 0 ? nil : String(count)
        }
    ) {
        self.paths = paths
        self.container = container
        self.preferences = preferences ?? Preferences(paths: paths)
        self.installer = installer ?? HookInstaller()
        self.hideApp = hideApp
        self.setBadge = setBadge
        importer = InboxImporter(context: container.mainContext, inboxURL: paths.inbox, now: now)
    }

    /// Creates the on-disk store under `MACHIAI_HOME`.
    static func makeContainer(paths: MachiaiPaths) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: paths.store)
        return try ModelContainer(for: Entry.self, configurations: configuration)
    }

    private var context: ModelContext { container.mainContext }

    // MARK: - Lifecycle

    /// Tells the hook that Machiai is open (see `translatesOnlyWhileOpen`).
    func markRunning(pid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        try? FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        try? "\(pid)\n".write(to: paths.appPID, atomically: true, encoding: .utf8)
    }

    func clearRunning() {
        try? FileManager.default.removeItem(at: paths.appPID)
    }

    // MARK: - Inbox

    func startWatching() {
        guard watcher == nil else { return }
        let watcher = InboxWatcher(inboxURL: paths.inbox) { [weak self] in self?.importInbox() }
        self.watcher = watcher
        watcher.start()
    }

    func importInbox() {
        importer.scan()
        refreshUnreadCount()
    }

    // MARK: - Queries

    func entries(in mailbox: Mailbox) -> [Entry] {
        let descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).filter(mailbox.includes)
    }

    var selectedEntry: Entry? {
        guard let id = selectedEntryID else { return nil }
        return try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })).first
    }

    func refreshUnreadCount() {
        let count = (try? context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { !$0.isRead }))) ?? 0
        unreadCount = count
        setBadge(count)
    }

    // MARK: - Actions

    /// Marks the entry read and moves the selection to the next unread entry in the current
    /// list. When nothing is left to read, optionally hides the app so the terminal is in front.
    func markRead(_ entry: Entry) {
        let list = entries(in: mailbox)
        let next = Self.nextUnread(after: entry.id, in: list.map { ($0.id, $0.isRead) })
        entry.isRead = true
        entry.readAt = .now
        save()
        selectedEntryID = next
        if unreadCount == 0, preferences.hidesWhenInboxEmpty {
            hideApp()
        }
    }

    func markUnread(_ entry: Entry) {
        entry.isRead = false
        entry.readAt = nil
        save()
    }

    func toggleFavorite(_ entry: Entry) {
        entry.isFavorite.toggle()
        entry.favoritedAt = entry.isFavorite ? .now : nil
        save()
    }

    func delete(_ entry: Entry) {
        let list = entries(in: mailbox)
        let ids = list.map(\.id)
        if let index = ids.firstIndex(of: entry.id) {
            let neighbors = ids.indices.filter { $0 != index }
            selectedEntryID = neighbors.first(where: { $0 > index }).map { ids[$0] }
                ?? neighbors.last.map { ids[$0] }
        }
        // A pending entry still has its inbox file, and its translation may land at any moment.
        importer.markDeleted(entry.id)
        context.delete(entry)
        save()
    }

    func copyTranslation(_ entry: Entry) {
        guard let translation = entry.translation else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translation, forType: .string)
    }

    func adjustFontSize(by delta: Double) {
        preferences.readingFontSize += delta
    }

    func resetFontSize() {
        preferences.readingFontSize = Preferences.defaultFontSize
    }

    private func save() {
        try? context.save()
        refreshUnreadCount()
    }

    /// The first unread entry after `id` in list order, wrapping around to earlier entries.
    static func nextUnread(after id: UUID, in list: [(id: UUID, isRead: Bool)]) -> UUID? {
        guard let index = list.firstIndex(where: { $0.id == id }) else {
            return list.first(where: { !$0.isRead && $0.id != id })?.id
        }
        let rotated = list[(index + 1)...] + list[..<index]
        return rotated.first(where: { !$0.isRead })?.id
    }
}
