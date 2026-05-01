import Foundation
import Network
import Logging
import PowerNAPCore

public final class NetworkOrchestrator: @unchecked Sendable {
    private let config: Config
    private let store: StateStore
    private let logger: Logger
    private let serviceOrder: NetworkServiceOrder
    private let pathMonitor: NetworkPathMonitor
    private let probe: NetworkProbe
    private let wifi: WiFiManager

    private let lock = NSLock()
    private var initialSnapshot: [String]?
    private var failoverActive = false
    private var lastProbeResults: [String: NetworkProbeResult] = [:]
    private var lastProbeAt: Date?
    private var probeTimer: DispatchSourceTimer?
    private let probeQueue = DispatchQueue(label: "dev.powernap.network.orchestrator", qos: .utility)
    private var started = false
    private var activeRunIds: Set<String> = []

    public init(config: Config, store: StateStore, logger: Logger) {
        self.config = config
        self.store = store
        self.logger = logger
        self.serviceOrder = NetworkServiceOrder(logger: logger)
        self.pathMonitor = NetworkPathMonitor(logger: logger)
        self.probe = NetworkProbe(logger: logger)
        self.wifi = WiFiManager(logger: logger)
    }

    public func start() {
        lock.lock()
        if started { lock.unlock(); return }
        started = true
        lock.unlock()

        guard config.network.enabled else {
            logger.info("network orchestrator disabled by config")
            return
        }

        pathMonitor.start()
        snapshotInitialOrder()

        pathMonitor.onUpdate { [weak self] snap in
            self?.handlePathUpdate(snap)
        }

        startProbeLoop()
    }

