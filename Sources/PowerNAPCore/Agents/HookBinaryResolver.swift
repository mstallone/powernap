import Foundation

public enum HookBinaryResolver {
    public static func resolve() -> String {
        if let env = ProcessInfo.processInfo.environment["POWERNAP_HOOK_BINARY"], !env.isEmpty,
           FileManager.default.isExecutableFile(atPath: env) {
            return env
        }

        let argv0 = CommandLine.arguments.first ?? ""
        if !argv0.isEmpty {
            let exeURL = URL(fileURLWithPath: argv0).resolvingSymlinksInPath()
            let sibling = exeURL.deletingLastPathComponent().appendingPathComponent("powernap-hook").path
            if FileManager.default.isExecutableFile(atPath: sibling) {
                return sibling
            }
        }

        let candidates = [
            "/usr/local/bin/powernap-hook",
            "/opt/homebrew/bin/powernap-hook",
            "\(NSHomeDirectory())/.local/bin/powernap-hook",
            "\(NSHomeDirectory())/bin/powernap-hook"
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for entry in path.split(separator: ":") {
                let cand = "\(entry)/powernap-hook"
                if FileManager.default.isExecutableFile(atPath: cand) {
                    return cand
                }
            }
        }

        return "powernap-hook"
    }
}
