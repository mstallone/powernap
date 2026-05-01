import Foundation
import Logging
import PowerNAPCore
import PowerNAPPlatform

public enum DaemonRuntime {
    public static func run(foreground: Bool, configPath: String?) async throws {
        PowerNAPLogger.bootstrap(label: "powernapd", toFile: ConfigPaths.logFilePath, level: .info)
        let logger = PowerNAPLogger.make("daemon")

        let config: Config
        let loadedPath = configPath ?? ConfigPaths.configFilePath
        do {
            try? ConfigLoader.writeDefaultIfMissing(to: loadedPath)
            config = try ConfigLoader.load(from: loadedPath)
        } catch {
            logger.error("config load failed: \(error)")
            throw error
        }

        let store = try StateStore(logger: logger)

        let openClamshell = try store.clamshellIsActive()
        if openClamshell {
            logger.warning("startup: found lingering clamshell_state=active - clearing (safety bias)")
            let recovery = ClamshellOverride(logger: logger)
            recovery.forceClearIgnoreErrors()
            try store.setClamshellActive(false, pid: nil)
        }
        let staleLeases = try store.janitorStaleLeases(olderThan: 300)
        if !staleLeases.isEmpty {
            logger.warning("startup janitor released \(staleLeases.count) stale leases")
        }

        writeWatchdogReadyMarker()

        logger.info("powernapd starting", metadata: [
            "foreground": .string(String(foreground)),
            "config": .string(loadedPath),
            "socket": .string(ConfigPaths.socketPath)
        ])

        let leaseManager = LeaseManager(config: config, store: store, logger: logger)
        leaseManager.start()

        let networkOrchestrator = NetworkOrchestrator(config: config, store: store, logger: logger)
        networkOrchestrator.start()

        let server = try DaemonServer(
            config: config,
            store: store,
            leaseManager: leaseManager,
            network: networkOrchestrator,
            logger: logger
        )
        try server.start()

        let heartbeat = HeartbeatWriter(intervalSeconds: config.safety.watchdogHeartbeatSeconds, logger: logger)
        heartbeat.start()

        setupSignalHandling(server: server, heartbeat: heartbeat, leaseManager: leaseManager, network: networkOrchestrator, store: store, logger: logger)

        logger.info("powernapd ready")

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DaemonShutdown.shared.registerCompletion {
                cont.resume()
            }
        }

        leaseManager.shutdown()
        networkOrchestrator.shutdown()
        heartbeat.stop()
        try? server.stop()
        clearHeartbeat()
        logger.info("powernapd stopped")
    }

    static func writeWatchdogReadyMarker() {
        let url = ConfigPaths.runtimeDir.appendingPathComponent("watchdog.ready")
        let contents = Data("{\"daemon_pid\":\(getpid()),\"set_at\":\(Date().timeIntervalSince1970)}".utf8)
        try? FileSystemHelper.writeAtomically(data: contents, to: url, permissions: 0o600)
    }

    static func clearHeartbeat() {
        try? FileManager.default.removeItem(atPath: ConfigPaths.heartbeatPath)
    }

    static func setupSignalHandling(server: DaemonServer, heartbeat: HeartbeatWriter, leaseManager: LeaseManager, network: NetworkOrchestrator, store: StateStore, logger: Logger) {
        signal(SIGPIPE, SIG_IGN)
        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource.setEventHandler {
            logger.info("SIGTERM received - shutting down")
            leaseManager.forceRelease(reason: .daemonShutdown)
            network.shutdown()
            try? store.setClamshellActive(false, pid: nil)
            DaemonShutdown.shared.trigger()
        }
        termSource.resume()
        signal(SIGTERM, SIG_IGN)

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSource.setEventHandler {
            logger.info("SIGINT received - shutting down")
            leaseManager.forceRelease(reason: .daemonShutdown)
            network.shutdown()
            try? store.setClamshellActive(false, pid: nil)
            DaemonShutdown.shared.trigger()
        }
        intSource.resume()
        signal(SIGINT, SIG_IGN)

        DaemonShutdown.shared.signalRetainer = [termSource, intSource]
    }
}

final class DaemonShutdown: @unchecked Sendable {
    static let shared = DaemonShutdown()
    private let lock = NSLock()
    private var completion: (() -> Void)?
    private var triggered = false
    var signalRetainer: [DispatchSourceSignal] = []

    func registerCompletion(_ cb: @escaping () -> Void) {
        lock.lock(); defer { lock.unlock() }
        if triggered {
            cb()
        } else {
            completion = cb
        }
    }

    func trigger() {
        lock.lock()
        let cb = completion
        completion = nil
        triggered = true
        lock.unlock()
        cb?()
    }
}

