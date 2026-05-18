import Foundation
import IOKit
import Logging

private let kPMSetClamshellSleepState: UInt32 = 12

public final class ClamshellOverride {
    private let lock = NSLock()
    private var _isActive: Bool = false
    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isActive
    }
    private let logger: Logger
    private let setDisablePower: (Bool) throws -> Void

    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "dev.powernap.power.clamshell")
        self.setDisablePower = Self.setDisableWithIOKit
    }

    init(logger: Logger? = nil, setDisablePower: @escaping (Bool) throws -> Void) {
        self.logger = logger ?? Logger(label: "dev.powernap.power.clamshell")
        self.setDisablePower = setDisablePower
    }

    public func enable() throws {
        lock.lock()
        defer { lock.unlock() }
        try setDisablePower(true)
        _isActive = true
        logger.info("clamshell override enabled (sleep-on-lid-close disabled)")
    }

    public func disable() throws {
        lock.lock()
        defer { lock.unlock() }
        try setDisablePower(false)
        _isActive = false
        logger.info("clamshell override disabled (sleep-on-lid-close re-enabled)")
    }

    @discardableResult
    public func forceClearIgnoreErrors() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            try setDisablePower(false)
            _isActive = false
            logger.warning("clamshell override force cleared (watchdog/shutdown)")
            return true
        } catch {
            logger.warning("clamshell override force clear failed (watchdog/shutdown)", metadata: ["error": "\(error)"])
            return false
        }
    }

    private static func setDisableWithIOKit(_ disableSleepOnLidClose: Bool) throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else {
            throw PowerError.clamshellMatchFailed
        }
        defer { IOObjectRelease(service) }

        var connect: io_connect_t = IO_OBJECT_NULL
        let openRC = IOServiceOpen(service, mach_task_self_, 0, &connect)
        if openRC != KERN_SUCCESS {
            throw PowerError.clamshellOpenFailed(code: openRC)
        }
        defer { IOServiceClose(connect) }

        var input: UInt64 = disableSleepOnLidClose ? 1 : 0
        let kr = withUnsafePointer(to: &input) { ptr in
            IOConnectCallScalarMethod(connect, kPMSetClamshellSleepState, ptr, 1, nil, nil)
        }
        if kr != KERN_SUCCESS {
            throw PowerError.clamshellCallFailed(code: kr)
        }
    }
}
