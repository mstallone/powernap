import XCTest
@testable import PowerNAPCore

final class LeaseTests: XCTestCase {

    func testFreshLeaseIsNotExpired() {
        let l = Lease(runId: "r1", leaseType: .idleSleep, expiresAt: Date().addingTimeInterval(60))
        XCTAssertFalse(l.isExpired)
        XCTAssertFalse(l.isReleased)
    }

    func testPastExpiryIsExpired() {
        let l = Lease(runId: "r1", leaseType: .clamshellSleep, expiresAt: Date().addingTimeInterval(-1))
        XCTAssertTrue(l.isExpired)
    }

    func testReleasedLeaseIsNotExpiredEvenIfPastTime() {
        let l = Lease(
            runId: "r1",
            leaseType: .idleSleep,
            expiresAt: Date().addingTimeInterval(-10),
            releasedAt: Date(),
            releaseReason: .turnIdle
        )
        XCTAssertTrue(l.isReleased)
        XCTAssertFalse(l.isExpired)
    }

    func testOptionalRunIdPreserved() {
        let l = Lease(runId: nil, leaseType: .idleSleep, expiresAt: Date().addingTimeInterval(60))
        XCTAssertNil(l.runId)
    }

    func testCodableRoundTrip() throws {
        let l = Lease(
            runId: "r1",
            leaseType: .clamshellSleep,
            acquiredAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200),
            heartbeatAt: Date(timeIntervalSince1970: 150),
            releasedAt: nil,
            releaseReason: nil,
            metadata: ["run": "abc"]
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let data = try enc.encode(l)
        let back = try dec.decode(Lease.self, from: data)
        XCTAssertEqual(back.id, l.id)
        XCTAssertEqual(back.runId, "r1")
        XCTAssertEqual(back.leaseType, .clamshellSleep)
        XCTAssertEqual(back.acquiredAt, l.acquiredAt)
        XCTAssertEqual(back.expiresAt, l.expiresAt)
        XCTAssertEqual(back.heartbeatAt, l.heartbeatAt)
        XCTAssertEqual(back.metadata["run"], "abc")
    }

    func testAllLeaseTypesHaveStableRawValues() {
        XCTAssertEqual(LeaseType.idleSleep.rawValue, "idle_sleep")
        XCTAssertEqual(LeaseType.clamshellSleep.rawValue, "clamshell_sleep")
    }

    func testAllReleaseReasonsStable() {
        XCTAssertEqual(LeaseReleaseReason.turnIdle.rawValue, "turn_idle")
        XCTAssertEqual(LeaseReleaseReason.sessionEnd.rawValue, "session_end")
        XCTAssertEqual(LeaseReleaseReason.processExit.rawValue, "process_exit")
        XCTAssertEqual(LeaseReleaseReason.ttlExpired.rawValue, "ttl_expired")
        XCTAssertEqual(LeaseReleaseReason.safetyCutoff.rawValue, "safety_cutoff")
        XCTAssertEqual(LeaseReleaseReason.watchdog.rawValue, "watchdog")
    }
}
