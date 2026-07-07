import Combine
import Foundation
import Network

/// Watches the network path and bumps `reconnects` whenever connectivity is REGAINED
/// (an offline→online transition), so the app can re-fetch live data instead of sitting
/// on a stale local cache. Pairs with the server-first Firestore reads: server-first
/// prefers live data on each fetch; this triggers a fetch the moment the network returns.
@MainActor
final class ConnectivityMonitor: ObservableObject {
    /// Increments on each offline→online transition. Observe with `.onChange` to refresh.
    @Published private(set) var reconnects = 0
    /// Current reachability (satisfied == online). Starts optimistic so we don't fire a
    /// spurious "reconnect" on first launch.
    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if satisfied && !self.isOnline { self.reconnects += 1 }   // offline -> online
                self.isOnline = satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.nbatrademachine.connectivity"))
    }

    func stop() { monitor.cancel() }
    deinit { monitor.cancel() }
}
