import XCTest
@testable import HybridChatCore

final class ProviderRouterTests: XCTestCase {
    func testAutomaticModePrefersRemoteWhenNetworkAndRemoteAreAvailable() async throws {
        let router = makeRouter(localAvailable: true, remoteAvailable: true)

        let selected = try await router.provider(for: .automatic, networkAvailable: true)

        XCTAssertEqual(selected.id, .remote)
    }

    func testAutomaticModeFallsBackToLocalWhenNetworkIsUnavailable() async throws {
        let router = makeRouter(localAvailable: true, remoteAvailable: true)

        let selected = try await router.provider(for: .automatic, networkAvailable: false)

        XCTAssertEqual(selected.id, .local)
    }

    func testAutomaticModeFallsBackToLocalWhenRemoteIsUnavailable() async throws {
        let router = makeRouter(localAvailable: true, remoteAvailable: false)

        let selected = try await router.provider(for: .automatic, networkAvailable: true)

        XCTAssertEqual(selected.id, .local)
    }

    func testOfflineOnlyNeverSelectsRemote() async throws {
        let router = makeRouter(localAvailable: true, remoteAvailable: true)

        let selected = try await router.provider(for: .offlineOnly, networkAvailable: true)

        XCTAssertEqual(selected.id, .local)
    }

    func testOnlineOnlyFailsWhenNetworkIsUnavailable() async {
        let router = makeRouter(localAvailable: true, remoteAvailable: true)

        do {
            _ = try await router.provider(for: .onlineOnly, networkAvailable: false)
            XCTFail("Expected networkUnavailable")
        } catch let error as ChatProviderError {
            guard case .networkUnavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOfflineOnlyFailsWhenLocalProviderIsUnavailable() async {
        let router = makeRouter(localAvailable: false, remoteAvailable: true)

        do {
            _ = try await router.provider(for: .offlineOnly, networkAvailable: true)
            XCTFail("Expected local provider unavailable")
        } catch let error as ChatProviderError {
            guard case .unavailable(.local) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAutomaticModeFailsWhenNeitherProviderCanBeUsed() async {
        let router = makeRouter(localAvailable: false, remoteAvailable: false)

        do {
            _ = try await router.provider(for: .automatic, networkAvailable: false)
            XCTFail("Expected noProviderAvailable")
        } catch let error as ChatProviderError {
            guard case .noProviderAvailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeRouter(
        localAvailable: Bool,
        remoteAvailable: Bool
    ) -> ProviderRouter {
        ProviderRouter(
            local: StubChatProvider(id: .local, available: localAvailable),
            remote: StubChatProvider(id: .remote, available: remoteAvailable)
        )
    }
}

private struct StubChatProvider: ChatProvider {
    let id: ChatProviderID
    let available: Bool

    func isAvailable() async -> Bool {
        available
    }

    func streamReply(to messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
