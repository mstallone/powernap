import XCTest
@testable import PowerNAPCore

final class TOMLMiniTests: XCTestCase {

    func testParseSimpleKeyValues() throws {
        let t = try TOMLMini.parse("""
        name = "hello"
        n = 42
        flag = true
        pi = 3.14
        """)
        XCTAssertEqual(t["name"]?.stringValue, "hello")
        XCTAssertEqual(t["n"]?.intValue, 42)
        XCTAssertEqual(t["flag"]?.boolValue, true)
        if case .double(let d) = t["pi"] ?? .bool(false) {
            XCTAssertEqual(d, 3.14, accuracy: 0.001)
        } else {
            XCTFail("expected double")
        }
    }

    func testParseTables() throws {
        let t = try TOMLMini.parse("""
        [power]
        closed_lid_enabled = true

        [safety]
        min_battery_percent = 15
        """)
        XCTAssertEqual(t["power"]?.tableValue?["closed_lid_enabled"]?.boolValue, true)
        XCTAssertEqual(t["safety"]?.tableValue?["min_battery_percent"]?.intValue, 15)
    }

    func testParseNestedTables() throws {
        let t = try TOMLMini.parse("""
        [agents.codex]
        enabled = true
        hook_mode = "global-inert"
        """)
        let agents = t["agents"]?.tableValue
        let codex = agents?["codex"]?.tableValue
        XCTAssertEqual(codex?["enabled"]?.boolValue, true)
        XCTAssertEqual(codex?["hook_mode"]?.stringValue, "global-inert")
    }

    func testParseArrays() throws {
        let t = try TOMLMini.parse("""
        endpoints = ["https://a.com", "https://b.com"]
        """)
        let arr = t["endpoints"]?.arrayValue
        XCTAssertEqual(arr?.count, 2)
        XCTAssertEqual(arr?[0].stringValue, "https://a.com")
    }

    func testParseArrayTables() throws {
        let t = try TOMLMini.parse("""
        [[hooks.events]]
        name = "SessionStart"
        phase = "starting"

        [[hooks.events]]
        name = "SessionEnd"
        """)
        let hooks = t["hooks"]?.tableValue
        let events = hooks?["events"]?.arrayValue
        XCTAssertEqual(events?.count, 2)
        XCTAssertEqual(events?[0].tableValue?["name"]?.stringValue, "SessionStart")
        XCTAssertEqual(events?[0].tableValue?["phase"]?.stringValue, "starting")
        XCTAssertEqual(events?[1].tableValue?["name"]?.stringValue, "SessionEnd")
    }

    func testStripsInlineComments() throws {
        let t = try TOMLMini.parse("""
        # top comment
        k = 1 # inline
        s = "a # not a comment"
        """)
        XCTAssertEqual(t["k"]?.intValue, 1)
        XCTAssertEqual(t["s"]?.stringValue, "a # not a comment")
    }

    func testEmptyInputReturnsEmpty() throws {
        let t = try TOMLMini.parse("")
        XCTAssertTrue(t.isEmpty)
    }

    func testSyntaxError() {
        XCTAssertThrowsError(try TOMLMini.parse("k"))
    }

    func testStringEscapes() throws {
        let t = try TOMLMini.parse(#"""
        s = "a\nb\t\"c\""
        """#)
        XCTAssertEqual(t["s"]?.stringValue, "a\nb\t\"c\"")
    }
}
