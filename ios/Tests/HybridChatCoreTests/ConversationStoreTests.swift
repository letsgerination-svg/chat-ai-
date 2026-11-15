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

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, conversation.id)
        XCTAssertEqual(loaded[0].title, conversation.title)
        XCTAssertEqual(loaded[0].messages.count, 1)
        XCTAssertEqual(loaded[0].messages[0].id, message.id)
        XCTAssertEqual(loaded[0].messages[0].role, message.role)
        XCTAssertEqual(loaded[0].messages[0].content, message.content)
        XCTAssertLessThan(abs(loaded[0].messages[0].createdAt.timeIntervalSince(message.createdAt)), 1)
        XCTAssertLessThan(abs(loaded[0].updatedAt.timeIntervalSince(conversation.updatedAt)), 1)

        try await store.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
