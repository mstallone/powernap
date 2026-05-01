import Foundation
import ArgumentParser
import PowerNAPCore

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show daemon status, active sessions, and leases."
    )

    @Flag(name: .long, help: "Emit JSON.")
    var json: Bool = false

    func run() async throws {
        let request = IPCRequest(body: .status)
        do {
            let resp = try UnixSocketClient.sendRequest(request)
            switch resp.body {
            case .status(let payload):
                try emit(payload, json: json)
            case .error(_, let message):
                FileHandle.standardError.write(Data("status error: \(message)\n".utf8))
                throw ExitCode(1)
            default:
                FileHandle.standardError.write(Data("unexpected response\n".utf8))
                throw ExitCode(1)
            }
        } catch {
            if json {
                let payload: [String: Any] = [
                    "daemon_running": false,
                    "error": "\(error)"
                ]
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } else {
                print("daemon: not running (\(error))")
            }
        }
    }

    private func emit(_ payload: StatusPayload, json: Bool) throws {
        if json {
            let enc = FrameCodec.makeEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(payload)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }
        print("daemon: \(payload.daemonRunning ? "running" : "stopped")")
        print("sessions: \(payload.sessions.count)")
        for s in payload.sessions {
            print("  - \(s.agent) \(s.runId) phase=\(s.phase.rawValue) started=\(s.startedAt)")
        }
        print("leases: \(payload.leases.count)")
        for l in payload.leases {
            let exp = l.expiresAt.map { " expires=\($0)" } ?? ""
            print("  - \(l.leaseType) held=\(l.held)\(exp)")
        }
        print("safety: thermal=\(payload.safety.thermalState) battery=\(payload.safety.batteryPercent.map(String.init) ?? "?")")
        print("network: \(payload.network.primary ?? "?") health=\(payload.network.health)")
    }
}
