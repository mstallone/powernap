import Foundation

public enum LeaseType: String, Codable, Sendable, CaseIterable {
    case idleSleep = "idle_sleep"
    case clamshellSleep = "clamshell_sleep"
}

public enum LeaseReleaseReason: String, Codable, Sendable {
    case waitingGrace = "waiting_grace"
    case turnIdle = "turn_idle"
    case sessionEnd = "session_end"
    case processExit = "process_exit"
    case ttlExpired = "ttl_expired"
    case safetyCutoff = "safety_cutoff"
    case manualRestore = "manual_restore"
    case watchdog = "watchdog"
    case daemonShutdown = "daemon_shutdown"
}

public struct Lease: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let runId: String?
    public let leaseType: LeaseType
    public let acquiredAt: Date
    public var expiresAt: Date
    public var heartbeatAt: Date
    public var releasedAt: Date?
    public var releaseReason: LeaseReleaseReason?
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        runId: String?,
        leaseType: LeaseType,
        acquiredAt: Date = Date(),
        expiresAt: Date,
        heartbeatAt: Date? = nil,
        releasedAt: Date? = nil,
        releaseReason: LeaseReleaseReason? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.runId = runId
        self.leaseType = leaseType
        self.acquiredAt = acquiredAt
        self.expiresAt = expiresAt
        self.heartbeatAt = heartbeatAt ?? acquiredAt
        self.releasedAt = releasedAt
        self.releaseReason = releaseReason
        self.metadata = metadata
    }

    public var isReleased: Bool { releasedAt != nil }

    public var isExpired: Bool {
        !isReleased && Date() >= expiresAt
    }
}
