import Foundation
import ArgumentParser

@main
@available(macOS 13.0, *)
struct PowerNAPDaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "powernapd",
        abstract: "PowerNAP per-user daemon.",
        version: "0.1.0"
    )

    @Flag(name: .long, help: "Run foreground (not as launchd agent).")
    var foreground: Bool = false

    @Option(name: .long, help: "Override config file path.")
    var config: String?

    mutating func run() async throws {
        try await DaemonRuntime.run(foreground: foreground, configPath: config)
    }
}
