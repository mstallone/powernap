import Foundation
import ArgumentParser

@main
@available(macOS 13.0, *)
struct PowerNAPCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "powernap",
        abstract: "Keep AI coding agents alive through lid-close sleep.",
        version: "0.1.0",
        subcommands: [
            CodexCommand.self,
            ClaudeCommand.self,
            RunCommand.self,
            StatusCommand.self,
            DoctorCommand.self,
            RestoreCommand.self,
            HooksCommand.self,
            LogsCommand.self,
            LeasesCommand.self,
            ConfigCommand.self,
            ShellInitCommand.self,
            InstallCommand.self,
            UninstallCommand.self
        ]
    )
}
