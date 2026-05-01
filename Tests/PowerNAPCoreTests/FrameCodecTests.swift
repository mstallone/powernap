import XCTest
@testable import PowerNAPCore

final class FrameCodecTests: XCTestCase {

    func testEncodeDecodeSimpleRequest() throws {
        let req = IPCRequest(body: .ping)
        let data = try FrameCodec.encode(req)
        XCTAssertGreaterThan(data.count, 4)
        let header = data.prefix(4)
        let length = (UInt32(header[0]) << 24) | (UInt32(header[1]) << 16) | (UInt32(header[2]) << 8) | UInt32(header[3])
        XCTAssertEqual(Int(length), data.count - 4)
        let payload = data.subdata(in: 4..<data.count)
        let decoded = try FrameCodec.decode(IPCRequest.self, from: payload)
        if case .ping = decoded.body {} else {
            XCTFail("expected .ping, got \(decoded.body)")
        }
        XCTAssertEqual(decoded.version, IPCProtocol.schemaVersion)
    }

    func testRoundTripHookEvent() throws {
        let input = HookEventMapper.Input(
            agent: "claude",
            runId: UUID().uuidString,
            sessionId: "s1",
            turnId: "t1",
            event: "UserPromptSubmit",
            cwd: "/Users/test",
            toolName: nil,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            extra: ["k": "v"]
        )
        let req = IPCRequest(token: "secret", body: .hookEvent(input))
        let data = try FrameCodec.encode(req)
        let payload = data.subdata(in: 4..<data.count)
        let decoded = try FrameCodec.decode(IPCRequest.self, from: payload)
        guard case .hookEvent(let out) = decoded.body else {
            XCTFail("expected hookEvent"); return
        }
        XCTAssertEqual(out.agent, "claude")
        XCTAssertEqual(out.runId, input.runId)
        XCTAssertEqual(out.sessionId, "s1")
        XCTAssertEqual(out.turnId, "t1")
        XCTAssertEqual(out.event, "UserPromptSubmit")
        XCTAssertEqual(out.cwd, "/Users/test")
        XCTAssertEqual(out.timestamp?.timeIntervalSince1970, 1_700_000_000)
        XCTAssertEqual(out.extra?["k"], "v")
        XCTAssertEqual(decoded.token, "secret")
    }

    func testRoundTripStatusResponse() throws {
        let status = StatusPayload(
            daemonRunning: true,
            sessions: [
                StatusPayload.ActiveSession(
                    runId: "r1", agent: "codex", phase: .active, startedAt: Date(timeIntervalSince1970: 1), lastEventAt: nil, pid: 123
                )
            ],
            leases: [
                StatusPayload.LeaseInfo(leaseType: "idle_sleep", held: true, expiresAt: Date(timeIntervalSince1970: 2))
            ],
            safety: StatusPayload.SafetyInfo(batteryPercent: 80, charging: true, thermalState: "nominal"),
            network: StatusPayload.NetworkInfo(primary: "en0", health: "ok", route: nil, lastProbe: nil)
        )
        let resp = IPCResponse(requestId: "r-123", body: .status(status))
        let data = try FrameCodec.encode(resp)
        let payload = data.subdata(in: 4..<data.count)
        let decoded = try FrameCodec.decode(IPCResponse.self, from: payload)
        guard case .status(let s) = decoded.body else { XCTFail("expected status"); return }
        XCTAssertTrue(s.daemonRunning)
        XCTAssertEqual(s.sessions.count, 1)
        XCTAssertEqual(s.sessions[0].runId, "r1")
        XCTAssertEqual(s.sessions[0].phase, .active)
        XCTAssertEqual(s.leases[0].leaseType, "idle_sleep")
        XCTAssertEqual(s.safety.batteryPercent, 80)
        XCTAssertEqual(s.network.primary, "en0")
        XCTAssertEqual(decoded.requestId, "r-123")
    }

    func testFrameTooLargeThrows() throws {
        struct Huge: Codable { let s: String }
        let big = String(repeating: "A", count: Int(IPCProtocol.maxFrameBytes) + 10)
        XCTAssertThrowsError(try FrameCodec.encode(Huge(s: big))) { err in
            if case FrameCodec.Error.frameTooLarge = err {} else {
                XCTFail("expected frameTooLarge, got \(err)")
            }
        }
    }

    func testBigEndianLengthFormatting() throws {
        struct Small: Codable { let x: Int }
        let data = try FrameCodec.encode(Small(x: 7))
        let header = data.prefix(4)
        let expected = UInt32(data.count - 4).bigEndian
        var found: UInt32 = 0
        withUnsafeMutableBytes(of: &found) { raw in
            for (i, b) in header.enumerated() { raw[i] = b }
        }
        XCTAssertEqual(found, expected)
    }

    func testDecodeFailureReportsUnderlyingError() {
        let invalid = Data("not json".utf8)
        XCTAssertThrowsError(try FrameCodec.decode(IPCRequest.self, from: invalid)) { err in
            if case FrameCodec.Error.decodingFailed = err {} else {
                XCTFail("expected decodingFailed, got \(err)")
            }
        }
    }
}
