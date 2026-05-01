import Foundation

public enum HookEventMapper {

    public struct Input: Codable, Sendable {
        public var agent: String?
        public var runId: String
        public var sessionId: String?
        public var turnId: String?
        public var event: String
        public var cwd: String?
        public var toolName: String?
        public var timestamp: Date?
        public var extra: [String: String]?

        public init(
            agent: String?,
            runId: String,
            sessionId: String? = nil,
            turnId: String? = nil,
            event: String,
            cwd: String? = nil,
            toolName: String? = nil,
            timestamp: Date? = nil,
            extra: [String: String]? = nil
        ) {
            self.agent = agent
            self.runId = runId
            self.sessionId = sessionId
            self.turnId = turnId
            self.event = event
            self.cwd = cwd
            self.toolName = toolName
            self.timestamp = timestamp
            self.extra = extra
        }

        enum CodingKeys: String, CodingKey {
            case agent
            case runId = "run_id"
            case sessionId = "session_id"
            case turnId = "turn_id"
            case event
            case cwd
            case toolName = "tool_name"
            case timestamp
            case extra
        }
    }

    public static func normalize(_ input: Input) -> AgentEvent {
        let phase = mapPhase(agent: input.agent, event: input.event)
        return AgentEvent(
            agent: input.agent ?? "generic",
            runId: input.runId,
            sessionId: input.sessionId,
            turnId: input.turnId,
            phase: phase,
            sourceEvent: input.event,
            cwd: input.cwd,
            toolName: input.toolName,
            timestamp: input.timestamp ?? Date()
        )
    }

    static func mapPhase(agent: String?, event: String) -> AgentPhase {
        switch event {
        case "SessionStart":
            return .starting
        case "UserPromptSubmit":
            return .active
        case "PreToolUse", "PostToolUse", "PostToolUseFailure", "PostToolBatch", "PermissionDenied", "ElicitationResult":
            return .active
        case "PermissionRequest", "Elicitation":
            return .waiting
        case "Notification":
            return .waiting
        case "Stop", "TeammateIdle":
            return .turnIdle
        case "SessionEnd":
            return .done
        case "StopFailure":
            return .error
        case "ProcessExit":
            return .done
        case "ProcessError":
            return .error
        default:
            return .active
        }
    }
}
