import XCTest
@testable import PowerNAPCore

final class ConfigLoaderTests: XCTestCase {

    func testDefaultConfigLoads() throws {
        let cfg = try ConfigLoader.parse(ConfigLoader.defaultTOML)
        XCTAssertTrue(cfg.power.closedLidEnabled)
        XCTAssertTrue(cfg.power.idleSleepAssertion)
        XCTAssertEqual(cfg.safety.minBatteryPercent, 20)
        XCTAssertEqual(cfg.safety.criticalBatteryPercent, 10)
        XCTAssertEqual(cfg.safety.watchdogHeartbeatSeconds, 60)
        XCTAssertEqual(cfg.safety.watchdogReleaseAfterSeconds, 180)
        XCTAssertTrue(cfg.network.enabled)
        XCTAssertTrue(cfg.network.preferUSBTether)
        XCTAssertEqual(cfg.codex.hookMode, "global-inert")
        XCTAssertEqual(cfg.claude.hookMode, "per-run-settings")
        XCTAssertFalse(cfg.premium.enabled)
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

    func testHotspotsArrayParses() throws {
        let cfg = try ConfigLoader.parse("""
        [[network.hotspots]]
        ssid = "Home"
        keychain_account = "PowerNAP Hotspot Home"

        [[network.hotspots]]
        ssid = "Office"
        """)
        XCTAssertEqual(cfg.network.hotspots.count, 2)
        XCTAssertEqual(cfg.network.hotspots[0].ssid, "Home")
        XCTAssertEqual(cfg.network.hotspots[0].keychainAccount, "PowerNAP Hotspot Home")
        XCTAssertEqual(cfg.network.hotspots[1].ssid, "Office")
    }

    func testProbeEndpointsParse() throws {
        let cfg = try ConfigLoader.parse("""
        [network]
        probe_endpoints = ["https://example.com"]
        """)
        XCTAssertEqual(cfg.network.probeEndpoints, ["https://example.com"])
    }

    func testDisabledFeaturesRespected() throws {
        let cfg = try ConfigLoader.parse("""
        [power]
        closed_lid_enabled = false

        [network]
        enabled = false
        """)
        XCTAssertFalse(cfg.power.closedLidEnabled)
        XCTAssertFalse(cfg.network.enabled)
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
