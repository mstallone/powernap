import Foundation
import Logging

public final class StateStore {
    private let db: SQLite
    private let queue = DispatchQueue(label: "dev.powernap.state", qos: .utility)
    private let logger: Logger

    public init(path: String = ConfigPaths.stateDBPath, logger: Logger? = nil) throws {
        let dir = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        self.db = try SQLite(path: path)
        self.logger = logger ?? PowerNAPLogger.make("state")
        try migrate()
        secureStoreFiles(path: path)
    }

    private func migrate() throws {
        try db.transaction {
            try db.exec("""
            CREATE TABLE IF NOT EXISTS schema_version(
                version INTEGER PRIMARY KEY
            );
            """)
            let current = try db.query("SELECT version FROM schema_version LIMIT 1;") { row in
                row.int(0)
            }.first ?? 0

            if current < 1 {
                try db.exec("""
                CREATE TABLE IF NOT EXISTS sessions(
                    run_id TEXT PRIMARY KEY,
                    agent TEXT NOT NULL,
                    session_id TEXT,
                    hook_token TEXT NOT NULL,
                    cwd TEXT,
                    started_at REAL NOT NULL,
                    ended_at REAL,
                    last_phase TEXT,
                    last_event_at REAL
                );
                CREATE INDEX IF NOT EXISTS idx_sessions_agent ON sessions(agent);

                CREATE TABLE IF NOT EXISTS leases(
                    id TEXT PRIMARY KEY,
                    run_id TEXT,
                    lease_type TEXT NOT NULL,
                    acquired_at REAL NOT NULL,
                    expires_at REAL NOT NULL,
                    heartbeat_at REAL NOT NULL,
                    released_at REAL,
                    release_reason TEXT,
                    metadata TEXT
                );
                CREATE INDEX IF NOT EXISTS idx_leases_open ON leases(released_at);
                CREATE INDEX IF NOT EXISTS idx_leases_run ON leases(run_id);

                CREATE TABLE IF NOT EXISTS events(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    run_id TEXT,
                    agent TEXT,
                    phase TEXT NOT NULL,
                    source_event TEXT,
                    tool_name TEXT,
                    cwd TEXT,
                    timestamp REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_events_run ON events(run_id);
                CREATE INDEX IF NOT EXISTS idx_events_ts ON events(timestamp);

                CREATE TABLE IF NOT EXISTS clamshell_state(
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    active INTEGER NOT NULL,
                    set_at REAL,
                    set_by_pid INTEGER
                );
                INSERT OR IGNORE INTO clamshell_state(id, active) VALUES(1, 0);
                """)
                try db.execute("INSERT INTO schema_version(version) VALUES(?);", [1])
            }
        }
    }

