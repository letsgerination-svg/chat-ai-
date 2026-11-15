import SwiftUI
import HybridChatCore
import LlamaRuntime

@main
struct HybridChatApp: App {
    var body: some Scene {
        WindowGroup {
            ChatScreen()
        }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var mode: ChatMode = .automatic
    @Published var draft = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var apiKeyInput = ""
    @Published var settingsMessage: String?
    @Published var isLocalModelInstalled = false
    @Published var isDownloadingModel = false
    @Published var modelDownloadMessage: String?

    let networkMonitor = NetworkStatusMonitor()
    private let keyStore = KeychainAPIKeyStore()
    private let conversationStore: ConversationStore
    private let router: ProviderRouter
    private let localProvider: LlamaLocalChatProvider
    private let modelManager: GGUFModelManager
    private var conversation = ChatConversation()

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        conversationStore = ConversationStore(fileURL: documents.appendingPathComponent("chat-history.json"))
        let modelsDirectory = documents.appendingPathComponent("Models", isDirectory: true)
        let modelURL = modelsDirectory.appendingPathComponent("Qwen3-1.7B-Q4_K_M.gguf")
        localProvider = LlamaLocalChatProvider(modelURL: modelURL)
        modelManager = GGUFModelManager(modelURL: modelURL)
        let remote = DeepSeekChatProvider(keyStore: keyStore)
        router = ProviderRouter(local: localProvider, remote: remote)
        networkMonitor.start()

        Task { await loadHistory() }
    }

    func loadHistory() async {
        isLocalModelInstalled = await modelManager.isInstalled()
        do {
            let saved = try await conversationStore.load()
            if let latest = saved.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                conversation = latest
                messages = latest.messages
            }
        } catch {
            errorMessage = "Не удалось загрузить историю: \(error.localizedDescription)"
        }
    }

    func send() async {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else { return }

        draft = ""
        isSending = true
        let userMessage = ChatMessage(role: .user, content: prompt)
        messages.append(userMessage)
        await persist()

        do {
            let provider = try await router.provider(
                for: mode,
                networkAvailable: networkMonitor.isConnected
            )
            let assistantID = UUID()
            let createdAt = Date()
            messages.append(ChatMessage(id: assistantID, role: .assistant, content: "", createdAt: createdAt))

            var answer = ""
            for try await token in provider.streamReply(to: messages.filter { $0.id != assistantID }) {
                answer += token
                if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                    messages[index] = ChatMessage(
                        id: assistantID,
                        role: .assistant,
                        content: answer,
                        createdAt: createdAt
                    )
                }
            }
            await persist()
        } catch {
            errorMessage = error.localizedDescription
            await persist()
        }

        isSending = false
    }

    func saveAPIKey() {
        do {
            try keyStore.save(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
            apiKeyInput = ""
            settingsMessage = "Ключ сохранён в Keychain."
        } catch {
            settingsMessage = "Не удалось сохранить ключ: \(error.localizedDescription)"
        }
    }

    func removeAPIKey() {
        do {
            try keyStore.delete()
            settingsMessage = "Ключ удалён."
        } catch {
            settingsMessage = "Не удалось удалить ключ: \(error.localizedDescription)"
        }
    }

    func downloadModel() async {
        guard !isDownloadingModel else { return }
        isDownloadingModel = true
        modelDownloadMessage = "Загрузка модели…"
        defer { isDownloadingModel = false }
        do {
            try await modelManager.download()
            isLocalModelInstalled = await modelManager.isInstalled()
            modelDownloadMessage = "Модель установлена. Офлайн-режим готов к запуску."
        } catch {
            modelDownloadMessage = "Ошибка загрузки: \(error.localizedDescription)"
        }
    }

    func deleteModel() {
        Task {
            do {
                try await modelManager.delete()
                isLocalModelInstalled = await modelManager.isInstalled()
                modelDownloadMessage = "Файл модели удалён."
            } catch {
                modelDownloadMessage = "Не удалось удалить модель: \(error.localizedDescription)"
            }
        }
    }

    func startNewChat() {
        conversation = ChatConversation()
        messages = []
        Task { await persist() }
    }

    private func persist() async {
        conversation.messages = messages
        conversation.updatedAt = .now
        if conversation.title == "Новый чат",
           let firstUserMessage = messages.first(where: { $0.role == .user }) {
            conversation.title = String(firstUserMessage.content.prefix(40))
        }
        do {
            try await conversationStore.save([conversation])
        } catch {
            errorMessage = "Не удалось сохранить историю: \(error.localizedDescription)"
        }
    }
}

struct ChatScreen: View {
    @StateObject private var model = ChatViewModel()
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Режим", selection: $model.mode) {
                    ForEach(ChatMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if model.messages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 38))
                            .foregroundStyle(.secondary)
                        Text("Новый чат").font(.title3.weight(.semibold))
                        Text("Задайте вопрос. История хранится на устройстве.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(model.messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: model.messages.count) { _ in
                            guard let last = model.messages.last else { return }
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Сообщение…", text: $model.draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                    Button {
                        Task { await model.send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                    }
                    .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending)
                }
                .padding()
            }
            .navigationTitle("Hybrid Chat")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.startNewChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Новый чат")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Настройки")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsScreen(model: model)
            }
            .alert("Ошибка", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant { bubble }
            Spacer(minLength: 36)
            if message.role == .user { bubble }
        }
    }

    private var bubble: some View {
        Text(message.content.isEmpty && message.role == .assistant ? "…" : message.content)
            .textSelection(.enabled)
            .padding(12)
            .background(message.role == .user ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct SettingsScreen: View {
    @ObservedObject var model: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("DeepSeek API") {
                    SecureField("Вставьте API-ключ", text: $model.apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Сохранить ключ в Keychain") {
                        model.saveAPIKey()
                    }
                    Button("Удалить сохранённый ключ", role: .destructive) {
                        model.removeAPIKey()
                    }
                    if let message = model.settingsMessage {
                        Text(message).font(.footnote)
                    }
                }

                Section("Приватность") {
                    Label("История хранится локально на iPhone", systemImage: "lock.fill")
                    Label("Ключ хранится в iOS Keychain", systemImage: "key.fill")
                    Text("В онлайн-режиме сообщения отправляются DeepSeek для генерации ответа. Офлайн-движок ещё не подключён.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Состояние") {
                    LabeledContent("Сеть", value: model.networkMonitor.isConnected ? "Доступна" : "Нет соединения")
                    LabeledContent("Офлайн-модель", value: model.isLocalModelInstalled ? "Найдена" : "Не установлена")
                    Text("Qwen3 1.7B Q4_K_M · около 1,28 ГБ · Apache 2.0")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if model.isDownloadingModel {
                        ProgressView("Загрузка модели…")
                    } else if !model.isLocalModelInstalled {
                        Button("Скачать офлайн-модель") {
                            Task { await model.downloadModel() }
                        }
                    } else {
                        Button("Удалить офлайн-модель", role: .destructive) {
                            model.deleteModel()
                        }
                    }
                    if let message = model.modelDownloadMessage {
                        Text(message).font(.footnote)
                    }
                    Text("Модель скачивается только после нажатия. Для загрузки потребуется около 1,28 ГБ свободного места.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
