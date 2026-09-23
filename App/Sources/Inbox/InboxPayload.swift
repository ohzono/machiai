import Foundation

/// The hook ↔ app file contract, schema version 1. See docs/SPEC.md §4.2.
struct InboxPayload: Decodable, Sendable, Equatable {
    static let supportedVersion = 1

    let version: Int
    let id: UUID
    let status: EntryStatus
    let createdAt: Date
    let updatedAt: Date?
    let sourceText: String
    let agent: String?
    let sessionID: String?
    let cwd: String?
    let targetLang: String?
    let translation: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case version, id, status, agent, cwd, translation, error
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sourceText = "source_text"
        case sessionID = "session_id"
        case targetLang = "target_lang"
    }

    enum DecodeError: Error, Equatable {
        case unsupportedVersion(Int)
        case emptySourceText
    }

    /// Decodes and validates one inbox file. Unknown fields are ignored.
    static func decode(_ data: Data) throws -> InboxPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(string) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO 8601 date: \(string)")
            )
        }
        let payload = try decoder.decode(InboxPayload.self, from: data)
        guard payload.version == supportedVersion else {
            throw DecodeError.unsupportedVersion(payload.version)
        }
        guard !payload.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodeError.emptySourceText
        }
        return payload
    }

    /// Accepts ISO 8601 with or without fractional seconds.
    private static func parseDate(_ string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }
}
