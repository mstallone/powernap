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

    public struct Hotspot: Sendable, Equatable {
        public var ssid: String
        public var keychainAccount: String?

        public init(ssid: String, keychainAccount: String? = nil) {
            self.ssid = ssid
            self.keychainAccount = keychainAccount ?? "PowerNAP Hotspot \(ssid)"
        }
    }

    public struct Network: Sendable, Equatable {
        public var enabled: Bool
        public var allowCellular: Bool
        public var preferUSBTether: Bool
        public var allowWiFiHotspot: Bool
        public var allowBluetoothPAN: Bool
        public var restoreServiceOrder: Bool
        public var keepTetherUntilTurnDone: Bool
        public var maxCellularMBPerSession: Int
        public var hotspots: [Hotspot]
        public var probeEndpoints: [String]

        public init(
            enabled: Bool = true,
            allowCellular: Bool = true,
            preferUSBTether: Bool = true,
            allowWiFiHotspot: Bool = true,
            allowBluetoothPAN: Bool = false,
            restoreServiceOrder: Bool = true,
            keepTetherUntilTurnDone: Bool = true,
            maxCellularMBPerSession: Int = 2048,
            hotspots: [Hotspot] = [],
            probeEndpoints: [String] = [
                "https://api.openai.com",
                "https://chatgpt.com",
                "https://api.anthropic.com",
                "https://claude.ai"
            ]
        ) {
            self.enabled = enabled
            self.allowCellular = allowCellular
            self.preferUSBTether = preferUSBTether
            self.allowWiFiHotspot = allowWiFiHotspot
            self.allowBluetoothPAN = allowBluetoothPAN
            self.restoreServiceOrder = restoreServiceOrder
            self.keepTetherUntilTurnDone = keepTetherUntilTurnDone
            self.maxCellularMBPerSession = maxCellularMBPerSession
            self.hotspots = hotspots
            self.probeEndpoints = probeEndpoints
        }
    }

    public struct AgentConfig: Sendable, Equatable {
        public var enabled: Bool
        public var hookMode: String
        public var proxyMode: String
        public var hookTimeoutSeconds: Int

        public init(enabled: Bool = true, hookMode: String, proxyMode: String = "env", hookTimeoutSeconds: Int = 2) {
            self.enabled = enabled
            self.hookMode = hookMode
            self.proxyMode = proxyMode
            self.hookTimeoutSeconds = hookTimeoutSeconds
        }
    }

    public struct Premium: Sendable, Equatable {
        public var enabled: Bool
        public var relayURL: String
        public var mode: String

        public init(enabled: Bool = false, relayURL: String = "", mode: String = "stable-egress") {
            self.enabled = enabled
            self.relayURL = relayURL
            self.mode = mode
        }
    }

    public var power: Power
    public var safety: Safety
    public var network: Network
    public var codex: AgentConfig
    public var claude: AgentConfig
    public var premium: Premium

    public init(
        power: Power = Power(),
        safety: Safety = Safety(),
        network: Network = Network(),
        codex: AgentConfig = AgentConfig(hookMode: "global-inert"),
        claude: AgentConfig = AgentConfig(hookMode: "per-run-settings"),
        premium: Premium = Premium()
    ) {
        self.power = power
        self.safety = safety
        self.network = network
        self.codex = codex
        self.claude = claude
        self.premium = premium
    }

    public static let `default` = Config()
}
