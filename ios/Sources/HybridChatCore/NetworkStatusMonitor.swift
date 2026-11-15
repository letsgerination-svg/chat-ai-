import Foundation
import Network

/// Lightweight reachability signal used by ProviderRouter.
/// A reachable network does not guarantee that the DeepSeek API is reachable;
/// the provider request remains the final availability check.
public final class NetworkStatusMonitor: @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "HybridChat.NetworkStatus")
    private let lock = NSLock()
    private var connected = false

    public init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
    }

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connected
    }

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.connected = path.status == .satisfied
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
        lock.lock()
        connected = false
        lock.unlock()
    }
}
