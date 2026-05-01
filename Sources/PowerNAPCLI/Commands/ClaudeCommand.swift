import Foundation
import ArgumentParser
import PowerNAPCore

struct ClaudeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude",
        abstract: "Run Claude Code under PowerNAP (installs per-run hooks)."
    )

    @Argument(parsing: .captureForPassthrough, help: "Arguments to forward to `claude`.")
    var passthrough: [String] = []

    func run() async throws {
        let runner = try AgentRunner(agent: "claude", binary: "claude", passthrough: passthrough)
        let status = try await runner.run()
        throw ExitCode(status)
    }
}
