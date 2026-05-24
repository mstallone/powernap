import Foundation
import ArgumentParser
import PowerNAPCore
import PowerNAPPlatform

struct RestoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "Release all PowerNAP leases and clear clamshell override."
    )

    @Option(name: .long, help: "Reason tag.")
    var reason: String = "manual"

    func run() async throws {
        let request = IPCRequest(body: .restore(reason: reason))
        do {
            let resp = try UnixSocketClient.sendRequest(request)
            switch resp.body {
            case .ack:
                print("restored.")
            case .error(_, let message):
                FileHandle.standardError.write(Data("restore error: \(message)\n".utf8))
                throw ExitCode(1)
            default:
                throw ExitCode(1)
            }
        } catch {
            FileHandle.standardError.write(Data("restore: daemon unavailable, attempting local safety restore (\(error))\n".utf8))
            do {
                try localRestore(reason: reason)
                print("restored locally.")
            } catch {
                FileHandle.standardError.write(Data("restore failed: \(error)\n".utf8))
                throw ExitCode(1)
            }
        }
    }

    private func localRestore(reason: String) throws {
        let logger = PowerNAPLogger.make("restore")
        let clamshell = ClamshellOverride(logger: logger)

        let store = try StateStore(logger: logger)
        let clamshellWasActive = try store.clamshellIsActive()
        let forceClearSucceeded = clamshell.forceClearIgnoreErrors()
        if clamshellWasActive && !forceClearSucceeded {
            throw LocalRestoreError.clamshellClearFailed
        }

        let open = try store.openLeases()
        for lease in open {
            try store.releaseLease(id: lease.id, reason: .manualRestore)
        }
        try store.setClamshellActive(false, pid: nil)
    }
}

private enum LocalRestoreError: LocalizedError {
    case clamshellClearFailed

    var errorDescription: String? {
        "clamshell override clear failed"
    }
}
