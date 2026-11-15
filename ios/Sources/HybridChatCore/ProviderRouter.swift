import Foundation

public struct ProviderRouter: Sendable {
    private let local: any ChatProvider
    private let remote: any ChatProvider

    public init(local: any ChatProvider, remote: any ChatProvider) {
        self.local = local
        self.remote = remote
    }

    /// Selects a provider without silently changing an explicit user choice.
    /// In automatic mode, network availability determines the preferred route.
    public func provider(
        for mode: ChatMode,
        networkAvailable: Bool
    ) async throws -> any ChatProvider {
        switch mode {
        case .offlineOnly:
            guard await local.isAvailable() else {
                throw ChatProviderError.unavailable(.local)
            }
            return local

        case .onlineOnly:
            guard networkAvailable else {
                throw ChatProviderError.networkUnavailable
            }
            guard await remote.isAvailable() else {
                throw ChatProviderError.unavailable(.remote)
            }
            return remote

        case .automatic:
            if networkAvailable, await remote.isAvailable() {
                return remote
            }
            guard await local.isAvailable() else {
                throw ChatProviderError.noProviderAvailable
            }
            return local
        }
    }
}
