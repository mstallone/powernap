import Foundation

public enum ClaudeHookInstallerError: Swift.Error, LocalizedError {
    case parseFailed(String)
    public var errorDescription: String? {
        switch self {
        case .parseFailed(let s): return "failed to parse existing ~/.claude/settings.json: \(s)"
        }
    }
}

public enum ClaudeHookInstaller {
    public static let allEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PermissionRequest",
        "PermissionDenied",
        "PostToolUse",
        "PostToolUseFailure",
        "PostToolBatch",
        "Notification",
        "Elicitation",
        "ElicitationResult",
        "Stop",
        "StopFailure",
        "TeammateIdle",
        "SessionEnd"
    ]

    public struct BuildResult: Sendable {
        public var overlayPath: String
        public var settingsArgValue: String
        public init(overlayPath: String, settingsArgValue: String) {
            self.overlayPath = overlayPath
            self.settingsArgValue = settingsArgValue
        }
    }

    public static func defaultSettingsPath(home: String = NSHomeDirectory()) -> String {
        "\(home)/.claude/settings.json"
    }

    public static func loadUserSettings(home: String = NSHomeDirectory()) -> [String: Any] {
        let path = defaultSettingsPath(home: home)
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              data.count > 0
        else { return [:] }
        return ((try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any]) ?? [:]
    }

    public static func buildOverlay(runId: String, hookBinaryPath: String? = nil, timeoutSeconds: Int = 2, home: String = NSHomeDirectory()) throws -> BuildResult {
        let hookPath = hookBinaryPath ?? HookBinaryResolver.resolve()
        var merged = loadUserSettings(home: home)

        var hooksBlock = (merged["hooks"] as? [String: Any]) ?? [:]

        for event in allEvents {
            var eventArr = (hooksBlock[event] as? [[String: Any]]) ?? []
            eventArr = eventArr.filter { ($0["powernap_managed"] as? Bool) != true }
            let entry: [String: Any] = [
                "powernap_managed": true,
                "hooks": [
                    [
                        "type": "command",
                        "command": hookPath,
                        "timeout": timeoutSeconds
                    ] as [String: Any]
                ]
            ]
            eventArr.append(entry)
            hooksBlock[event] = eventArr
        }

        merged["hooks"] = hooksBlock

        let overlayDir = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Caches/PowerNAP/claude-overlays", isDirectory: true)
        try FileSystemHelper.ensureDirectory(at: overlayDir, permissions: 0o700)

        let safeRunId = runId.replacingOccurrences(of: "/", with: "_")
        let overlayURL = overlayDir.appendingPathComponent("settings-\(safeRunId).json")
        let outData = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        try FileSystemHelper.writeAtomically(data: outData, to: overlayURL, permissions: 0o600)

        return BuildResult(overlayPath: overlayURL.path, settingsArgValue: overlayURL.path)
    }

    public static func cleanupOverlay(path: String) {
        let url = URL(fileURLWithPath: path)
        _ = try? FileManager.default.removeItem(at: url)
    }

    public static func cleanupStaleOverlays(olderThan seconds: TimeInterval = 24 * 3600) {
        let overlayDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches/PowerNAP/claude-overlays", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: overlayDir, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else { return }
        let cutoff = Date().addingTimeInterval(-seconds)
        for url in entries {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let mtime = attrs[.modificationDate] as? Date,
               mtime < cutoff {
                _ = try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
