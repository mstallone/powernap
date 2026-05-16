import XCTest
@testable import PowerNAPCore

final class HookInstallerTests: XCTestCase {

    private var fakeHome: URL!

    override func setUp() {
        super.setUp()
        fakeHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pn-hook-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
    }

    override func tearDown() {
        super.tearDown()
        if let h = fakeHome { try? FileManager.default.removeItem(at: h) }
    }

    func testCodexInstallCreatesFileWithAllEventsNested() throws {
        let r = try CodexHookInstaller.install(hookBinaryPath: "/usr/local/bin/powernap-hook", home: fakeHome.path)
        XCTAssertFalse(r.wasAlreadyInstalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.path))

        let data = try Data(contentsOf: URL(fileURLWithPath: r.path))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])
        let hooksRoot = try XCTUnwrap(obj["hooks"] as? [String: Any])

        XCTAssertEqual(Set(hooksRoot.keys), Set(CodexHookInstaller.allEvents))

        for event in CodexHookInstaller.allEvents {
            let groups = try XCTUnwrap(hooksRoot[event] as? [[String: Any]], "event \(event)")
            XCTAssertEqual(groups.count, 1, "event \(event) should have exactly one matcher group")
            let group = groups[0]
            let handlers = try XCTUnwrap(group["hooks"] as? [[String: Any]])
            XCTAssertEqual(handlers.count, 1)
            let handler = handlers[0]
            XCTAssertEqual(handler["type"] as? String, "command")
            XCTAssertEqual(handler["command"] as? String, "/usr/local/bin/powernap-hook")
            XCTAssertEqual(handler["timeout"] as? Int, 2)
        }
    }

    func testCodexInstallWritesConfigTomlFeatureFlag() throws {
        let r = try CodexHookInstaller.install(hookBinaryPath: "/usr/local/bin/powernap-hook", home: fakeHome.path)
        XCTAssertTrue(r.configTomlModified)
        let tomlData = try Data(contentsOf: URL(fileURLWithPath: r.configTomlPath))
        let s = String(data: tomlData, encoding: .utf8) ?? ""
        let parsed = try TOMLMini.parse(s)
        let features = try XCTUnwrap(parsed["features"]?.tableValue)
        XCTAssertEqual(features["hooks"]?.boolValue, true)
        XCTAssertNil(features["codex_hooks"])
    }

    func testCodexInstallPreservesExistingConfigTomlContent() throws {
        let tomlPath = CodexHookInstaller.configTomlPath(home: fakeHome.path)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: tomlPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingToml = """
        model = "gpt-4"

        [profile]
        name = "default"
        """
        try existingToml.write(to: URL(fileURLWithPath: tomlPath), atomically: true, encoding: .utf8)

        _ = try CodexHookInstaller.install(hookBinaryPath: "/bin/powernap-hook", home: fakeHome.path)

        let after = try String(contentsOf: URL(fileURLWithPath: tomlPath), encoding: .utf8)
        XCTAssertTrue(after.contains("model = \"gpt-4\""))
        XCTAssertTrue(after.contains("[profile]"))
        XCTAssertTrue(after.contains("name = \"default\""))
        let parsed = try TOMLMini.parse(after)
        XCTAssertEqual(parsed["features"]?.tableValue?["hooks"]?.boolValue, true)
        XCTAssertNil(parsed["features"]?.tableValue?["codex_hooks"])
        XCTAssertEqual(parsed["model"]?.stringValue, "gpt-4")
        XCTAssertEqual(parsed["profile"]?.tableValue?["name"]?.stringValue, "default")
    }

    func testCodexInstallReusesExistingFeaturesSection() throws {
        let tomlPath = CodexHookInstaller.configTomlPath(home: fakeHome.path)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: tomlPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingToml = """
        [features]
        some_other_flag = true
        """
        try existingToml.write(to: URL(fileURLWithPath: tomlPath), atomically: true, encoding: .utf8)

        _ = try CodexHookInstaller.install(hookBinaryPath: "/bin/powernap-hook", home: fakeHome.path)

        let after = try String(contentsOf: URL(fileURLWithPath: tomlPath), encoding: .utf8)
        let parsed = try TOMLMini.parse(after)
        let features = try XCTUnwrap(parsed["features"]?.tableValue)
        XCTAssertEqual(features["hooks"]?.boolValue, true)
        XCTAssertNil(features["codex_hooks"])
        XCTAssertEqual(features["some_other_flag"]?.boolValue, true)
        let featuresCount = after.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces) == "[features]" }.count
        XCTAssertEqual(featuresCount, 1)
    }

    func testCodexInstallMigratesDeprecatedCodexHooksFlag() throws {
        let tomlPath = CodexHookInstaller.configTomlPath(home: fakeHome.path)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: tomlPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingToml = """
        [features]
        codex_hooks = true
        some_other_flag = true
        """
        try existingToml.write(to: URL(fileURLWithPath: tomlPath), atomically: true, encoding: .utf8)

        let result = try CodexHookInstaller.install(hookBinaryPath: "/bin/powernap-hook", home: fakeHome.path)

        let after = try String(contentsOf: URL(fileURLWithPath: tomlPath), encoding: .utf8)
        let parsed = try TOMLMini.parse(after)
        let features = try XCTUnwrap(parsed["features"]?.tableValue)
        XCTAssertTrue(result.configTomlModified)
        XCTAssertEqual(features["hooks"]?.boolValue, true)
        XCTAssertNil(features["codex_hooks"])
        XCTAssertEqual(features["some_other_flag"]?.boolValue, true)
        XCTAssertFalse(after.contains("codex_hooks"))
    }

    func testCodexInstallIdempotentOnConfigToml() throws {
        _ = try CodexHookInstaller.install(hookBinaryPath: "/bin/powernap-hook", home: fakeHome.path)
        let r2 = try CodexHookInstaller.install(hookBinaryPath: "/bin/powernap-hook", home: fakeHome.path)
        XCTAssertFalse(r2.configTomlModified, "second install should see flag already set")
    }

    func testCodexInstallPreservesExistingUserHook() throws {
        let existing: [String: Any] = [
            "hooks": [
                "PostToolUse": [
                    [
                        "hooks": [
                            ["type": "command", "command": "/tmp/user-hook", "timeout": 5] as [String: Any]
                        ]
                    ] as [String: Any]
                ]
            ]
        ]
        let path = CodexHookInstaller.configPath(home: fakeHome.path)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: existing).write(to: URL(fileURLWithPath: path))

        _ = try CodexHookInstaller.install(hookBinaryPath: "/bin/powernap-hook", home: fakeHome.path)

        let outData = try Data(contentsOf: URL(fileURLWithPath: path))
        let outObj = try XCTUnwrap(JSONSerialization.jsonObject(with: outData, options: []) as? [String: Any])
        let hooksRoot = try XCTUnwrap(outObj["hooks"] as? [String: Any])
        let postToolUse = try XCTUnwrap(hooksRoot["PostToolUse"] as? [[String: Any]])

        XCTAssertTrue(postToolUse.contains { group in
            (group["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String) == "/tmp/user-hook" } == true
        })
        XCTAssertTrue(postToolUse.contains { group in
            (group["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String) == "/bin/powernap-hook" } == true
        })
    }

    func testCodexInstallIsIdempotent() throws {
        _ = try CodexHookInstaller.install(hookBinaryPath: "/bin/powernap-hook", home: fakeHome.path)
        _ = try CodexHookInstaller.install(hookBinaryPath: "/bin/powernap-hook", home: fakeHome.path)

        let data = try Data(contentsOf: URL(fileURLWithPath: CodexHookInstaller.configPath(home: fakeHome.path)))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])
        let hooksRoot = try XCTUnwrap(obj["hooks"] as? [String: Any])
        for event in CodexHookInstaller.allEvents {
            let groups = try XCTUnwrap(hooksRoot[event] as? [[String: Any]], "event \(event)")
            let ours = groups.filter { group in
                (group["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String)?.contains("powernap-hook") == true } == true
            }
            XCTAssertEqual(ours.count, 1, "event \(event) should have exactly one powernap group after 2 installs")
        }
    }

    func testCodexUninstallPreservesUserHooks() throws {
        let existing: [String: Any] = [
            "hooks": [
                "PostToolUse": [
                    [
                        "hooks": [
                            ["type": "command", "command": "/tmp/user-hook", "timeout": 5] as [String: Any]
                        ]
                    ] as [String: Any]
                ]
            ]
        ]
        let path = CodexHookInstaller.configPath(home: fakeHome.path)
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: existing).write(to: URL(fileURLWithPath: path))

        _ = try CodexHookInstaller.install(hookBinaryPath: "/bin/powernap-hook", home: fakeHome.path)
        let removed = try CodexHookInstaller.uninstall(home: fakeHome.path)
        XCTAssertTrue(removed)

        let outData = try Data(contentsOf: URL(fileURLWithPath: path))
        let outObj = try XCTUnwrap(JSONSerialization.jsonObject(with: outData, options: []) as? [String: Any])
        let hooksRoot = try XCTUnwrap(outObj["hooks"] as? [String: Any])
        let postToolUse = try XCTUnwrap(hooksRoot["PostToolUse"] as? [[String: Any]])
        XCTAssertTrue(postToolUse.contains { group in
            (group["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String) == "/tmp/user-hook" } == true
        })
        XCTAssertFalse(postToolUse.contains { group in
            (group["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String)?.contains("powernap-hook") == true } == true
        })
        XCTAssertNil(outObj[CodexHookInstaller.managedMarker])
    }

    func testCodexUninstallRemovesFileIfOnlyOurContent() throws {
        _ = try CodexHookInstaller.install(hookBinaryPath: "/bin/powernap-hook", home: fakeHome.path)
        let removed = try CodexHookInstaller.uninstall(home: fakeHome.path)
        XCTAssertTrue(removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: CodexHookInstaller.configPath(home: fakeHome.path)))
    }

    func testCodexIsInstalledReflectsState() throws {
        XCTAssertFalse(CodexHookInstaller.isInstalled(home: fakeHome.path))
        _ = try CodexHookInstaller.install(hookBinaryPath: "/bin/powernap-hook", home: fakeHome.path)
        XCTAssertTrue(CodexHookInstaller.isInstalled(home: fakeHome.path))
        _ = try CodexHookInstaller.uninstall(home: fakeHome.path)
        XCTAssertFalse(CodexHookInstaller.isInstalled(home: fakeHome.path))
    }

    func testClaudeOverlayMergesExistingSettings() throws {
        let settingsPath = "\(fakeHome.path)/.claude/settings.json"
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: settingsPath).deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing: [String: Any] = [
            "permissions": ["allow_tool": "bash"],
            "hooks": [
                "PostToolUse": [
                    ["hooks": [["type": "command", "command": "/tmp/user-hook"]]] as [String: Any]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: URL(fileURLWithPath: settingsPath))

        let r = try ClaudeHookInstaller.buildOverlay(
            runId: "r-abc",
            hookBinaryPath: "/bin/powernap-hook",
            home: fakeHome.path
        )
        defer { ClaudeHookInstaller.cleanupOverlay(path: r.overlayPath) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: r.overlayPath))
        let data = try Data(contentsOf: URL(fileURLWithPath: r.overlayPath))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])
        XCTAssertNotNil(obj["permissions"])
        let hooksRoot = try XCTUnwrap(obj["hooks"] as? [String: Any])
        for event in ClaudeHookInstaller.allEvents {
            let entries = try XCTUnwrap(hooksRoot[event] as? [[String: Any]])
            XCTAssertTrue(entries.contains(where: { ($0["powernap_managed"] as? Bool) == true }))
        }
        let postToolUse = try XCTUnwrap(hooksRoot["PostToolUse"] as? [[String: Any]])
        XCTAssertTrue(
            postToolUse.contains(where: { entry in
                guard let arr = entry["hooks"] as? [[String: Any]] else { return false }
                return arr.contains(where: { ($0["command"] as? String) == "/tmp/user-hook" })
            })
        )
    }

    func testClaudeOverlayCleanup() throws {
        let r = try ClaudeHookInstaller.buildOverlay(runId: "cleanup-test", hookBinaryPath: "/x", home: fakeHome.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.overlayPath))
        ClaudeHookInstaller.cleanupOverlay(path: r.overlayPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: r.overlayPath))
    }
}