    public func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        probeTimer?.cancel()
        probeTimer = nil
        pathMonitor.stop()
        if config.network.restoreServiceOrder, let snap = initialSnapshot {
            try? serviceOrder.restoreFromSnapshot(snap)
            logger.info("restored network service order on shutdown")
        }
        started = false
    }

    public func preferUSBTether() {
        guard config.network.preferUSBTether else { return }
        do {
            if let usb = try serviceOrder.preferUSBTether() {
                setFailoverActive(false)
                logger.info("prefer USB tether: \(usb)")
                Task { [weak self] in
                    await self?.verifyFailover(serviceName: usb)
                }
            } else {
                logger.info("prefer USB tether: no USB tether found")
            }
        } catch {
            logger.error("prefer USB tether failed: \(error)")
        }
    }

    public func preferBluetoothPAN() {
        guard config.network.allowBluetoothPAN else { return }
        do {
            if let bluetooth = try serviceOrder.preferBluetoothPAN() {
                setFailoverActive(false)
                logger.info("prefer Bluetooth PAN: \(bluetooth)")
                Task { [weak self] in
                    await self?.verifyFailover(serviceName: bluetooth)
                }
            } else {
                logger.info("prefer Bluetooth PAN: no Bluetooth PAN service found")
            }
        } catch {
            logger.error("prefer Bluetooth PAN failed: \(error)")
        }
    }

    public func handleAgentEvent(_ event: AgentEvent) {
        lock.lock()
        let hadActive = !activeRunIds.isEmpty
        switch event.phase {
        case .active:
            activeRunIds.insert(event.runId)
        case .waiting, .turnIdle, .done, .error:
            activeRunIds.remove(event.runId)
        case .starting:
            break
        }
        let hasActive = !activeRunIds.isEmpty
        lock.unlock()

        if hadActive && !hasActive {
            restoreServiceOrder()
        }
    }

    public func restoreServiceOrder() {
        guard config.network.restoreServiceOrder else { return }
        lock.lock()
        let snap = initialSnapshot
        lock.unlock()
        if let snap {
            do {
                try serviceOrder.restoreFromSnapshot(snap)
                lock.lock()
                failoverActive = false
                lock.unlock()
                logger.info("restored service order")
            } catch {
                logger.error("restore failed: \(error)")
            }
        }
    }

    public func joinConfiguredHotspotIfAvailable() async -> Bool {
        guard config.network.allowWiFiHotspot else { return false }
        for hotspot in config.network.hotspots {
            do {
                let password: String?
                if let account = hotspot.keychainAccount {
                    password = try? Keychain.getString(account: account)
                } else {
                    password = try? Keychain.getString(account: "PowerNAP Hotspot \(hotspot.ssid)")
                }
                try wifi.associate(ssid: hotspot.ssid, password: password)
                logger.info("joined hotspot \(hotspot.ssid)")
                return await verifyFailover(serviceName: nil)
            } catch {
                logger.warning("hotspot join failed for \(hotspot.ssid): \(error)")
            }
        }
        return false
    }

    public func statusPayload() -> NetworkStatusPayload {
        lock.lock()
        let probes = lastProbeResults
        let active = failoverActive
        let snap = initialSnapshot
        lock.unlock()

        let pathSnap = pathMonitor.snapshot()
        let routeInterface = try? serviceOrder.defaultRouteInterface()
        let primaryName = routeInterface ?? pathSnap.interfaceName
        let pathStr = pathSnap.status.rawValue

        let services = (try? serviceOrder.listServices()) ?? []
        let payloadServices: [NetworkStatusPayload.Service] = services.map { s in
            NetworkStatusPayload.Service(name: s.name, interface: s.device, active: s.device == primaryName, enabled: s.enabled)
        }
        let usbPresent = (try? serviceOrder.listServices()).map { services in
            serviceOrder.findUSBTether(services) != nil
        } ?? false

        var probeStrings: [String: String] = [:]
        for (k, v) in probes {
            switch v {
            case .ok(let ms): probeStrings[k] = "ok:\(ms)ms"
            case .failed(let reason): probeStrings[k] = "fail:\(reason)"
            }
        }

        return NetworkStatusPayload(
            primaryInterface: primaryName,
            primaryService: services.first(where: { $0.device == primaryName })?.name,
            path: pathStr,
            services: payloadServices,
            hotspotConfigured: !config.network.hotspots.isEmpty,
            usbTetherPresent: usbPresent,
            probeResults: probeStrings,
            serviceOrderSnapshot: snap,
            failoverActive: active
        )
    }

    private func snapshotInitialOrder() {
        do {
            let order = try serviceOrder.currentOrder()
            lock.lock()
            initialSnapshot = order
            lock.unlock()
            try? serviceOrder.snapshot(to: store)
            logger.info("initial service order snapshot captured: \(order.count) services")
        } catch {
            logger.warning("failed to snapshot service order: \(error)")
        }
    }

    private func handlePathUpdate(_ snap: NetworkPathSnapshot) {
        Task { [weak self] in
            guard let self else { return }
            await self.runProbes()
            self.maybeFailover(snap: snap)
        }
    }

    private func startProbeLoop() {
        let t = DispatchSource.makeTimerSource(queue: probeQueue)
        t.schedule(deadline: .now() + .seconds(30), repeating: .seconds(30))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.runProbes() }
        }
        t.resume()
        lock.lock()
        probeTimer = t
        lock.unlock()
    }

    private func runProbes() async {
        let endpoints = config.network.probeEndpoints.isEmpty
            ? NetworkProbe.defaultEndpoints
            : config.network.probeEndpoints
        let results = await probe.probeAll(endpoints: endpoints)
        storeProbeResults(results)
    }

    private func storeProbeResults(_ results: [String: NetworkProbeResult]) {
        lock.lock()
        defer { lock.unlock() }
        lastProbeResults = results
        lastProbeAt = Date()
    }

    private func maybeFailover(snap: NetworkPathSnapshot) {
        guard config.network.enabled else { return }
        guard hasActiveTurn() else { return }

        let pathBad = snap.status != .satisfied
        if pathBad {
            logger.warning("network unsatisfied, attempting failover")
            if config.network.preferUSBTether {
                preferUSBTether()
            }
            if !isFailoverActive() && config.network.allowWiFiHotspot {
                Task { [weak self] in
                    _ = await self?.joinConfiguredHotspotIfAvailable()
                }
            }
            if !isFailoverActive() && config.network.allowBluetoothPAN {
                preferBluetoothPAN()
            }
        }
    }

    @discardableResult
    private func verifyFailover(serviceName: String?) async -> Bool {
        let expectedDevice: String? = {
            guard let serviceName,
                  let services = try? serviceOrder.listServices(),
                  let service = services.first(where: { $0.name == serviceName }) else {
                return nil
            }
            return service.device
        }()

        let routeInterface = try? serviceOrder.defaultRouteInterface()
        let routeOK = expectedDevice == nil || routeInterface == expectedDevice
        let endpoints = config.network.probeEndpoints.isEmpty
            ? NetworkProbe.defaultEndpoints
            : config.network.probeEndpoints
        let results = await probe.probeAll(endpoints: endpoints)
        storeProbeResults(results)
        let probesOK = results.contains { _, result in
            if case .ok = result { return true }
            return false
        }
        let verified = routeOK && probesOK

        setFailoverActive(verified)

        if verified {
            logger.info(
                "failover verified",
                metadata: [
                    "service": "\(serviceName ?? "unknown")",
                    "route": "\(routeInterface ?? "unknown")"
                ]
            )
        } else {
            logger.warning(
                "failover not verified",
                metadata: [
                    "service": "\(serviceName ?? "unknown")",
                    "expectedDevice": "\(expectedDevice ?? "unknown")",
                    "route": "\(routeInterface ?? "unknown")",
                    "probesOK": "\(probesOK)"
                ]
            )
        }
        return verified
    }

    private func isFailoverActive() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return failoverActive
    }

    private func setFailoverActive(_ active: Bool) {
        lock.lock()
        failoverActive = active
        lock.unlock()
    }

    private func hasActiveTurn() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !activeRunIds.isEmpty
    }
}
