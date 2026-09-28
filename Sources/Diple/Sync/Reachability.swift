import Foundation
import Network

@MainActor
final class Reachability {
    private let monitor = NWPathMonitor()
    var onChange: ((Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.onChange?(online) }
        }
        monitor.start(queue: DispatchQueue(label: "com.chagas42.diple.reachability"))
    }
}
