import Foundation

public enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

public struct ChatMessage: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let role: ChatRole
    public let content: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public enum ChatProviderID: String, Sendable {
    case local
    case remote
}

public enum ChatMode: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case automatic
    case offlineOnly
    case onlineOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return "Автоматически"
        case .offlineOnly: return "Только офлайн"
        case .onlineOnly: return "Только онлайн"
        }
    }
}

public enum ChatProviderError: Error, LocalizedError {
    case unavailable(ChatProviderID)
    case noProviderAvailable
    case networkUnavailable

    public var errorDescription: String? {
        switch self {
        case .unavailable(let provider):
            return "The \(provider.rawValue) provider is unavailable."
        case .noProviderAvailable:
            return "No chat provider is currently available."
        case .networkUnavailable:
            return "The network is unavailable."
        }
    }
}

/// All inference engines implement the same streaming interface.
/// The local implementation must never transmit prompts or history over the network.
public protocol ChatProvider: Sendable {
    var id: ChatProviderID { get }
    func isAvailable() async -> Bool
    func streamReply(
        to messages: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error>
}
