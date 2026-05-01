import Foundation
import ArgumentParser
import PowerNAPCore

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Generic PowerNAP wrapper for any agent command."
    )

    @Option(name: .long, help: "Agent kind tag (codex | claude | generic).")
    var agent: String = "generic"

    @Argument(help: "Command binary to run.")
    var command: String

    @Argument(parsing: .captureForPassthrough, help: "Arguments to forward to the command.")
    var passthrough: [String] = []

    func run() async throws {
        let runner = try AgentRunner(agent: agent, binary: command, passthrough: passthrough)
        let status = try await runner.run()
        throw ExitCode(status)
    }
}
