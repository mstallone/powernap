import Foundation
import PowerNAPCore

public enum HookBinary {
    enum ParseError: Swift.Error, LocalizedError {
        case missingEvent
        case invalidPayload(String)

        var errorDescription: String? {
            switch self {
            case .missingEvent:
                return "missing hook event name"
            case .invalidPayload(let detail):
                return "invalid hook payload: \(detail)"
            }
        }
    }

    public static func run() -> Int32 {
        let env = ProcessInfo.processInfo.environment
        guard let runId = env["POWERNAP_RUN_ID"], !runId.isEmpty else {
            return 0
        }
        let debug = env["POWERNAP_HOOK_DEBUG"] == "1" || env["POWERNAP_HOOK_DEBUG"]?.lowercased() == "true"
        let token = env["POWERNAP_HOOK_TOKEN"] ?? ""
        let socketPath = env["POWERNAP_SOCKET"] ?? ConfigPaths.socketPath

        let stdinData = FileHandle.standardInput.availableData
        let input: HookEventMapper.Input
        do {
            input = try parse(stdinData: stdinData, runId: runId, env: env)
        } catch {
            if debug {
                FileHandle.standardError.write(Data("powernap-hook: parse error: \(error)\n".utf8))
            }
            return 0
        }

        let request = IPCRequest(token: token, body: .hookEvent(input))
        do {
            _ = try UnixSocketClient.sendRequest(request, socketPath: socketPath, timeoutSeconds: 2.0)
        } catch {
            if debug {
                FileHandle.standardError.write(Data("powernap-hook: send error: \(error)\n".utf8))
            }
        }
        return 0
    }

    static func parse(stdinData: Data, runId: String, env: [String: String]) throws -> HookEventMapper.Input {
        var agent = env["POWERNAP_AGENT"]
        var eventName: String?
        var sessionId: String?
        var turnId: String?
        var cwd: String?
        var toolName: String?
        var timestamp: Date?
        var extra: [String: String] = [:]

        if !stdinData.isEmpty {
            let decoded: Any
            do {
                decoded = try JSONSerialization.jsonObject(with: stdinData, options: [])
            } catch {
                throw ParseError.invalidPayload(error.localizedDescription)
            }
            guard let obj = decoded as? [String: Any] else {
                throw ParseError.invalidPayload("top-level JSON must be an object")
            }
            if let hookEvent = obj["hook_event_name"] as? String ?? obj["hook"] as? String ?? obj["event"] as? String {
                eventName = hookEvent
            }
            if let sid = obj["session_id"] as? String {
                sessionId = sid
            }
            if let tid = obj["turn_id"] as? String {
                turnId = tid
            }
            if let cd = obj["cwd"] as? String {
                cwd = cd
            }
            if let tn = obj["tool_name"] as? String {
                toolName = tn
            }
            if let ts = obj["timestamp"] as? Double {
                timestamp = Date(timeIntervalSince1970: ts)
            } else if let ts = obj["timestamp"] as? String {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                timestamp = f.date(from: ts) ?? {
                    let f2 = ISO8601DateFormatter()
                    f2.formatOptions = [.withInternetDateTime]
                    return f2.date(from: ts)
                }()
            }
            if let ag = obj["agent"] as? String {
                agent = ag
            }
            for (k, v) in obj where !["hook_event_name", "hook", "event", "session_id", "turn_id", "cwd", "tool_name", "timestamp", "agent"].contains(k) {
                if let s = v as? String {
                    extra[k] = s
                } else if let n = v as? NSNumber {
                    extra[k] = n.stringValue
                }
            }
        }

        if let forcedEvent = env["POWERNAP_EVENT"], !forcedEvent.isEmpty {
            eventName = forcedEvent
        }

        guard let eventName, !eventName.isEmpty else {
            throw ParseError.missingEvent
        }

        return HookEventMapper.Input(
            agent: agent,
            runId: runId,
            sessionId: sessionId,
            turnId: turnId,
            event: eventName,
            cwd: cwd,
            toolName: toolName,
            timestamp: timestamp,
            extra: extra.isEmpty ? nil : extra
        )
    }
}
