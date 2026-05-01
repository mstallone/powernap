import Foundation
import Logging
import PowerNAPCore

public final class LeaseManager: @unchecked Sendable {
    public struct SafetyGateResult {
        public let allowIdle: Bool
        public let allowClamshell: Bool
        public let reasons: [String]
    }

    public struct Snapshot: Sendable {
        public let idleHeld: Bool
        public let clamshellActive: Bool
        public let activeRunIds: [String]
        public let lastDecision: String?
    }

    private let config: Config
    private let store: StateStore
    private let logger: Logger
    private let idle: IdleAssertion
    private let clamshell: ClamshellOverride
    private let battery: BatteryMonitor
    private let thermal: ThermalMonitor
    private let lid: LidMonitor

    private let lock = NSLock()
    private var activeRuns: [String: ActiveRun] = [:]
    private var idleLeaseID: String?
    private var clamshellLeaseID: String?
    private var heartbeatTimer: DispatchSourceTimer?
    private let heartbeatQueue = DispatchQueue(label: "dev.powernap.lease.heartbeat", qos: .utility)
    private var lastSafetyBlock: String?

    private struct ActiveRun {
        var runId: String
        var agent: String
        var phase: AgentPhase
        var lastSeen: Date
        var startedAt: Date
    }

    public init(config: Config, store: StateStore, logger: Logger) {
        self.config = config
        self.store = store
        self.logger = logger
        self.idle = IdleAssertion(kind: .preventIdleSleep, reason: "PowerNAP active turn", logger: logger)
        self.clamshell = ClamshellOverride(logger: logger)
        self.battery = BatteryMonitor(logger: logger)
        self.thermal = ThermalMonitor()
        self.lid = LidMonitor(logger: logger)
    }

    public func start() {
        startHeartbeat()
    }

    public func shutdown(reason: LeaseReleaseReason = .daemonShutdown) {
        lock.lock()
        defer { lock.unlock() }
        releaseAll(reason: reason, lockHeld: true)
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    public func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(
            idleHeld: idle.isHeld,
            clamshellActive: clamshell.isActive,
            activeRunIds: Array(activeRuns.keys),
            lastDecision: lastSafetyBlock
        )
    }

    public func handleAgentEvent(_ event: AgentEvent) {
        lock.lock()
        defer { lock.unlock() }
        updateActiveRun(for: event)
        evaluate(triggerEvent: event.sourceEvent)
    }

    public func reevaluate(reason: String) {
        lock.lock(); defer { lock.unlock() }
        evaluate(triggerEvent: reason)
    }

    public func forceRelease(reason: LeaseReleaseReason) {
        lock.lock(); defer { lock.unlock() }
        releaseAll(reason: reason, lockHeld: true)
    }

    private func updateActiveRun(for event: AgentEvent) {
        switch event.phase {
        case .starting, .active:
            var run = activeRuns[event.runId] ?? ActiveRun(
                runId: event.runId,
                agent: event.agent,
                phase: event.phase,
                lastSeen: event.timestamp,
                startedAt: event.timestamp
            )
            run.phase = event.phase
            run.lastSeen = event.timestamp
            run.agent = event.agent
            activeRuns[event.runId] = run
        case .waiting:
            if var run = activeRuns[event.runId] {
                run.phase = .waiting
                run.lastSeen = event.timestamp
                activeRuns[event.runId] = run
            }
        case .turnIdle, .done, .error:
            activeRuns.removeValue(forKey: event.runId)
        }
    }

    private func evaluate(triggerEvent: String) {
        let hasActiveTurn = activeRuns.values.contains { $0.phase == .active }
        let hasWaitingRun = activeRuns.values.contains { $0.phase == .waiting }
        let anyOpen = !activeRuns.isEmpty

        let gates = safetyGates()
        if !gates.allowIdle && idle.isHeld {
            logger.warning("safety cutoff: releasing idle assertion", metadata: [
                "reasons": .string(gates.reasons.joined(separator: "; "))
            ])
            releaseIdle(reason: .safetyCutoff)
        }
        if !gates.allowClamshell && clamshell.isActive {
            logger.warning("safety cutoff: disabling clamshell override", metadata: [
                "reasons": .string(gates.reasons.joined(separator: "; "))
            ])
            releaseClamshell(reason: .safetyCutoff)
        }

        let releaseWhenWaiting = config.power.releaseWhenWaiting
        let shouldHoldIdle: Bool = {
            if !config.power.idleSleepAssertion { return false }
            if !gates.allowIdle { return false }
            if hasActiveTurn { return true }
            if hasWaitingRun && !releaseWhenWaiting { return true }
            return false
        }()

        let shouldHoldClamshell: Bool = {
            if !config.power.closedLidEnabled { return false }
            if !gates.allowClamshell { return false }
            if !config.power.prearmClamshellOnActive { return hasActiveTurn }
            if hasActiveTurn { return true }
            if hasWaitingRun && !releaseWhenWaiting { return true }
            return false
        }()

        if shouldHoldIdle {
            acquireIdleIfNeeded()
        } else if idle.isHeld && !hasActiveTurn {
            releaseIdle(reason: releaseReason(triggerEvent: triggerEvent))
        }

        if shouldHoldClamshell {
            acquireClamshellIfNeeded()
        } else if clamshell.isActive && (!anyOpen || (hasWaitingRun && releaseWhenWaiting)) {
            releaseClamshell(reason: releaseReason(triggerEvent: triggerEvent))
        }

        if let lid = lid.isClosed(), lid {
            if hasActiveTurn, let ttl = activeTTLCutoff() {
                if let runStart = activeRuns.values.map({ $0.startedAt }).min(), runStart < ttl {
                    logger.warning("lid-closed active TTL exceeded - releasing", metadata: [
                        "ttl_minutes": .string(String(config.power.maxClosedLidMinutes))
                    ])
                    releaseAll(reason: .ttlExpired, lockHeld: true)
                }
            }
        }
    }

