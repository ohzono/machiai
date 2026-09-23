import Foundation
import SwiftData

enum EntryStatus: String, Codable, Sendable {
    case pending
    case done
    case failed

    var isTerminal: Bool { self != .pending }
}

/// One captured prompt and its translation. See docs/SPEC.md §5.1.
@Model
final class Entry {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var sourceText: String
    var translation: String?
    /// Stored as a raw string so it can be used in `#Predicate`.
    var statusRaw: String
    var errorMessage: String?
    var agent: String?
    var sessionID: String?
    var cwd: String?

    // User state. Owned by the app; never overwritten by imports.
    var isRead: Bool = false
    var readAt: Date?
    var isFavorite: Bool = false
    var favoritedAt: Date?

    init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        sourceText: String,
        status: EntryStatus,
        translation: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceText = sourceText
        self.statusRaw = status.rawValue
        self.translation = translation
    }

    var status: EntryStatus {
        get { EntryStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    /// Last path component of the working directory the prompt was typed in.
    var projectName: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}
