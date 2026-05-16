import XCTest
import Foundation
@testable import PowerNAPCore

final class DaemonIntegrationTests: XCTestCase {

    private var daemon: Process?
    private var tmpDir: URL!
    private var runtimeDir: URL!
    private var appSupportDir: URL!
    private var logsDir: URL!
    private var configPath: String!
    private var socketPath: String!
    private var stdoutFile: URL!
    private var stderrFile: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        guard let daemonURL = Self.findDaemonBinary() else {
            throw XCTSkip("powernapd binary not found at \(Self.expectedDaemonPath) - run `swift build --product powernapd` first.")
        }

        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        tmpDir = URL(fileURLWithPath: "/tmp/pn-it-\(shortID)", isDirectory: true)
        runtimeDir = tmpDir.appendingPathComponent("r", isDirectory: true)
        appSupportDir = tmpDir.appendingPathComponent("a", isDirectory: true)
        logsDir = tmpDir.appendingPathComponent("l", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)

        configPath = tmpDir.appendingPathComponent("config.toml").path
        try Self.safeTestConfig.write(toFile: configPath, atomically: true, encoding: .utf8)

        socketPath = runtimeDir.appendingPathComponent("daemon.sock").path
        stdoutFile = tmpDir.appendingPathComponent("daemon.stdout")
        stderrFile = tmpDir.appendingPathComponent("daemon.stderr")
        FileManager.default.createFile(atPath: stdoutFile.path, contents: nil)
        FileManager.default.createFile(atPath: stderrFile.path, contents: nil)

        let proc = Process()
        proc.executableURL = daemonURL
        proc.arguments = ["--foreground", "--config", configPath]
        proc.environment = daemonEnvironment()
        proc.standardOutput = FileHandle(forWritingAtPath: stdoutFile.path)
        proc.standardError = FileHandle(forWritingAtPath: stderrFile.path)
        try proc.run()
        daemon = proc

