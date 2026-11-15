import Foundation

public enum GGUFModelManagerError: Error, LocalizedError, Sendable {
    case invalidDownloadResponse
    case downloadFailed(Int)
    case incompleteDownload(expected: Int64, actual: Int64)

    public var errorDescription: String? {
        switch self {
        case .invalidDownloadResponse:
            return "Сервер модели вернул некорректный ответ."
        case .downloadFailed(let status):
            return "Сервер модели ответил HTTP \(status). Попробуйте позже или проверьте доступ к Hugging Face."
        case .incompleteDownload(let expected, let actual):
            return "Модель скачалась не полностью (\(actual) из \(expected) байт). Проверьте соединение и повторите загрузку."
        }
    }
}

/// Downloads the user-selected GGUF file into the app's private Documents/Models directory.
public actor GGUFModelManager {
    public let modelURL: URL
    private let remoteURL: URL
    private let session: URLSession

    public init(
        modelURL: URL,
        remoteURL: URL = URL(string: "https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf?download=true")!,
        session: URLSession? = nil
    ) {
        self.modelURL = modelURL
        self.remoteURL = remoteURL

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 180
            configuration.timeoutIntervalForResource = 6 * 60 * 60
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    public func isInstalled() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    public func download() async throws {
        let directory = modelURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var lastError: Error?
        for attempt in 1...3 {
            do {
                var request = URLRequest(url: remoteURL)
                request.httpMethod = "GET"
                request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                request.setValue("HybridChat-iOS/1.0", forHTTPHeaderField: "User-Agent")
                request.cachePolicy = .reloadIgnoringLocalCacheData

                let (temporaryURL, response) = try await session.download(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw GGUFModelManagerError.invalidDownloadResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw GGUFModelManagerError.downloadFailed(http.statusCode)
                }

                let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
                let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                let expectedSize = http.expectedContentLength
                if expectedSize > 0 && actualSize != expectedSize {
                    throw GGUFModelManagerError.incompleteDownload(
                        expected: expectedSize,
                        actual: actualSize
                    )
                }
                guard actualSize >= 500_000_000 else {
                    throw GGUFModelManagerError.incompleteDownload(
                        expected: max(expectedSize, 500_000_000),
                        actual: actualSize
                    )
                }

                let stagedURL = directory.appendingPathComponent(modelURL.lastPathComponent + ".download")
                if FileManager.default.fileExists(atPath: stagedURL.path) {
                    try FileManager.default.removeItem(at: stagedURL)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: stagedURL)

                if FileManager.default.fileExists(atPath: modelURL.path) {
                    try FileManager.default.removeItem(at: modelURL)
                }
                try FileManager.default.moveItem(at: stagedURL, to: modelURL)
                return
            } catch {
                lastError = error
                guard attempt < 3, Self.isRetryable(error) else {
                    throw Self.presentableError(error)
                }
                try await Task.sleep(for: .seconds(attempt * 2))
            }
        }
        throw Self.presentableError(lastError ?? GGUFModelManagerError.invalidDownloadResponse)
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else { return }
        try FileManager.default.removeItem(at: modelURL)
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    private static func presentableError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else { return error }
        let detail: String
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed:
            detail = "Нет доступа к интернету. Подключитесь к Wi-Fi и повторите."
        case .timedOut:
            detail = "Истекло время ожидания сервера. Повторите загрузку при стабильном Wi-Fi."
        case .networkConnectionLost:
            detail = "Соединение прервалось во время загрузки. Повторите попытку."
        case .cannotFindHost, .dnsLookupFailed:
            detail = "Не удалось найти сервер Hugging Face. Проверьте DNS или VPN."
        case .cannotConnectToHost:
            detail = "Не удалось подключиться к серверу Hugging Face. Проверьте доступ к сайту."
        default:
            detail = "Сетевая ошибка (\(urlError.code.rawValue)): \(urlError.localizedDescription)"
        }
        return NSError(
            domain: "HybridChat.ModelDownload",
            code: urlError.code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: detail]
        )
    }
}
