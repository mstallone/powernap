import Foundation
import Darwin
import Logging
import Security
import PowerNAPCore
import PowerNAPPlatform

struct AgentRunner {
    let agent: String
    let binary: String
    let passthrough: [String]
    let logger: Logger

    init(agent: String, binary: String, passthrough: [String]) throws {
        self.agent = agent
        self.binary = binary
        self.passthrough = passthrough
        self.logger = Logger(label: "dev.powernap.cli.runner.\(agent)")
    }

    func run() async throws -> Int32 {
        let resolved = try resolveBinary(binary)
        let runId = UUID().uuidString
        let token = try generateToken()
        let socketPath = ConfigPaths.socketPath
        let hookBinary = HookBinaryResolver.resolve()

        var finalArgs = passthrough
        var overlayToCleanup: String?

        do {
            switch agent {
            case "codex":
                let result = try CodexHookInstaller.install(hookBinaryPath: hookBinary)
                if !result.wasAlreadyInstalled {
                    FileHandle.standardError.write(Data("powernap: installed Codex hook at \(result.path)\n".utf8))
                }
            case "claude":
                let overlay = try ClaudeHookInstaller.buildOverlay(runId: runId, hookBinaryPath: hookBinary)
                overlayToCleanup = overlay.overlayPath
                finalArgs = ["--settings", overlay.settingsArgValue] + passthrough
            default:
                break
            }
        } catch {
            throw AgentRunnerError.hookSetupFailed(agent, error)
        }

        defer {
            if let overlay = overlayToCleanup {
                ClaudeHookInstaller.cleanupOverlay(path: overlay)
            }
        }

        var env = ProcessInfo.processInfo.environment
        env["POWERNAP_RUN_ID"] = runId
        env["POWERNAP_HOOK_TOKEN"] = token
        env["POWERNAP_SOCKET"] = socketPath
        env["POWERNAP_AGENT"] = agent
        env["POWERNAP_HOOK_BINARY"] = hookBinary

        do {
            try sendSyntheticEvent(runId: runId, token: token, event: "SessionStart")
            // Hold protection immediately; native hooks can later move the run to waiting or idle.
            try sendSyntheticEvent(runId: runId, token: token, event: "UserPromptSubmit")
        } catch {
            throw AgentRunnerError.daemonUnavailable(error)
        }

        let useTTY = isatty(0) != 0 && isatty(1) != 0
        let status: Int32
        if useTTY {
            status = try runWithPTY(executable: resolved, arguments: finalArgs, environment: env)
        } else {
            status = try runInline(executable: resolved, arguments: finalArgs, environment: env)
        }

        try? endSession(runId: runId, token: token, phase: status == 0 ? "done" : "error")
        ClaudeHookInstaller.cleanupStaleOverlays()

        return status
    }

    private func runWithPTY(executable: String, arguments: [String], environment: [String: String]) throws -> Int32 {
        let pty = PTYSession(logger: logger)
        let opts = PTYSession.SpawnOptions(
            executable: executable,
            arguments: arguments,
            environment: environment,
            cwd: FileManager.default.currentDirectoryPath
        )
        try pty.spawn(opts)
        pty.forwardCurrentWindowSize()
        do { try pty.makeStdinRaw() } catch { logger.debug("stdin raw-mode unavailable: \(error)") }

        let relay = PTYRelay(pty: pty, logger: logger)
        relay.start()
        let status = pty.wait()
        relay.stop()
        pty.close()
        return status
    }

    private func runInline(executable: String, arguments: [String], environment: [String: String]) throws -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.environment = environment
        task.standardInput = FileHandle.standardInput
        task.standardOutput = FileHandle.standardOutput
        task.standardError = FileHandle.standardError
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }

    private func sendSyntheticEvent(runId: String, token: String, event: String) throws {
        let input = HookEventMapper.Input(
            agent: agent,
            runId: runId,
            sessionId: nil,
            turnId: nil,
            event: event,
            cwd: event == "SessionStart" ? FileManager.default.currentDirectoryPath : nil,
            toolName: nil,
            timestamp: Date(),
            extra: nil
        )
        let req = IPCRequest(token: token, body: .hookEvent(input))
        _ = try UnixSocketClient.sendRequest(req)
    }

    private func endSession(runId: String, token: String, phase: String) throws {
        let input = HookEventMapper.Input(
            agent: agent,
            runId: runId,
            sessionId: nil,
            turnId: nil,
            event: phase == "error" ? "ProcessError" : "SessionEnd",
            cwd: nil,
            toolName: nil,
            timestamp: Date(),
            extra: nil
        )
        let req = IPCRequest(token: token, body: .hookEvent(input))
        _ = try UnixSocketClient.sendRequest(req)
    }

    private func generateToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AgentRunnerError.tokenGenerationFailed(status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func resolveBinary(_ name: String) throws -> String {
        if name.contains("/") { return name }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for entry in path.split(separator: ":") {
            let cand = "\(entry)/\(name)"
            if FileManager.default.isExecutableFile(atPath: cand) { return cand }
        }
        throw AgentRunnerError.binaryNotFound(name)
    }
}

enum AgentRunnerError: Swift.Error, LocalizedError {
    case binaryNotFound(String)
    case tokenGenerationFailed(OSStatus)
    case hookSetupFailed(String, Swift.Error)
    case daemonUnavailable(Swift.Error)
    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let n): return "Binary '\(n)' not found on PATH."
        case .tokenGenerationFailed(let status): return "Unable to generate secure run token (Security.framework status \(status))."
        case .hookSetupFailed(let agent, let error): return "Unable to set up \(agent) hooks: \(error)"
        case .daemonUnavailable(let error): return "PowerNAP daemon is required but not reachable: \(error)"
        }
    }
}
