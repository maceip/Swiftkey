import Foundation
import Testing
import CSQLite
import SwiftKeyCore
@testable import SwiftKeyAuthority

private func ledgerDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-ledger-test-" + UUID().uuidString)
}

/// Test-only connection used to simulate disk corruption/transaction failures.
/// It intentionally bypasses the production store's exclusive process lock.
private func alterDatabase(_ directory: URL, _ sql: String) throws {
    var database: OpaquePointer?
    let result = sqlite3_open_v2(directory.appendingPathComponent("authority.sqlite3").path, &database, SQLITE_OPEN_READWRITE, nil)
    guard result == SQLITE_OK, let database else { throw AuthorityError.rejected("Test database did not open") }
    defer { sqlite3_close_v2(database) }
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw AuthorityError.rejected("Test SQL failed") }
}

private func firstCommit(_ directory: URL) throws -> LedgerHead {
    let store = try LedgerStore(directory: directory)
    try store.commit(state: Data("private-state-one".utf8), events: [LedgerEventDraft(timestamp: 100, kind: "account.created", accountID: "account-a", details: ["name": "Alpha"]), LedgerEventDraft(timestamp: 101, kind: "device.enrolled", accountID: "account-a", deviceID: "device-a", actorDeviceID: "device-a")])
    return try store.head()
}

@Test func ledgerStateEventsAndCheckpointSurviveRestart() throws {
    let directory = ledgerDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let originalHead = try firstCommit(directory)
    let store = try LedgerStore(directory: directory)
    #expect(try store.loadState() == Data("private-state-one".utf8))
    #expect(try store.head() == originalHead)
    let events = try store.events(after: 0, limit: 20)
    #expect(events.map(\.sequence) == [1, 2])
    #expect(events[0].previousHash == LedgerHead.genesis.hash)
    #expect(events[1].previousHash == events[0].hash)
    #expect(events[1].hash == originalHead.hash)
    try store.commit(state: Data("private-state-two".utf8), events: [])
    #expect(try store.head() == originalHead)
    #expect(try store.loadState() == Data("private-state-two".utf8))
}

@Test func ledgerPaginationAndAccountFiltering() throws {
    let directory = ledgerDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LedgerStore(directory: directory)
    try store.commit(state: Data(), events: [LedgerEventDraft(timestamp: 1, kind: "a", accountID: "a"), LedgerEventDraft(timestamp: 2, kind: "b", accountID: "b"), LedgerEventDraft(timestamp: 3, kind: "a", accountID: "a")])
    #expect(try store.events(after: 0, limit: 1).map(\.sequence) == [1])
    #expect(try store.events(after: 1, limit: 5).map(\.sequence) == [2, 3])
    #expect(try store.events(after: 0, limit: 5, accountID: "a").map(\.sequence) == [1, 3])
    #expect(try store.events(after: UInt64.max, limit: 5).isEmpty)
    #expect(throws: (any Error).self) { try store.events(after: 0, limit: 1001) }
}

@Test func ledgerCommitRollsBackStateAndAllEventsOnWriteFailure() throws {
    let directory = ledgerDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let initialHead = try firstCommit(directory)
    let store = try LedgerStore(directory: directory)
    // Failure occurs after the new event and private checkpoint are inserted,
    // when the snapshot update runs. None may survive the failed transaction.
    try alterDatabase(directory, "CREATE TRIGGER inject_snapshot_failure BEFORE UPDATE ON authority_snapshot BEGIN SELECT RAISE(ABORT,'fixture failure'); END;")
    #expect(throws: (any Error).self) { try store.commit(state: Data("must-not-commit".utf8), events: [LedgerEventDraft(timestamp: 102, kind: "must-not-append")]) }
    #expect(try store.head() == initialHead)
    #expect(try store.loadState() == Data("private-state-one".utf8))
    #expect(try store.events(after: 0, limit: 20).count == 2)
    try alterDatabase(directory, "DROP TRIGGER inject_snapshot_failure")
    try store.commit(state: Data("success".utf8), events: [LedgerEventDraft(timestamp: 103, kind: "after-rollback")])
    #expect(try store.head().sequence == 3)
}

