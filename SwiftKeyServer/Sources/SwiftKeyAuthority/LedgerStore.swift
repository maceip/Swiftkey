import Foundation
import Darwin
import CSQLite
import SwiftKeyCore

/// Private SQLite state and public hash-linked events share one FULL-sync WAL
/// transaction. The directory lock prevents two authority processes. Hashes
/// detect partial corruption and divergence, not a complete rollback or rewrite
/// by an attacker who can replace the entire database and all checkpoints.
/// External checkpoint anchoring is required for that stronger guarantee.
final class LedgerStore: @unchecked Sendable {
    private let files: SecureStateFile
    private let lock = NSLock()
    private var database: OpaquePointer?
    private var cachedHead = LedgerHead.genesis
    private var commitSequence: UInt64 = 0
    private var commitHash = Data(repeating: 0, count: 32)
    private var stateHash: Data?
    private var poisoned = false
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL) throws {
        self.files = try SecureStateFile(directory: directory)
        // SecureStateFile already rejected a symlink at the state directory.
        // Resolve parent aliases such as macOS /var -> /private/var before
        // SQLite NOFOLLOW checks every path component. Do not resolve the
        // database filename: a symlink there must still be rejected.
        guard let resolved = realpath(files.directory.path, nil) else { throw AuthorityError.rejected("Cannot resolve authority state directory") }
        let path = String(cString: resolved) + "/authority.sqlite3"
        free(resolved)
        let created = open(path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        if created >= 0 { close(created) }
        else if errno != EEXIST { throw AuthorityError.rejected("Cannot create authority database") }
        for suffix in ["", "-wal", "-shm"] { try Self.checkPrivateFile(path + suffix, required: suffix.isEmpty) }
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW
        guard sqlite3_open_v2(path, &connection, flags, nil) == SQLITE_OK, let connection else {
            let code = sqlite3_extended_errcode(connection)
            if let connection { sqlite3_close_v2(connection) }
            throw AuthorityError.rejected("Cannot open authority database (SQLite \(code))")
        }
        database = connection
        do {
            sqlite3_extended_result_codes(connection, 1)
            sqlite3_busy_timeout(connection, 5_000)
            try execute("PRAGMA trusted_schema=OFF; PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL; PRAGMA fullfsync=ON; PRAGMA checkpoint_fullfsync=ON; PRAGMA secure_delete=ON;")
            try require(try integerScalar("PRAGMA synchronous") >= 2 && integerScalar("PRAGMA fullfsync") == 1 && integerScalar("PRAGMA checkpoint_fullfsync") == 1, "SQLite full synchronization is required")
            do {
                let journal = try prepare("PRAGMA journal_mode=WAL")
                defer { sqlite3_finalize(journal) }
                try require(sqlite3_step(journal) == SQLITE_ROW && string(journal, 0) == "wal", "SQLite WAL mode is required")
            }
            let version = try integerScalar("PRAGMA user_version")
            if version == 0 {
                try require(try integerScalar("SELECT count(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'") == 0, "Unrecognized existing authority database")
                try execute(Self.schema)
            }
            try require(try integerScalar("PRAGMA user_version") == 1 && integerScalar("PRAGMA application_id") == 0x534b4c31, "Unsupported authority database format")
            try verifyDatabase()
            for suffix in ["", "-wal", "-shm"] { try Self.checkPrivateFile(path + suffix, required: suffix.isEmpty) }
            let directoryFD = open(files.directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard directoryFD >= 0 else { throw AuthorityError.rejected("Cannot open ledger directory") }
            defer { close(directoryFD) }
            try require(fsync(directoryFD) == 0, "Cannot flush ledger directory")
        } catch {
            sqlite3_close_v2(connection); database = nil; throw error
        }
    }
    deinit { if let database { sqlite3_close_v2(database) } }

    func writePublicKeyPin(_ publicKey: Data) throws {
        try lock.withLock { try healthy(); try files.write(Data((publicKey.base64EncodedString() + "\n").utf8), name: "server-public-key.txt") }
    }

    /// Legacy JSON is only read if SQLite has never committed a snapshot. The
    /// caller owns migration policy; this method does not import or erase it.
    func loadState() throws -> Data? {
        try lock.withLock {
            try healthy()
            let statement = try prepare("SELECT data,state_hash,commit_sequence FROM authority_snapshot WHERE singleton=1")
            defer { sqlite3_finalize(statement) }
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                try integrity(commitSequence == 0, "Missing authority snapshot")
                return try files.read("authority.json")
            }
            try checkRow(status)
            let data = blob(statement, 0)
            try integrity(ProtocolCrypto.sha256(data) == blob(statement, 1) && blob(statement, 1) == stateHash && uint(statement, 2) == commitSequence, "Authority snapshot diverged from ledger checkpoint")
            return data
        }
    }

    func head() throws -> LedgerHead { try lock.withLock { try healthy(); return cachedHead } }

    func events(after: UInt64, limit: Int, accountID: String? = nil) throws -> [LedgerEvent] {
        try lock.withLock {
            try healthy()
            try require((1...1000).contains(limit), "Ledger page limit must be between 1 and 1000")
            guard after <= UInt64(Int64.max) else { return [] }
            let filter = accountID == nil ? "" : " AND account_id=?"
            let statement = try prepare("SELECT sequence,timestamp,kind,account_id,device_id,actor_device_id,details,previous_hash,hash FROM ledger_events WHERE sequence>?" + filter + " ORDER BY sequence LIMIT ?")
            defer { sqlite3_finalize(statement) }
            try bind(after, statement, 1)
            if let accountID { try bind(accountID, statement, 2) }
            try bind(UInt64(limit), statement, accountID == nil ? 2 : 3)
            var result: [LedgerEvent] = []
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { return result }
                try checkRow(status)
                let event = try event(statement)
                try integrity(event.hash == ProtocolCrypto.sha256(try event.canonicalBytes()), "Ledger event hash mismatch")
                result.append(event)
            }
        }
    }

    func commit(state: Data, events drafts: [LedgerEventDraft]) throws {
        try lock.withLock {
            try healthy()
            try require(drafts.count <= 1000 && commitSequence < UInt64(Int64.max), "Ledger transaction exceeds supported bounds")
            var nextHead = cachedHead
            let additions = try drafts.map { draft in
                try require(nextHead.sequence < UInt64(Int64.max) && draft.timestamp <= UInt64(Int64.max), "Ledger sequence or timestamp exceeds SQLite range")
                let value = try LedgerEvent(sequence: nextHead.sequence + 1, draft: draft, previousHash: nextHead.hash)
                nextHead = LedgerHead(sequence: value.sequence, hash: value.hash)
                return value
            }
            let nextStateHash = ProtocolCrypto.sha256(state)
            let nextCommit = commitSequence + 1
            let nextCommitHash = try checkpointHash(sequence: nextCommit, stateHash: nextStateHash, head: nextHead, previousHash: commitHash)
            try execute("BEGIN IMMEDIATE")
            do {
                try verifyCurrentCheckpoint()
                for event in additions { try insert(event) }
                let checkpoint = try prepare("INSERT INTO ledger_commits(sequence,state_hash,event_sequence,event_hash,previous_hash,hash) VALUES(?,?,?,?,?,?)")
                defer { sqlite3_finalize(checkpoint) }
                try bind(nextCommit, checkpoint, 1); try bind(nextStateHash, checkpoint, 2)
                try bind(nextHead.sequence, checkpoint, 3); try bind(nextHead.hash, checkpoint, 4)
                try bind(commitHash, checkpoint, 5); try bind(nextCommitHash, checkpoint, 6)
                try done(checkpoint)
                let snapshot = try prepare("INSERT INTO authority_snapshot(singleton,data,state_hash,commit_sequence) VALUES(1,?,?,?) ON CONFLICT(singleton) DO UPDATE SET data=excluded.data,state_hash=excluded.state_hash,commit_sequence=excluded.commit_sequence")
                defer { sqlite3_finalize(snapshot) }
                try bind(state, snapshot, 1); try bind(nextStateHash, snapshot, 2); try bind(nextCommit, snapshot, 3)
                try done(snapshot)
                try execute("COMMIT")
                cachedHead = nextHead; commitSequence = nextCommit; commitHash = nextCommitHash; stateHash = nextStateHash
            } catch {
                if sqlite3_get_autocommit(database) == 0 {
                    do { try execute("ROLLBACK") } catch { poisoned = true }
                } else { poisoned = true }
                throw error
            }
        }
    }

    private func healthy() throws { try require(!poisoned, "Ledger persistence failed; reopen the authority", code: "unavailable") }
    private func integrity(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        try require(try condition(), message, code: "ledgerIntegrity")
    }
    private func verifyCurrentCheckpoint() throws {
        let statement = try prepare("SELECT sequence,hash FROM ledger_commits ORDER BY sequence DESC LIMIT 1")
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { try integrity(commitSequence == 0, "Ledger checkpoint disappeared") }
        else {
            try checkRow(status)
            try integrity(uint(statement, 0) == commitSequence && blob(statement, 1) == commitHash, "Ledger changed outside this authority")
        }
        let snapshot = try prepare("SELECT data,state_hash,commit_sequence FROM authority_snapshot WHERE singleton=1")
        defer { sqlite3_finalize(snapshot) }
        let snapshotStatus = sqlite3_step(snapshot)
        if commitSequence == 0 { try integrity(snapshotStatus == SQLITE_DONE, "Unexpected authority snapshot") }
        else {
            try checkRow(snapshotStatus)
            try integrity(ProtocolCrypto.sha256(blob(snapshot, 0)) == stateHash && blob(snapshot, 1) == stateHash && uint(snapshot, 2) == commitSequence, "Authority state changed outside this ledger")
        }
        let eventHead = try prepare("SELECT sequence,hash FROM ledger_events ORDER BY sequence DESC LIMIT 1")
        defer { sqlite3_finalize(eventHead) }
        let eventStatus = sqlite3_step(eventHead)
        if cachedHead.sequence == 0 { try integrity(eventStatus == SQLITE_DONE, "Unexpected ledger event") }
        else {
            try checkRow(eventStatus)
            try integrity(uint(eventHead, 0) == cachedHead.sequence && blob(eventHead, 1) == cachedHead.hash, "Ledger head changed outside this authority")
        }
    }

    private func verifyDatabase() throws {
        let check = try prepare("PRAGMA quick_check")
        defer { sqlite3_finalize(check) }
        try integrity(sqlite3_step(check) == SQLITE_ROW && string(check, 0) == "ok", "SQLite integrity check failed")
        var eventHead = LedgerHead.genesis
        let events = try prepare("SELECT sequence,timestamp,kind,account_id,device_id,actor_device_id,details,previous_hash,hash FROM ledger_events ORDER BY sequence")
        defer { sqlite3_finalize(events) }
        while true {
            let status = sqlite3_step(events)
            if status == SQLITE_DONE { break }
            try checkRow(status)
            let value = try event(events)
            try integrity(value.sequence == eventHead.sequence + 1 && value.previousHash == eventHead.hash && value.hash == ProtocolCrypto.sha256(try value.canonicalBytes()), "Ledger event chain is damaged or reordered")
            eventHead = LedgerHead(sequence: value.sequence, hash: value.hash)
        }
        var sequence: UInt64 = 0
        var previousHash = LedgerHead.genesis.hash
        var lastHead = LedgerHead.genesis
        var lastStateHash: Data?
        let commits = try prepare("SELECT sequence,state_hash,event_sequence,event_hash,previous_hash,hash FROM ledger_commits ORDER BY sequence")
        defer { sqlite3_finalize(commits) }
        while true {
            let status = sqlite3_step(commits)
            if status == SQLITE_DONE { break }
            try checkRow(status)
            let nextSequence = try uint(commits, 0)
            let digest = blob(commits, 1)
            let head = LedgerHead(sequence: try uint(commits, 2), hash: blob(commits, 3))
            let hash = blob(commits, 5)
            try integrity(nextSequence == sequence + 1 && digest.count == 32 && head.sequence >= lastHead.sequence && head.sequence <= eventHead.sequence && blob(commits, 4) == previousHash, "Ledger commit chain is damaged or reordered")
            try integrity(hash == checkpointHash(sequence: nextSequence, stateHash: digest, head: head, previousHash: previousHash), "Ledger commit hash mismatch")
            try integrity(try hashAt(head.sequence) == head.hash, "Ledger checkpoint references a different event head")
            sequence = nextSequence; previousHash = hash; lastHead = head; lastStateHash = digest
        }
        try integrity(lastHead == eventHead, "Ledger events are not bound to committed authority state")
        let snapshot = try prepare("SELECT data,state_hash,commit_sequence FROM authority_snapshot WHERE singleton=1")
        defer { sqlite3_finalize(snapshot) }
        let status = sqlite3_step(snapshot)
        if sequence == 0 { try integrity(status == SQLITE_DONE && eventHead == .genesis, "Uncommitted authority snapshot exists") }
        else {
            try checkRow(status)
            let digest = ProtocolCrypto.sha256(blob(snapshot, 0))
            try integrity(digest == blob(snapshot, 1) && digest == lastStateHash && uint(snapshot, 2) == sequence, "Authority snapshot does not match latest ledger checkpoint")
        }
        cachedHead = eventHead; commitSequence = sequence; commitHash = previousHash; stateHash = lastStateHash
    }

    private func hashAt(_ sequence: UInt64) throws -> Data {
        if sequence == 0 { return LedgerHead.genesis.hash }
        let statement = try prepare("SELECT hash FROM ledger_events WHERE sequence=?")
        defer { sqlite3_finalize(statement) }
        try bind(sequence, statement, 1); try checkRow(sqlite3_step(statement)); return blob(statement, 0)
    }
    private func checkpointHash(sequence: UInt64, stateHash: Data, head: LedgerHead, previousHash: Data) throws -> Data {
        var encoder = try CanonicalEncoder(domain: "authority-ledger-checkpoint-v1")
        encoder.append(sequence); try encoder.append(stateHash); encoder.append(head.sequence)
        try encoder.append(head.hash); try encoder.append(previousHash)
        return ProtocolCrypto.sha256(encoder.data)
    }
    private func insert(_ event: LedgerEvent) throws {
        let statement = try prepare("INSERT INTO ledger_events(sequence,timestamp,kind,account_id,device_id,actor_device_id,details,previous_hash,hash) VALUES(?,?,?,?,?,?,?,?,?)")
        defer { sqlite3_finalize(statement) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try bind(event.sequence, statement, 1); try bind(event.timestamp, statement, 2); try bind(event.kind, statement, 3)
        try bind(event.accountID, statement, 4); try bind(event.deviceID, statement, 5); try bind(event.actorDeviceID, statement, 6)
        try bind(encoder.encode(event.details), statement, 7); try bind(event.previousHash, statement, 8); try bind(event.hash, statement, 9)
        try done(statement)
    }
    private func event(_ statement: OpaquePointer) throws -> LedgerEvent {
        LedgerEvent(sequence: try uint(statement, 0), timestamp: try uint(statement, 1), kind: string(statement, 2), accountID: optionalString(statement, 3), deviceID: optionalString(statement, 4), actorDeviceID: optionalString(statement, 5), details: try JSONDecoder().decode([String: String].self, from: blob(statement, 6)), previousHash: blob(statement, 7), hash: blob(statement, 8))
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw AuthorityError.protocolFailure(code: "ledgerPersistence", message: "SQLite transaction failed (\(sqlite3_extended_errcode(database)))") }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw AuthorityError.protocolFailure(code: "ledgerPersistence", message: "Cannot prepare ledger statement") }
        return statement
    }
    private func integerScalar(_ sql: String) throws -> UInt64 {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        try checkRow(sqlite3_step(statement)); return try uint(statement, 0)
    }
    private func checkRow(_ status: Int32) throws { try require(status == SQLITE_ROW, "Cannot read ledger record", code: "ledgerIntegrity") }
    private func done(_ statement: OpaquePointer) throws { try require(sqlite3_step(statement) == SQLITE_DONE, "Cannot write ledger record", code: "ledgerPersistence") }
    private func bind(_ value: UInt64, _ statement: OpaquePointer, _ index: Int32) throws {
        try require(value <= UInt64(Int64.max) && sqlite3_bind_int64(statement, index, Int64(value)) == SQLITE_OK, "Cannot bind ledger integer")
    }
    private func bind(_ value: String?, _ statement: OpaquePointer, _ index: Int32) throws {
        let status: Int32
        if let value { status = value.withCString { sqlite3_bind_text(statement, index, $0, Int32(value.utf8.count), Self.transient) } }
        else { status = sqlite3_bind_null(statement, index) }
        try require(status == SQLITE_OK, "Cannot bind ledger string")
    }
    private func bind(_ value: Data, _ statement: OpaquePointer, _ index: Int32) throws {
        try require(value.count <= Int(Int32.max), "Ledger data exceeds SQLite range")
        let status = value.isEmpty ? sqlite3_bind_zeroblob(statement, index, 0) : value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), Self.transient) }
        try require(status == SQLITE_OK, "Cannot bind ledger data")
    }
    private func uint(_ statement: OpaquePointer, _ index: Int32) throws -> UInt64 {
        let value = sqlite3_column_int64(statement, index)
        try integrity(sqlite3_column_type(statement, index) == SQLITE_INTEGER && value >= 0, "Invalid ledger integer")
        return UInt64(value)
    }
    private func blob(_ statement: OpaquePointer, _ index: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: count)
    }
    private func string(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, index) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, index))), as: UTF8.self)
    }
    private func optionalString(_ statement: OpaquePointer, _ index: Int32) -> String? { sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : string(statement, index) }
    private static func checkPrivateFile(_ path: String, required: Bool) throws {
        var info = stat()
        if lstat(path, &info) != 0 {
            if errno == ENOENT && !required { return }
            throw AuthorityError.rejected("Cannot inspect ledger file")
        }
        try require((info.st_mode & S_IFMT) == S_IFREG && info.st_uid == geteuid() && info.st_nlink == 1 && (info.st_mode & 0o077) == 0, "Ledger files must be private owned regular files")
    }

    private static let schema = """
    BEGIN IMMEDIATE;
    CREATE TABLE authority_snapshot(singleton INTEGER PRIMARY KEY CHECK(singleton=1),data BLOB NOT NULL,state_hash BLOB NOT NULL CHECK(length(state_hash)=32),commit_sequence INTEGER NOT NULL CHECK(commit_sequence>0));
    CREATE TABLE ledger_events(sequence INTEGER PRIMARY KEY CHECK(sequence>0),timestamp INTEGER NOT NULL CHECK(timestamp>=0),kind TEXT NOT NULL,account_id TEXT,device_id TEXT,actor_device_id TEXT,details BLOB NOT NULL,previous_hash BLOB NOT NULL CHECK(length(previous_hash)=32),hash BLOB NOT NULL CHECK(length(hash)=32));
    CREATE INDEX ledger_events_account_sequence ON ledger_events(account_id,sequence);
    CREATE TABLE ledger_commits(sequence INTEGER PRIMARY KEY CHECK(sequence>0),state_hash BLOB NOT NULL CHECK(length(state_hash)=32),event_sequence INTEGER NOT NULL CHECK(event_sequence>=0),event_hash BLOB NOT NULL CHECK(length(event_hash)=32),previous_hash BLOB NOT NULL CHECK(length(previous_hash)=32),hash BLOB NOT NULL CHECK(length(hash)=32));
    CREATE TRIGGER ledger_events_no_update BEFORE UPDATE ON ledger_events BEGIN SELECT RAISE(ABORT,'append-only ledger'); END;
    CREATE TRIGGER ledger_events_no_delete BEFORE DELETE ON ledger_events BEGIN SELECT RAISE(ABORT,'append-only ledger'); END;
    CREATE TRIGGER ledger_commits_no_update BEFORE UPDATE ON ledger_commits BEGIN SELECT RAISE(ABORT,'append-only checkpoints'); END;
    CREATE TRIGGER ledger_commits_no_delete BEFORE DELETE ON ledger_commits BEGIN SELECT RAISE(ABORT,'append-only checkpoints'); END;
    PRAGMA application_id=0x534b4c31;
    PRAGMA user_version=1;
    COMMIT;
    """
}
