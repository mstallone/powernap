import Foundation

public enum IPCProtocol {
    public static let schemaVersion: UInt32 = 1
    public static let maxFrameBytes: UInt32 = 256 * 1024
}

public struct IPCRequest: Codable, Sendable {
    public enum Body: Codable, Sendable {
        case hookEvent(HookEventMapper.Input)
        case status
        case restore(reason: String?)
        case listLeases
        case listSessions
        case ping
    }

    public var version: UInt32
    public var id: String
    public var token: String?
    public var body: Body

    public init(version: UInt32 = IPCProtocol.schemaVersion, id: String = UUID().uuidString, token: String? = nil, body: Body) {
        self.version = version
        self.id = id
        self.token = token
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case version
        case id
        case token
        case body
    }
}

public struct IPCResponse: Codable, Sendable {
    public enum Body: Codable, Sendable {
        case ack
        case error(code: String, message: String)
        case status(StatusPayload)
        case leases([LeasePayload])
        case sessions([SessionPayload])
    }

    public var version: UInt32
    public var requestId: String?
    public var body: Body

    public init(version: UInt32 = IPCProtocol.schemaVersion, requestId: String? = nil, body: Body) {
        self.version = version
        self.requestId = requestId
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case version
        case requestId = "request_id"
        case body
    }
}

public struct StatusPayload: Codable, Sendable {
    public struct ActiveSession: Codable, Sendable {
        public var runId: String
        public var agent: String
        public var phase: AgentPhase
        public var startedAt: Date
        public var lastEventAt: Date?
        public var pid: Int32?

        public init(runId: String, agent: String, phase: AgentPhase, startedAt: Date, lastEventAt: Date?, pid: Int32?) {
            self.runId = runId
            self.agent = agent
            self.phase = phase
            self.startedAt = startedAt
            self.lastEventAt = lastEventAt
            self.pid = pid
        }
    }

    public struct LeaseInfo: Codable, Sendable {
        public var leaseType: String
        public var held: Bool
        public var expiresAt: Date?

        public init(leaseType: String, held: Bool, expiresAt: Date?) {
            self.leaseType = leaseType
            self.held = held
            self.expiresAt = expiresAt
        }
    }

    public struct SafetyInfo: Codable, Sendable {
        public var batteryPercent: Int?
        public var charging: Bool?
        public var thermalState: String

        public init(batteryPercent: Int?, charging: Bool?, thermalState: String) {
            self.batteryPercent = batteryPercent
            self.charging = charging
            self.thermalState = thermalState
        }
    }

    public var daemonRunning: Bool
    public var sessions: [ActiveSession]
    public var leases: [LeaseInfo]
    public var safety: SafetyInfo

    public init(
        daemonRunning: Bool,
        sessions: [ActiveSession],
        leases: [LeaseInfo],
        safety: SafetyInfo
    ) {
        self.daemonRunning = daemonRunning
        self.sessions = sessions
        self.leases = leases
        self.safety = safety
    }
}

public struct LeasePayload: Codable, Sendable {
    public var leaseId: String
    public var runId: String
    public var leaseType: String
    public var acquiredAt: Date
    public var expiresAt: Date
    public var releasedAt: Date?
    public var releaseReason: String?

    public init(leaseId: String, runId: String, leaseType: String, acquiredAt: Date, expiresAt: Date, releasedAt: Date?, releaseReason: String?) {
        self.leaseId = leaseId
        self.runId = runId
        self.leaseType = leaseType
        self.acquiredAt = acquiredAt
        self.expiresAt = expiresAt
        self.releasedAt = releasedAt
        self.releaseReason = releaseReason
    }
}

public struct SessionPayload: Codable, Sendable {
    public var runId: String
    public var agent: String
    public var command: String
    public var cwd: String?
    public var pid: Int32?
    public var ptyId: String?
    public var startedAt: Date
    public var lastEventAt: Date?
    public var phase: AgentPhase
    public var exitStatus: Int32?

    public init(runId: String, agent: String, command: String, cwd: String?, pid: Int32?, ptyId: String?, startedAt: Date, lastEventAt: Date?, phase: AgentPhase, exitStatus: Int32?) {
        self.runId = runId
        self.agent = agent
        self.command = command
        self.cwd = cwd
        self.pid = pid
        self.ptyId = ptyId
        self.startedAt = startedAt
        self.lastEventAt = lastEventAt
        self.phase = phase
        self.exitStatus = exitStatus
    }
}
