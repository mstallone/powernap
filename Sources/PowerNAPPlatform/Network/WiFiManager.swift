import Foundation
import CoreWLAN
import Logging

public final class WiFiManager {
    private let logger: Logger
    private let client: CWWiFiClient

    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "dev.powernap.network.wifi")
        self.client = CWWiFiClient.shared()
    }

    public var interface: CWInterface? { client.interface() }

    public func currentSSID() -> String? {
        interface?.ssid()
    }

    public func isPowered() -> Bool {
        interface?.powerOn() ?? false
    }

    public func setPowered(_ on: Bool) throws {
        guard let iface = interface else {
            throw WiFiError.noInterface
        }
        try iface.setPower(on)
        logger.info("Wi-Fi power set", metadata: ["state": "\(on)"])
    }

    public func scan(ssid: String? = nil) throws -> [CWNetwork] {
        guard let iface = interface else { throw WiFiError.noInterface }
        let results: Set<CWNetwork>
        if let ssid {
            results = try iface.scanForNetworks(withName: ssid)
        } else {
            results = try iface.scanForNetworks(withName: nil)
        }
        return Array(results)
    }

    public func associate(ssid: String, password: String?) throws {
        guard let iface = interface else { throw WiFiError.noInterface }
        try iface.setPower(true)
        let networks = try iface.scanForNetworks(withName: ssid)
        guard let target = networks.first(where: { $0.ssid == ssid }) ?? networks.first else {
            throw WiFiError.ssidNotFound(ssid)
        }
        try iface.associate(to: target, password: password)
        logger.info("associated with Wi-Fi", metadata: ["ssid": "\(ssid)"])
    }

    public func disassociate() {
        interface?.disassociate()
    }
}

public enum WiFiError: Swift.Error, LocalizedError {
    case noInterface
    case ssidNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .noInterface: return "No Wi-Fi interface available"
        case .ssidNotFound(let s): return "Wi-Fi SSID not found: \(s)"
        }
    }
}
