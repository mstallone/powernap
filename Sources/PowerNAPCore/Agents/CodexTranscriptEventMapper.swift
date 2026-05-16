import Foundation

public enum CodexTranscriptEvent: Equatable, Sendable {
    case matchedSession
    case rejectedSession
    case hookEvent(String)
}

public enum CodexTranscriptEventMapper {
    public static func map(line: String, workingDirectory: String) -> CodexTranscriptEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any]
        else {
            return nil
        }

        switch type {
        case "session_meta":
            guard let cwd = payload["cwd"] as? String,
                  samePath(cwd, workingDirectory)
            else {
                return nil
            }
            if let source = payload["source"] as? String, source != "cli" {
                return .rejectedSession
            }
            return .matchedSession

        case "turn_context":
            guard let cwd = payload["cwd"] as? String,
                  samePath(cwd, workingDirectory)
            else {
                return nil
            }
            return .matchedSession

        case "event_msg":
            guard let eventType = payload["type"] as? String else { return nil }
            switch eventType {
            case "task_started":
                return .hookEvent("UserPromptSubmit")
            case "task_complete", "turn_aborted":
                return .hookEvent("Stop")
            default:
                return nil
            }

        default:
            return nil
        }
    }

    private static func samePath(_ lhs: String, _ rhs: String) -> Bool {
        let left = URL(fileURLWithPath: lhs).standardizedFileURL.path
        let right = URL(fileURLWithPath: rhs).standardizedFileURL.path
        return left == right
    }
}
