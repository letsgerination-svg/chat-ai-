import Foundation

private struct DeepSeekRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
}

private struct DeepSeekStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta?
    }

    let choices: [Choice]?
    let error: ProviderErrorBody?

    struct ProviderErrorBody: Decodable {
        let message: String?
    }
}

public enum DeepSeekProviderError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int, String?)
    case providerMessage(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Добавьте API-ключ DeepSeek в настройках."
        case .invalidResponse:
            return "DeepSeek вернул некорректный ответ."
        case .httpStatus(let code, let message):
            return message.map { "DeepSeek HTTP \(code): \($0)" }
                ?? "DeepSeek HTTP error: \(code)."
        case .providerMessage(let message):
            return message
        }
    }
}

/// DeepSeek Chat Completions adapter. Credentials are read from Keychain
/// for each request and are never persisted in the request history.
public final class DeepSeekChatProvider: ChatProvider, @unchecked Sendable {
    public let id: ChatProviderID = .remote

    private let keyStore: any APIKeyStore
    private let model: String
    private let endpoint: URL
    private let session: URLSession

    public init(
        keyStore: any APIKeyStore,
        model: String = "deepseek-chat",
        endpoint: URL = URL(string: "https://api.deepseek.com/chat/completions")!,
        session: URLSession = .shared
    ) {
        self.keyStore = keyStore
        self.model = model
        self.endpoint = endpoint
        self.session = session
    }

    public func isAvailable() async -> Bool {
        guard let key = try? keyStore.read() else { return false }
        return !(key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    public func streamReply(
        to messages: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let apiKey = try keyStore.read(),
                          !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw DeepSeekProviderError.missingAPIKey
                    }

                    let requestMessages = messages.map {
                        DeepSeekRequest.Message(role: $0.role.rawValue, content: $0.content)
                    }
                    let payload = DeepSeekRequest(
                        model: model,
                        messages: requestMessages,
                        stream: true
                    )

                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONEncoder().encode(payload)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw DeepSeekProviderError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 8_000 { break }
                        }
                        throw DeepSeekProviderError.httpStatus(http.statusCode, body.isEmpty ? nil : body)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let dataText = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if dataText == "[DONE]" { break }
                        guard let data = dataText.data(using: .utf8) else { continue }

                        let chunk = try JSONDecoder().decode(DeepSeekStreamChunk.self, from: data)
                        if let message = chunk.error?.message {
                            throw DeepSeekProviderError.providerMessage(message)
                        }
                        for choice in chunk.choices ?? [] {
                            if let text = choice.delta?.content, !text.isEmpty {
                                continuation.yield(text)
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
