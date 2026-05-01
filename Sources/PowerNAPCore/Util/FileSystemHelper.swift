import Foundation

public enum FileSystemHelper {
    @discardableResult
    public static func ensureDirectory(at url: URL, permissions: Int? = 0o700) throws -> URL {
        let fm = FileManager.default
        var attrs: [FileAttributeKey: Any] = [:]
        if let p = permissions { attrs[.posixPermissions] = NSNumber(value: p) }
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: attrs)
        }
        return url
    }

    public static func writeAtomically(data: Data, to url: URL, permissions: Int = 0o600) throws {
        let tmp = url.appendingPathExtension("tmp.\(UInt64.random(in: 0..<UInt64.max))")
        try FileSystemHelper.ensureDirectory(at: url.deletingLastPathComponent(), permissions: 0o700)
        try data.write(to: tmp, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: permissions)], ofItemAtPath: tmp.path)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try? FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmp, to: url)
    }

    public static func readIfExists(_ url: URL) -> Data? {
        FileManager.default.fileExists(atPath: url.path) ? (try? Data(contentsOf: url)) : nil
    }
}