@Test(arguments: [
    "UPDATE authority_snapshot SET data=X'74616D7065726564' WHERE singleton=1",
    "UPDATE authority_snapshot SET data=X'74616D7065726564',state_hash=zeroblob(32) WHERE singleton=1",
    "DROP TRIGGER ledger_events_no_update; UPDATE ledger_events SET kind='tampered' WHERE sequence=1",
    "DROP TRIGGER ledger_events_no_delete; DELETE FROM ledger_events WHERE sequence=1",
    "DROP TRIGGER ledger_events_no_update; UPDATE ledger_events SET sequence=99 WHERE sequence=1",
    "DROP TRIGGER ledger_commits_no_update; UPDATE ledger_commits SET state_hash=zeroblob(32) WHERE sequence=1",
    "DROP TRIGGER ledger_commits_no_delete; DELETE FROM ledger_commits WHERE sequence=1"
])
func ledgerRejectsTamperingOrReorderingOnOpen(_ sql: String) throws {
    let directory = ledgerDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    _ = try firstCommit(directory)
    try alterDatabase(directory, sql)
    #expect(throws: (any Error).self) { try LedgerStore(directory: directory) }
}

@Test func ledgerDetectsLiveSnapshotDivergenceBeforeCommit() throws {
    let directory = ledgerDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    _ = try firstCommit(directory)
    let store = try LedgerStore(directory: directory)
    try alterDatabase(directory, "UPDATE authority_snapshot SET data=X'74616D7065726564' WHERE singleton=1")
    #expect(throws: (any Error).self) { try store.loadState() }
    #expect(throws: (any Error).self) { try store.commit(state: Data("new".utf8), events: []) }
}

@Test func legacySnapshotIsReadWithoutModificationAndImportIsExplicit() throws {
    let directory = ledgerDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let legacy = Data("legacy-private-state".utf8)
    func writeLegacy() throws { let files = try SecureStateFile(directory: directory); try files.write(legacy, name: "authority.json") }
    try writeLegacy()
    let store = try LedgerStore(directory: directory)
    #expect(try store.loadState() == legacy)
    #expect(try store.head() == .genesis)
    try store.commit(state: Data("imported-state".utf8), events: [LedgerEventDraft(timestamp: 10, kind: "authority.imported")])
    #expect(try store.loadState() == Data("imported-state".utf8))
    #expect(try Data(contentsOf: directory.appendingPathComponent("authority.json")) == legacy)
}

@Test func ledgerPermissionsAndExclusiveLock() throws {
    let directory = ledgerDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LedgerStore(directory: directory)
    try store.commit(state: Data("state".utf8), events: [])
    for name in ["authority.sqlite3", "authority.sqlite3-wal", "authority.sqlite3-shm"] {
        let path = directory.appendingPathComponent(name).path
        if FileManager.default.fileExists(atPath: path) {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }
    #expect(throws: (any Error).self) { try LedgerStore(directory: directory) }
}

@Test func ledgerRejectsDatabaseSymlink() throws {
    let directory = ledgerDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    func createDirectory() throws { _ = try SecureStateFile(directory: directory) }
    try createDirectory()
    try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("authority.sqlite3").path, withDestinationPath: directory.appendingPathComponent("elsewhere").path)
    #expect(throws: (any Error).self) { try LedgerStore(directory: directory) }
}

@Test func ledgerCanonicalHashIsIndependentOfDictionaryInsertionOrder() throws {
    let first = LedgerEventDraft(timestamp: 12, kind: "device.enrolled", accountID: "account", details: ["z": "last", "a": "first"])
    var details: [String: String] = [:]; details["a"] = "first"; details["z"] = "last"
    let second = LedgerEventDraft(timestamp: 12, kind: "device.enrolled", accountID: "account", details: details)
    let left = try LedgerEvent(sequence: 1, draft: first, previousHash: LedgerHead.genesis.hash)
    let right = try LedgerEvent(sequence: 1, draft: second, previousHash: LedgerHead.genesis.hash)
    #expect(left.hash == right.hash)
    #expect(try left.canonicalBytes() == right.canonicalBytes())
    #expect(left.hash == ProtocolCrypto.sha256(try left.canonicalBytes()))
    let composed = LedgerEventDraft(timestamp: 12, kind: "event", details: ["caf\u{e9}": "r\u{e9}sum\u{e9}"])
    let decomposed = LedgerEventDraft(timestamp: 12, kind: "event", details: ["cafe\u{301}": "re\u{301}sume\u{301}"])
    #expect(try LedgerEvent(sequence: 1, draft: composed, previousHash: LedgerHead.genesis.hash).hash == LedgerEvent(sequence: 1, draft: decomposed, previousHash: LedgerHead.genesis.hash).hash)
}
