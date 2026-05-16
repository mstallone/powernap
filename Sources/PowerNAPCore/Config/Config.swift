import Foundation

public struct Config: Sendable, Equatable {
    public struct Power: Sendable, Equatable {
        public var closedLidEnabled: Bool
        public var idleSleepAssertion: Bool
        public var maxClosedLidMinutes: Int
        public var releaseWhenWaiting: Bool
        public var prearmClamshellOnActive: Bool

        public init(
            closedLidEnabled: Bool = true,
            idleSleepAssertion: Bool = true,
            maxClosedLidMinutes: Int = 120,
            releaseWhenWaiting: Bool = true,
            prearmClamshellOnActive: Bool = true
        ) {
            self.closedLidEnabled = closedLidEnabled
            self.idleSleepAssertion = idleSleepAssertion
            self.maxClosedLidMinutes = maxClosedLidMinutes
            self.releaseWhenWaiting = releaseWhenWaiting
            self.prearmClamshellOnActive = prearmClamshellOnActive
        }
    }

    public struct Safety: Sendable, Equatable {
        public var minBatteryPercent: Int
        public var criticalBatteryPercent: Int
        public var allowOnBattery: Bool
        public var allowThermalSerious: Bool
        public var watchdogHeartbeatSeconds: Int
        public var watchdogReleaseAfterSeconds: Int
        public var activeLeaseTTLSeconds: Int
        public var waitingGraceSeconds: Int

        public init(
            minBatteryPercent: Int = 20,
            criticalBatteryPercent: Int = 10,
            allowOnBattery: Bool = true,
            allowThermalSerious: Bool = false,
            watchdogHeartbeatSeconds: Int = 60,
            watchdogReleaseAfterSeconds: Int = 180,
            activeLeaseTTLSeconds: Int = 1800,
            waitingGraceSeconds: Int = 20
        ) {
            self.minBatteryPercent = minBatteryPercent
            self.criticalBatteryPercent = criticalBatteryPercent
            self.allowOnBattery = allowOnBattery
            self.allowThermalSerious = allowThermalSerious
            self.watchdogHeartbeatSeconds = watchdogHeartbeatSeconds
            self.watchdogReleaseAfterSeconds = watchdogReleaseAfterSeconds
            self.activeLeaseTTLSeconds = activeLeaseTTLSeconds
            self.waitingGraceSeconds = waitingGraceSeconds
        }
    }

    public struct AgentConfig: Sendable, Equatable {
        public var enabled: Bool
        public var hookMode: String
        public var hookTimeoutSeconds: Int

        public init(enabled: Bool = true, hookMode: String, hookTimeoutSeconds: Int = 2) {
            self.enabled = enabled
            self.hookMode = hookMode
            self.hookTimeoutSeconds = hookTimeoutSeconds
        }
    }

    public var power: Power
    public var safety: Safety
    public var codex: AgentConfig
    public var claude: AgentConfig

    public init(
        power: Power = Power(),
        safety: Safety = Safety(),
        codex: AgentConfig = AgentConfig(hookMode: "global-inert"),
        claude: AgentConfig = AgentConfig(hookMode: "per-run-settings")
    ) {
        self.power = power
        self.safety = safety
        self.codex = codex
        self.claude = claude
    }

    public static let `default` = Config()
}
