import XCTest
@testable import PowerNAPCore

final class ConfigLoaderTests: XCTestCase {

    func testDefaultConfigLoads() throws {
        let cfg = try ConfigLoader.parse(ConfigLoader.defaultTOML)
        XCTAssertTrue(cfg.power.closedLidEnabled)
        XCTAssertTrue(cfg.power.idleSleepAssertion)
        XCTAssertEqual(cfg.power.maxClosedLidMinutes, 720)
        XCTAssertEqual(cfg.safety.minBatteryPercent, 20)
        XCTAssertEqual(cfg.safety.criticalBatteryPercent, 10)
        XCTAssertEqual(cfg.safety.watchdogHeartbeatSeconds, 60)
        XCTAssertEqual(cfg.safety.watchdogReleaseAfterSeconds, 180)
        XCTAssertEqual(cfg.safety.activeLeaseTTLSeconds, 43_200)
        XCTAssertEqual(cfg.codex.hookMode, "global-inert")
        XCTAssertEqual(cfg.claude.hookMode, "per-run-settings")
    }

    func testOverrideBatteryThresholds() throws {
        let cfg = try ConfigLoader.parse("""
        [safety]
        min_battery_percent = 30
        critical_battery_percent = 15
        """)
        XCTAssertEqual(cfg.safety.minBatteryPercent, 30)
        XCTAssertEqual(cfg.safety.criticalBatteryPercent, 15)
    }

    func testAgentOverridesParse() throws {
        let cfg = try ConfigLoader.parse("""
        [agents.codex]
        enabled = false
        hook_timeout_seconds = 7

        [agents.claude]
        hook_mode = "custom-settings"
        """)
        XCTAssertFalse(cfg.codex.enabled)
        XCTAssertEqual(cfg.codex.hookTimeoutSeconds, 7)
        XCTAssertEqual(cfg.claude.hookMode, "custom-settings")
    }

    func testDisabledFeaturesRespected() throws {
        let cfg = try ConfigLoader.parse("""
        [power]
        closed_lid_enabled = false
        """)
        XCTAssertFalse(cfg.power.closedLidEnabled)
    }

    func testPersistenceRoundTrip() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pn-config-test-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try ConfigLoader.writeDefaultIfMissing(to: tmp.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
        let cfg = try ConfigLoader.load(from: tmp.path)
        XCTAssertTrue(cfg.power.closedLidEnabled)
    }

    func testMissingFileReturnsDefault() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pn-missing-\(UUID().uuidString).toml").path
        let cfg = try ConfigLoader.load(from: tmp)
        XCTAssertEqual(cfg, Config.default)
    }
}