    private func secureStoreFiles(path: String) {
        let fm = FileManager.default
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: 0o600)]
        for candidate in [path, "\(path)-wal", "\(path)-shm"] where fm.fileExists(atPath: candidate) {
            try? fm.setAttributes(attrs, ofItemAtPath: candidate)
        }
    }

    public func sync<R>(_ body: () throws -> R) rethrows -> R {
        try queue.sync(execute: body)
    }

    public func createSession(runId: String, agent: String, sessionId: String?, hookToken: String, cwd: String?) throws {
        _ = try queue.sync {
            try db.execute("""
            INSERT OR REPLACE INTO sessions(run_id, agent, session_id, hook_token, cwd, started_at)
            VALUES(?, ?, ?, ?, ?, ?);
            """, [runId, agent, sessionId, hookToken, cwd, Date().timeIntervalSince1970])
        }
    }

    public func endSession(runId: String, phase: String) throws {
        _ = try queue.sync {
            try db.execute("""
            UPDATE sessions SET ended_at = ?, last_phase = ?, last_event_at = ?
            WHERE run_id = ?;
            """, [Date().timeIntervalSince1970, phase, Date().timeIntervalSince1970, runId])
        }
    }

    public func lookupHookToken(runId: String) throws -> String? {
        try queue.sync {
            try db.query("SELECT hook_token FROM sessions WHERE run_id = ? LIMIT 1;", [runId]) { row in
                row.string(0) ?? ""
            }.first
        }
    }

    public func recordEvent(_ event: AgentEvent) throws {
        try queue.sync {
            try db.execute("""
            INSERT INTO events(run_id, agent, phase, source_event, tool_name, cwd, timestamp)
            VALUES(?, ?, ?, ?, ?, ?, ?);
            """, [
                event.runId,
                event.agent,
                event.phase.rawValue,
                event.sourceEvent,
                event.toolName,
                event.cwd,
                event.timestamp.timeIntervalSince1970
            ])
            try db.execute("""
            UPDATE sessions SET last_phase = ?, last_event_at = ?
            WHERE run_id = ?;
            """, [event.phase.rawValue, event.timestamp.timeIntervalSince1970, event.runId])
        }
    }

    public func saveLease(_ lease: Lease) throws {
        try queue.sync {
            let metaJSON: String?
            if lease.metadata.isEmpty {
                metaJSON = nil
            } else {
                let data = try JSONEncoder().encode(lease.metadata)
                metaJSON = String(data: data, encoding: .utf8)
            }
            try db.execute("""
            INSERT OR REPLACE INTO leases(id, run_id, lease_type, acquired_at, expires_at, heartbeat_at, released_at, release_reason, metadata)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, [
                lease.id,
                lease.runId,
                lease.leaseType.rawValue,
                lease.acquiredAt.timeIntervalSince1970,
                lease.expiresAt.timeIntervalSince1970,
                lease.heartbeatAt.timeIntervalSince1970,
                lease.releasedAt?.timeIntervalSince1970,
                lease.releaseReason?.rawValue,
                metaJSON
            ])
        }
    }

    public func releaseLease(id: String, reason: LeaseReleaseReason, at: Date = Date()) throws {
        _ = try queue.sync {
            try db.execute("""
            UPDATE leases SET released_at = ?, release_reason = ?
            WHERE id = ? AND released_at IS NULL;
            """, [at.timeIntervalSince1970, reason.rawValue, id])
        }
    }

    public func heartbeat(leaseID: String, at: Date = Date()) throws {
        _ = try queue.sync {
            try db.execute("""
            UPDATE leases SET heartbeat_at = ? WHERE id = ? AND released_at IS NULL;
            """, [at.timeIntervalSince1970, leaseID])
        }
    }

    public func extendLease(id: String, expiresAt: Date) throws {
        _ = try queue.sync {
            try db.execute("""
            UPDATE leases SET expires_at = ? WHERE id = ? AND released_at IS NULL;
            """, [expiresAt.timeIntervalSince1970, id])
        }
    }

    public func openLeases() throws -> [Lease] {
        try queue.sync {
            try db.query("""
            SELECT id, run_id, lease_type, acquired_at, expires_at, heartbeat_at, released_at, release_reason, metadata
            FROM leases WHERE released_at IS NULL;
            """) { row in
                try rowToLease(row)
            }
        }
    }

    public func allLeases(limit: Int = 200) throws -> [Lease] {
        try queue.sync {
            try db.query("""
            SELECT id, run_id, lease_type, acquired_at, expires_at, heartbeat_at, released_at, release_reason, metadata
            FROM leases ORDER BY acquired_at DESC LIMIT ?;
            """, [limit]) { row in
                try rowToLease(row)
            }
        }
    }

    public func leasesForRun(_ runId: String) throws -> [Lease] {
        try queue.sync {
            try db.query("""
            SELECT id, run_id, lease_type, acquired_at, expires_at, heartbeat_at, released_at, release_reason, metadata
            FROM leases WHERE run_id = ?;
            """, [runId]) { row in
                try rowToLease(row)
            }
        }
    }

    public func openSessions() throws -> [SessionRow] {
        try queue.sync {
            try db.query("""
            SELECT run_id, agent, session_id, cwd, started_at, ended_at, last_phase, last_event_at
            FROM sessions WHERE ended_at IS NULL ORDER BY started_at DESC;
            """) { row in
                SessionRow(
                    runId: row.string(0) ?? "",
                    agent: row.string(1) ?? "",
                    sessionId: row.string(2),
                    cwd: row.string(3),
                    startedAt: Date(timeIntervalSince1970: row.double(4)),
                    endedAt: row.isNull(5) ? nil : Date(timeIntervalSince1970: row.double(5)),
                    lastPhase: row.string(6),
                    lastEventAt: row.isNull(7) ? nil : Date(timeIntervalSince1970: row.double(7))
                )
            }
        }
    }

    public func setClamshellActive(_ active: Bool, pid: Int32?) throws {
        try queue.sync {
            let pidParam: SQLiteBindable? = pid.map { Int($0) }
            try db.execute("""
            UPDATE clamshell_state SET active = ?, set_at = ?, set_by_pid = ? WHERE id = 1;
            """, [active ? 1 : 0, Date().timeIntervalSince1970, pidParam])
        }
    }

    public func clamshellIsActive() throws -> Bool {
        try queue.sync {
            try db.query("SELECT active FROM clamshell_state WHERE id = 1;") { row in
                row.bool(0)
            }.first ?? false
        }
    }

    public func janitorStaleLeases(olderThan ttl: TimeInterval, now: Date = Date()) throws -> [Lease] {
        try queue.sync {
            let cutoff = now.timeIntervalSince1970 - ttl
            let stale: [Lease] = try db.query("""
            SELECT id, run_id, lease_type, acquired_at, expires_at, heartbeat_at, released_at, release_reason, metadata
            FROM leases WHERE released_at IS NULL AND heartbeat_at < ?;
            """, [cutoff]) { row in
                try rowToLease(row)
            }
            for lease in stale {
                try db.execute("""
                UPDATE leases SET released_at = ?, release_reason = ?
                WHERE id = ?;
                """, [now.timeIntervalSince1970, LeaseReleaseReason.watchdog.rawValue, lease.id])
            }
            return stale
        }
    }

    private func rowToLease(_ row: SQLiteRow) throws -> Lease {
        let metaJSON = row.string(8)
        let metadata: [String: String]
        if let s = metaJSON, let data = s.data(using: .utf8), !s.isEmpty {
            metadata = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        } else {
            metadata = [:]
        }
        let reasonRaw = row.string(7)
        return Lease(
            id: row.string(0) ?? "",
            runId: row.string(1),
            leaseType: LeaseType(rawValue: row.string(2) ?? "") ?? .idleSleep,
            acquiredAt: Date(timeIntervalSince1970: row.double(3)),
            expiresAt: Date(timeIntervalSince1970: row.double(4)),
            heartbeatAt: Date(timeIntervalSince1970: row.double(5)),
            releasedAt: row.isNull(6) ? nil : Date(timeIntervalSince1970: row.double(6)),
            releaseReason: reasonRaw.flatMap(LeaseReleaseReason.init(rawValue:)),
            metadata: metadata
        )
    }
}

public struct SessionRow: Codable, Sendable {
    public let runId: String
    public let agent: String
    public let sessionId: String?
    public let cwd: String?
    public let startedAt: Date
    public let endedAt: Date?
    public let lastPhase: String?
    public let lastEventAt: Date?
}