final class HeartbeatWriter {
    private let intervalSeconds: Int
    private let logger: Logger
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "dev.powernap.heartbeat", qos: .utility)
    private let generation: String

    init(intervalSeconds: Int, logger: Logger) {
        self.intervalSeconds = max(5, intervalSeconds)
        self.logger = logger
        self.generation = UUID().uuidString
    }

    func start() {
        writeOnce()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .seconds(intervalSeconds), repeating: .seconds(intervalSeconds))
        t.setEventHandler { [weak self] in self?.writeOnce() }
        t.resume()
        self.timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func writeOnce() {
        let payload: [String: Any] = [
            "pid": getpid(),
            "generation": generation,
            "written_at": Date().timeIntervalSince1970
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            do {
                try FileSystemHelper.writeAtomically(data: data, to: URL(fileURLWithPath: ConfigPaths.heartbeatPath), permissions: 0o600)
            } catch {
                logger.error("heartbeat write failed: \(error)")
            }
        }
    }
}

public final class DaemonServer {
    private let config: Config
    private let store: StateStore
    private let logger: Logger
    private let ingestor: HookEventIngestor
    private let leaseManager: LeaseManager
    private let network: NetworkOrchestrator
    private let expectedUID: uid_t

    private var serverFD: Int32 = -1
    private var accepting = false
    private let acceptQueue = DispatchQueue(label: "dev.powernap.accept", qos: .utility)

    public init(config: Config, store: StateStore, leaseManager: LeaseManager, network: NetworkOrchestrator, logger: Logger) throws {
        self.config = config
        self.store = store
        self.logger = logger
        self.leaseManager = leaseManager
        self.network = network
        self.ingestor = HookEventIngestor(store: store, leaseManager: leaseManager, logger: logger)
        self.expectedUID = getuid()
    }

    public func start() throws {
        let path = ConfigPaths.socketPath
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { throw SysError.fromErrno() }
        serverFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        if pathBytes.count >= maxLen { throw UnixSocketClient.ClientError.pathTooLong(path) }

        withUnsafeMutablePointer(to: &addr.sun_path) { tuple in
            tuple.withMemoryRebound(to: CChar.self, capacity: maxLen) { cptr in
                for i in 0..<pathBytes.count {
                    cptr[i] = CChar(bitPattern: pathBytes[i])
                }
                cptr[pathBytes.count] = 0
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                bind(fd, saPtr, size)
            }
        }
        if bindResult < 0 { throw SysError.fromErrno() }

        chmod(path, 0o600)

        if listen(fd, 16) < 0 { throw SysError.fromErrno() }

        accepting = true
        acceptQueue.async { [weak self] in self?.acceptLoop() }
        logger.info("IPC server listening", metadata: ["path": .string(path)])
    }

    public func stop() throws {
        accepting = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(ConfigPaths.socketPath)
    }

