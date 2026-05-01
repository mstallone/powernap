import Foundation
import ArgumentParser

@main
@available(macOS 13.0, *)
struct PowerNAPWatchdogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "powernap-watchdog",
        abstract: "Independent watchdog for PowerNAP clamshell override.",
        version: "0.1.0"
    )

    @Flag(name: .long, help: "Single-shot janitor run, then exit.")
    var oneShot: Bool = false

    mutating func run() async throws {
        try await WatchdogRuntime.run(oneShot: oneShot)
    }
}
