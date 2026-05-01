import Foundation
import ArgumentParser
import PowerNAPCore

struct CodexCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codex",
        abstract: "Run Codex under PowerNAP (installs per-run hooks)."
    )

    @Argument(parsing: .captureForPassthrough, help: "Arguments to forward to `codex`.")
    var passthrough: [String] = []

    func run() async throws {
        let runner = try AgentRunner(agent: "codex", binary: "codex", passthrough: passthrough)
        let status = try await runner.run()
        throw ExitCode(status)
    }
}
