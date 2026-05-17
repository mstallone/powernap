import Foundation
import Logging

final class CodexStartupLeaseGuard {
    private let timeoutSeconds: TimeInterval
    private let logger: Logger
    private let expire: () -> Void
    private let queue = DispatchQueue(label: "dev.powernap.codex-startup-lease", qos: .utility)

    private var timer: DispatchSourceTimer?
    private var turnStarted = false
    private var stopped = false

    init(timeoutSeconds: TimeInterval, logger: Logger, expire: @escaping () -> Void) {
        self.timeoutSeconds = timeoutSeconds
        self.logger = logger
        self.expire = expire
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil, !self.stopped else { return }

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + self.timeoutSeconds)
            timer.setEventHandler { [weak self] in self?.expireIfNoTurnStarted() }
            timer.resume()
            self.timer = timer
        }
    }

    func markTurnStarted() {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.turnStarted = true
            self.cancelTimer()
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            cancelTimer()
        }
    }

    private func expireIfNoTurnStarted() {
        guard !stopped, !turnStarted else {
            cancelTimer()
            return
        }

        stopped = true
        cancelTimer()
        logger.debug("codex startup lease grace elapsed; releasing until first turn")
        expire()
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }
}
