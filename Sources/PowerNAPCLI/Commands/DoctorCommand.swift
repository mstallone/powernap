import Foundation
import Darwin
import ArgumentParser
import PowerNAPCore
import PowerNAPPlatform

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Run diagnostics for PowerNAP installation."
    )

    @Flag(name: .long, help: "Temporarily enable and immediately clear the clamshell override to verify the IOKit path.")
    var hardwareSpike: Bool = false

    @Flag(name: .long, help: "Skip outbound HTTPS reachability probes.")
    var skipNetworkProbes: Bool = false

    @Option(name: .long, help: "Timeout in seconds for subprocess checks.")
    var checkTimeoutSeconds: Double = 5

    func run() async throws {
        var failures = 0
        var warnings = 0

        func report(_ level: Level, _ name: String, detail: String = "") {
            let marker: String
            switch level {
            case .ok:
                marker = "[ok]"
            case .warning:
                marker = "[warn]"
                warnings += 1
            case .failure:
                marker = "[FAIL]"
                failures += 1
            }
            print("\(marker) \(name)\(detail.isEmpty ? "" : " - \(detail)")")
        }

        func check(_ name: String, ok: Bool, detail: String = "", warnOnly: Bool = false) {
            if ok {
                report(.ok, name, detail: detail)
            } else {
                report(warnOnly ? .warning : .failure, name, detail: detail)
            }
        }

        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment

        let sw = runProcess("/usr/bin/sw_vers", ["-productVersion"], timeoutSeconds: checkTimeoutSeconds).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let arch = runProcess("/usr/bin/uname", ["-m"], timeoutSeconds: checkTimeoutSeconds).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        check("macOS", ok: !sw.isEmpty, detail: "\(sw.isEmpty ? "unknown" : sw) \(arch.isEmpty ? "" : arch)")

        check("app-support dir", ok: fm.fileExists(atPath: ConfigPaths.appSupportDir.path), detail: ConfigPaths.appSupportDir.path)
        check("logs dir", ok: fm.fileExists(atPath: ConfigPaths.logsDir.path), detail: ConfigPaths.logsDir.path)
        check("runtime dir", ok: fm.fileExists(atPath: ConfigPaths.runtimeDir.path), detail: ConfigPaths.runtimeDir.path)
        check("socket path parent writable", ok: access(ConfigPaths.runtimeDir.path, W_OK) == 0)

        let daemonPlist = "\(NSHomeDirectory())/Library/LaunchAgents/dev.powernap.daemon.plist"
        let watchdogPlist = "\(NSHomeDirectory())/Library/LaunchAgents/dev.powernap.watchdog.plist"
        check("daemon LaunchAgent", ok: fm.fileExists(atPath: daemonPlist), detail: daemonPlist, warnOnly: true)
        check("watchdog LaunchAgent", ok: fm.fileExists(atPath: watchdogPlist), detail: watchdogPlist, warnOnly: true)

        let hookPath = HookBinaryResolver.resolve()
        check("powernap-hook executable", ok: fm.isExecutableFile(atPath: hookPath), detail: hookPath)

        let config: Config
        do {
            config = try ConfigLoader.load()
            report(.ok, "config parse", detail: ConfigPaths.configFilePath)
        } catch {
            report(.failure, "config parse", detail: "\(error)")
            config = .default
        }

        let hbAge: String
        if let attrs = try? fm.attributesOfItem(atPath: ConfigPaths.heartbeatPath),
           let mod = attrs[.modificationDate] as? Date {
            hbAge = "\(Int(Date().timeIntervalSince(mod)))s ago"
        } else {
            hbAge = "missing"
        }
        let heartbeatOK: Bool
        if hbAge == "missing" {
            heartbeatOK = false
        } else if let seconds = Int(hbAge.replacingOccurrences(of: "s ago", with: "")) {
            heartbeatOK = seconds <= max(config.safety.watchdogReleaseAfterSeconds, config.safety.watchdogHeartbeatSeconds * 3)
        } else {
            heartbeatOK = true
        }
        check("daemon heartbeat", ok: heartbeatOK, detail: hbAge, warnOnly: true)

        do {
            _ = try UnixSocketClient.sendRequest(IPCRequest(body: .ping))
            check("daemon ipc", ok: true)
        } catch {
            check("daemon ipc", ok: false, detail: "\(error)")
        }

        check("sqlite state db", ok: fm.fileExists(atPath: ConfigPaths.stateDBPath), detail: ConfigPaths.stateDBPath, warnOnly: true)

        let idle = IdleAssertion(reason: "PowerNAP doctor")
        do {
            try idle.acquire()
            idle.release()
            report(.ok, "idle sleep assertion", detail: "created and released")
        } catch {
            report(.failure, "idle sleep assertion", detail: "\(error)")
        }

        if hardwareSpike {
            let clamshell = ClamshellOverride()
            do {
                try clamshell.enable()
                try clamshell.disable()
                report(.ok, "clamshell override spike", detail: "enabled and cleared")
            } catch {
                clamshell.forceClearIgnoreErrors()
                report(.failure, "clamshell override spike", detail: "\(error)")
            }
        } else {
            report(.warning, "clamshell override spike", detail: "skipped; run `powernap doctor --hardware-spike` before closed-lid QA")
        }

        let battery = BatteryMonitor().safeForClosedLid(
            minPercent: config.safety.minBatteryPercent,
            criticalPercent: config.safety.criticalBatteryPercent,
            allowOnBattery: config.safety.allowOnBattery
        )
        check("battery safety", ok: battery.ok, detail: battery.reason, warnOnly: true)

        let thermal = ThermalMonitor().safeForClosedLid(allowSerious: config.safety.allowThermalSerious)
        check("thermal safety", ok: thermal.ok, detail: thermal.reason, warnOnly: true)

        let codex = findExecutable("codex", env: env)
        check("Codex CLI", ok: codex != nil, detail: codex ?? "not found", warnOnly: true)
        if let codex {
            let versionResult = runProcess(codex, ["--version"], timeoutSeconds: checkTimeoutSeconds)
            let version = versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            check("Codex version", ok: versionResult.status == 0, detail: version.isEmpty ? versionResult.stderr : version, warnOnly: true)
            let featuresResult = runProcess(codex, ["features", "list"], timeoutSeconds: checkTimeoutSeconds)
            let features = featuresResult.stdout
            check("Codex hooks feature", ok: featuresResult.status == 0 && features.contains("codex_hooks") && features.contains("true"), detail: featuresResult.status == 124 ? featuresResult.stderr : (features.contains("codex_hooks") ? "codex_hooks present" : "codex_hooks missing"), warnOnly: true)
            check("Codex PowerNAP hook installed", ok: CodexHookInstaller.isInstalled(), detail: CodexHookInstaller.configPath(), warnOnly: true)
        }

        let claude = findExecutable("claude", env: env)
        check("Claude Code CLI", ok: claude != nil, detail: claude ?? "not found", warnOnly: true)
        if let claude {
            let versionResult = runProcess(claude, ["--version"], timeoutSeconds: checkTimeoutSeconds)
            let version = versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            check("Claude Code version", ok: versionResult.status == 0, detail: version.isEmpty ? versionResult.stderr : version, warnOnly: true)
            let helpResult = runProcess(claude, ["--help"], timeoutSeconds: checkTimeoutSeconds)
            let help = helpResult.stdout
            check("Claude per-run settings", ok: helpResult.status == 0 && help.contains("--settings"), detail: helpResult.status == 124 ? helpResult.stderr : "--settings support", warnOnly: true)
            check("Claude hook stream flag", ok: helpResult.status == 0 && help.contains("--include-hook-events"), detail: helpResult.status == 124 ? helpResult.stderr : "--include-hook-events support", warnOnly: true)
        }

        do {
            let order = NetworkServiceOrder()
            let services = try order.listServices()
            let names = services.map(\.name)
            check("network services", ok: !services.isEmpty, detail: names.joined(separator: ", "))
            let usb = order.findUSBTether(services)
            check("iPhone USB service", ok: usb != nil, detail: usb ?? "not present", warnOnly: true)
            let wifi = services.first(where: { order.isWiFiService($0) })
            check("Wi-Fi service", ok: wifi != nil, detail: wifi.map { "\($0.name) \($0.device ?? "")" } ?? "not present", warnOnly: true)
            let bluetooth = order.findBluetoothPAN(services)
            if config.network.allowBluetoothPAN {
                check("Bluetooth PAN service", ok: bluetooth != nil, detail: bluetooth ?? "not present", warnOnly: true)
            }

            let serviceOrder = try order.currentOrder()
            check("network service order snapshot", ok: !serviceOrder.isEmpty, detail: serviceOrder.joined(separator: " > "))

            if usb == nil && config.network.hotspots.isEmpty && !(config.network.allowBluetoothPAN && bluetooth != nil) {
                report(.warning, "coffee-shop-to-car network fallback", detail: "no iPhone USB service, configured hotspot, or Bluetooth PAN service")
            } else {
                let fallback = usb != nil
                    ? "iPhone USB available"
                    : ((config.network.allowBluetoothPAN && bluetooth != nil) ? "Bluetooth PAN available" : "configured hotspot present")
                report(.ok, "coffee-shop-to-car network fallback", detail: fallback)
            }
        } catch {
            report(.failure, "network service inspection", detail: "\(error)")
        }

        let route = runProcess("/sbin/route", ["-n", "get", "default"], timeoutSeconds: checkTimeoutSeconds)
        check("default route", ok: route.status == 0, detail: firstUsefulLine(route.stdout) ?? route.stderr, warnOnly: true)

        if config.network.enabled && !skipNetworkProbes {
            let probe = NetworkProbe(timeout: 3)
            let results = await probe.probeAll(endpoints: config.network.probeEndpoints)
            let okEndpoints = results.compactMap { endpoint, result -> String? in
                if case .ok = result { return endpoint }
                return nil
            }
            check("agent HTTPS probes", ok: !okEndpoints.isEmpty, detail: okEndpoints.isEmpty ? "no endpoint reachable" : okEndpoints.joined(separator: ", "), warnOnly: true)
        } else if skipNetworkProbes {
            report(.warning, "agent HTTPS probes", detail: "skipped")
        }

        print("summary: \(failures) failure(s), \(warnings) warning(s)")

        if failures > 0 {
            throw ExitCode(1)
        }
    }

    private enum Level {
        case ok
        case warning
        case failure
    }

    private struct ProcessResult {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    private func findExecutable(_ name: String, env: [String: String]) -> String? {
        let candidates = (env["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":")
            .map { String($0) + "/" + name }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private func runProcess(_ path: String, _ args: [String], timeoutSeconds: Double) -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return ProcessResult(status: 127, stdout: "", stderr: "not executable: \(path)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }
        do {
            try process.run()
            let timeout = DispatchTime.now() + .milliseconds(max(1, Int(timeoutSeconds * 1000)))
            if finished.wait(timeout: timeout) == .timedOut {
                process.terminate()
                if finished.wait(timeout: .now() + 1) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + 1)
                }
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
                let detail = err.isEmpty ? "timed out after \(timeoutSeconds)s" : "\(err) (timed out after \(timeoutSeconds)s)"
                return ProcessResult(status: 124, stdout: out, stderr: detail)
            }
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            return ProcessResult(
                status: process.terminationStatus,
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errData, encoding: .utf8) ?? ""
            )
        } catch {
            return ProcessResult(status: 126, stdout: "", stderr: "\(error)")
        }
    }

    private func firstUsefulLine(_ text: String) -> String? {
        text.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
    }
}
