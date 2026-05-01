import Foundation
import IOKit
import IOKit.pwr_mgt
import Logging

public final class IdleAssertion {
    public enum Kind: String {
        case preventIdleSleep
        case preventDisplaySleep
        case preventSystemSleep

        fileprivate var assertionType: CFString {
            switch self {
            case .preventIdleSleep: return kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
            case .preventDisplaySleep: return kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
            case .preventSystemSleep: return kIOPMAssertionTypePreventSystemSleep as CFString
            }
        }
    }

    private var assertionID: IOPMAssertionID = 0
    private let lock = NSLock()
    private let logger: Logger
    private(set) public var kind: Kind
    private(set) public var reason: String
    private(set) public var isHeld: Bool = false

    public init(kind: Kind = .preventIdleSleep, reason: String = "PowerNAP active turn", logger: Logger? = nil) {
        self.kind = kind
        self.reason = reason
        self.logger = logger ?? Logger(label: "dev.powernap.power.idle")
    }

    public func acquire() throws {
        lock.lock()
        defer { lock.unlock() }
        if isHeld { return }
        var id: IOPMAssertionID = 0
        let rc = IOPMAssertionCreateWithName(
            kind.assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        if rc != kIOReturnSuccess {
            throw PowerError.assertionFailed(code: Int32(rc))
        }
        assertionID = id
        isHeld = true
        logger.info("idle assertion acquired", metadata: ["id": "\(id)", "kind": "\(kind.rawValue)"])
    }

    public func release() {
        lock.lock()
        defer { lock.unlock() }
        if !isHeld { return }
        let rc = IOPMAssertionRelease(assertionID)
        if rc != kIOReturnSuccess {
            logger.warning("idle assertion release returned", metadata: ["code": "\(rc)"])
        }
        assertionID = 0
        isHeld = false
        logger.info("idle assertion released")
    }

    deinit {
        if isHeld {
            _ = IOPMAssertionRelease(assertionID)
        }
    }
}

public enum PowerError: Swift.Error, LocalizedError {
    case assertionFailed(code: Int32)
    case clamshellMatchFailed
    case clamshellOpenFailed(code: Int32)
    case clamshellCallFailed(code: Int32)

    public var errorDescription: String? {
        switch self {
        case .assertionFailed(let c): return "IOPM assertion failed (\(c))"
        case .clamshellMatchFailed: return "Failed to match IOPMrootDomain service"
        case .clamshellOpenFailed(let c): return "Failed to open IOPMrootDomain user client (\(c))"
        case .clamshellCallFailed(let c): return "Clamshell scalar call failed (\(c))"
        }
    }
}
