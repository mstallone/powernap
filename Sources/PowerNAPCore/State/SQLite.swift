import Foundation
import SQLite3

public enum SQLiteError: Swift.Error, LocalizedError {
    case openFailed(code: Int32, message: String)
    case prepareFailed(code: Int32, message: String, sql: String)
    case bindFailed(code: Int32, message: String)
    case stepFailed(code: Int32, message: String)
    case execFailed(code: Int32, message: String, sql: String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let c, let m): return "SQLite open failed (\(c)): \(m)"
        case .prepareFailed(let c, let m, let sql): return "SQLite prepare failed (\(c)): \(m) — sql: \(sql)"
        case .bindFailed(let c, let m): return "SQLite bind failed (\(c)): \(m)"
        case .stepFailed(let c, let m): return "SQLite step failed (\(c)): \(m)"
        case .execFailed(let c, let m, let sql): return "SQLite exec failed (\(c)): \(m) — sql: \(sql)"
        }
    }
}

internal let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

public final class SQLite {
    private var db: OpaquePointer?
    public let path: String

    public init(path: String) throws {
        self.path = path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        if rc != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let h = handle { sqlite3_close(h) }
            throw SQLiteError.openFailed(code: rc, message: msg)
        }
        self.db = handle
        _ = try? exec("PRAGMA journal_mode=WAL;")
        _ = try? exec("PRAGMA synchronous=NORMAL;")
        _ = try? exec("PRAGMA foreign_keys=ON;")
        _ = try? exec("PRAGMA busy_timeout=5000;")
    }

    deinit {
        if let db = db { sqlite3_close(db) }
    }

    public func exec(_ sql: String) throws {
        let rc = sqlite3_exec(db, sql, nil, nil, nil)
        if rc != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.execFailed(code: rc, message: msg, sql: sql)
        }
    }

    @discardableResult
    public func execute(_ sql: String, _ params: [SQLiteBindable?] = []) throws -> Int {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if rc != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        try bindAll(stmt, params)
        let step = sqlite3_step(stmt)
        if step != SQLITE_DONE && step != SQLITE_ROW {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.stepFailed(code: step, message: msg)
        }
        return Int(sqlite3_changes(db))
    }

    public func query<R>(_ sql: String, _ params: [SQLiteBindable?] = [], _ rowBuilder: (SQLiteRow) throws -> R) throws -> [R] {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if rc != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepareFailed(code: rc, message: msg, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        try bindAll(stmt, params)
        var rows: [R] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            if step != SQLITE_ROW {
                let msg = String(cString: sqlite3_errmsg(db))
                throw SQLiteError.stepFailed(code: step, message: msg)
            }
            let row = SQLiteRow(stmt: stmt!)
            rows.append(try rowBuilder(row))
        }
        return rows
    }

    public func lastInsertRowID() -> Int64 {
        sqlite3_last_insert_rowid(db)
    }

    public func transaction<R>(_ body: () throws -> R) throws -> R {
        try exec("BEGIN TRANSACTION;")
        do {
            let result = try body()
            try exec("COMMIT;")
            return result
        } catch {
            _ = try? exec("ROLLBACK;")
            throw error
        }
    }

    private func bindAll(_ stmt: OpaquePointer?, _ params: [SQLiteBindable?]) throws {
        for (idx, p) in params.enumerated() {
            let i = Int32(idx + 1)
            let rc: Int32
            if let p = p {
                rc = p.sqliteBind(stmt, index: i)
            } else {
                rc = sqlite3_bind_null(stmt, i)
            }
            if rc != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw SQLiteError.bindFailed(code: rc, message: msg)
            }
        }
    }
}

public protocol SQLiteBindable {
    func sqliteBind(_ stmt: OpaquePointer?, index: Int32) -> Int32
}

extension String: SQLiteBindable {
    public func sqliteBind(_ stmt: OpaquePointer?, index: Int32) -> Int32 {
        sqlite3_bind_text(stmt, index, self, -1, SQLITE_TRANSIENT)
    }
}

extension Int: SQLiteBindable {
    public func sqliteBind(_ stmt: OpaquePointer?, index: Int32) -> Int32 {
        sqlite3_bind_int64(stmt, index, Int64(self))
    }
}

extension Int64: SQLiteBindable {
    public func sqliteBind(_ stmt: OpaquePointer?, index: Int32) -> Int32 {
        sqlite3_bind_int64(stmt, index, self)
    }
}

extension Int32: SQLiteBindable {
    public func sqliteBind(_ stmt: OpaquePointer?, index: Int32) -> Int32 {
        sqlite3_bind_int(stmt, index, self)
    }
}

extension Double: SQLiteBindable {
    public func sqliteBind(_ stmt: OpaquePointer?, index: Int32) -> Int32 {
        sqlite3_bind_double(stmt, index, self)
    }
}

extension Bool: SQLiteBindable {
    public func sqliteBind(_ stmt: OpaquePointer?, index: Int32) -> Int32 {
        sqlite3_bind_int(stmt, index, self ? 1 : 0)
    }
}

extension Data: SQLiteBindable {
    public func sqliteBind(_ stmt: OpaquePointer?, index: Int32) -> Int32 {
        withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, index, raw.baseAddress, Int32(raw.count), SQLITE_TRANSIENT)
        }
    }
}

public struct SQLiteRow {
    public let stmt: OpaquePointer

    public func string(_ idx: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: cstr)
    }

    public func int(_ idx: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, idx))
    }

    public func int64(_ idx: Int32) -> Int64 {
        sqlite3_column_int64(stmt, idx)
    }

    public func int32(_ idx: Int32) -> Int32 {
        sqlite3_column_int(stmt, idx)
    }

    public func double(_ idx: Int32) -> Double {
        sqlite3_column_double(stmt, idx)
    }

    public func bool(_ idx: Int32) -> Bool {
        sqlite3_column_int(stmt, idx) != 0
    }

    public func isNull(_ idx: Int32) -> Bool {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL
    }
}
