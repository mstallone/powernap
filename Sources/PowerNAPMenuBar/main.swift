import AppKit
import Foundation
import PowerNAPCore

final class PowerNAPMenuApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var snapshot = MenuSnapshot.offline("Starting...")
    private let refreshInterval: TimeInterval = 5

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        refreshStatus()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    private func configureStatusItem() {
        statusItem.behavior = [.removalAllowed, .terminationOnRemoval]
        statusItem.menu = NSMenu()
    }

    private func refreshStatus() {
        snapshot = loadSnapshot()
        updateIcon()
        rebuildMenu()
    }

    private func loadSnapshot() -> MenuSnapshot {
        do {
            let response = try UnixSocketClient.sendRequest(IPCRequest(body: .status), timeoutSeconds: 0.75)
            switch response.body {
            case .status(let payload):
                return MenuSnapshot(payload: payload, refreshedAt: Date())
            case .error(_, let message):
                return .offline(message)
            default:
                return .offline("Unexpected daemon response")
            }
        } catch {
            return .offline("Daemon unavailable")
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbolName: String
        let description: String
        switch snapshot.sleepState {
        case .blocked:
            symbolName = "bolt.circle.fill"
            description = "PowerNAP is keeping this Mac awake"
        case .allowed:
            symbolName = "moon.fill"
            description = "PowerNAP allows normal sleep"
        case .unknown:
            symbolName = "questionmark.circle"
            description = "PowerNAP daemon status is unknown"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = snapshot.activeThreadCount > 0 ? " \(snapshot.activeThreadCount)" : ""
        button.toolTip = snapshot.summary
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(headerItem(snapshot.summary))
        menu.addItem(detailItem("Sleep", snapshot.sleepState.label))
        menu.addItem(detailItem("Active protected threads", "\(snapshot.activeThreadCount)"))
        menu.addItem(detailItem("Power leases", "\(snapshot.powerLeaseCount)"))
        menu.addItem(detailItem("Last refresh", relativeTime(snapshot.refreshedAt)))

        if let payload = snapshot.payload {
            menu.addItem(.separator())
            menu.addItem(detailItem("Daemon", payload.daemonRunning ? "running" : "stopped"))
            menu.addItem(detailItem("Thermal", payload.safety.thermalState))
            menu.addItem(detailItem("Battery", batteryText(payload.safety)))

            menu.addItem(.separator())
            appendSessions(payload.sessions, to: menu)

            menu.addItem(.separator())
            appendLeases(payload.leases, to: menu)
        } else if let errorMessage = snapshot.errorMessage {
            menu.addItem(.separator())
            menu.addItem(detailItem("Status", errorMessage))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Refresh Now", action: #selector(refreshNow)))
        menu.addItem(actionItem("Restore Power State", action: #selector(restorePowerState)))
        menu.addItem(actionItem("Open Logs Folder", action: #selector(openLogsFolder)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit PowerNAP Menu", action: #selector(quit)))

        statusItem.menu = menu
    }

    private func appendSessions(_ sessions: [StatusPayload.ActiveSession], to menu: NSMenu) {
        menu.addItem(sectionItem("Sessions"))
        if sessions.isEmpty {
            menu.addItem(disabledItem("No active sessions"))
            return
        }
        for session in sessions {
            let run = String(session.runId.prefix(8))
            let lastEvent = session.lastEventAt.map { relativeTime($0) } ?? "no events yet"
            menu.addItem(disabledItem("\(session.agent) \(run) - \(session.phase.rawValue) - \(lastEvent)"))
        }
    }

    private func appendLeases(_ leases: [StatusPayload.LeaseInfo], to menu: NSMenu) {
        menu.addItem(sectionItem("Leases"))
        if leases.isEmpty {
            menu.addItem(disabledItem("No held leases"))
            return
        }
        for lease in leases {
            let expiry = lease.expiresAt.map { "expires \(relativeTime($0))" } ?? "no expiry"
            menu.addItem(disabledItem("\(lease.leaseType) - \(expiry)"))
        }
    }

    private func batteryText(_ safety: StatusPayload.SafetyInfo) -> String {
        let percent = safety.batteryPercent.map { "\($0)%" } ?? "unknown"
        let power = safety.charging.map { $0 ? "charging" : "on battery" } ?? "power unknown"
        return "\(percent), \(power)"
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds == 0 { return "now" }
        let absSeconds = abs(seconds)
        let value: Int
        let unit: String
        if absSeconds < 60 {
            value = absSeconds
            unit = "s"
        } else if absSeconds < 3600 {
            value = absSeconds / 60
            unit = "m"
        } else {
            value = absSeconds / 3600
            unit = "h"
        }
        return seconds > 0 ? "in \(value)\(unit)" : "\(value)\(unit) ago"
    }

    private func headerItem(_ title: String) -> NSMenuItem {
        let item = disabledItem(title)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
        )
        return item
    }

    private func sectionItem(_ title: String) -> NSMenuItem {
        let item = disabledItem(title)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        return item
    }

    private func detailItem(_ label: String, _ value: String) -> NSMenuItem {
        disabledItem("\(label): \(value)")
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    @objc private func refreshNow() {
        refreshStatus()
    }

    @objc private func restorePowerState() {
        do {
            let response = try UnixSocketClient.sendRequest(
                IPCRequest(body: .restore(reason: "menubar")),
                timeoutSeconds: 2
            )
            if case .ack = response.body {
                refreshStatus()
            } else {
                snapshot = .offline("Restore returned unexpected response")
                updateIcon()
                rebuildMenu()
            }
        } catch {
            snapshot = .offline("Restore failed: \(error.localizedDescription)")
            updateIcon()
            rebuildMenu()
        }
    }

    @objc private func openLogsFolder() {
        NSWorkspace.shared.open(ConfigPaths.logsDir)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@main
enum PowerNAPMenuMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = PowerNAPMenuApp()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

private enum SleepState {
    case blocked
    case allowed
    case unknown

    var label: String {
        switch self {
        case .blocked:
            return "blocked by PowerNAP"
        case .allowed:
            return "allowed normally"
        case .unknown:
            return "unknown"
        }
    }
}

private struct MenuSnapshot {
    var payload: StatusPayload?
    var errorMessage: String?
    var refreshedAt: Date

    init(payload: StatusPayload, refreshedAt: Date) {
        self.payload = payload
        self.errorMessage = nil
        self.refreshedAt = refreshedAt
    }

    static func offline(_ message: String) -> MenuSnapshot {
        MenuSnapshot(payload: nil, errorMessage: message, refreshedAt: Date())
    }

    private init(payload: StatusPayload?, errorMessage: String?, refreshedAt: Date) {
        self.payload = payload
        self.errorMessage = errorMessage
        self.refreshedAt = refreshedAt
    }

    var activeThreadCount: Int {
        guard let payload else { return 0 }
        return payload.sessions.filter { $0.phase == .active }.count
    }

    var powerLeaseCount: Int {
        guard let payload else { return 0 }
        return payload.leases.filter { lease in
            lease.held && (lease.leaseType == LeaseType.idleSleep.rawValue || lease.leaseType == LeaseType.clamshellSleep.rawValue)
        }.count
    }

    var sleepState: SleepState {
        guard payload != nil else { return .unknown }
        return powerLeaseCount > 0 ? .blocked : .allowed
    }

    var summary: String {
        if let errorMessage {
            return "PowerNAP: \(errorMessage)"
        }
        switch sleepState {
        case .blocked:
            if activeThreadCount == 0 {
                return "Mac sleep blocked by held PowerNAP lease"
            }
            let threadWord = activeThreadCount == 1 ? "thread" : "threads"
            return "Mac sleep blocked by \(activeThreadCount) active \(threadWord)"
        case .allowed:
            return "Mac can sleep normally"
        case .unknown:
            return "PowerNAP status unknown"
        }
    }
}
