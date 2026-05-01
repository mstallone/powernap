import Foundation
import ArgumentParser
import PowerNAPCore

struct HooksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hooks",
        abstract: "Inspect, install, or clean agent hook configuration.",
        subcommands: [
            HooksStatusCommand.self,
            HooksInstallCommand.self,
            HooksUninstallCommand.self,
            HooksCleanCommand.self
        ],
        defaultSubcommand: HooksStatusCommand.self
    )
}

struct HooksStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Print detected hook configuration for Codex/Claude."
    )
    func run() async throws {
        let home = NSHomeDirectory()
        let codexPath = CodexHookInstaller.configPath(home: home)
        let claudePath = ClaudeHookInstaller.defaultSettingsPath(home: home)

        let codexInstalled = CodexHookInstaller.isInstalled(home: home)
        print("codex hooks: \(FileManager.default.fileExists(atPath: codexPath) ? codexPath : "not present") [\(codexInstalled ? "PowerNAP managed" : "not PowerNAP managed")]")
        print("claude settings: \(FileManager.default.fileExists(atPath: claudePath) ? claudePath : "not present") [per-run overlay; no global mutation]")
        print("hook binary: \(HookBinaryResolver.resolve())")
    }
}

struct HooksInstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install PowerNAP hook into Codex (~/.codex/hooks.json). Claude uses per-run overlay, no install needed."
    )

    @Option(name: .long, help: "Override powernap-hook binary path")
    var hookBinary: String?

    @Option(name: .long, help: "Hook timeout in seconds (default: 2)")
    var timeout: Int = 2

    func run() async throws {
        let hookPath = hookBinary ?? HookBinaryResolver.resolve()
        let result = try CodexHookInstaller.install(hookBinaryPath: hookPath, timeoutSeconds: timeout)
        print("codex hooks installed at \(result.path)")
        if let backup = result.backupPath {
            print("backed up prior content at \(backup)")
        }
        print("events installed: \(result.eventsInstalled.joined(separator: ", "))")
        if result.configTomlModified {
            print("enabled [features] codex_hooks = true in \(result.configTomlPath)")
        } else {
            print("[features] codex_hooks already enabled in \(result.configTomlPath)")
        }
        print("note: hooks are inert unless POWERNAP_RUN_ID/POWERNAP_HOOK_TOKEN env is set")
    }
}

struct HooksUninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove PowerNAP hook from Codex config. Preserves user's other hooks."
    )
    func run() async throws {
        let changed = try CodexHookInstaller.uninstall()
        if changed {
            print("removed PowerNAP entries from \(CodexHookInstaller.configPath())")
        } else {
            print("no PowerNAP entries found in Codex hooks")
        }
        ClaudeHookInstaller.cleanupStaleOverlays(olderThan: 0)
        print("cleaned Claude per-run overlays (if any)")
    }
}

struct HooksCleanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Clean stale Claude per-run overlays (does not touch Codex or global settings)."
    )
    func run() async throws {
        ClaudeHookInstaller.cleanupStaleOverlays(olderThan: 0)
        print("cleaned stale Claude per-run overlays")
        print("note: codex hook entry preserved. Use `powernap hooks uninstall` to remove it.")
    }
}
