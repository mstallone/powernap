import Foundation

public struct ThermalStatus: Sendable {
    public enum State: String, Sendable {
        case nominal
        case fair
        case serious
        case critical
        case unknown
    }
    public var state: State
}

public final class ThermalMonitor {
    public init() {}

    public func snapshot() -> ThermalStatus {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return ThermalStatus(state: .nominal)
        case .fair: return ThermalStatus(state: .fair)
        case .serious: return ThermalStatus(state: .serious)
        case .critical: return ThermalStatus(state: .critical)
        @unknown default: return ThermalStatus(state: .unknown)
        }
    }

    public func safeForClosedLid(allowSerious: Bool) -> (ok: Bool, reason: String) {
        let s = snapshot()
        switch s.state {
        case .nominal, .fair: return (true, "thermal \(s.state.rawValue)")
        case .serious: return (allowSerious, "thermal serious")
        case .critical: return (false, "thermal critical")
        case .unknown: return (true, "thermal unknown")
        }
    }
}
