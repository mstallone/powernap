import XCTest
@testable import PowerNAPPlatform

final class ClamshellOverrideTests: XCTestCase {
    func testForceClearIgnoreErrorsKeepsActiveAfterRestoreFailure() throws {
        var calls: [Bool] = []
        let override = ClamshellOverride(setDisablePower: { disableSleepOnLidClose in
            calls.append(disableSleepOnLidClose)
            if !disableSleepOnLidClose {
                throw PowerError.clamshellMatchFailed
            }
        })

        try override.enable()
        let didClear = override.forceClearIgnoreErrors()

        XCTAssertFalse(didClear)
        XCTAssertTrue(override.isActive)
        XCTAssertEqual(calls, [true, false])
    }

    func testForceClearIgnoreErrorsMarksInactiveAfterRestoreSuccess() throws {
        let override = ClamshellOverride(setDisablePower: { _ in })

        try override.enable()
        let didClear = override.forceClearIgnoreErrors()

        XCTAssertTrue(didClear)
        XCTAssertFalse(override.isActive)
    }
}
