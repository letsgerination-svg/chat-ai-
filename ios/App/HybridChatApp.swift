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
    @Published var githubTokenInput = ""
    @Published var cloudflareTokenInput = ""
    @Published var githubConnectionStatus = "Не подключён"
    @Published var cloudflareConnectionStatus = "Не подключён"
    @Published var isCheckingGitHub = false
    @Published var isCheckingCloudflare = false
    @Published var githubRepositories: [GitHubRepository] = []
    @Published var cloudflareAccounts: [CloudflareAccount] = []
    @Published var cloudflareWorkers: [CloudflareWorker] = []
    @Published var selectedCloudflareAccountID = ""
    @Published var isLoadingGitHubRepositories = false
    @Published var isLoadingCloudflareResources = false

    private let githubIntegration = GitHubIntegration()
    private let cloudflareIntegration = CloudflareIntegration()
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

        var pendingAssistantID: UUID?
        do {
            let provider = try await router.provider(
                for: mode,
                networkAvailable: networkMonitor.isConnected
            )
            let assistantID = UUID()
            pendingAssistantID = assistantID
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
            if let pendingAssistantID {
                messages.removeAll { $0.id == pendingAssistantID && $0.content.isEmpty }
            }
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

    func saveGitHubToken() {
        do {
            try githubIntegration.saveToken(githubTokenInput)
            githubTokenInput = ""
            githubConnectionStatus = "Токен сохранён. Проверяю…"
            Task { await checkGitHubConnection() }
        } catch { githubConnectionStatus = "Ошибка: \(error.localizedDescription)" }
    }

    func checkGitHubConnection() async {
        guard !isCheckingGitHub else { return }
        isCheckingGitHub = true
        defer { isCheckingGitHub = false }
        do {
            let login = try await githubIntegration.validateConnection()
            githubConnectionStatus = "Подключён: @\(login)"
            await loadGitHubRepositories()
        } catch { githubConnectionStatus = "Ошибка: \(error.localizedDescription)" }
    }

    func loadGitHubRepositories() async {
        guard !isLoadingGitHubRepositories else { return }
        isLoadingGitHubRepositories = true
        defer { isLoadingGitHubRepositories = false }
        do {
            githubRepositories = try await githubIntegration.repositories()
        } catch {
            githubConnectionStatus = "Ошибка загрузки репозиториев: \(error.localizedDescription)"
        }
    }

    func disconnectGitHub() {
        do {
            try githubIntegration.disconnect()
            githubRepositories = []
            githubConnectionStatus = "Отключён"
        }
        catch { githubConnectionStatus = "Ошибка: \(error.localizedDescription)" }
    }

    func saveCloudflareToken() {
        do {
            try cloudflareIntegration.saveToken(cloudflareTokenInput)
            cloudflareTokenInput = ""
            cloudflareConnectionStatus = "Токен сохранён. Проверяю…"
            Task { await checkCloudflareConnection() }
        } catch { cloudflareConnectionStatus = "Ошибка: \(error.localizedDescription)" }
    }

    func checkCloudflareConnection() async {
        guard !isCheckingCloudflare else { return }
        isCheckingCloudflare = true
        defer { isCheckingCloudflare = false }
        do {
            try await cloudflareIntegration.validateConnection()
            cloudflareConnectionStatus = "Подключён"
            await loadCloudflareAccounts()
        } catch { cloudflareConnectionStatus = "Ошибка: \(error.localizedDescription)" }
    }

    func loadCloudflareAccounts() async {
        guard !isLoadingCloudflareResources else { return }
        isLoadingCloudflareResources = true
        defer { isLoadingCloudflareResources = false }
        do {
            cloudflareAccounts = try await cloudflareIntegration.accounts()
            if !cloudflareAccounts.contains(where: { $0.id == selectedCloudflareAccountID }) {
                selectedCloudflareAccountID = cloudflareAccounts.first?.id ?? ""
            }
            await loadCloudflareWorkers()
        } catch {
            cloudflareConnectionStatus = "Ошибка загрузки аккаунтов: \(error.localizedDescription)"
        }
    }

    func loadCloudflareWorkers() async {
        guard !selectedCloudflareAccountID.isEmpty else {
            cloudflareWorkers = []
            return
        }
        do {
            cloudflareWorkers = try await cloudflareIntegration.workers(accountID: selectedCloudflareAccountID)
        } catch {
            cloudflareConnectionStatus = "Ошибка загрузки Workers: \(error.localizedDescription)"
        }
    }

    func disconnectCloudflare() {
        do {
            try cloudflareIntegration.disconnect()
            cloudflareAccounts = []
            cloudflareWorkers = []
            selectedCloudflareAccountID = ""
            cloudflareConnectionStatus = "Отключён"
        }
        catch { cloudflareConnectionStatus = "Ошибка: \(error.localizedDescription)" }
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

                Section("GitHub") {
                    SecureField("Fine-grained access token", text: $model.githubTokenInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Сохранить токен в Keychain") { model.saveGitHubToken() }
                        .disabled(model.githubTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Проверить подключение и загрузить репозитории") { Task { await model.checkGitHubConnection() } }
                    if model.isCheckingGitHub || model.isLoadingGitHubRepositories { ProgressView() }
                    Text(model.githubConnectionStatus).font(.footnote)
                    if !model.githubRepositories.isEmpty {
                        Text("Репозитории (\(model.githubRepositories.count))").font(.subheadline.weight(.semibold))
                        ForEach(model.githubRepositories) { repository in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(repository.full_name)
                                Text(repository.privateRepo ? "Приватный" : "Публичный")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Отключить GitHub", role: .destructive) { model.disconnectGitHub() }
                    Text("Fine-grained token только для нужных репозиториев: Metadata read, Contents read/write, Pull requests read/write.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Cloudflare") {
                    SecureField("Cloudflare API token", text: $model.cloudflareTokenInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Сохранить токен в Keychain") { model.saveCloudflareToken() }
                        .disabled(model.cloudflareTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Проверить подключение и загрузить аккаунты") { Task { await model.checkCloudflareConnection() } }
                    if model.isCheckingCloudflare || model.isLoadingCloudflareResources { ProgressView() }
                    Text(model.cloudflareConnectionStatus).font(.footnote)
                    if !model.cloudflareAccounts.isEmpty {
                        Picker("Аккаунт", selection: $model.selectedCloudflareAccountID) {
                            ForEach(model.cloudflareAccounts) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                        .onChange(of: model.selectedCloudflareAccountID) { _ in
                            Task { await model.loadCloudflareWorkers() }
                        }
                        Text("Workers (\(model.cloudflareWorkers.count))").font(.subheadline.weight(.semibold))
                        ForEach(model.cloudflareWorkers) { worker in
                            Text(worker.id)
                        }
                    }
                    Button("Отключить Cloudflare", role: .destructive) { model.disconnectCloudflare() }
                    Text("Используйте API Token с минимальными правами на нужный аккаунт. Не используйте Global API Key.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Приватность") {
                    Label("История хранится локально на iPhone", systemImage: "lock.fill")
                    Label("Ключ хранится в iOS Keychain", systemImage: "key.fill")
                    Text("Сообщения передаются DeepSeek только при онлайн-генерации. Токены GitHub и Cloudflare хранятся в Keychain и отправляются только соответствующим API.")
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
