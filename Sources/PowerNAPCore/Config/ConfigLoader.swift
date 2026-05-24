import Foundation

public enum ConfigLoader {

    public static func load(from path: String = ConfigPaths.configFilePath) throws -> Config {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return Config.default
        }
        let data = try String(contentsOfFile: path, encoding: .utf8)
        return try parse(data)
    }

    public static func parse(_ text: String) throws -> Config {
        let tree = try TOMLMini.parse(text)
        return build(from: tree)
    }

    public static func writeDefaultIfMissing(to path: String = ConfigPaths.configFilePath) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) { return }
        let dir = (path as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try defaultTOML.write(toFile: path, atomically: true, encoding: .utf8)
    }

    public static let defaultTOML: String = """
    [power]
    closed_lid_enabled = true
    idle_sleep_assertion = true
    max_closed_lid_minutes = 720
    release_when_waiting = true
    prearm_clamshell_on_active = true

    [safety]
    min_battery_percent = 20
    critical_battery_percent = 10
    allow_on_battery = true
    allow_thermal_serious = false
    watchdog_heartbeat_seconds = 60
    watchdog_release_after_seconds = 180
    active_lease_ttl_seconds = 43200
    waiting_grace_seconds = 20

    [agents.codex]
    enabled = true
    hook_mode = "global-inert"
    hook_timeout_seconds = 2

    [agents.claude]
    enabled = true
    hook_mode = "per-run-settings"
    hook_timeout_seconds = 2

    """

    private static func build(from tree: [String: TOMLValue]) -> Config {
        var cfg = Config.default

        if let powerT = tree["power"]?.tableValue {
            cfg.power.closedLidEnabled = powerT["closed_lid_enabled"]?.boolValue ?? cfg.power.closedLidEnabled
            cfg.power.idleSleepAssertion = powerT["idle_sleep_assertion"]?.boolValue ?? cfg.power.idleSleepAssertion
            cfg.power.maxClosedLidMinutes = powerT["max_closed_lid_minutes"]?.intValue ?? cfg.power.maxClosedLidMinutes
            cfg.power.releaseWhenWaiting = powerT["release_when_waiting"]?.boolValue ?? cfg.power.releaseWhenWaiting
            cfg.power.prearmClamshellOnActive = powerT["prearm_clamshell_on_active"]?.boolValue ?? cfg.power.prearmClamshellOnActive
        }

        if let safetyT = tree["safety"]?.tableValue {
            cfg.safety.minBatteryPercent = safetyT["min_battery_percent"]?.intValue ?? cfg.safety.minBatteryPercent
            cfg.safety.criticalBatteryPercent = safetyT["critical_battery_percent"]?.intValue ?? cfg.safety.criticalBatteryPercent
            cfg.safety.allowOnBattery = safetyT["allow_on_battery"]?.boolValue ?? cfg.safety.allowOnBattery
            cfg.safety.allowThermalSerious = safetyT["allow_thermal_serious"]?.boolValue ?? cfg.safety.allowThermalSerious
            cfg.safety.watchdogHeartbeatSeconds = safetyT["watchdog_heartbeat_seconds"]?.intValue ?? cfg.safety.watchdogHeartbeatSeconds
            cfg.safety.watchdogReleaseAfterSeconds = safetyT["watchdog_release_after_seconds"]?.intValue ?? cfg.safety.watchdogReleaseAfterSeconds
            cfg.safety.activeLeaseTTLSeconds = safetyT["active_lease_ttl_seconds"]?.intValue ?? cfg.safety.activeLeaseTTLSeconds
            cfg.safety.waitingGraceSeconds = safetyT["waiting_grace_seconds"]?.intValue ?? cfg.safety.waitingGraceSeconds
        }

        if let agentsT = tree["agents"]?.tableValue {
            if let codexT = agentsT["codex"]?.tableValue {
                cfg.codex.enabled = codexT["enabled"]?.boolValue ?? cfg.codex.enabled
                cfg.codex.hookMode = codexT["hook_mode"]?.stringValue ?? cfg.codex.hookMode
                cfg.codex.hookTimeoutSeconds = codexT["hook_timeout_seconds"]?.intValue ?? cfg.codex.hookTimeoutSeconds
            }
            if let claudeT = agentsT["claude"]?.tableValue {
                cfg.claude.enabled = claudeT["enabled"]?.boolValue ?? cfg.claude.enabled
                cfg.claude.hookMode = claudeT["hook_mode"]?.stringValue ?? cfg.claude.hookMode
                cfg.claude.hookTimeoutSeconds = claudeT["hook_timeout_seconds"]?.intValue ?? cfg.claude.hookTimeoutSeconds
            }
        }

        return cfg
    }
}
