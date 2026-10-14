import Foundation
import SQLite3

public enum TrafficStoreError: Error, LocalizedError {
    case open(String)
    case sqlite(String)

    public var errorDescription: String? {
        switch self {
        case .open(let message): return L10n.format("无法打开数据库：{0}", message)
        case .sqlite(let message): return L10n.format("数据库错误：{0}", message)
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class TrafficStore {
    public let url: URL
    private var database: OpaquePointer?

    public convenience init() throws {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(
            "SSIDTrafficMonitor",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try self.init(url: directory.appendingPathComponent("usage.sqlite3"))
    }

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) != SQLITE_OK {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "unknown error"
            if let database { sqlite3_close(database) }
            self.database = nil
            throw TrafficStoreError.open(message)
        }

        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try migrate()
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    public func touch(_ identity: NetworkIdentity, at date: Date = Date()) throws {
        try withStatement(
            """
            INSERT INTO networks (
                identity_key, ssid, network_type, display_name, last_interface,
                total_download, total_upload, first_seen, last_used
            ) VALUES (?, ?, ?, ?, ?, 0, 0, ?, ?)
            ON CONFLICT(identity_key) DO UPDATE SET
                ssid = excluded.ssid,
                network_type = excluded.network_type,
                last_interface = excluded.last_interface,
                last_used = excluded.last_used;
            """
        ) { statement in
            bind(identity, to: statement)
            sqlite3_bind_double(statement, 6, date.timeIntervalSince1970)
            sqlite3_bind_double(statement, 7, date.timeIntervalSince1970)
            try stepDone(statement)
        }
    }

    public func setDisplayName(_ displayName: String, for identityKey: String) throws {
        try withStatement(
            "UPDATE networks SET display_name = ? WHERE identity_key = ?;"
        ) { statement in
            bindText(displayName, at: 1, to: statement)
            bindText(identityKey, at: 2, to: statement)
            try stepDone(statement)
        }
    }

    public func record(_ records: [UsageRecord]) throws {
        guard !records.isEmpty else { return }
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for record in records {
                try recordWithoutTransaction(record)
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func fetchSummaries(
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) throws -> [NetworkSummary] {
        let today = DayKey.string(for: referenceDate, calendar: calendar)
        let sevenStart = DayKey.recentSevenStart(
            for: referenceDate,
            calendar: calendar
        )
        let monthStart = DayKey.monthStart(
            for: referenceDate,
            calendar: calendar
        )

        let sql = """
        SELECT
            n.identity_key, n.display_name, n.ssid, n.network_type,
            n.last_interface, n.total_download, n.total_upload,
            n.first_seen, n.last_used,
            COALESCE(SUM(CASE WHEN d.usage_date = ? THEN d.download ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN d.usage_date = ? THEN d.upload ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN d.usage_date >= ? AND d.usage_date <= ?
                              THEN d.download ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN d.usage_date >= ? AND d.usage_date <= ?
                              THEN d.upload ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN d.usage_date >= ? AND d.usage_date <= ?
                              THEN d.download ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN d.usage_date >= ? AND d.usage_date <= ?
                              THEN d.upload ELSE 0 END), 0)
        FROM networks n
        LEFT JOIN daily_usage d ON d.network_id = n.id
        GROUP BY n.id
        ORDER BY (n.total_download + n.total_upload) DESC, n.last_used DESC;
        """

        return try withStatement(sql) { statement in
            bindText(today, at: 1, to: statement)
            bindText(today, at: 2, to: statement)
            bindText(sevenStart, at: 3, to: statement)
            bindText(today, at: 4, to: statement)
            bindText(sevenStart, at: 5, to: statement)
            bindText(today, at: 6, to: statement)
            bindText(monthStart, at: 7, to: statement)
            bindText(today, at: 8, to: statement)
            bindText(monthStart, at: 9, to: statement)
            bindText(today, at: 10, to: statement)

            var result: [NetworkSummary] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let key = columnText(statement, 0),
                      let displayName = columnText(statement, 1),
                      let kindText = columnText(statement, 3),
                      let kind = NetworkKind(rawValue: kindText),
                      let interfaceName = columnText(statement, 4) else {
                    continue
                }

                let identity = NetworkIdentity(
                    key: key,
                    displayName: displayName,
                    ssid: columnText(statement, 2),
                    kind: kind,
                    interfaceName: interfaceName
                )
                result.append(
                    NetworkSummary(
                        identity: identity,
                        today: UsageAmount(
                            download: columnUInt64(statement, 9),
                            upload: columnUInt64(statement, 10)
                        ),
                        recentSevenDays: UsageAmount(
                            download: columnUInt64(statement, 11),
                            upload: columnUInt64(statement, 12)
                        ),
                        month: UsageAmount(
                            download: columnUInt64(statement, 13),
                            upload: columnUInt64(statement, 14)
                        ),
                        allTime: UsageAmount(
                            download: columnUInt64(statement, 5),
                            upload: columnUInt64(statement, 6)
                        ),
                        firstSeen: Date(
                            timeIntervalSince1970: sqlite3_column_double(statement, 7)
                        ),
                        lastUsed: Date(
                            timeIntervalSince1970: sqlite3_column_double(statement, 8)
                        )
                    )
                )
            }
            return result
        }
    }

    public func clearHistory() throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try execute("DELETE FROM daily_usage;")
            try execute("DELETE FROM networks;")
            try execute("COMMIT;")
            try execute("PRAGMA wal_checkpoint(TRUNCATE);")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS networks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                identity_key TEXT NOT NULL UNIQUE,
                ssid TEXT,
                network_type TEXT NOT NULL,
                display_name TEXT NOT NULL,
                last_interface TEXT NOT NULL,
                total_download INTEGER NOT NULL DEFAULT 0 CHECK(total_download >= 0),
                total_upload INTEGER NOT NULL DEFAULT 0 CHECK(total_upload >= 0),
                first_seen REAL NOT NULL,
                last_used REAL NOT NULL
            );
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS daily_usage (
                network_id INTEGER NOT NULL REFERENCES networks(id) ON DELETE CASCADE,
                usage_date TEXT NOT NULL,
                download INTEGER NOT NULL DEFAULT 0 CHECK(download >= 0),
                upload INTEGER NOT NULL DEFAULT 0 CHECK(upload >= 0),
                PRIMARY KEY(network_id, usage_date)
            );
            """
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS idx_daily_usage_date ON daily_usage(usage_date);"
        )
    }

    private func recordWithoutTransaction(_ record: UsageRecord) throws {
        try touch(record.identity, at: record.timestamp)
        guard let networkID = try networkID(for: record.identity.key) else {
            throw TrafficStoreError.sqlite("network row was not created")
        }
        let download = clampedInt64(record.amount.download)
        let upload = clampedInt64(record.amount.upload)

        try withStatement(
            """
            UPDATE networks
            SET total_download = total_download + ?,
                total_upload = total_upload + ?,
                last_used = ?,
                last_interface = ?
            WHERE id = ?;
            """
        ) { statement in
            sqlite3_bind_int64(statement, 1, download)
            sqlite3_bind_int64(statement, 2, upload)
            sqlite3_bind_double(statement, 3, record.timestamp.timeIntervalSince1970)
            bindText(record.identity.interfaceName, at: 4, to: statement)
            sqlite3_bind_int64(statement, 5, networkID)
            try stepDone(statement)
        }

        try withStatement(
            """
            INSERT INTO daily_usage (network_id, usage_date, download, upload)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(network_id, usage_date) DO UPDATE SET
                download = download + excluded.download,
                upload = upload + excluded.upload;
            """
        ) { statement in
            sqlite3_bind_int64(statement, 1, networkID)
            bindText(record.day, at: 2, to: statement)
            sqlite3_bind_int64(statement, 3, download)
            sqlite3_bind_int64(statement, 4, upload)
            try stepDone(statement)
        }
    }

    private func networkID(for key: String) throws -> Int64? {
        try withStatement(
            "SELECT id FROM networks WHERE identity_key = ? LIMIT 1;"
        ) { statement in
            bindText(key, at: 1, to: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return sqlite3_column_int64(statement, 0)
        }
    }

    private func bind(_ identity: NetworkIdentity, to statement: OpaquePointer?) {
        bindText(identity.key, at: 1, to: statement)
        if let ssid = identity.ssid {
            bindText(ssid, at: 2, to: statement)
        } else {
            sqlite3_bind_null(statement, 2)
        }
        bindText(identity.kind.rawValue, at: 3, to: statement)
        bindText(identity.displayName, at: 4, to: statement)
        bindText(identity.interfaceName, at: 5, to: statement)
    }

    private func execute(_ sql: String) throws {
        guard let database else {
            throw TrafficStoreError.sqlite("database is closed")
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorPointer)
            throw TrafficStoreError.sqlite(message)
        }
    }

    private func withStatement<T>(
        _ sql: String,
        body: (OpaquePointer?) throws -> T
    ) throws -> T {
        guard let database else {
            throw TrafficStoreError.sqlite("database is closed")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TrafficStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "unknown error"
            throw TrafficStoreError.sqlite(message)
        }
    }

    private func bindText(
        _ value: String,
        at index: Int32,
        to statement: OpaquePointer?
    ) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
    }

    private func columnUInt64(_ statement: OpaquePointer?, _ index: Int32) -> UInt64 {
        let value = sqlite3_column_int64(statement, index)
        return value < 0 ? 0 : UInt64(value)
    }

    private func clampedInt64(_ value: UInt64) -> Int64 {
        value > UInt64(Int64.max) ? Int64.max : Int64(value)
    }
}
