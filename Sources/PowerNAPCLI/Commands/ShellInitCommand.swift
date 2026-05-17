import Foundation
import ArgumentParser

struct ShellInitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shell-init",
        abstract: "Print shell aliases for launching protected agents without the `powernap` prefix."
    )

    @Option(name: .long, help: "Shell syntax to print: sh or fish.")
    var shell: Shell = .sh

    func run() throws {
        switch shell {
        case .sh:
            print("alias codex='powernap codex'")
            print("alias claude='powernap claude'")
        case .fish:
            print("alias codex 'powernap codex'")
            print("alias claude 'powernap claude'")
        }
    }
}

enum Shell: String, ExpressibleByArgument {
    case sh
    case fish
}
