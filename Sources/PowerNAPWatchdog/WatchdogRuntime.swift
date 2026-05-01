import Foundation
import Logging
import PowerNAPCore
import PowerNAPPlatform

public enum WatchdogRuntime {
    public static func run(oneShot: Bool) async throws {
        PowerNAPLogger.bootstrap(label: "watchdog", toFile: ConfigPaths.watchdogLogPath, level: .info)
        let logger = PowerNAPLogger.make("watchdog")

        let store = try StateStore(logger: logger)
        let config = (try? ConfigLoader.load()) ?? .default
        let staleThreshold = TimeInterval(max(30, config.safety.watchdogReleaseAfterSeconds))

        if oneShot {
            try performCheck(store: store, logger: logger, staleThreshold: staleThreshold)
            return
        }

        logger.info("watchdog starting (poll 20s)", metadata: [
            "stale_threshold_seconds": .string(String(Int(staleThreshold)))
        ])

        try performCheck(store: store, logger: logger, staleThreshold: staleThreshold)

        while true {
            try await Task.sleep(nanoseconds: 20 * 1_000_000_000)
            do {
                try performCheck(store: store, logger: logger, staleThreshold: staleThreshold)
            } catch {
                logger.error("watchdog check failed: \(error)")
            }
        }
    }

    static let staleThresholdSeconds: TimeInterval = 180

    static func performCheck(store: StateStore, logger: Logger, staleThreshold: TimeInterval = staleThresholdSeconds) throws {
        let active = try store.clamshellIsActive()
        guard active else { return }

        let heartbeatAge = currentHeartbeatAge()
        let daemonAlive = isDaemonAlive()

        if heartbeatAge > staleThresholdSeconds || !daemonAlive {
            logger.warning("releasing clamshell - heartbeat_age=\(String(format: "%.1f", heartbeatAge))s daemon_alive=\(daemonAlive)")
            let clamshell = ClamshellOverride(logger: logger)
            clamshell.forceClearIgnoreErrors()
            try store.setClamshellActive(false, pid: nil)
            let stale = try store.janitorStaleLeases(olderThan: staleThresholdSeconds)
            logger.warning("released \(stale.count) stale leases")
        }
    }

    static func currentHeartbeatAge() -> TimeInterval {
        let path = ConfigPaths.heartbeatPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let written = obj["written_at"] as? Double else {
            return Double.greatestFiniteMagnitude
        }
        return Date().timeIntervalSince1970 - written
    }

    static func isDaemonAlive() -> Bool {
        let path = ConfigPaths.heartbeatPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = (obj["pid"] as? Int32) ?? (obj["pid"] as? NSNumber).map({ $0.int32Value }) else {
            return false
        }
        if pid <= 0 { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
