import Foundation
import ArgumentParser
import PowerNAPCore

struct LogsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "Tail PowerNAP daemon or watchdog logs."
    )

    @Flag(name: .shortAndLong, help: "Follow the log (like tail -f).")
    var follow: Bool = false

    @Option(name: .long, help: "Which log: daemon or watchdog.")
    var which: String = "daemon"

    func run() async throws {
        let path: String
        switch which {
        case "daemon": path = ConfigPaths.logFilePath
        case "watchdog": path = ConfigPaths.watchdogLogPath
        default:
            FileHandle.standardError.write(Data("unknown log: \(which)\n".utf8))
            throw ExitCode(2)
        }
        if !FileManager.default.fileExists(atPath: path) {
            print("log missing: \(path)")
            return
        }
        var args: [String] = []
        if follow { args.append("-f") }
        args.append(path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        task.arguments = args
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            throw ExitCode(task.terminationStatus)
        }
    }
}
