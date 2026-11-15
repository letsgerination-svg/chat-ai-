import Foundation

public struct ChatConversation: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var messages: [ChatMessage]
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "Новый чат",
        messages: [ChatMessage] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.updatedAt = updatedAt
    }
}

/// Stores conversation history only in the app's local sandbox.
public actor ConversationStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() throws -> [ChatConversation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([ChatConversation].self, from: data)
    }

    public func save(_ conversations: [ChatConversation]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(conversations)
        try data.write(to: fileURL, options: .atomic)
    }

    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }
}