    private func acceptLoop() {
        while accepting {
            var peer = sockaddr_un()
            var len = socklen_t(MemoryLayout<sockaddr_un>.size)
            let cfd = withUnsafeMutablePointer(to: &peer) { ptr -> Int32 in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    accept(serverFD, saPtr, &len)
                }
            }
            if cfd < 0 {
                if errno == EINTR { continue }
                if !accepting { return }
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handleClient(fd: cfd)
            }
        }
    }

    private func handleClient(fd: Int32) {
        defer { close(fd) }
        if !peerUIDMatches(fd: fd) {
            logger.warning("rejecting client: peer uid mismatch")
            return
        }
        do {
            let frame = try FrameCodec.readLengthPrefixedFrame(fromFileDescriptor: fd)
            let request = try FrameCodec.decode(IPCRequest.self, from: frame)
            let response = handle(request: request, peerFD: fd)
            let data = try FrameCodec.encode(response)
            try FrameCodec.writeLengthPrefixedFrame(toFileDescriptor: fd, payload: data.subdata(in: 4..<data.count))
        } catch {
            logger.warning("client error: \(error)")
        }
    }

    private func peerUIDMatches(fd: Int32) -> Bool {
        var cred = xucred()
        var len = socklen_t(MemoryLayout<xucred>.size)
        let rc = withUnsafeMutablePointer(to: &cred) { ptr -> Int32 in
            getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, ptr, &len)
        }
        if rc != 0 {
            logger.error("LOCAL_PEERCRED failed: errno=\(errno)")
            return false
        }
        if cred.cr_version != XUCRED_VERSION { return false }
        return cred.cr_uid == expectedUID
    }

    private func handle(request: IPCRequest, peerFD: Int32) -> IPCResponse {
        switch request.body {
        case .hookEvent(let input):
            do {
                try ingestor.ingest(input: input, providedToken: request.token)
                network.handleAgentEvent(HookEventMapper.normalize(input))
                return IPCResponse(requestId: request.id, body: .ack)
            } catch {
                return IPCResponse(requestId: request.id, body: .error(code: "ingest_failed", message: "\(error)"))
            }
        case .status:
            let payload = buildStatusPayload()
            return IPCResponse(requestId: request.id, body: .status(payload))
        case .listLeases:
            let leases = (try? store.allLeases()) ?? []
            let payloads = leases.map { lease in
                LeasePayload(
                    leaseId: lease.id,
                    runId: lease.runId ?? "",
                    leaseType: lease.leaseType.rawValue,
                    acquiredAt: lease.acquiredAt,
                    expiresAt: lease.expiresAt,
                    releasedAt: lease.releasedAt,
                    releaseReason: lease.releaseReason?.rawValue
                )
            }
            return IPCResponse(requestId: request.id, body: .leases(payloads))
        case .listSessions:
            let sessions = (try? store.openSessions()) ?? []
            let payloads = sessions.map { row in
                SessionPayload(
                    runId: row.runId,
                    agent: row.agent,
                    command: "",
                    cwd: row.cwd,
                    pid: nil,
                    ptyId: nil,
                    startedAt: row.startedAt,
                    lastEventAt: row.lastEventAt,
                    phase: AgentPhase(rawValue: row.lastPhase ?? "active") ?? .active,
                    exitStatus: nil
                )
            }
            return IPCResponse(requestId: request.id, body: .sessions(payloads))
        case .restore(let reason):
            leaseManager.forceRelease(reason: .manualRestore)
            let clamshell = ClamshellOverride(logger: logger)
            clamshell.forceClearIgnoreErrors()
            network.restoreServiceOrder()
            let open = (try? store.openLeases()) ?? []
            for lease in open {
                try? store.releaseLease(id: lease.id, reason: .manualRestore)
            }
            try? store.setClamshellActive(false, pid: nil)
            logger.warning("restore requested (reason=\(reason ?? "-")): released \(open.count) leases")
            return IPCResponse(requestId: request.id, body: .ack)
        case .networkStatus:
            return IPCResponse(requestId: request.id, body: .network(network.statusPayload()))
        case .networkPreferUSB:
            network.preferUSBTether()
            return IPCResponse(requestId: request.id, body: .ack)
        case .networkPreferBluetoothPAN:
            network.preferBluetoothPAN()
            return IPCResponse(requestId: request.id, body: .ack)
        case .networkRestore:
            network.restoreServiceOrder()
            return IPCResponse(requestId: request.id, body: .ack)
        case .ping:
            return IPCResponse(requestId: request.id, body: .ack)
        }
    }

    private func buildStatusPayload() -> StatusPayload {
        let sessions = (try? store.openSessions()) ?? []
        let activeSessions = sessions.map { row in
            StatusPayload.ActiveSession(
                runId: row.runId,
                agent: row.agent,
                phase: AgentPhase(rawValue: row.lastPhase ?? "active") ?? .active,
                startedAt: row.startedAt,
                lastEventAt: row.lastEventAt,
                pid: nil
            )
        }
        let leases = (try? store.openLeases()) ?? []
        let leaseInfos = leases.map { lease in
            StatusPayload.LeaseInfo(
                leaseType: lease.leaseType.rawValue,
                held: true,
                expiresAt: lease.expiresAt
            )
        }
        let batt = BatteryMonitor(logger: logger).snapshot()
        let therm = ThermalMonitor().snapshot()
        let netStatus = network.statusPayload()
        return StatusPayload(
            daemonRunning: true,
            sessions: activeSessions,
            leases: leaseInfos,
            safety: StatusPayload.SafetyInfo(
                batteryPercent: batt.percent,
                charging: batt.isCharging,
                thermalState: therm.state.rawValue
            ),
            network: StatusPayload.NetworkInfo(
                primary: netStatus.primaryInterface,
                health: netStatus.probeResults.isEmpty ? "unknown" : "ok",
                route: netStatus.primaryService,
                lastProbe: nil
            )
        )
    }
}

final class HookEventIngestor {
    private let store: StateStore
    private let leaseManager: LeaseManager
    private let logger: Logger
    private let queue = DispatchQueue(label: "dev.powernap.ingest", qos: .utility)

    init(store: StateStore, leaseManager: LeaseManager, logger: Logger) {
        self.store = store
        self.leaseManager = leaseManager
        self.logger = logger
    }

    func ingest(input: HookEventMapper.Input, providedToken: String?) throws {
        let event = HookEventMapper.normalize(input)
        let existingToken = try store.lookupHookToken(runId: event.runId)
        if let expected = existingToken {
            guard let token = providedToken, token == expected else {
                throw HookAuthError.tokenMismatch
            }
        } else {
            if event.phase == .starting {
                let token = providedToken ?? ""
                try store.createSession(
                    runId: event.runId,
                    agent: event.agent,
                    sessionId: event.sessionId,
                    hookToken: token,
                    cwd: event.cwd
                )
            } else {
                throw HookAuthError.unknownSession
            }
        }
        try store.recordEvent(event)
        if event.phase == .done || event.phase == .error {
            try? store.endSession(runId: event.runId, phase: event.phase.rawValue)
        }
        logger.info("hook event \(event.sourceEvent) -> \(event.phase.rawValue)", metadata: [
            "run_id": .string(event.runId),
            "agent": .string(event.agent)
        ])
        leaseManager.handleAgentEvent(event)
    }
}

enum HookAuthError: Swift.Error, LocalizedError {
    case tokenMismatch
    case unknownSession

    var errorDescription: String? {
        switch self {
        case .tokenMismatch: return "hook token mismatch"
        case .unknownSession: return "unknown run_id (no SessionStart received)"
        }
    }
}
