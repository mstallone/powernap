import Foundation

public enum CodexHookInstallerError: Swift.Error, LocalizedError {
    case encodingFailed
    case parseFailed(String)
    case configTomlWriteFailed(String)
    public var errorDescription: String? {
        switch self {
        case .encodingFailed: return "failed to encode Codex hooks.json"
        case .parseFailed(let s): return "failed to parse existing ~/.codex/hooks.json: \(s)"
        case .configTomlWriteFailed(let s): return "failed to ensure [features] hooks in ~/.codex/config.toml: \(s)"
        }
    }
}

public enum CodexHookInstaller {
    public static let managedMarker = "powernap-managed"
    public static let allEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PermissionRequest",
        "Stop"
    ]

    public struct InstallResult: Sendable {
        public var path: String
        public var backupPath: String?
        public var wasAlreadyInstalled: Bool
        public var eventsInstalled: [String]
        public var configTomlPath: String
        public var configTomlModified: Bool
        public init(
            path: String,
            backupPath: String?,
            wasAlreadyInstalled: Bool,
            eventsInstalled: [String],
            configTomlPath: String,
            configTomlModified: Bool
        ) {
            self.path = path
            self.backupPath = backupPath
            self.wasAlreadyInstalled = wasAlreadyInstalled
            self.eventsInstalled = eventsInstalled
            self.configTomlPath = configTomlPath
            self.configTomlModified = configTomlModified
        }
    }

    public static func configPath(home: String = NSHomeDirectory()) -> String {
        "\(home)/.codex/hooks.json"
    }

    public static func configTomlPath(home: String = NSHomeDirectory()) -> String {
        "\(home)/.codex/config.toml"
    }

    @discardableResult
    public static func install(
        hookBinaryPath: String? = nil,
        timeoutSeconds: Int = 2,
        home: String = NSHomeDirectory()
    ) throws -> InstallResult {
        let hookPath = hookBinaryPath ?? HookBinaryResolver.resolve()
        let filePath = configPath(home: home)
        let fileURL = URL(fileURLWithPath: filePath)
        let dir = fileURL.deletingLastPathComponent()
        try FileSystemHelper.ensureDirectory(at: dir, permissions: 0o700)

        let fm = FileManager.default
        var existing: [String: Any] = [:]
        var backupPath: String?

        if fm.fileExists(atPath: filePath), let data = try? Data(contentsOf: fileURL), data.count > 0 {
            do {
                if let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] {
                    existing = obj
                }
            } catch {
                throw CodexHookInstallerError.parseFailed(error.localizedDescription)
            }

            let bkPath = filePath + ".powernap.bak"
            if !fm.fileExists(atPath: bkPath) {
                try? fm.copyItem(atPath: filePath, toPath: bkPath)
            }
            backupPath = bkPath
        }

        var hooksRoot: [String: Any] = (existing["hooks"] as? [String: Any]) ?? [:]

        var wasAlreadyInstalled = false
        for event in allEvents {
            var groups = (hooksRoot[event] as? [[String: Any]]) ?? []
            let (filtered, removedPowerNAP) = filterPowerNAPGroups(groups)
            if removedPowerNAP { wasAlreadyInstalled = true }
            groups = filtered

            let handler: [String: Any] = [
                "type": "command",
                "command": hookPath,
                "timeout": timeoutSeconds
            ]
            let matcherGroup: [String: Any] = [
                "hooks": [handler]
            ]
            groups.append(matcherGroup)
            hooksRoot[event] = groups
        }

        existing["hooks"] = hooksRoot

        let outData: Data
        do {
            outData = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw CodexHookInstallerError.encodingFailed
        }

        try FileSystemHelper.writeAtomically(data: outData, to: fileURL, permissions: 0o644)

        let tomlPath = configTomlPath(home: home)
        let tomlModified: Bool
        do {
            tomlModified = try ensureFeatureFlag(home: home)
        } catch {
            throw CodexHookInstallerError.configTomlWriteFailed(error.localizedDescription)
        }

        return InstallResult(
            path: filePath,
            backupPath: backupPath,
            wasAlreadyInstalled: wasAlreadyInstalled,
            eventsInstalled: allEvents,
            configTomlPath: tomlPath,
            configTomlModified: tomlModified
        )
    }

    @discardableResult
    public static func uninstall(home: String = NSHomeDirectory()) throws -> Bool {
        let filePath = configPath(home: home)
        let fileURL = URL(fileURLWithPath: filePath)
        let fm = FileManager.default
        guard fm.fileExists(atPath: filePath) else { return false }

        guard let data = try? Data(contentsOf: fileURL), data.count > 0,
              var obj = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any] else {
            return false
        }

        var changed = false
        if var hooksRoot = obj["hooks"] as? [String: Any] {
            for (event, value) in hooksRoot {
                guard let groups = value as? [[String: Any]] else { continue }
                let (filtered, removed) = filterPowerNAPGroups(groups)
                if removed { changed = true }
                if filtered.isEmpty {
                    hooksRoot.removeValue(forKey: event)
                } else {
                    hooksRoot[event] = filtered
                }
            }
            if hooksRoot.isEmpty {
                obj.removeValue(forKey: "hooks")
            } else {
                obj["hooks"] = hooksRoot
            }
        }
        if obj[managedMarker] != nil {
            obj.removeValue(forKey: managedMarker)
            changed = true
        }

        if obj.isEmpty {
            try? fm.removeItem(at: fileURL)
            return changed
        }

        let outData = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try FileSystemHelper.writeAtomically(data: outData, to: fileURL, permissions: 0o644)
        return changed
    }

    public static func isInstalled(home: String = NSHomeDirectory()) -> Bool {
        let filePath = configPath(home: home)
        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let obj = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any]
        else {
            return false
        }
        if obj[managedMarker] != nil { return true }
        if let hooksRoot = obj["hooks"] as? [String: Any] {
            for (_, value) in hooksRoot {
                guard let groups = value as? [[String: Any]] else { continue }
                if groups.contains(where: { groupContainsPowerNAPHandler($0) }) {
                    return true
                }
            }
        }
        return false
    }

    private static func filterPowerNAPGroups(
        _ groups: [[String: Any]]
    ) -> (filtered: [[String: Any]], removedAny: Bool) {
        var result: [[String: Any]] = []
        var removedAny = false
        for group in groups {
            if groupContainsPowerNAPHandler(group) {
                removedAny = true
                continue
            }
            result.append(group)
        }
        return (result, removedAny)
    }

    private static func groupContainsPowerNAPHandler(_ group: [String: Any]) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
        return handlers.contains { handler in
            guard let cmd = handler["command"] as? String else { return false }
            return cmd.contains("powernap-hook")
        }
    }

    @discardableResult
    private static func ensureFeatureFlag(home: String) throws -> Bool {
        let path = configTomlPath(home: home)
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        try FileSystemHelper.ensureDirectory(at: url.deletingLastPathComponent(), permissions: 0o700)

        var content = ""
        if fm.fileExists(atPath: path), let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) {
            content = s
            let bkPath = path + ".powernap.bak"
            if !fm.fileExists(atPath: bkPath) {
                try? fm.copyItem(atPath: path, toPath: bkPath)
            }
        }

        if let parsed = try? TOMLMini.parse(content),
           let features = parsed["features"]?.tableValue,
           features["hooks"]?.boolValue == true,
           features["codex_hooks"] == nil {
            return false
        }

        var lines = content.isEmpty ? [] : content.components(separatedBy: "\n")
        if let featuresIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) {
            var sectionEnd = lines.count
            for i in (featuresIdx + 1)..<lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("[") && t.hasSuffix("]") {
                    sectionEnd = i
                    break
                }
            }
            var hooksIdx: Int? = nil
            var i = featuresIdx + 1
            while i < sectionEnd {
                switch tomlKeyName(in: lines[i]) {
                case "codex_hooks":
                    lines.remove(at: i)
                    sectionEnd -= 1
                    continue
                case "hooks":
                    hooksIdx = i
                default:
                    break
                }
                i += 1
            }
            if let hi = hooksIdx {
                lines[hi] = "hooks = true"
            } else {
                lines.insert("hooks = true", at: featuresIdx + 1)
            }
        } else {
            if !content.isEmpty && !content.hasSuffix("\n") {
                lines.append("")
            }
            lines.append("")
            lines.append("[features]")
            lines.append("hooks = true")
        }

        let newContent = lines.joined(separator: "\n")
        if newContent == content {
            return false
        }
        try FileSystemHelper.writeAtomically(data: Data(newContent.utf8), to: url, permissions: 0o644)
        return true
    }

    private static func tomlKeyName(in line: String) -> String? {
        let withoutComment = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? line
        guard let equalsIdx = withoutComment.firstIndex(of: "=") else { return nil }
        return withoutComment[..<equalsIdx].trimmingCharacters(in: .whitespaces)
    }
}
