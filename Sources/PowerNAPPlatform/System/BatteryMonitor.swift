import Foundation
import IOKit
import IOKit.ps
import Logging

public struct BatteryStatus: Sendable {
    public var hasBattery: Bool
    public var percent: Int?
    public var isCharging: Bool?
    public var isOnAC: Bool
    public var timeToEmptyMinutes: Int?
    public var timeToFullMinutes: Int?
}

public final class BatteryMonitor {
    private let logger: Logger

    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "dev.powernap.system.battery")
    }

    public func snapshot() -> BatteryStatus {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return BatteryStatus(hasBattery: false, percent: nil, isCharging: nil, isOnAC: true, timeToEmptyMinutes: nil, timeToFullMinutes: nil)
        }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatteryStatus(hasBattery: false, percent: nil, isCharging: nil, isOnAC: true, timeToEmptyMinutes: nil, timeToFullMinutes: nil)
        }
        for src in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = info[kIOPSTypeKey] as? String
            if type != kIOPSInternalBatteryType {
                continue
            }
            let capacity = info[kIOPSCurrentCapacityKey] as? Int
            let max = info[kIOPSMaxCapacityKey] as? Int
            let charging = info[kIOPSIsChargingKey] as? Bool
            let state = info[kIOPSPowerSourceStateKey] as? String
            let onAC = state == kIOPSACPowerValue
            let timeToEmpty = info[kIOPSTimeToEmptyKey] as? Int
            let timeToFull = info[kIOPSTimeToFullChargeKey] as? Int
            var percent: Int?
            if let capacity, let max, max > 0 {
                percent = Int((Double(capacity) / Double(max)) * 100.0)
            } else if let capacity {
                percent = capacity
            }
            return BatteryStatus(
                hasBattery: true,
                percent: percent,
                isCharging: charging,
                isOnAC: onAC,
                timeToEmptyMinutes: timeToEmpty.flatMap { $0 < 0 ? nil : $0 },
                timeToFullMinutes: timeToFull.flatMap { $0 < 0 ? nil : $0 }
            )
        }
        return BatteryStatus(hasBattery: false, percent: nil, isCharging: nil, isOnAC: true, timeToEmptyMinutes: nil, timeToFullMinutes: nil)
    }

    public func safeForClosedLid(minPercent: Int, criticalPercent: Int, allowOnBattery: Bool) -> (ok: Bool, reason: String) {
        let s = snapshot()
        if !s.hasBattery { return (true, "no internal battery present") }
        if s.isOnAC { return (true, "on AC") }
        if !allowOnBattery { return (false, "battery power disallowed by policy") }
        if let p = s.percent {
            if p <= criticalPercent { return (false, "battery at critical (\(p)%)") }
            if p < minPercent { return (false, "battery below threshold (\(p)% < \(minPercent)%)") }
            return (true, "battery at \(p)%")
        }
        return (true, "battery level unknown, proceeding")
    }
}
