import XCTest
@testable import PowerNAPPlatform

final class PTYSessionTests: XCTestCase {
    func testSpawnTrueExitsZero() throws {
        let session = PTYSession()
        let opts = PTYSession.SpawnOptions(executable: "/usr/bin/true", arguments: [])
        try session.spawn(opts)
        XCTAssertGreaterThan(session.pid, 0)
        XCTAssertTrue(session.isRunning)
        let code = session.wait()
        XCTAssertEqual(code, 0)
        XCTAssertEqual(session.exitStatus, 0)
        XCTAssertFalse(session.isRunning)
        session.close()
    }

    func testSpawnFalseExitsNonZero() throws {
        let session = PTYSession()
        let opts = PTYSession.SpawnOptions(executable: "/usr/bin/false", arguments: [])
        try session.spawn(opts)
        let code = session.wait()
        XCTAssertNotEqual(code, 0)
        session.close()
    }

    func testSpawnNonexistentThrows() {
        let session = PTYSession()
        let opts = PTYSession.SpawnOptions(executable: "/nope/does/not/exist-\(UUID().uuidString)", arguments: [])
        XCTAssertThrowsError(try session.spawn(opts))
    }

    func testSpawnCatReadsStdinFromPTY() throws {
        let session = PTYSession()
        let opts = PTYSession.SpawnOptions(executable: "/bin/cat", arguments: ["/etc/hosts"])
        try session.spawn(opts)
        XCTAssertGreaterThan(session.pid, 0)
        XCTAssertGreaterThanOrEqual(session.masterFD, 0)

        let fd = session.masterFD
        let deadline = Date().addingTimeInterval(5)
        var got = Data()
        let bufSize = 4096
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        while Date() < deadline {
            if let status = session.tryReap() {
                _ = status
                break
            }
            var pollRead = fd_set()
            FDSetHelper.zero(&pollRead)
            FDSetHelper.set(fd, in: &pollRead)
            var tv = timeval(tv_sec: 0, tv_usec: 200_000)
            let rc = select(fd + 1, &pollRead, nil, nil, &tv)
            if rc > 0 {
                let n = read(fd, buf, bufSize)
                if n > 0 {
                    got.append(buf, count: n)
                } else if n == 0 {
                    break
                }
            }
        }
        _ = session.wait()
        session.close()
        XCTAssertFalse(got.isEmpty, "cat should have produced output from /etc/hosts")
    }

    func testTryReapReturnsNilWhileRunning() throws {
        let session = PTYSession()
        let opts = PTYSession.SpawnOptions(executable: "/bin/sleep", arguments: ["2"])
        try session.spawn(opts)
        XCTAssertNil(session.tryReap())
        session.sendSignal(SIGKILL)
        _ = session.wait()
        session.close()
    }

    func testOutputNewlineDetectionTreatsOnlyLineFeedAsComplete() {
        XCTAssertFalse(PTYRelay.outputNeedsTrailingNewline(after: nil))
        XCTAssertFalse(PTYRelay.outputNeedsTrailingNewline(after: UInt8(ascii: "\n")))
        XCTAssertTrue(PTYRelay.outputNeedsTrailingNewline(after: UInt8(ascii: "\r")))
        XCTAssertTrue(PTYRelay.outputNeedsTrailingNewline(after: UInt8(ascii: " ")))
    }
}

enum FDSetHelper {
    static func zero(_ set: inout fd_set) {
        set = fd_set()
    }

    static func set(_ fd: Int32, in set: inout fd_set) {
        let intOffset = Int(fd / 32)
        let bitOffset = Int(fd % 32)
        let mask: Int32 = 1 << bitOffset
        withUnsafeMutablePointer(to: &set.fds_bits) { tuplePtr in
            tuplePtr.withMemoryRebound(to: Int32.self, capacity: 32) { ptr in
                ptr[intOffset] |= mask
            }
        }
    }
}
