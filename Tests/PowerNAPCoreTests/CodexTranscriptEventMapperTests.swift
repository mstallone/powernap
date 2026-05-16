import XCTest
@testable import PowerNAPCore

final class CodexTranscriptEventMapperTests: XCTestCase {
    private let cwd = "/Users/stallone/Developer/powernap"

    func testMatchesCliSessionMetaForCurrentWorkingDirectory() {
        let line = #"{"type":"session_meta","payload":{"cwd":"/Users/stallone/Developer/powernap","source":"cli"}}"#
        XCTAssertEqual(CodexTranscriptEventMapper.map(line: line, workingDirectory: cwd), .matchedSession)
    }

    func testRejectsNonCliSessionMetaForCurrentWorkingDirectory() {
        let line = #"{"type":"session_meta","payload":{"cwd":"/Users/stallone/Developer/powernap","source":"desktop"}}"#
        XCTAssertEqual(CodexTranscriptEventMapper.map(line: line, workingDirectory: cwd), .rejectedSession)
    }

    func testMatchesTurnContextForCurrentWorkingDirectory() {
        let line = #"{"type":"turn_context","payload":{"cwd":"/Users/stallone/Developer/powernap"}}"#
        XCTAssertEqual(CodexTranscriptEventMapper.map(line: line, workingDirectory: cwd), .matchedSession)
    }

    func testTaskStartedMapsToUserPromptSubmit() {
        let line = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}"#
        XCTAssertEqual(CodexTranscriptEventMapper.map(line: line, workingDirectory: cwd), .hookEvent("UserPromptSubmit"))
    }

    func testTaskCompleteMapsToStop() {
        let line = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"t1"}}"#
        XCTAssertEqual(CodexTranscriptEventMapper.map(line: line, workingDirectory: cwd), .hookEvent("Stop"))
    }

    func testTurnAbortedMapsToStop() {
        let line = #"{"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#
        XCTAssertEqual(CodexTranscriptEventMapper.map(line: line, workingDirectory: cwd), .hookEvent("Stop"))
    }

    func testIgnoresMalformedLines() {
        XCTAssertNil(CodexTranscriptEventMapper.map(line: "{", workingDirectory: cwd))
    }

    func testIgnoresUnrelatedWorkingDirectory() {
        let line = #"{"type":"session_meta","payload":{"cwd":"/tmp/other","source":"cli"}}"#
        XCTAssertNil(CodexTranscriptEventMapper.map(line: line, workingDirectory: cwd))
    }
}
