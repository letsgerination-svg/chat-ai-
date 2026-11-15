import Foundation

public enum DeveloperIntegrationError: Error, LocalizedError, Sendable {
    case missingCredential(String)
    case invalidResponse
    case httpStatus(Int, String)
    case apiRejected(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredential(let provider): return "Сначала добавьте токен доступа для \(provider) в настройках."
        case .invalidResponse: return "Сервер вернул ответ в неизвестном формате."
        case .httpStatus(let code, let message): return "HTTP \(code): \(message)"
        case .apiRejected(let message): return message
        }
    }
}

public struct GitHubRepository: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let full_name: String
    public let privateRepo: Bool
    public let html_url: URL
    enum CodingKeys: String, CodingKey { case id, name, full_name, html_url; case privateRepo = "private" }
}

public struct GitHubPullRequest: Decodable, Sendable {
    public let number: Int
    public let html_url: URL
    public let title: String
    public let state: String
}

public struct GitHubContentItem: Decodable, Identifiable, Sendable {
    public let name: String
    public let path: String
    public let type: String
    public let sha: String
    public let size: Int?
    public var id: String { path }
}

private struct GitHubUser: Decodable { let login: String }
private struct GitHubFile: Decodable { let content: String?; let sha: String; let encoding: String }

public struct GitHubFileSnapshot: Sendable {
    public let content: String
    public let sha: String
    public init(content: String, sha: String) { self.content = content; self.sha = sha }
}
private struct GitHubWriteResult: Decodable { let content: GitHubFile? }
private struct GitHubWriteFile: Encodable { let message: String; let content: String; let sha: String?; let branch: String? }
private struct GitHubPullRequestBody: Encodable { let title: String; let head: String; let base: String; let body: String }

/// GitHub REST client. The fine-grained PAT is read from Keychain for each request.
public final class GitHubIntegration: Sendable {
    private let credentialStore: KeychainAPIKeyStore
    private let session: URLSession
    private let baseURL = URL(string: "https://api.github.com")!

    public init(credentialStore: KeychainAPIKeyStore = KeychainAPIKeyStore(account: "github-access-token"), session: URLSession = .shared) {
        self.credentialStore = credentialStore
        self.session = session
    }

