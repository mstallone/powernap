import Foundation
import ArgumentParser
import PowerNAPCore

struct LeasesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "leases",
        abstract: "List current and recent leases."
    )

    @Flag(name: .long, help: "Emit JSON.")
    var json: Bool = false

    func run() async throws {
        let resp = try UnixSocketClient.sendRequest(IPCRequest(body: .listLeases))
        switch resp.body {
        case .leases(let leases):
            if json {
                let enc = FrameCodec.makeEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try enc.encode(leases)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } else {
                for l in leases {
                    let released = l.releasedAt.map { " released=\($0) reason=\(l.releaseReason ?? "")" } ?? ""
                    print("\(l.leaseId) type=\(l.leaseType) run=\(l.runId) acquired=\(l.acquiredAt) expires=\(l.expiresAt)\(released)")
                }
                if leases.isEmpty { print("no leases.") }
            }
        case .error(_, let m):
            FileHandle.standardError.write(Data("leases error: \(m)\n".utf8))
            throw ExitCode(1)
        default:
            throw ExitCode(1)
        }
    }
}