        try waitForSocket(timeoutSeconds: 10.0)
    }

    override func tearDownWithError() throws {
        if let proc = daemon {
            if proc.isRunning {
                kill(proc.processIdentifier, SIGTERM)
                let deadline = Date().addingTimeInterval(5)
                while proc.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                    proc.waitUntilExit()
                }
            }
            daemon = nil
        }
        if let tmp = tmpDir {
            try? FileManager.default.removeItem(at: tmp)
        }
        try super.tearDownWithError()
    }

    func testDaemonHandlesFullSessionLifecycle() throws {
        let pingResponse = try send(.ping)
        assertAck(pingResponse)

        let initialStatus = try send(.status)
        guard case let .status(initialPayload) = initialStatus.body else {
            return XCTFail("expected .status response, got \(initialStatus.body)")
        }
        XCTAssertTrue(initialPayload.daemonRunning)
        XCTAssertTrue(initialPayload.sessions.isEmpty, "no sessions expected before SessionStart")

        let runId = "run-\(UUID().uuidString.prefix(8))"
        let token = "tok-\(UUID().uuidString.prefix(8))"

        let startResp = try send(.hookEvent(HookEventMapper.Input(
            agent: "codex",
            runId: runId,
            sessionId: "sess-1",
            turnId: nil,
            event: "SessionStart",
            cwd: FileManager.default.currentDirectoryPath
        )), token: token)
        assertAck(startResp)

        let afterStart = try send(.status)
        guard case let .status(afterStartPayload) = afterStart.body else {
            return XCTFail("expected .status")
        }
        XCTAssertEqual(afterStartPayload.sessions.count, 1, "one active session after SessionStart")
        XCTAssertEqual(afterStartPayload.sessions.first?.runId, runId)
        XCTAssertEqual(afterStartPayload.sessions.first?.agent, "codex")

        let listSessions = try send(.listSessions)
        guard case let .sessions(sessionsPayload) = listSessions.body else {
            return XCTFail("expected .sessions")
        }
        XCTAssertEqual(sessionsPayload.count, 1)
        XCTAssertEqual(sessionsPayload.first?.runId, runId)

        let promptResp = try send(.hookEvent(HookEventMapper.Input(
            agent: "codex",
            runId: runId,
            sessionId: "sess-1",
            turnId: "turn-1",
            event: "UserPromptSubmit"
        )), token: token)
        assertAck(promptResp)

        let toolResp = try send(.hookEvent(HookEventMapper.Input(
            agent: "codex",
            runId: runId,
            sessionId: "sess-1",
            turnId: "turn-1",
            event: "PreToolUse",
            toolName: "bash"
        )), token: token)
        assertAck(toolResp)

        let leasesResp = try send(.listLeases)
        guard case .leases = leasesResp.body else {
            return XCTFail("expected .leases response")
        }

        let badTokenResp = try send(.hookEvent(HookEventMapper.Input(
            agent: "codex",
            runId: runId,
            event: "UserPromptSubmit"
        )), token: "wrong-token")
        if case let .error(code, _) = badTokenResp.body {
            XCTAssertEqual(code, "ingest_failed")
        } else {
            XCTFail("expected error for mismatched token")
        }

        let unknownResp = try send(.hookEvent(HookEventMapper.Input(
            agent: "codex",
            runId: "unknown-run-id",
            event: "UserPromptSubmit"
        )), token: "any")
        if case let .error(code, _) = unknownResp.body {
            XCTAssertEqual(code, "ingest_failed")
        } else {
            XCTFail("expected error for unknown run_id without SessionStart")
        }

        let stopResp = try send(.hookEvent(HookEventMapper.Input(
            agent: "codex",
            runId: runId,
            sessionId: "sess-1",
            event: "Stop"
        )), token: token)
        assertAck(stopResp)

        let endResp = try send(.hookEvent(HookEventMapper.Input(
            agent: "codex",
            runId: runId,
            sessionId: "sess-1",
            event: "SessionEnd"
        )), token: token)
        assertAck(endResp)

        let finalStatus = try send(.status)
        guard case let .status(finalPayload) = finalStatus.body else {
            return XCTFail("expected .status")
        }
        XCTAssertTrue(finalPayload.sessions.isEmpty, "session should be closed after SessionEnd")

        let restoreResp = try send(.restore(reason: "integration-test"))
        assertAck(restoreResp)
    }

    func testDaemonShutsDownCleanlyOnSIGTERM() throws {
        let before = try send(.ping)
        assertAck(before)

        guard let proc = daemon else {
            return XCTFail("daemon not running")
        }
        kill(proc.processIdentifier, SIGTERM)

        let deadline = Date().addingTimeInterval(5)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertFalse(proc.isRunning, "daemon should exit within 5s of SIGTERM")
        XCTAssertEqual(proc.terminationStatus, 0, "daemon should exit cleanly")
    }

    private func send(
        _ body: IPCRequest.Body,
        token: String? = nil,
        timeout: Double = 3.0
    ) throws -> IPCResponse {
        let request = IPCRequest(token: token, body: body)
        return try UnixSocketClient.sendRequest(
            request,
            socketPath: socketPath,
            timeoutSeconds: timeout
        )
    }

    private func assertAck(_ response: IPCResponse, file: StaticString = #filePath, line: UInt = #line) {
        if case .ack = response.body { return }
        XCTFail("expected .ack, got \(response.body)", file: file, line: line)
    }

    private func waitForSocket(timeoutSeconds: Double) throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let proc = daemon, !proc.isRunning {
                let out = (try? String(contentsOfFile: stdoutFile.path)) ?? ""
                let err = (try? String(contentsOfFile: stderrFile.path)) ?? ""
                throw NSError(domain: "DaemonIntegrationTests", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "daemon exited before socket became ready.\nstdout:\n\(out)\nstderr:\n\(err)"
                ])
            }
            if FileManager.default.fileExists(atPath: socketPath) {
                do {
                    _ = try UnixSocketClient.sendRequest(
                        IPCRequest(body: .ping),
                        socketPath: socketPath,
                        timeoutSeconds: 0.5
                    )
                    return
                } catch {
                    Thread.sleep(forTimeInterval: 0.1)
                    continue
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let out = (try? String(contentsOfFile: stdoutFile.path)) ?? ""
        let err = (try? String(contentsOfFile: stderrFile.path)) ?? ""
        throw NSError(domain: "DaemonIntegrationTests", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "daemon socket never became ready at \(socketPath ?? "?").\nstdout:\n\(out)\nstderr:\n\(err)"
        ])
    }

    private func daemonEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["POWERNAP_RUNTIME_DIR"] = runtimeDir.path
        env["POWERNAP_APP_SUPPORT_DIR"] = appSupportDir.path
        env["POWERNAP_LOGS_DIR"] = logsDir.path
        return env
    }

    private static var expectedDaemonPath: String {
        findPackageRoot().appendingPathComponent(".build/debug/powernapd").path
    }

    private static func findDaemonBinary() -> URL? {
        let candidate = findPackageRoot().appendingPathComponent(".build/debug/powernapd")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    private static func findPackageRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
            let pkg = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: pkg.path) {
                return url
            }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static let safeTestConfig: String = """
    [power]
    closed_lid_enabled = false
    idle_sleep_assertion = false
    max_closed_lid_minutes = 120
    release_when_waiting = true
    prearm_clamshell_on_active = false

    [safety]
    min_battery_percent = 20
    critical_battery_percent = 10
    allow_on_battery = true
    allow_thermal_serious = false
    watchdog_heartbeat_seconds = 60
    watchdog_release_after_seconds = 180
    active_lease_ttl_seconds = 1800
    waiting_grace_seconds = 20

    [agents.codex]
    enabled = true
    hook_mode = "global-inert"
    hook_timeout_seconds = 2

    [agents.claude]
    enabled = true
    hook_mode = "per-run-settings"
    hook_timeout_seconds = 2

    """
}
