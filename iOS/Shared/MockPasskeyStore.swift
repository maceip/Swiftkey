import Foundation
import Darwin
import SwiftKeyPasskeys

/// Simulator-only software-key storage. This is deliberately separate from every SwiftKey root.
public final class MockPasskeyStore: @unchecked Sendable {
    public static let appGroup = "group.com.maceip.swiftkey.mock"
    public static var isMockEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private struct Envelope: Codable {
        var version: Int = 1
        var mode: String = "SIMULATOR SOFTWARE MOCK ONLY"
        var state: MockPasskeyState
    }
    private static let processLock = NSLock()
    private let directory: URL?
    let publishesSystemIdentities: Bool
    private let maximumBytes = 4 * 1024 * 1024

    /// A custom directory supports isolated simulator tests; the runtime gate cannot be overridden.
    public init(directoryURL: URL? = nil) {
        publishesSystemIdentities = directoryURL == nil
        if let directoryURL { directory = directoryURL }
        else {
            directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)?
                .appendingPathComponent("SimulatorMockPasskeys", isDirectory: true)
        }
    }

    public func credentials() throws -> [MockPasskeyCredential] {
        try locked { try MockPasskeyEngine(state: read()).credentials }
    }

    /// Approval, signing and consumed-request persistence share one cross-process transaction.
    public func transaction<T>(_ body: (inout MockPasskeyEngine) throws -> T) throws -> T {
        try locked {
            var engine = try MockPasskeyEngine(state: read())
            let value = try body(&engine)
            try write(engine.state)
            return value
        }
    }

    /// Removes only this explicitly mocked store. No keychain or protocol-root access occurs here.
    public func resetMockState() throws {
        try locked { try write(MockPasskeyState()) }
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        guard Self.isMockEnabled else { throw MockPasskeyStorageError.unavailable }
        guard let directory else { throw MockPasskeyStorageError.appGroupUnavailable }
        Self.processLock.lock(); defer { Self.processLock.unlock() }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
        let attributes = try manager.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw MockPasskeyStorageError.invalidState
        }
        let fd = Darwin.open(directory.appendingPathComponent("store.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw MockPasskeyStorageError.ioUnavailable }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw MockPasskeyStorageError.ioUnavailable }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    private var file: URL { directory!.appendingPathComponent("software-mock-credentials-v1.json") }

    private func read() throws -> MockPasskeyState {
        let fd = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 {
            if errno == ENOENT { return MockPasskeyState() }
            throw MockPasskeyStorageError.invalidState
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= maximumBytes else { throw MockPasskeyStorageError.invalidState }
        var bytes = Data(count: Int(info.st_size))
        let count = bytes.withUnsafeMutableBytes { buffer -> Int in
            var total = 0
            while total < buffer.count {
                let count = Darwin.read(fd, buffer.baseAddress!.advanced(by: total), buffer.count - total)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return -1 }
                total += count
            }
            return total
        }
        guard count == bytes.count else { throw MockPasskeyStorageError.invalidState }
        do {
            guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  Set(object.keys) == ["version", "mode", "state"] else { throw MockPasskeyStorageError.invalidState }
            let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
            guard envelope.version == 1, envelope.mode == "SIMULATOR SOFTWARE MOCK ONLY" else {
                throw MockPasskeyStorageError.invalidState
            }
            return envelope.state
        } catch { throw MockPasskeyStorageError.invalidState }
    }

    private func write(_ state: MockPasskeyState) throws {
        let bytes = try JSONEncoder().encode(Envelope(state: state))
        guard bytes.count <= maximumBytes else { throw MockPasskeyStorageError.capacity }
        let temporary = directory!.appendingPathComponent("pending-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Protection is applied before rename, so the committed file is never briefly unprotected.
        try bytes.write(to: temporary, options: [.withoutOverwriting, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        let fd = Darwin.open(temporary.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw MockPasskeyStorageError.ioUnavailable }
        let flushed = fsync(fd); Darwin.close(fd)
        guard flushed == 0, Darwin.rename(temporary.path, file.path) == 0 else {
            throw MockPasskeyStorageError.ioUnavailable
        }
        let directoryFD = Darwin.open(directory!.path, O_RDONLY)
        if directoryFD >= 0 { _ = fsync(directoryFD); Darwin.close(directoryFD) }
    }
}

public enum MockPasskeyStorageError: LocalizedError {
    case unavailable, ioUnavailable, appGroupUnavailable, invalidState, capacity
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Mock mode is available only in a Debug iOS Simulator build."
        case .ioUnavailable: "Mock mode could not access its shared storage. Check the simulator's storage and try again."
        case .appGroupUnavailable: "Mock mode cannot open its shared app-group container. Check the simulator entitlements."
        case .invalidState: "Mock mode storage is invalid or unreadable. Existing data was preserved."
        case .capacity: "Mock mode storage is full. Use an isolated test store to start another test."
        }
    }
}
