import Foundation
import SwiftData

/// Imports inbox JSON files into SwiftData. See docs/SPEC.md §5.2.
///
/// - Upserts by `id`, so importing the same file any number of times is safe.
/// - Never downgrades a `done`/`failed` entry back to `pending`.
/// - Never touches user state (`isRead`, `isFavorite`).
/// - Deletes files once they reach a terminal status; keeps `pending` files so the hook can
///   rewrite them.
@MainActor
final class InboxImporter {
    struct Summary: Equatable {
        var imported = 0
        var rejected = 0
        var timedOut = 0
    }

    static let pendingTimeout: TimeInterval = 10 * 60

    private let context: ModelContext
    private let inboxURL: URL
    private let now: () -> Date
    private let fileManager = FileManager.default

    init(context: ModelContext, inboxURL: URL, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.inboxURL = inboxURL
        self.now = now
    }

    var rejectedURL: URL { inboxURL.appending(path: "rejected", directoryHint: .isDirectory) }

    /// Files to delete once the store has been saved. Deleting earlier would lose the only copy of
    /// a translation if the save fails.
    private var filesToRemove: [URL] = []

    @discardableResult
    func scan() -> Summary {
        var summary = Summary()
        filesToRemove = []
        try? fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        let files = (try? fileManager.contentsOfDirectory(at: inboxURL, includingPropertiesForKeys: nil)) ?? []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.pathExtension == "json" && !url.lastPathComponent.hasPrefix(".") {
            do {
                try importFile(at: url)
                summary.imported += 1
            } catch {
                reject(url)
                summary.rejected += 1
            }
        }

        summary.timedOut = expireStalePending()
        do {
            try context.save()
            filesToRemove.forEach { try? fileManager.removeItem(at: $0) }
        } catch {
            // Keep the files; the next scan imports them again (upserts are idempotent).
            context.rollback()
        }
        filesToRemove = []
        return summary
    }

    private func importFile(at url: URL) throws {
        let payload = try InboxPayload.decode(Data(contentsOf: url))
        let id = payload.id
        let existing = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })).first

        if let existing {
            // A late `pending` write must not undo a finished translation.
            if !(existing.status.isTerminal && payload.status == .pending) {
                apply(payload, to: existing)
            }
        } else {
            let entry = Entry(
                id: payload.id,
                createdAt: payload.createdAt,
                updatedAt: payload.updatedAt ?? payload.createdAt,
                sourceText: payload.sourceText,
                status: payload.status
            )
            apply(payload, to: entry)
            context.insert(entry)
        }

        if payload.status.isTerminal {
            filesToRemove.append(url)
        }
    }

    private func apply(_ payload: InboxPayload, to entry: Entry) {
        entry.createdAt = payload.createdAt
        entry.updatedAt = payload.updatedAt ?? payload.createdAt
        entry.sourceText = payload.sourceText
        entry.status = payload.status
        entry.translation = payload.translation
        entry.errorMessage = payload.error
        entry.agent = payload.agent
        entry.sessionID = payload.sessionID
        entry.cwd = payload.cwd
    }

    /// Marks entries stuck in `pending` (e.g. the translator was killed) as failed.
    private func expireStalePending() -> Int {
        let pending = EntryStatus.pending.rawValue
        let cutoff = now().addingTimeInterval(-Self.pendingTimeout)
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.statusRaw == pending && $0.updatedAt < cutoff }
        )
        let stale = (try? context.fetch(descriptor)) ?? []
        for entry in stale {
            entry.status = .failed
            entry.errorMessage = String(localized: "Timed out")
            entry.updatedAt = now()
            filesToRemove.append(inboxURL.appending(path: "\(entry.id.uuidString).json"))
        }
        return stale.count
    }

    private func reject(_ url: URL) {
        try? fileManager.createDirectory(at: rejectedURL, withIntermediateDirectories: true)
        let destination = rejectedURL.appending(path: url.lastPathComponent)
        try? fileManager.removeItem(at: destination)
        try? fileManager.moveItem(at: url, to: destination)
    }
}
