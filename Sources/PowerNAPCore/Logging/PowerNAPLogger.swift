import Foundation
import Logging

public enum PowerNAPLogger {

    public static let subsystem = "dev.powernap"

    public static func bootstrap(label: String, toFile: String? = nil, level: Logger.Level = .info) {
        LoggingSystem.bootstrap { lab in
            var handlers: [LogHandler] = []
            handlers.append(StreamLogHandler.standardError(label: lab))
            if let toFile {
                if let fh = try? FileLogHandler.makeOrAppend(label: lab, path: toFile, level: level) {
                    handlers.append(fh)
                }
            }
            return MultiplexLogHandler(handlers)
        }
    }

    public static func make(_ label: String, level: Logger.Level = .info) -> Logger {
        var logger = Logger(label: "\(subsystem).\(label)")
        logger.logLevel = level
        return logger
    }
}

public struct FileLogHandler: LogHandler {
    public var metadata: Logger.Metadata = [:]
    public var logLevel: Logger.Level = .info

    private let label: String
    private let fd: Int32
    private let lock: NSLock

    private init(label: String, fd: Int32) {
        self.label = label
        self.fd = fd
        self.lock = NSLock()
    }

    public static func makeOrAppend(label: String, path: String, level: Logger.Level) throws -> FileLogHandler {
        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if fd < 0 { throw SysError.fromErrno() }
        var handler = FileLogHandler(label: label, fd: fd)
        handler.logLevel = level
        return handler
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    #if compiler(>=6.1)
    public func log(event: LogEvent) {
        writeLogLine(level: event.level, message: event.message, metadata: event.metadata)
    }
    #endif

    public func log(level: Logger.Level,
                    message: Logger.Message,
                    metadata: Logger.Metadata?,
                    source: String,
                    file: String,
                    function: String,
                    line: UInt) {
        writeLogLine(level: level, message: message, metadata: metadata)
    }

    private func writeLogLine(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?) {
        let ts = FileLogHandler.isoTimestamp(Date())
        var merged = self.metadata
        if let metadata { for (k, v) in metadata { merged[k] = v } }
        let metaStr = merged.isEmpty ? "" : " " + merged.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let line = "\(ts) \(level.rawValue.uppercased()) [\(label)] \(message)\(metaStr)\n"
        lock.lock()
        defer { lock.unlock() }
        _ = line.withCString { ptr in
            Darwin.write(fd, ptr, strlen(ptr))
        }
    }

    private static func isoTimestamp(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}