    private func activeTTLCutoff() -> Date? {
        guard config.power.maxClosedLidMinutes > 0 else { return nil }
        return Date().addingTimeInterval(-Double(config.power.maxClosedLidMinutes) * 60.0)
    }

    private func releaseReason(triggerEvent: String) -> LeaseReleaseReason {
        switch triggerEvent {
        case "Stop": return .turnIdle
        case "SessionEnd", "ProcessExit": return .sessionEnd
        case "ProcessError": return .processExit
        default: return .turnIdle
        }
    }

    private func safetyGates() -> SafetyGateResult {
        var reasons: [String] = []
        var allowIdle = true
        var allowClamshell = true

        let batt = battery.safeForClosedLid(
            minPercent: config.safety.minBatteryPercent,
            criticalPercent: config.safety.criticalBatteryPercent,
            allowOnBattery: config.safety.allowOnBattery
        )
        if !batt.ok {
            allowClamshell = false
            reasons.append("battery: \(batt.reason)")
            let snap = battery.snapshot()
            if let p = snap.percent, p <= config.safety.criticalBatteryPercent {
                allowIdle = false
            }
        }

        let therm = thermal.safeForClosedLid(allowSerious: config.safety.allowThermalSerious)
        if !therm.ok {
            allowClamshell = false
            reasons.append("thermal: \(therm.reason)")
            if therm.reason.contains("critical") {
                allowIdle = false
            }
        }

        lastSafetyBlock = reasons.isEmpty ? nil : reasons.joined(separator: "; ")
        return SafetyGateResult(allowIdle: allowIdle, allowClamshell: allowClamshell, reasons: reasons)
    }

    private func acquireIdleIfNeeded() {
        if idle.isHeld { return }
        do {
            try idle.acquire()
            let runId = activeRuns.keys.first
            let lease = Lease(
                runId: runId,
                leaseType: .idleSleep,
                acquiredAt: Date(),
                expiresAt: Date().addingTimeInterval(Double(config.safety.activeLeaseTTLSeconds))
            )
            try? store.saveLease(lease)
            idleLeaseID = lease.id
            logger.info("acquired idle-sleep lease", metadata: [
                "lease_id": .string(lease.id),
                "run_id": .string(runId ?? "-")
            ])
        } catch {
            logger.error("idle acquire failed: \(error)")
        }
    }

    private func acquireClamshellIfNeeded() {
        if clamshell.isActive { return }
        do {
            try clamshell.enable()
            try? store.setClamshellActive(true, pid: getpid())
            let runId = activeRuns.keys.first
            let lease = Lease(
                runId: runId,
                leaseType: .clamshellSleep,
                acquiredAt: Date(),
                expiresAt: Date().addingTimeInterval(Double(config.safety.activeLeaseTTLSeconds))
            )
            try? store.saveLease(lease)
            clamshellLeaseID = lease.id
            logger.info("acquired clamshell-sleep lease", metadata: [
                "lease_id": .string(lease.id),
                "run_id": .string(runId ?? "-")
            ])
        } catch {
            logger.error("clamshell enable failed: \(error)")
        }
    }

    private func releaseIdle(reason: LeaseReleaseReason) {
        if !idle.isHeld { return }
        idle.release()
        if let id = idleLeaseID {
            try? store.releaseLease(id: id, reason: reason)
            idleLeaseID = nil
        }
        logger.info("released idle-sleep lease", metadata: ["reason": .string(reason.rawValue)])
    }

    private func releaseClamshell(reason: LeaseReleaseReason) {
        if !clamshell.isActive { return }
        do { try clamshell.disable() } catch {
            logger.error("clamshell disable failed: \(error) - forcing clear")
            clamshell.forceClearIgnoreErrors()
        }
        try? store.setClamshellActive(false, pid: nil)
        if let id = clamshellLeaseID {
            try? store.releaseLease(id: id, reason: reason)
            clamshellLeaseID = nil
        }
        logger.info("released clamshell-sleep lease", metadata: ["reason": .string(reason.rawValue)])
    }

    private func releaseAll(reason: LeaseReleaseReason, lockHeld: Bool) {
        releaseIdle(reason: reason)
        releaseClamshell(reason: reason)
    }

    private func startHeartbeat() {
        let seconds = max(5, config.safety.watchdogHeartbeatSeconds / 2)
        let timer = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        timer.schedule(deadline: .now() + .seconds(seconds), repeating: .seconds(seconds))
        timer.setEventHandler { [weak self] in
            self?.heartbeat()
        }
        timer.resume()
        self.heartbeatTimer = timer
    }

    private func heartbeat() {
        lock.lock()
        let idleID = idleLeaseID
        let clamID = clamshellLeaseID
        lock.unlock()
        if let id = idleID { try? store.heartbeat(leaseID: id) }
        if let id = clamID { try? store.heartbeat(leaseID: id) }
        reevaluate(reason: "heartbeat")
    }
}
