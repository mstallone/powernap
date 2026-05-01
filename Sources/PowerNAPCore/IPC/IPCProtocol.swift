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
        case networkStatus
        case networkPreferUSB
        case networkPreferBluetoothPAN
        case networkRestore
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
        case network(NetworkStatusPayload)
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

    public struct NetworkInfo: Codable, Sendable {
        public var primary: String?
        public var health: String
        public var route: String?
        public var lastProbe: String?

        public init(primary: String?, health: String, route: String?, lastProbe: String?) {
            self.primary = primary
            self.health = health
            self.route = route
            self.lastProbe = lastProbe
        }
    }

    public var daemonRunning: Bool
    public var sessions: [ActiveSession]
    public var leases: [LeaseInfo]
    public var safety: SafetyInfo
    public var network: NetworkInfo

    public init(
        daemonRunning: Bool,
        sessions: [ActiveSession],
        leases: [LeaseInfo],
        safety: SafetyInfo,
        network: NetworkInfo
    ) {
        self.daemonRunning = daemonRunning
        self.sessions = sessions
        self.leases = leases
        self.safety = safety
        self.network = network
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

public struct NetworkStatusPayload: Codable, Sendable {
    public struct Service: Codable, Sendable {
        public var name: String
        public var interface: String?
        public var active: Bool
        public var enabled: Bool

        public init(name: String, interface: String?, active: Bool, enabled: Bool) {
            self.name = name
            self.interface = interface
            self.active = active
            self.enabled = enabled
        }
    }

    public var primaryInterface: String?
    public var primaryService: String?
    public var path: String
    public var services: [Service]
    public var hotspotConfigured: Bool
    public var usbTetherPresent: Bool
    public var probeResults: [String: String]
    public var serviceOrderSnapshot: [String]?
    public var failoverActive: Bool

    public init(
        primaryInterface: String?,
        primaryService: String?,
        path: String,
        services: [Service],
        hotspotConfigured: Bool,
        usbTetherPresent: Bool,
        probeResults: [String: String],
        serviceOrderSnapshot: [String]?,
        failoverActive: Bool
    ) {
        self.primaryInterface = primaryInterface
        self.primaryService = primaryService
        self.path = path
        self.services = services
        self.hotspotConfigured = hotspotConfigured
        self.usbTetherPresent = usbTetherPresent
        self.probeResults = probeResults
        self.serviceOrderSnapshot = serviceOrderSnapshot
        self.failoverActive = failoverActive
    }
}
