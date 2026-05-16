import Foundation
import ArgumentParser
import PowerNAPCore

struct UninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Unload and remove PowerNAP launch agents."
    )

    func run() async throws {
        let home = NSHomeDirectory()
        let daemonPlist = "\(home)/Library/LaunchAgents/dev.powernap.daemon.plist"
        let watchdogPlist = "\(home)/Library/LaunchAgents/dev.powernap.watchdog.plist"
        let menuPlist = "\(home)/Library/LaunchAgents/dev.powernap.menu.plist"

        _ = try? runLC(["bootout", "gui/\(getuid())/dev.powernap.daemon"])
        _ = try? runLC(["bootout", "gui/\(getuid())/dev.powernap.watchdog"])
        _ = try? runLC(["bootout", "gui/\(getuid())/dev.powernap.menu"])

        try? FileManager.default.removeItem(atPath: daemonPlist)
        try? FileManager.default.removeItem(atPath: watchdogPlist)
        try? FileManager.default.removeItem(atPath: menuPlist)

        print("removed launch agents (state/config preserved).")
    }

    private func runLC(_ args: [String]) throws -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }
}
