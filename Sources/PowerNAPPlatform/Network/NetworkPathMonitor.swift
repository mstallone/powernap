import Foundation
import Network
import Logging

public struct NetworkPathSnapshot: Sendable {
    public enum Status: String, Sendable { case satisfied, unsatisfied, requiresConnection, unknown }
    public enum InterfaceType: String, Sendable { case wifi, cellular, wiredEthernet, loopback, other, none }

    public var status: Status
    public var primaryInterface: InterfaceType
    public var interfaceName: String?
    public var isExpensive: Bool
    public var isConstrained: Bool
    public var availableInterfaces: [String]
}

public final class NetworkPathMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.powernap.network.path", qos: .utility)
    private var listeners: [(NetworkPathSnapshot) -> Void] = []
    private let lock = NSLock()
    private var started = false
    private var latest: NetworkPathSnapshot = NetworkPathSnapshot(
        status: .unknown,
        primaryInterface: .none,
        interfaceName: nil,
        isExpensive: false,
        isConstrained: false,
        availableInterfaces: []
    )
    private let logger: Logger

    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "dev.powernap.network.path")
    }

    public func start() {
        lock.lock()
        if started { lock.unlock(); return }
        started = true
        lock.unlock()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let snap = Self.convert(path)
            self.lock.lock()
            self.latest = snap
            let cbs = self.listeners
            self.lock.unlock()
            self.logger.info("network path update", metadata: [
                "status": "\(snap.status.rawValue)",
                "primary": "\(snap.primaryInterface.rawValue)",
                "iface": "\(snap.interfaceName ?? "-")",
                "expensive": "\(snap.isExpensive)"
            ])
            for cb in cbs { cb(snap) }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }

    public func snapshot() -> NetworkPathSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    public func onUpdate(_ callback: @escaping (NetworkPathSnapshot) -> Void) {
        lock.lock()
        listeners.append(callback)
        lock.unlock()
    }

    private static func convert(_ path: NWPath) -> NetworkPathSnapshot {
        let status: NetworkPathSnapshot.Status
        switch path.status {
        case .satisfied: status = .satisfied
        case .unsatisfied: status = .unsatisfied
        case .requiresConnection: status = .requiresConnection
        @unknown default: status = .unknown
        }
        var primary: NetworkPathSnapshot.InterfaceType = .none
        var name: String?
        let types: [NWInterface.InterfaceType] = [.wifi, .cellular, .wiredEthernet, .loopback, .other]
        for t in types {
            if path.usesInterfaceType(t) {
                switch t {
                case .wifi: primary = .wifi
                case .cellular: primary = .cellular
                case .wiredEthernet: primary = .wiredEthernet
                case .loopback: primary = .loopback
                case .other: primary = .other
                @unknown default: primary = .other
                }
                if let iface = path.availableInterfaces.first(where: { $0.type == t }) {
                    name = iface.name
                }
                break
            }
        }
        return NetworkPathSnapshot(
            status: status,
            primaryInterface: primary,
            interfaceName: name,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            availableInterfaces: path.availableInterfaces.map { $0.name }
        )
    }
}
