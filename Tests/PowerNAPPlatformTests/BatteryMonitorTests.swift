import XCTest
@testable import PowerNAPPlatform

final class BatteryMonitorTests: XCTestCase {
    func testSnapshotReturnsValidStatus() {
        let monitor = BatteryMonitor()
        let status = monitor.snapshot()
        if status.hasBattery {
            if let percent = status.percent {
                XCTAssertGreaterThanOrEqual(percent, 0)
                XCTAssertLessThanOrEqual(percent, 100)
            }
        } else {
            XCTAssertTrue(status.isOnAC, "desktop without battery should be on AC")
            XCTAssertNil(status.percent)
        }
    }

    func testSafeForClosedLidOnACAlwaysOK() {
        let monitor = BatteryMonitor()
        let status = monitor.snapshot()
        let result = monitor.safeForClosedLid(minPercent: 20, criticalPercent: 10, allowOnBattery: false)
        if status.isOnAC || !status.hasBattery {
            XCTAssertTrue(result.ok, "on AC or no battery should allow closed lid; got \(result.reason)")
        }
    }

    func testSafeForClosedLidOnBatteryDisallowed() {
        let monitor = BatteryMonitor()
        let status = monitor.snapshot()
        if status.hasBattery && !status.isOnAC {
            let result = monitor.safeForClosedLid(minPercent: 20, criticalPercent: 10, allowOnBattery: false)
            XCTAssertFalse(result.ok)
            XCTAssertTrue(result.reason.contains("battery power disallowed"))
        }
    }

    func testSafeForClosedLidRespectsCriticalThreshold() {
        let monitor = BatteryMonitor()
        let status = monitor.snapshot()
        if status.hasBattery, let percent = status.percent, !status.isOnAC {
            let result = monitor.safeForClosedLid(minPercent: 20, criticalPercent: percent + 10, allowOnBattery: true)
            XCTAssertFalse(result.ok, "threshold above current percent should forbid closed lid")
        }
    }
}
