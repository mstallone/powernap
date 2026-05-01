import Foundation

public enum AgentPhase: String, Codable, Sendable, CaseIterable {
    case starting
    case active
    case waiting
    case turnIdle = "turn_idle"
    case done
    case error
}

public struct AgentEvent: Codable, Sendable, Hashable {
    public var agent: String
    public var runId: String
    public var sessionId: String?
    public var turnId: String?
    public var phase: AgentPhase
    public var sourceEvent: String
    public var cwd: String?
    public var toolName: String?
    public var timestamp: Date

    public init(
        agent: String,
        runId: String,
        sessionId: String? = nil,
        turnId: String? = nil,
        phase: AgentPhase,
        sourceEvent: String,
        cwd: String? = nil,
        toolName: String? = nil,
        timestamp: Date = Date()
    ) {
        self.agent = agent
        self.runId = runId
        self.sessionId = sessionId
        self.turnId = turnId
        self.phase = phase
        self.sourceEvent = sourceEvent
        self.cwd = cwd
        self.toolName = toolName
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case agent
        case runId = "run_id"
        case sessionId = "session_id"
        case turnId = "turn_id"
        case phase
        case sourceEvent = "source_event"
        case cwd
        case toolName = "tool_name"
        case timestamp
    }
}

public enum AgentKind: String, Codable, Sendable {
    case codex
    case claude
    case generic
}
