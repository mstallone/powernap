import Foundation
import IOKit
import Logging

public final class LidMonitor {
    private var service: io_service_t = IO_OBJECT_NULL
    private let logger: Logger

    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "dev.powernap.system.lid")
        self.service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleClamshellState"))
    }

    deinit {
        if service != IO_OBJECT_NULL { IOObjectRelease(service) }
    }

    public func isClosed() -> Bool? {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(rootDomain) }
        let key = "AppleClamshellState" as CFString
        guard let value = IORegistryEntryCreateCFProperty(rootDomain, key, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    public func causesSleep() -> Bool? {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(rootDomain) }
        let key = "AppleClamshellCausesSleep" as CFString
        guard let value = IORegistryEntryCreateCFProperty(rootDomain, key, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }
}
