import Foundation
import SwiftData
import Testing
@testable import Machiai

@MainActor
struct InboxImporterTests {
    let container: ModelContainer
    let inbox: URL
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: Entry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        inbox = FileManager.default.temporaryDirectory
            .appending(path: "machiai-tests-\(UUID().uuidString)/inbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    }

    func importer(now: Date = .now) -> InboxImporter {
        InboxImporter(context: context, inboxURL: inbox, now: { now })
    }

    func write(_ payload: [String: Any], name: String? = nil) throws -> URL {
        let url = inbox.appending(path: name ?? "\(payload["id"] ?? UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: payload).write(to: url)
        return url
    }

    func allEntries() throws -> [Entry] {
        try context.fetch(FetchDescriptor<Entry>())
    }

    @Test func importsPendingAndKeepsFile() throws {
        let id = UUID()
        let url = try write(Fixture.payload(id: id, status: "pending"))

        let summary = importer().scan()

        #expect(summary == .init(imported: 1, rejected: 0, timedOut: 0))
        let entries = try allEntries()
        #expect(entries.count == 1)
        #expect(entries[0].id == id)
        #expect(entries[0].status == .pending)
        #expect(entries[0].sourceText == "ビルドが遅い原因を調べて")
        #expect(entries[0].projectName == "myapp")
        #expect(FileManager.default.fileExists(atPath: url.path), "pending files stay for the hook to rewrite")
    }

    @Test func importingTwiceIsIdempotent() throws {
        _ = try write(Fixture.payload(status: "pending"))
        let importer = importer()
        importer.scan()
        importer.scan()
        #expect(try allEntries().count == 1)
    }

    @Test func pendingThenDoneUpdatesTranslationAndDeletesFile() throws {
        let id = UUID()
        let url = try write(Fixture.payload(id: id, status: "pending"))
        let importer = importer()
        importer.scan()

        _ = try write(Fixture.payload(id: id, status: "done", translation: "Find out why the build is slow."))
        importer.scan()

        let entry = try #require(try allEntries().first)
        #expect(entry.status == .done)
        #expect(entry.translation == "Find out why the build is slow.")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func latePendingDoesNotDowngradeDone() throws {
        let id = UUID()
        _ = try write(Fixture.payload(id: id, status: "done", translation: "Done."))
        let importer = importer()
        importer.scan()

        _ = try write(Fixture.payload(id: id, status: "pending"))
        importer.scan()

        let entry = try #require(try allEntries().first)
        #expect(entry.status == .done)
        #expect(entry.translation == "Done.")
    }

    @Test func reimportPreservesUserState() throws {
        let id = UUID()
        _ = try write(Fixture.payload(id: id, status: "pending"))
        let importer = importer()
        importer.scan()
        let entry = try #require(try allEntries().first)
        entry.isRead = true
        entry.isFavorite = true

        _ = try write(Fixture.payload(id: id, status: "done", translation: "Hi."))
        importer.scan()

        #expect(entry.isRead)
        #expect(entry.isFavorite)
        #expect(entry.translation == "Hi.")
    }

    @Test func failedEntryKeepsErrorAndDeletesFile() throws {
        let url = try write(Fixture.payload(status: "failed", error: "claude CLI not found"))
        importer().scan()
        let entry = try #require(try allEntries().first)
        #expect(entry.status == .failed)
        #expect(entry.errorMessage == "claude CLI not found")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func ignoresDotfilesAndNonJSON() throws {
        _ = try write(Fixture.payload(status: "pending"), name: ".in-progress.tmp")
        _ = try write(Fixture.payload(status: "pending"), name: ".hidden.json")
        try Data("hello".utf8).write(to: inbox.appending(path: "notes.txt"))
        let summary = importer().scan()
        #expect(summary.imported == 0)
        #expect(summary.rejected == 0)
        #expect(try allEntries().isEmpty)
    }

    enum InvalidCase: String, CaseIterable, Sendable {
        case futureVersion, missingSourceText, blankSourceText, badStatus, badID

        var payload: [String: Any] {
            switch self {
            case .futureVersion: Fixture.payload(version: 2)
            case .missingSourceText: Fixture.payload(removing: "source_text")
            case .blankSourceText: Fixture.payload(source: "   ")
            case .badStatus: Fixture.payload(status: "translating")
            case .badID: Fixture.payload(rawID: "not-a-uuid")
            }
        }
    }

    @Test(arguments: InvalidCase.allCases)
    func rejectsInvalidFiles(_ invalid: InvalidCase) throws {
        let url = try write(invalid.payload, name: "bad.json")
        let summary = importer().scan()
        #expect(summary.rejected == 1, "\(invalid.rawValue)")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: inbox.appending(path: "rejected/bad.json").path))
        #expect(try allEntries().isEmpty)
    }

    @Test func acceptsUnknownFieldsAndFractionalDates() throws {
        var payload = Fixture.payload(status: "pending")
        payload["created_at"] = "2026-09-23T10:15:30.123Z"
        payload["something_new"] = ["nested": true]
        _ = try write(payload)
        #expect(importer().scan().imported == 1)
    }

    @Test func stalePendingTimesOut() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let url = try write(Fixture.payload(status: "pending", date: created))

        importer(now: created.addingTimeInterval(9 * 60)).scan()
        #expect(try allEntries().first?.status == .pending)

        let summary = importer(now: created.addingTimeInterval(11 * 60)).scan()
        #expect(summary.timedOut == 1)
        let entry = try #require(try allEntries().first)
        #expect(entry.status == .failed)
        #expect(entry.errorMessage != nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

enum Fixture {
    static func payload(
        id: UUID = UUID(),
        rawID: String? = nil,
        status: String = "pending",
        version: Int = 1,
        source: String = "ビルドが遅い原因を調べて",
        translation: String? = nil,
        error: String? = nil,
        date: Date = .now,
        removing key: String? = nil
    ) -> [String: Any] {
        let stamp = ISO8601DateFormatter().string(from: date)
        var payload: [String: Any] = [
            "version": version,
            "id": rawID ?? id.uuidString,
            "status": status,
            "agent": "claude-code",
            "created_at": stamp,
            "updated_at": stamp,
            "session_id": "s-1",
            "cwd": "/Users/me/work/myapp",
            "source_text": source,
            "target_lang": "English",
            "translation": translation.map { $0 as Any } ?? NSNull(),
            "error": error.map { $0 as Any } ?? NSNull(),
        ]
        if let key { payload.removeValue(forKey: key) }
        return payload
    }
}
