import Foundation
import ArgumentParser
import PowerNAPCore

struct RelayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "relay",
        abstract: "Premium egress relay (stub in v0).",
        subcommands: [RelayStatusCommand.self, RelayConnectCommand.self],
        defaultSubcommand: RelayStatusCommand.self
    )
}

struct RelayStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show relay state.")
    func run() async throws {
        print("relay: disabled (premium feature not yet available)")
    }
}

struct RelayConnectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "connect", abstract: "Connect to a premium relay (stub).")

    @Option(name: .long, help: "Relay URL.")
    var url: String?

    func run() async throws {
        FileHandle.standardError.write(Data("relay: not yet available in v0. Stay tuned.\n".utf8))
        throw ExitCode(2)
    }
}
