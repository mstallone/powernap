import Foundation
import Network
import Logging

public enum NetworkProbeResult: Sendable {
    case ok(latencyMs: Int)
    case failed(reason: String)
}

public final class NetworkProbe {
    public static let defaultEndpoints: [String] = [
        "https://captive.apple.com/hotspot-detect.html",
        "https://www.gstatic.com/generate_204",
        "https://1.1.1.1/cdn-cgi/trace"
    ]

    private let logger: Logger
    private let session: URLSession

    public init(logger: Logger? = nil, timeout: TimeInterval = 5) {
        self.logger = logger ?? Logger(label: "dev.powernap.network.probe")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        cfg.waitsForConnectivity = false
        cfg.httpShouldUsePipelining = false
        cfg.urlCache = nil
        self.session = URLSession(configuration: cfg)
    }

    public func probe(urlString: String) async -> NetworkProbeResult {
        guard let url = URL(string: urlString) else {
            return .failed(reason: "invalid URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let start = Date()
        do {
            let (_, response) = try await session.data(for: req)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            if let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) {
                return .ok(latencyMs: ms)
            }
            return .failed(reason: "status \(((response as? HTTPURLResponse)?.statusCode).map(String.init) ?? "-")")
        } catch {
            return .failed(reason: "\(error.localizedDescription)")
        }
    }

    public func probeAll(endpoints: [String] = NetworkProbe.defaultEndpoints) async -> [String: NetworkProbeResult] {
        var out: [String: NetworkProbeResult] = [:]
        await withTaskGroup(of: (String, NetworkProbeResult).self) { group in
            for e in endpoints {
                group.addTask { (e, await self.probe(urlString: e)) }
            }
            for await (e, r) in group {
                out[e] = r
            }
        }
        return out
    }

    public func anyOK(endpoints: [String] = NetworkProbe.defaultEndpoints) async -> Bool {
        let results = await probeAll(endpoints: endpoints)
        return results.contains { if case .ok = $0.value { return true } else { return false } }
    }
}
