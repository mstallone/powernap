import XCTest
@testable import PowerNAPCore

final class IPCProtocolTests: XCTestCase {

    func testRequestEncodingIncludesSchemaVersion() throws {
        let req = IPCRequest(body: .ping)
        let data = try FrameCodec.encode(req)
        let payload = data.subdata(in: 4..<data.count)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: payload, options: []) as? [String: Any])
        XCTAssertEqual(obj["version"] as? Int, Int(IPCProtocol.schemaVersion))
    }

    func testAllRequestBodiesEncode() throws {
        let bodies: [IPCRequest.Body] = [
            .ping,
            .status,
            .listLeases,
            .listSessions,
            .networkStatus,
            .networkPreferUSB,
            .networkPreferBluetoothPAN,
            .networkRestore,
            .restore(reason: "test")
        ]
        for body in bodies {
            let req = IPCRequest(body: body)
            let data = try FrameCodec.encode(req)
            XCTAssertGreaterThan(data.count, 4)
        }
    }

    func testAckResponse() throws {
        let resp = IPCResponse(body: .ack)
        let data = try FrameCodec.encode(resp)
        let payload = data.subdata(in: 4..<data.count)
        let back = try FrameCodec.decode(IPCResponse.self, from: payload)
        if case .ack = back.body {} else { XCTFail("expected ack") }
    }

    func testErrorResponsePreservesCodeAndMessage() throws {
        let resp = IPCResponse(body: .error(code: "AUTH", message: "invalid token"))
        let data = try FrameCodec.encode(resp)
        let payload = data.subdata(in: 4..<data.count)
        let back = try FrameCodec.decode(IPCResponse.self, from: payload)
        guard case .error(let c, let m) = back.body else { XCTFail("expected error"); return }
        XCTAssertEqual(c, "AUTH")
        XCTAssertEqual(m, "invalid token")
    }

    func testNetworkStatusPayloadRoundTrip() throws {
        let net = NetworkStatusPayload(
            primaryInterface: "en0",
            primaryService: "Wi-Fi",
            path: "satisfied",
            services: [
                NetworkStatusPayload.Service(name: "Wi-Fi", interface: "en0", active: true, enabled: true),
                NetworkStatusPayload.Service(name: "iPhone USB", interface: "en6", active: false, enabled: true)
            ],
            hotspotConfigured: true,
            usbTetherPresent: true,
            probeResults: ["https://api.openai.com": "ok:42ms"],
            serviceOrderSnapshot: ["Wi-Fi", "iPhone USB"],
            failoverActive: false
        )
        let resp = IPCResponse(body: .network(net))
        let data = try FrameCodec.encode(resp)
        let payload = data.subdata(in: 4..<data.count)
        let back = try FrameCodec.decode(IPCResponse.self, from: payload)
        guard case .network(let n) = back.body else { XCTFail("expected network"); return }
        XCTAssertEqual(n.primaryInterface, "en0")
        XCTAssertEqual(n.services.count, 2)
        XCTAssertEqual(n.probeResults["https://api.openai.com"], "ok:42ms")
        XCTAssertEqual(n.serviceOrderSnapshot, ["Wi-Fi", "iPhone USB"])
    }

    func testMaxFrameBoundaryAccepted() throws {
        let headroom = 64
        let safeSize = Int(IPCProtocol.maxFrameBytes) - headroom
        struct S: Codable { let s: String }
        let safe = String(repeating: "x", count: safeSize)
        let data = try FrameCodec.encode(S(s: safe))
        XCTAssertLessThanOrEqual(data.count, Int(IPCProtocol.maxFrameBytes) + 4)
    }
}
