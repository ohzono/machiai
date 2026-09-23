import Foundation
import SwiftData
import Testing
@testable import Machiai

@MainActor
struct AppModelTests {
    let home: URL
    let model: AppModel
    let hideCount: Counter
    let badges: Recorder<Int>

    final class Counter { var value = 0 }
    final class Recorder<T> { var values: [T] = [] }

    init() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "machiai-model-\(UUID().uuidString)")
        let paths = MachiaiPaths(home: home)
        let container = try ModelContainer(
            for: Entry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let defaults = try #require(UserDefaults(suiteName: "machiai-tests-\(UUID().uuidString)"))
        let hideCount = Counter()
        let badges = Recorder<Int>()
        self.hideCount = hideCount
        self.badges = badges
        model = AppModel(
            paths: paths,
            container: container,
            preferences: Preferences(paths: paths, defaults: defaults),
            installer: HookInstaller(settingsURL: home.appending(path: "settings.json"), bundledScript: nil),
            hideApp: { hideCount.value += 1 },
            setBadge: { badges.values.append($0) }
        )
    }

    /// Inserts entries newest first: the first title is the newest.
    @discardableResult
    func insert(_ titles: [String]) -> [Entry] {
        let base = Date.now
        let entries = titles.enumerated().map { index, title in
            Entry(
                id: UUID(),
                createdAt: base.addingTimeInterval(-Double(index)),
                updatedAt: base,
                sourceText: title,
                status: .done,
                translation: title
            )
        }
        entries.forEach(model.container.mainContext.insert)
        try? model.container.mainContext.save()
        model.refreshUnreadCount()
        return entries
    }

    @Test func nextUnreadWrapsAround() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(AppModel.nextUnread(after: a, in: [(a, false), (b, false), (c, false)]) == b)
        #expect(AppModel.nextUnread(after: c, in: [(a, false), (b, true), (c, false)]) == a)
        #expect(AppModel.nextUnread(after: a, in: [(a, false), (b, true), (c, true)]) == nil)
        #expect(AppModel.nextUnread(after: UUID(), in: [(a, true), (b, false)]) == b)
    }

    @Test func markReadSelectsNextAndUpdatesBadge() {
        let entries = insert(["one", "two", "three"])
        #expect(model.unreadCount == 3)
        model.selectedEntryID = entries[0].id

        model.markRead(entries[0])

        #expect(entries[0].isRead)
        #expect(entries[0].readAt != nil)
        #expect(model.selectedEntryID == entries[1].id)
        #expect(model.unreadCount == 2)
        #expect(badges.values.last == 2)
        #expect(hideCount.value == 0)
    }

    @Test func readingTheLastUnreadHidesTheApp() {
        let entries = insert(["only"])
        model.markRead(entries[0])
        #expect(model.selectedEntryID == nil)
        #expect(model.unreadCount == 0)
        #expect(badges.values.last == 0)
        #expect(hideCount.value == 1)
    }

    @Test func hidingCanBeTurnedOff() {
        model.preferences.hidesWhenInboxEmpty = false
        let entries = insert(["only"])
        model.markRead(entries[0])
        #expect(hideCount.value == 0)
    }

    @Test func favoriteAndUnreadToggles() {
        let entry = insert(["one"])[0]
        model.toggleFavorite(entry)
        #expect(entry.isFavorite)
        #expect(entry.favoritedAt != nil)
        model.toggleFavorite(entry)
        #expect(!entry.isFavorite)
        #expect(entry.favoritedAt == nil)

        model.preferences.hidesWhenInboxEmpty = false
        model.markRead(entry)
        model.markUnread(entry)
        #expect(!entry.isRead)
        #expect(model.unreadCount == 1)
    }

    @Test func mailboxesFilterEntries() {
        let entries = insert(["one", "two", "three"])
        model.preferences.hidesWhenInboxEmpty = false
        model.markRead(entries[1])
        model.toggleFavorite(entries[2])
        #expect(model.entries(in: .unread).map(\.id) == [entries[0].id, entries[2].id])
        #expect(model.entries(in: .favorites).map(\.id) == [entries[2].id])
        #expect(model.entries(in: .all).count == 3)
    }

    @Test func deleteSelectsNeighbor() {
        let entries = insert(["one", "two", "three"])
        model.selectedEntryID = entries[1].id
        model.delete(entries[1])
        #expect(model.selectedEntryID == entries[2].id)
        #expect(model.entries(in: .all).count == 2)

        model.delete(entries[2])
        #expect(model.selectedEntryID == entries[0].id)
    }

    @Test func fontSizeIsClamped() {
        model.resetFontSize()
        #expect(model.preferences.readingFontSize == Preferences.defaultFontSize)
        for _ in 0..<50 { model.adjustFontSize(by: 2) }
        #expect(model.preferences.readingFontSize == Preferences.fontSizeRange.upperBound)
        for _ in 0..<50 { model.adjustFontSize(by: -2) }
        #expect(model.preferences.readingFontSize == Preferences.fontSizeRange.lowerBound)
    }
}
