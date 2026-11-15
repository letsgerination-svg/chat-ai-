import Foundation
import llama
import HybridChatCore

public enum LlamaRuntimeError: Error, LocalizedError, Sendable {
    case modelLoadFailed
    case contextCreationFailed
    case promptTooLong
    case promptEvaluationFailed
    case tokenEvaluationFailed

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed: return "Не удалось открыть GGUF-модель."
        case .contextCreationFailed: return "Не удалось создать контекст llama.cpp."
        case .promptTooLong: return "Запрос слишком длинный для текущего контекста модели."
        case .promptEvaluationFailed: return "Не удалось обработать запрос локальной моделью."
        case .tokenEvaluationFailed: return "Ошибка генерации токена локальной моделью."
        }
    }
}

/// Owns one llama.cpp model/context pair. All C API access is serialized by this actor.
public actor LlamaEngine {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocabulary: OpaquePointer
    private let sampler: OpaquePointer
    private var batch: llama_batch
    private let contextLength: Int32
    private var currentPosition: Int32 = 0
    private var pendingUTF8: [CChar] = []

    public init(modelPath: String, contextLength: Int32 = 2048) throws {
        self.contextLength = contextLength
        llama_backend_init()

        var modelParams = llama_model_default_params()
#if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
#else
        modelParams.n_gpu_layers = -1
#endif
        guard let loadedModel = modelPath.withCString({
            llama_model_load_from_file($0, modelParams)
        }) else {
            llama_backend_free()
            throw LlamaRuntimeError.modelLoadFailed
        }
        model = loadedModel

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextLength)
        contextParams.n_batch = UInt32(contextLength)
        contextParams.n_ubatch = min(512, UInt32(contextLength))
        let threadCount = Int32(max(1, min(6, ProcessInfo.processInfo.processorCount - 2)))
        contextParams.n_threads = threadCount
        contextParams.n_threads_batch = threadCount

        guard let createdContext = llama_init_from_model(loadedModel, contextParams) else {
            llama_model_free(loadedModel)
            llama_backend_free()
            throw LlamaRuntimeError.contextCreationFailed
        }
        context = createdContext
        vocabulary = llama_model_get_vocab(loadedModel)

        let samplerParams = llama_sampler_chain_default_params()
        let createdSampler = llama_sampler_chain_init(samplerParams)
        sampler = createdSampler
        llama_sampler_chain_add(createdSampler, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(createdSampler, llama_sampler_init_dist(UInt32.max))
        batch = llama_batch_init(contextLength, 0, 1)
    }

    deinit {
        llama_sampler_free(sampler)
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
        llama_backend_free()
    }

    public func generate(
        prompt: String,
        maxTokens: Int = 384
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try prepare(prompt: prompt)
                    for _ in 0..<maxTokens {
                        guard currentPosition < contextLength else { break }
                        try Task.checkCancellation()
                        guard let piece = try nextTokenPiece() else { break }
                        if !piece.isEmpty {
                            continuation.yield(piece)
                        }
                    }
                    let remainder = flushPendingUTF8()
                    if !remainder.isEmpty {
                        continuation.yield(remainder)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func prepare(prompt: String) throws {
        llama_memory_clear(llama_get_memory(context), true)
        pendingUTF8.removeAll(keepingCapacity: true)
        currentPosition = 0
        batch.n_tokens = 0

        let tokenCapacity = Int32(prompt.utf8.count + 8)
        let tokenBuffer = UnsafeMutablePointer<llama_token>.allocate(capacity: Int(tokenCapacity))
        defer { tokenBuffer.deallocate() }

        var tokenCount = prompt.withCString {
            llama_tokenize(
                vocabulary, $0, Int32(prompt.utf8.count),
                tokenBuffer, tokenCapacity, true, true
            )
        }

        if tokenCount < 0 {
            let required = -tokenCount
            let largerBuffer = UnsafeMutablePointer<llama_token>.allocate(capacity: Int(required))
            defer { largerBuffer.deallocate() }
            tokenCount = prompt.withCString {
                llama_tokenize(
                    vocabulary, $0, Int32(prompt.utf8.count),
                    largerBuffer, required, true, true
                )
            }
            guard tokenCount > 0 else { throw LlamaRuntimeError.promptEvaluationFailed }
            guard tokenCount < contextLength else { throw LlamaRuntimeError.promptTooLong }
            for index in 0..<Int(tokenCount) {
                addToken(largerBuffer[index], position: Int32(index), wantsLogits: index == Int(tokenCount) - 1)
            }
        } else {
            guard tokenCount > 0 else { throw LlamaRuntimeError.promptEvaluationFailed }
            guard tokenCount < contextLength else { throw LlamaRuntimeError.promptTooLong }
            for index in 0..<Int(tokenCount) {
                addToken(tokenBuffer[index], position: Int32(index), wantsLogits: index == Int(tokenCount) - 1)
            }
        }

        guard llama_decode(context, batch) == 0 else {
            throw LlamaRuntimeError.promptEvaluationFailed
        }
        currentPosition = tokenCount
    }

    private func nextTokenPiece() throws -> String? {
        let token = llama_sampler_sample(sampler, context, batch.n_tokens - 1)
        if llama_vocab_is_eog(vocabulary, token) {
            return nil
        }

        let piece = tokenPiece(token)
        batch.n_tokens = 0
        addToken(token, position: currentPosition, wantsLogits: true)
        currentPosition += 1

        guard llama_decode(context, batch) == 0 else {
            throw LlamaRuntimeError.tokenEvaluationFailed
        }
        return piece
    }

    private func addToken(
        _ token: llama_token,
        position: llama_pos,
        wantsLogits: Bool
    ) {
        let index = Int(batch.n_tokens)
        batch.token[index] = token
        batch.pos[index] = position
        batch.n_seq_id[index] = 1
        batch.seq_id[index]![0] = 0
        batch.logits[index] = wantsLogits ? 1 : 0
        batch.n_tokens += 1
    }

    private func tokenPiece(_ token: llama_token) -> String {
        let initialCapacity: Int32 = 128
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(initialCapacity))
        defer { buffer.deallocate() }

        let count = llama_token_to_piece(
            vocabulary, token, buffer, initialCapacity, 0, false
        )
        if count > 0 {
            pendingUTF8.append(contentsOf: UnsafeBufferPointer(start: buffer, count: Int(count)))
        } else if count < 0 {
            let required = -count
            let larger = UnsafeMutablePointer<CChar>.allocate(capacity: Int(required))
            defer { larger.deallocate() }
            let actual = llama_token_to_piece(vocabulary, token, larger, required, 0, false)
            if actual > 0 {
                pendingUTF8.append(contentsOf: UnsafeBufferPointer(start: larger, count: Int(actual)))
            }
        }

        guard let decoded = String(validatingUTF8: pendingUTF8 + [0]) else {
            return ""
        }
        pendingUTF8.removeAll(keepingCapacity: true)
        return decoded
    }

    private func flushPendingUTF8() -> String {
        let bytes = pendingUTF8.map { UInt8(bitPattern: $0) }
        pendingUTF8.removeAll()
        return String(decoding: bytes, as: UTF8.self)
    }
}

private actor LlamaEnginePool {
    private var loadedEngine: LlamaEngine?
    private var loadedPath: String?

    func getEngine(for modelPath: String) throws -> LlamaEngine {
        if let loadedEngine, loadedPath == modelPath {
            return loadedEngine
        }
        let newEngine = try LlamaEngine(modelPath: modelPath)
        loadedEngine = newEngine
        loadedPath = modelPath
        return newEngine
    }
}

/// Local provider for Qwen-style GGUF models. The prompt is never sent to a network service.
public final class LlamaLocalChatProvider: ChatProvider, @unchecked Sendable {
    public let id: ChatProviderID = .local

    private let modelURL: URL
    private let enginePool = LlamaEnginePool()
    private let maxTokens: Int

    public init(modelURL: URL, maxTokens: Int = 384) {
        self.modelURL = modelURL
        self.maxTokens = maxTokens
    }

    public func isAvailable() async -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    public func streamReply(
        to messages: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard await isAvailable() else {
                        throw ChatProviderError.unavailable(.local)
                    }
                    let engine = try await enginePool.getEngine(for: modelURL.path)
                    let prompt = Self.makePrompt(from: messages)
                    let output = await engine.generate(prompt: prompt, maxTokens: maxTokens)
                    for try await piece in output {
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func makePrompt(from messages: [ChatMessage]) -> String {
        var prompt = ""
        for message in messages {
            let role: String
            switch message.role {
            case .system: role = "system"
            case .user: role = "user"
            case .assistant: role = "assistant"
            }
            prompt += "<|im_start|>\(role)\n\(message.content)<|im_end|>\n"
        }
        prompt += "<|im_start|>assistant\n"
        return prompt
    }
}
