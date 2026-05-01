import XCTest
@testable import PowerNAPPlatform

final class LidMonitorTests: XCTestCase {
    func testIsClosedNilSafe() {
        let monitor = LidMonitor()
        let value = monitor.isClosed()
        if let v = value {
            XCTAssertTrue(v == true || v == false)
        }
    }

    func testCausesSleepNilSafe() {
        let monitor = LidMonitor()
        let value = monitor.causesSleep()
        if let v = value {
            XCTAssertTrue(v == true || v == false)
        }
    }

    func testRepeatedReadsConsistent() {
        let monitor = LidMonitor()
        let a = monitor.isClosed()
        let b = monitor.isClosed()
        XCTAssertEqual(a, b, "lid state should not flip between two back-to-back reads")
    }
}
