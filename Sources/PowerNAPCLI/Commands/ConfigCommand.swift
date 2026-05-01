import Foundation
import ArgumentParser
import PowerNAPCore

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Inspect or edit PowerNAP configuration.",
        subcommands: [ConfigPathCommand.self, ConfigShowCommand.self, ConfigEditCommand.self, ConfigValidateCommand.self],
        defaultSubcommand: ConfigShowCommand.self
    )
}

struct ConfigPathCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "path", abstract: "Print config file path.")
    func run() async throws { print(ConfigPaths.configFilePath) }
}

struct ConfigShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Print effective config (defaults + overrides).")
    func run() async throws {
        let cfg = try ConfigLoader.load(from: ConfigPaths.configFilePath)
        print("[power]")
        print("  closed_lid_enabled = \(cfg.power.closedLidEnabled)")
        print("  prearm_clamshell_on_active = \(cfg.power.prearmClamshellOnActive)")
        print("  max_closed_lid_minutes = \(cfg.power.maxClosedLidMinutes)")
        print("[safety]")
        print("  min_battery_percent = \(cfg.safety.minBatteryPercent)")
        print("  active_lease_ttl_seconds = \(cfg.safety.activeLeaseTTLSeconds)")
        print("  waiting_grace_seconds = \(cfg.safety.waitingGraceSeconds)")
        print("  watchdog_heartbeat_seconds = \(cfg.safety.watchdogHeartbeatSeconds)")
        print("  watchdog_release_after_seconds = \(cfg.safety.watchdogReleaseAfterSeconds)")
        print("[network]")
        print("  enabled = \(cfg.network.enabled)")
        print("  prefer_usb_tether = \(cfg.network.preferUSBTether)")
        print("  allow_wifi_hotspot = \(cfg.network.allowWiFiHotspot)")
        print("  allow_bluetooth_pan = \(cfg.network.allowBluetoothPAN)")
        if !cfg.network.hotspots.isEmpty {
            print("  hotspots:")
            for h in cfg.network.hotspots {
                print("    - \(h.ssid)")
            }
        }
        print("[codex]")
        print("  enabled = \(cfg.codex.enabled)  mode = \(cfg.codex.hookMode)")
        print("[claude]")
        print("  enabled = \(cfg.claude.enabled)  mode = \(cfg.claude.hookMode)")
    }
}

struct ConfigEditCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "edit", abstract: "Open config file in $EDITOR.")
    func run() async throws {
        let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vi"
        let path = ConfigPaths.configFilePath
        if !FileManager.default.fileExists(atPath: path) {
            let sample = "[power]\n# closed_lid_enabled = true\n# prearm_clamshell_on_active = true\n\n[network]\n# prefer_usb_tether = true\n# [[network.hotspots]]\n# ssid = \"MyHotspot\"\n"
            try sample.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = [editor, path]
        try task.run()
        task.waitUntilExit()
    }
}

struct ConfigValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "validate", abstract: "Validate config by loading it.")
    func run() async throws {
        do {
            _ = try ConfigLoader.load(from: ConfigPaths.configFilePath)
            print("config ok.")
        } catch {
            FileHandle.standardError.write(Data("config error: \(error)\n".utf8))
            throw ExitCode(1)
        }
    }
}
