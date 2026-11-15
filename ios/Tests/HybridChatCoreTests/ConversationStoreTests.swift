import XCTest
@testable import HybridChatCore

final class ConversationStoreTests: XCTestCase {
    func testMissingFileLoadsAsEmptyHistory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ConversationStore(fileURL: directory.appendingPathComponent("history.json"))

        let conversations = try await store.load()

        XCTAssertTrue(conversations.isEmpty)
    }

    func testSaveAndLoadRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("history.json")
        let store = ConversationStore(fileURL: fileURL)
        let message = ChatMessage(role: .user, content: "Проверка офлайн-истории")
        let conversation = ChatConversation(
            title: "Тест",
            messages: [message]
        )

        try await store.save([conversation])
        let loaded = try await store.load()

        XCTAssertEqual(loaded, [conversation])
        try await store.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
