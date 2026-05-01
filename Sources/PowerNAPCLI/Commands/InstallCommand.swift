import Foundation
import ArgumentParser
import PowerNAPCore

struct InstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install launchd agents for powernapd and powernap-watchdog."
    )

    @Flag(name: .long, help: "Skip loading agents after writing plists.")
    var noLoad: Bool = false

    func run() async throws {
        if getuid() == 0 {
            FileHandle.standardError.write(Data("powernap install must run as the target user, not as root. Re-run without sudo (install.sh handles privilege escalation internally).\n".utf8))
            throw ExitCode(2)
        }

        let home = NSHomeDirectory()
        let agentsDir = "\(home)/Library/LaunchAgents"
        let fm = FileManager.default
        try fm.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: ConfigPaths.logsDir.path, withIntermediateDirectories: true)

        let daemonBin = try locateBinary("powernapd")
        let watchdogBin = try locateBinary("powernap-watchdog")

        let daemonPlistPath = "\(agentsDir)/dev.powernap.daemon.plist"
        let watchdogPlistPath = "\(agentsDir)/dev.powernap.watchdog.plist"

        let daemonPlist = try plistData(label: "dev.powernap.daemon", program: daemonBin, args: [], logsName: "powernapd")
        let watchdogPlist = try plistData(label: "dev.powernap.watchdog", program: watchdogBin, args: [], logsName: "watchdog")
        try daemonPlist.write(to: URL(fileURLWithPath: daemonPlistPath), options: [.atomic])
        try watchdogPlist.write(to: URL(fileURLWithPath: watchdogPlistPath), options: [.atomic])

        print("wrote \(daemonPlistPath)")
        print("wrote \(watchdogPlistPath)")

        if !noLoad {
            let uid = getuid()
            _ = try? run("/bin/launchctl", ["bootout", "gui/\(uid)/dev.powernap.daemon"])
            _ = try? run("/bin/launchctl", ["bootout", "gui/\(uid)/dev.powernap.watchdog"])
            try await Task.sleep(nanoseconds: 300_000_000)
            try await bootstrapWithRetry(uid: uid, plistPath: daemonPlistPath, label: "dev.powernap.daemon")
            try await bootstrapWithRetry(uid: uid, plistPath: watchdogPlistPath, label: "dev.powernap.watchdog")
            print("bootstrapped launch agents.")
        } else {
            print("skipped launchctl bootstrap. Load with:")
            print("  launchctl bootstrap gui/\(getuid()) \(daemonPlistPath)")
            print("  launchctl bootstrap gui/\(getuid()) \(watchdogPlistPath)")
        }
    }

    private func bootstrapWithRetry(uid: uid_t, plistPath: String, label: String) async throws {
        do {
            try run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistPath])
        } catch {
            _ = try? run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
            try await Task.sleep(nanoseconds: 500_000_000)
            try run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistPath])
        }
    }

    private func plistData(label: String, program: String, args: [String], logsName: String) throws -> Data {
        let logsDir = ConfigPaths.logsDir.path
        var programArguments = [program]
        programArguments.append(contentsOf: args)
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
            "RunAtLoad": true,
            "KeepAlive": [
                "Crashed": true,
                "SuccessfulExit": false
            ],
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": "\(logsDir)/\(logsName).out.log",
            "StandardErrorPath": "\(logsDir)/\(logsName).err.log",
            "EnvironmentVariables": [
                "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            ]
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    private func locateBinary(_ name: String) throws -> String {
        let ownExec = CommandLine.arguments.first ?? "powernap"
        let expanded = (ownExec as NSString).expandingTildeInPath
        let ownURL: URL
        if (expanded as NSString).isAbsolutePath {
            ownURL = URL(fileURLWithPath: expanded)
        } else {
            ownURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(expanded)
        }
        let candidate = ownURL.resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .appendingPathComponent(name)
            .path
        if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        if let found = which(name) { return found }
        throw ExitCode(2)
    }

    private func which(_ name: String) -> String? {
        for p in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let full = "\(p)/\(name)"
            if FileManager.default.isExecutableFile(atPath: full) { return full }
        }
        return nil
    }

    @discardableResult
    private func run(_ binary: String, _ args: [String]) throws -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = args
        let out = Pipe()
        let err = Pipe()
        task.standardOutput = out
        task.standardError = err
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "PowerNAPInstall", code: Int(task.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "\(binary) \(args.joined(separator: " ")) failed with exit \(task.terminationStatus)\nstdout:\(stdout)\nstderr:\(stderr)"
            ])
        }
        return task.terminationStatus
    }
}
