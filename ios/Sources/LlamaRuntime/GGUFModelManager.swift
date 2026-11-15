import Foundation

public enum GGUFModelManagerError: Error, LocalizedError, Sendable {
    case invalidDownloadResponse
    case downloadFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidDownloadResponse:
            return "Сервер модели вернул некорректный ответ."
        case .downloadFailed(let status):
            return "Загрузка модели завершилась с HTTP-ошибкой \(status)."
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
        remoteURL: URL = URL(string: "https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf")!,
        session: URLSession = .shared
    ) {
        self.modelURL = modelURL
        self.remoteURL = remoteURL
        self.session = session
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

        let (temporaryURL, response) = try await session.download(from: remoteURL)
        guard let http = response as? HTTPURLResponse else {
            throw GGUFModelManagerError.invalidDownloadResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GGUFModelManagerError.downloadFailed(http.statusCode)
        }

        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: modelURL)
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else { return }
        try FileManager.default.removeItem(at: modelURL)
    }
}
