import XCTest
@testable import PowerNAPPlatform

final class ThermalMonitorTests: XCTestCase {
    func testSnapshotReturnsKnownState() {
        let monitor = ThermalMonitor()
        let snapshot = monitor.snapshot()
        let allowed: Set<ThermalStatus.State> = [.nominal, .fair, .serious, .critical, .unknown]
        XCTAssertTrue(allowed.contains(snapshot.state))
    }

    func testSafeForClosedLidNominalAlwaysOK() {
        let monitor = ThermalMonitor()
        let snapshot = monitor.snapshot()
        let result = monitor.safeForClosedLid(allowSerious: false)
        switch snapshot.state {
        case .nominal, .fair:
            XCTAssertTrue(result.ok, "nominal/fair should allow closed lid; got \(result.reason)")
        case .critical:
            XCTAssertFalse(result.ok, "critical should forbid closed lid")
        case .serious:
            XCTAssertFalse(result.ok, "serious with allowSerious=false should forbid closed lid")
        case .unknown:
            XCTAssertTrue(result.ok)
        }
    }

    func testSafeForClosedLidSeriousWithAllow() {
        let monitor = ThermalMonitor()
        let snapshot = monitor.snapshot()
        if snapshot.state == .serious {
            let result = monitor.safeForClosedLid(allowSerious: true)
            XCTAssertTrue(result.ok)
        }
    }
}
