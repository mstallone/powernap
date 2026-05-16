import Foundation

public enum ConfigPaths {
    public static var appSupportDir: URL {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment["POWERNAP_APP_SUPPORT_DIR"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            ensurePrivateDirectory(url)
            return url
        }
        if let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let url = dir.appendingPathComponent("PowerNAP", isDirectory: true)
            ensurePrivateDirectory(url)
            return url
        }
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/PowerNAP", isDirectory: true)
        ensurePrivateDirectory(url)
        return url
    }

    public static var logsDir: URL {
        if let override = ProcessInfo.processInfo.environment["POWERNAP_LOGS_DIR"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            ensurePrivateDirectory(url)
            return url
        }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let dir = home.appendingPathComponent("Library/Logs/PowerNAP", isDirectory: true)
        ensurePrivateDirectory(dir)
        return dir
    }

    public static var runtimeDir: URL {
        let env = ProcessInfo.processInfo.environment
        if let xdgRuntime = env["POWERNAP_RUNTIME_DIR"] {
            let url = URL(fileURLWithPath: xdgRuntime, isDirectory: true)
            ensurePrivateDirectory(url)
            return url
        }
        if let tmpdir = env["TMPDIR"] {
            let url = URL(fileURLWithPath: tmpdir, isDirectory: true).appendingPathComponent("PowerNAP", isDirectory: true)
            ensurePrivateDirectory(url)
            return url
        }
        let url = URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent("PowerNAP-\(NSUserName())", isDirectory: true)
        ensurePrivateDirectory(url)
        return url
    }

    public static var socketPath: String {
        runtimeDir.appendingPathComponent("daemon.sock").path
    }

    public static var heartbeatPath: String {
        runtimeDir.appendingPathComponent("daemon.heartbeat").path
    }

    public static var clamshellStatePath: String {
        runtimeDir.appendingPathComponent("clamshell.state").path
    }

    public static var pidFilePath: String {
        runtimeDir.appendingPathComponent("daemon.pid").path
    }

    public static var stateDBPath: String {
        let dir = appSupportDir
        ensurePrivateDirectory(dir)
        return dir.appendingPathComponent("state.sqlite").path
    }

    public static var configFilePath: String {
        let dir = appSupportDir
        ensurePrivateDirectory(dir)
        return dir.appendingPathComponent("config.toml").path
    }

    public static var logFilePath: String {
        logsDir.appendingPathComponent("powernapd.log").path
    }

    public static var watchdogLogPath: String {
        logsDir.appendingPathComponent("watchdog.log").path
    }

    private static func ensurePrivateDirectory(_ url: URL) {
        let fm = FileManager.default
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: 0o700)]
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: attrs)
        }
        try? fm.setAttributes(attrs, ofItemAtPath: url.path)
    }
}
