import Foundation
import Logging
import PowerNAPCore

public struct NetworkService: Sendable, Equatable, Codable {
    public var name: String
    public var enabled: Bool
    public var hardwarePort: String?
    public var device: String?
}

public final class NetworkServiceOrder {
    private let logger: Logger
    public static let networksetupPath = "/usr/sbin/networksetup"

    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "dev.powernap.network.order")
    }

    public func listServices() throws -> [NetworkService] {
        let output = try run(args: ["-listallnetworkservices"])
        let lines = output.split(separator: "\n").map { String($0) }
        var services: [NetworkService] = []
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            var enabled = true
            var name = line
            if line.hasPrefix("*") {
                enabled = false
                name = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            services.append(NetworkService(name: name, enabled: enabled, hardwarePort: nil, device: nil))
        }
        if let hw = try? run(args: ["-listallhardwareports"]) {
            let blocks = hw.components(separatedBy: "\n\n")
            for block in blocks {
                var port: String?
                var device: String?
                for line in block.split(separator: "\n") {
                    if line.hasPrefix("Hardware Port: ") {
                        port = String(line.dropFirst("Hardware Port: ".count))
                    } else if line.hasPrefix("Device: ") {
                        device = String(line.dropFirst("Device: ".count))
                    }
                }
                if let port, let device {
                    if let idx = services.firstIndex(where: { $0.name == port }) {
                        services[idx].hardwarePort = port
                        services[idx].device = device
                    }
                }
            }
        }
        return services
    }

    public func currentOrder() throws -> [String] {
        let output = try run(args: ["-listnetworkserviceorder"])
        let order = parseServiceOrder(output)
        if !order.isEmpty { return order }
        return try listServices().map { $0.name }
    }

    public func snapshot(to store: StateStore) throws {
        let order = try currentOrder()
        try store.saveNetworkSnapshot(serviceOrder: order)
        logger.info("network snapshot saved", metadata: ["services": "\(order.count)"])
    }

    @discardableResult
    public func setOrder(_ order: [String]) throws -> String {
        var args: [String] = ["-ordernetworkservices"]
        args.append(contentsOf: order)
        let out = try run(args: args)
        logger.info("service order set", metadata: ["order": "\(order.joined(separator: ","))"])
        return out
    }

    public func setEnabled(_ service: String, enabled: Bool) throws {
        _ = try run(args: ["-setnetworkserviceenabled", service, enabled ? "on" : "off"])
    }

    public func restoreFromSnapshot(_ order: [String]) throws {
        let current = Set(try currentOrder())
        let filtered = order.filter { current.contains($0) }
        let missing = current.subtracting(filtered)
        let finalOrder = filtered + missing.sorted()
        try setOrder(finalOrder)
    }

    public func preferUSBTether() throws -> String? {
        let services = try listServices()
        let usbName = findUSBTether(services)
        guard let usb = usbName else { return nil }
        var order = try currentOrder()
        order.removeAll { $0 == usb }
        order.insert(usb, at: 0)
        try setOrder(order)
        return usb
    }

    public func preferBluetoothPAN() throws -> String? {
        let services = try listServices()
        guard let bluetooth = findBluetoothPAN(services) else { return nil }
        var order = try currentOrder()
        order.removeAll { $0 == bluetooth }
        order.insert(bluetooth, at: 0)
        try setOrder(order)
        return bluetooth
    }

    public func defaultRouteInterface() throws -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/route")
        proc.arguments = ["-n", "get", "default"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        if proc.terminationStatus != 0 {
            let err = String(data: errData, encoding: .utf8) ?? ""
            throw NSError(domain: "route", code: Int(proc.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "route -n get default failed: \(err)"
            ])
        }
        let output = String(data: outData, encoding: .utf8) ?? ""
        return parseDefaultRouteInterface(output)
    }

    public func findUSBTether(_ services: [NetworkService]) -> String? {
        let patterns = ["iPhone USB", "iPhone", "USB Tether", "USB Ethernet", "RNDIS"]
        for p in patterns {
            if let match = services.first(where: { $0.name.contains(p) }) {
                return match.name
            }
        }
        return nil
    }

    public func findBluetoothPAN(_ services: [NetworkService]) -> String? {
        services.first { service in
            let haystack = "\(service.name) \(service.hardwarePort ?? "")"
            return haystack.localizedCaseInsensitiveContains("Bluetooth PAN")
                || haystack.localizedCaseInsensitiveContains("Bluetooth")
                || haystack.localizedCaseInsensitiveContains("PAN")
        }?.name
    }

    public func isWiFiService(_ s: NetworkService) -> Bool {
        s.name.contains("Wi-Fi") || s.name.contains("AirPort") || s.hardwarePort?.contains("Wi-Fi") == true
    }

    public func parseServiceOrder(_ output: String) -> [String] {
        var order: [String] = []
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("("), let close = line.firstIndex(of: ")") else { continue }
            let afterClose = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            if !afterClose.isEmpty {
                order.append(afterClose)
            }
        }
        return order
    }

    public func parseDefaultRouteInterface(_ output: String) -> String? {
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("interface:") else { continue }
            return line.dropFirst("interface:".count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func run(args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.networksetupPath)
        proc.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        if proc.terminationStatus != 0 {
            let err = String(data: errData, encoding: .utf8) ?? ""
            throw NSError(domain: "networksetup", code: Int(proc.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "networksetup \(args.joined(separator: " ")) failed: \(err)"
            ])
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }
}
