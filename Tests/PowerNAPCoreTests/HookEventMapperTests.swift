import XCTest
@testable import PowerNAPCore

final class HookEventMapperTests: XCTestCase {

    private func input(event: String, agent: String? = "codex") -> HookEventMapper.Input {
        HookEventMapper.Input(agent: agent, runId: "r1", event: event)
    }

    func testSessionStartMapsToStarting() {
        XCTAssertEqual(HookEventMapper.normalize(input(event: "SessionStart")).phase, .starting)
    }

    func testUserPromptSubmitMapsToActive() {
        XCTAssertEqual(HookEventMapper.normalize(input(event: "UserPromptSubmit")).phase, .active)
    }

    func testToolUseMapsToActive() {
        XCTAssertEqual(HookEventMapper.normalize(input(event: "PreToolUse")).phase, .active)
        XCTAssertEqual(HookEventMapper.normalize(input(event: "PostToolUse")).phase, .active)
    }

    func testPermissionRequestMapsToWaiting() {
        XCTAssertEqual(HookEventMapper.normalize(input(event: "PermissionRequest")).phase, .waiting)
    }

    func testClaudeElicitationMapsToWaiting() {
        XCTAssertEqual(HookEventMapper.normalize(input(event: "Elicitation", agent: "claude")).phase, .waiting)
    }

    func testNotificationMapsToWaiting() {
        XCTAssertEqual(HookEventMapper.normalize(input(event: "Notification")).phase, .waiting)
    }

    func testStopMapsToTurnIdle() {
        XCTAssertEqual(HookEventMapper.normalize(input(event: "Stop")).phase, .turnIdle)
    }

    func testClaudeTeammateIdleMapsToTurnIdle() {
        XCTAssertEqual(HookEventMapper.normalize(input(event: "TeammateIdle", agent: "claude")).phase, .turnIdle)
    }

    func testSessionEndMapsToDone() {
        XCTAssertEqual(HookEventMapper.normalize(input(event: "SessionEnd")).phase, .done)
    }

    func testClaudeStopFailureMapsToError() {
        XCTAssertEqual(HookEventMapper.normalize(input(event: "StopFailure", agent: "claude")).phase, .error)
    }

    func testProcessExitMapsToDone() {
        XCTAssertEqual(HookEventMapper.normalize(input(event: "ProcessExit")).phase, .done)
    }

    func testProcessErrorMapsToError() {
        XCTAssertEqual(HookEventMapper.normalize(input(event: "ProcessError")).phase, .error)
    }

    func testUnknownEventDefaultsToActive() {
        XCTAssertEqual(HookEventMapper.normalize(input(event: "MysteryEvent")).phase, .active)
    }

    func testDefaultAgentWhenMissing() {
        let e = HookEventMapper.normalize(
            HookEventMapper.Input(agent: nil, runId: "r1", event: "SessionStart")
        )
        XCTAssertEqual(e.agent, "generic")
    }

    func testPreservesRunIdAndSessionAndTurn() {
        let i = HookEventMapper.Input(
            agent: "codex",
            runId: "run-abc",
            sessionId: "sess-123",
            turnId: "turn-9",
            event: "PreToolUse",
            cwd: "/tmp",
            toolName: "bash",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let e = HookEventMapper.normalize(i)
        XCTAssertEqual(e.runId, "run-abc")
        XCTAssertEqual(e.sessionId, "sess-123")
        XCTAssertEqual(e.turnId, "turn-9")
        XCTAssertEqual(e.cwd, "/tmp")
        XCTAssertEqual(e.toolName, "bash")
        XCTAssertEqual(e.sourceEvent, "PreToolUse")
    }
}
