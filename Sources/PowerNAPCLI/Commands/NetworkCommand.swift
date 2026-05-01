import Foundation
import ArgumentParser
import PowerNAPCore

struct NetworkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "network",
        abstract: "Inspect or override network failover behavior.",
        subcommands: [
            NetworkStatusCommand.self,
            NetworkPreferUSBCommand.self,
            NetworkPreferBluetoothCommand.self,
            NetworkRestoreCommand.self
        ],
        defaultSubcommand: NetworkStatusCommand.self
    )
}

struct NetworkStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Print network status from daemon.")

    @Flag(name: .long, help: "Emit JSON.")
    var json: Bool = false

    func run() async throws {
        let resp = try UnixSocketClient.sendRequest(IPCRequest(body: .networkStatus))
        switch resp.body {
        case .network(let payload):
            if json {
                let enc = FrameCodec.makeEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try enc.encode(payload)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } else {
                print("primary: \(payload.primaryInterface ?? "?") service=\(payload.primaryService ?? "?")")
                print("path: \(payload.path)")
                print("failover-active: \(payload.failoverActive)")
                print("usb-tether-present: \(payload.usbTetherPresent)")
                for svc in payload.services {
                    print("  - \(svc.name) iface=\(svc.interface ?? "?") active=\(svc.active) enabled=\(svc.enabled)")
                }
            }
        default:
            throw ExitCode(1)
        }
    }
}

struct NetworkPreferUSBCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "prefer-usb", abstract: "Force USB tether preference (best effort).")
    func run() async throws {
        let resp = try UnixSocketClient.sendRequest(IPCRequest(body: .networkPreferUSB))
        if case .error(_, let m) = resp.body {
            FileHandle.standardError.write(Data("error: \(m)\n".utf8))
            throw ExitCode(1)
        }
        print("requested USB tether preference.")
    }
}

struct NetworkPreferBluetoothCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "prefer-bluetooth", abstract: "Force Bluetooth PAN preference (best effort).")
    func run() async throws {
        let resp = try UnixSocketClient.sendRequest(IPCRequest(body: .networkPreferBluetoothPAN))
        if case .error(_, let m) = resp.body {
            FileHandle.standardError.write(Data("error: \(m)\n".utf8))
            throw ExitCode(1)
        }
        print("requested Bluetooth PAN preference.")
    }
}

struct NetworkRestoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "restore", abstract: "Restore original service order.")
    func run() async throws {
        let resp = try UnixSocketClient.sendRequest(IPCRequest(body: .networkRestore))
        if case .error(_, let m) = resp.body {
            FileHandle.standardError.write(Data("error: \(m)\n".utf8))
            throw ExitCode(1)
        }
        print("service order restored.")
    }
}
