import Foundation
import Network

struct NetworkState: Sendable, Equatable {
    enum Interface: String, Sendable { case wifi, wired, cellular, loopback, other, none }

    var online = true
    var status = "unknown"
    var interface = Interface.other
    var expensive = false
    var constrained = false

    init() {}

    init(_ path: NWPath) {
        online = path.status == .satisfied
        status = switch path.status {
        case .satisfied:           "satisfied"
        case .unsatisfied:         "unsatisfied"
        case .requiresConnection:  "requires_connection"
        @unknown default:          "unknown"
        }
        interface =
            path.status != .satisfied ? .none
            : path.usesInterfaceType(.wiredEthernet) ? .wired
            : path.usesInterfaceType(.wifi) ? .wifi
            : path.usesInterfaceType(.cellular) ? .cellular
            : path.usesInterfaceType(.loopback) ? .loopback
            : .other
        expensive = path.isExpensive
        constrained = path.isConstrained
    }
}

@MainActor
final class Reachability {
    private let monitor = NWPathMonitor()
    var onChange: ((NetworkState) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let state = NetworkState(path)
            Task { @MainActor in self?.onChange?(state) }
        }
        monitor.start(queue: DispatchQueue(label: "com.chagas42.diple.reachability"))
    }
}