    public func saveToken(_ token: String) throws { try credentialStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines)) }
    public func disconnect() throws { try credentialStore.delete() }

    public func validateConnection() async throws -> String {
        let user: GitHubUser = try await request(path: "/user")
        return user.login
    }

    public func repositories() async throws -> [GitHubRepository] {
        try await request(path: "/user/repos?sort=updated&per_page=100&affiliation=owner,collaborator,organization_member")
    }

    public func contents(owner: String, repository: String, path: String = "", branch: String? = nil) async throws -> [GitHubContentItem] {
        let encodedPath = path.isEmpty ? "" : "/" + path.split(separator: "/").map { Self.encodePathComponent(String($0)) }.joined(separator: "/")
        var endpoint = "/repos/\(Self.encodePathComponent(owner))/\(Self.encodePathComponent(repository))/contents\(encodedPath)"
        if let branch, var components = URLComponents(string: endpoint) {
            components.queryItems = [URLQueryItem(name: "ref", value: branch)]
            endpoint = components.string ?? endpoint
        }
        return try await request(path: endpoint)
    }

    public func readTextFile(owner: String, repository: String, path: String, branch: String? = nil) async throws -> String {
        try await readTextFileSnapshot(owner: owner, repository: repository, path: path, branch: branch).content
    }

    public func readTextFileSnapshot(owner: String, repository: String, path: String, branch: String? = nil) async throws -> GitHubFileSnapshot {
        let safePath = path.split(separator: "/").map { Self.encodePathComponent(String($0)) }.joined(separator: "/")
        var endpoint = "/repos/\\(Self.encodePathComponent(owner))/\\(Self.encodePathComponent(repository))/contents/\\(safePath)"
        if let branch, var components = URLComponents(string: endpoint) {
            components.queryItems = [URLQueryItem(name: "ref", value: branch)]
            endpoint = components.string ?? endpoint
        }
        let file: GitHubFile = try await request(path: endpoint)
        guard file.encoding == "base64", let encoded = file.content,
              let data = Data(base64Encoded: encoded.replacingOccurrences(of: "\\n", with: "")),
              let text = String(data: data, encoding: .utf8) else { throw DeveloperIntegrationError.invalidResponse }
        return GitHubFileSnapshot(content: text, sha: file.sha)
    }

    public func writeTextFile(owner: String, repository: String, path: String, content: String, message: String, existingSHA: String? = nil, branch: String? = nil) async throws {
        let safePath = path.split(separator: "/").map { Self.encodePathComponent(String($0)) }.joined(separator: "/")
        let payload = GitHubWriteFile(message: message, content: Data(content.utf8).base64EncodedString(), sha: existingSHA, branch: branch)
        let _: GitHubWriteResult = try await send(path: "/repos/\(Self.encodePathComponent(owner))/\(Self.encodePathComponent(repository))/contents/\(safePath)", method: "PUT", body: try JSONEncoder().encode(payload))
    }

    public func createPullRequest(owner: String, repository: String, title: String, head: String, base: String, body: String = "") async throws -> GitHubPullRequest {
        let payload = GitHubPullRequestBody(title: title, head: head, base: base, body: body)
        return try await send(path: "/repos/\(Self.encodePathComponent(owner))/\(Self.encodePathComponent(repository))/pulls", method: "POST", body: try JSONEncoder().encode(payload))
    }

    private static func encodePathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? value
    }

    private func request<Response: Decodable>(path: String) async throws -> Response {
        try await send(path: path, method: "GET", body: nil)
    }

    private func send<Response: Decodable>(path: String, method: String, body: Data?) async throws -> Response {
        guard let token = try credentialStore.read(), !token.isEmpty else { throw DeveloperIntegrationError.missingCredential("GitHub") }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw DeveloperIntegrationError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = body }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeveloperIntegrationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? "GitHub request failed"
            throw DeveloperIntegrationError.httpStatus(http.statusCode, message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

public struct CloudflareAccount: Decodable, Identifiable, Sendable { public let id: String; public let name: String }
public struct CloudflareWorker: Decodable, Identifiable, Sendable { public let id: String; public let etag: String?; public let handlers: [String]?; public let modified_on: String? }
private struct CloudflareMessage: Decodable { let code: Int?; let message: String }
private struct CloudflareEnvelope<Result: Decodable>: Decodable { let success: Bool; let errors: [CloudflareMessage]; let result: Result }
private struct CloudflareTokenStatus: Decodable { let id: String?; let status: String? }

/// Cloudflare REST client. Use a narrowly scoped API token; never embed a shared token in the app.
public final class CloudflareIntegration: Sendable {
    private let credentialStore: KeychainAPIKeyStore
    private let session: URLSession
    private let baseURL = URL(string: "https://api.cloudflare.com/client/v4")!

    public init(credentialStore: KeychainAPIKeyStore = KeychainAPIKeyStore(account: "cloudflare-api-token"), session: URLSession = .shared) {
        self.credentialStore = credentialStore
        self.session = session
    }

    public func saveToken(_ token: String) throws { try credentialStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines)) }
    public func disconnect() throws { try credentialStore.delete() }

    public func validateConnection() async throws {
        let _: CloudflareTokenStatus = try await request(path: "/user/tokens/verify")
    }

    public func accounts() async throws -> [CloudflareAccount] {
        let result: [CloudflareAccount] = try await request(path: "/accounts?per_page=50")
        return result
    }

    public func workers(accountID: String) async throws -> [CloudflareWorker] {
        let safeID = accountID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-"))) ?? accountID
        let result: [CloudflareWorker] = try await request(path: "/accounts/\(safeID)/workers/scripts")
        return result
    }

    private func request<Result: Decodable>(path: String) async throws -> Result {
        guard let token = try credentialStore.read(), !token.isEmpty else { throw DeveloperIntegrationError.missingCredential("Cloudflare") }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw DeveloperIntegrationError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeveloperIntegrationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let errors = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["errors"] as? [[String: Any]]
            let message = errors?.first?["message"] as? String ?? "Cloudflare request failed"
            throw DeveloperIntegrationError.httpStatus(http.statusCode, message)
        }
        let envelope = try JSONDecoder().decode(CloudflareEnvelope<Result>.self, from: data)
        guard envelope.success else { throw DeveloperIntegrationError.apiRejected(envelope.errors.map(\.message).joined(separator: "; ")) }
        return envelope.result
    }
}
