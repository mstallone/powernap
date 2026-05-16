import Foundation
import Logging
import PowerNAPCore

final class CodexSessionFileMonitor {
    private let workingDirectory: String
    private let sessionsRoot: URL
    private let logger: Logger
    private let emit: (String) -> Void
    private let startedAt: Date
    private let queue = DispatchQueue(label: "dev.powernap.codex-session-monitor", qos: .utility)
    private let fileManager = FileManager.default

    private var timer: DispatchSourceTimer?
    private var offsets: [String: UInt64] = [:]
    private var partialLines: [String: String] = [:]
    private var rejectedPaths = Set<String>()
    private var selectedPath: String?
    private var running = false

    init(
        workingDirectory: String,
        logger: Logger,
        sessionsRoot: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions"),
        emit: @escaping (String) -> Void
    ) {
        self.workingDirectory = workingDirectory
        self.sessionsRoot = sessionsRoot
        self.logger = logger
        self.emit = emit
        self.startedAt = Date()
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.running else { return }
            self.running = true

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(750))
            timer.setEventHandler { [weak self] in self?.scan() }
            timer.resume()
            self.timer = timer
            self.logger.debug("codex session transcript monitor started", metadata: [
                "cwd": .string(self.workingDirectory),
                "root": .string(self.sessionsRoot.path)
            ])
        }
    }

    func stop() {
        queue.sync {
            running = false
            timer?.cancel()
            timer = nil
            offsets.removeAll()
            partialLines.removeAll()
            rejectedPaths.removeAll()
            selectedPath = nil
        }
    }

    private func scan() {
        guard running else { return }
        for url in candidateTranscriptURLs() {
            readNewLines(from: url)
        }
    }

    private func candidateTranscriptURLs() -> [URL] {
        let roots = candidateDayRoots()
        let threshold = startedAt.addingTimeInterval(-5)
        var seen = Set<String>()
        var urls: [URL] = []
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let path = url.path
                guard seen.insert(path).inserted else { continue }
                if selectedPath == path {
                    urls.append(url)
                    continue
                }
                guard !rejectedPaths.contains(path) else { continue }

                let values = try? url.resourceValues(forKeys: keys)
                let createdAt = values?.creationDate ?? .distantPast
                let modifiedAt = values?.contentModificationDate ?? .distantPast
                if createdAt >= threshold || modifiedAt >= threshold {
                    urls.append(url)
                }
            }
        }

        return urls.sorted { $0.path < $1.path }
    }

    private func candidateDayRoots() -> [URL] {
        let calendar = Calendar.current
        let dates = [startedAt, Date()]
        var roots: [URL] = []
        var seen = Set<String>()

        for date in dates {
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year, let month = components.month, let day = components.day else { continue }
            let root = sessionsRoot
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)
            if seen.insert(root.path).inserted {
                roots.append(root)
            }
        }

        return roots
    }

    private func readNewLines(from url: URL) {
        let path = url.path
        guard !rejectedPaths.contains(path) else { return }

        do {
            let attrs = try fileManager.attributesOfItem(atPath: path)
            let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            let startOffset = min(offsets[path] ?? 0, fileSize)

            let handle = try FileHandle(forReadingFrom: url)
            defer { handle.closeFile() }
            handle.seek(toFileOffset: startOffset)
            let data = handle.readDataToEndOfFile()
            offsets[path] = handle.offsetInFile
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

            process(text: text, from: path)
        } catch {
            logger.debug("codex transcript read failed", metadata: [
                "path": .string(path),
                "error": .string(String(describing: error))
            ])
        }
    }

    private func process(text: String, from path: String) {
        let buffered = (partialLines[path] ?? "") + text
        let finishedWithNewline = buffered.hasSuffix("\n")
        var lines = buffered.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        if finishedWithNewline {
            partialLines[path] = nil
            if lines.last == "" { lines.removeLast() }
        } else {
            partialLines[path] = lines.popLast() ?? ""
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let event = CodexTranscriptEventMapper.map(line: trimmed, workingDirectory: workingDirectory)
            else {
                continue
            }

            switch event {
            case .matchedSession:
                if selectedPath == nil {
                    selectedPath = path
                    logger.debug("codex transcript selected", metadata: ["path": .string(path)])
                }
            case .rejectedSession:
                if selectedPath != path {
                    rejectedPaths.insert(path)
                }
            case .hookEvent(let hookEvent):
                guard selectedPath == path else { continue }
                emit(hookEvent)
            }
        }
    }
}
