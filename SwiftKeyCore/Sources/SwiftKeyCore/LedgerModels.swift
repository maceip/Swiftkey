import Foundation

public struct LedgerHead: Codable, Sendable, Equatable {
    public let sequence: UInt64
    public let hash: Data
    public init(sequence: UInt64, hash: Data) { self.sequence = sequence; self.hash = hash }
    public static let genesis = LedgerHead(sequence: 0, hash: Data(repeating: 0, count: 32))
}

public struct LedgerEvent: Codable, Sendable, Equatable {
    public let sequence: UInt64
    public let timestamp: UInt64
    public let kind: String
    public let accountID: String?
    public let deviceID: String?
    public let actorDeviceID: String?
    public let details: [String: String]
    public let previousHash: Data
    public let hash: Data

    public init(sequence: UInt64, timestamp: UInt64, kind: String, accountID: String?, deviceID: String?, actorDeviceID: String?, details: [String: String], previousHash: Data, hash: Data) {
        self.sequence = sequence; self.timestamp = timestamp; self.kind = kind
        self.accountID = accountID; self.deviceID = deviceID; self.actorDeviceID = actorDeviceID
        self.details = details; self.previousHash = previousHash; self.hash = hash
    }

    /// Bytes covered by hash; the hash field itself is excluded. Details keys
    /// sort lexicographically by NFC UTF-8 bytes, independently of JSON ordering.
    public func canonicalBytes() throws -> Data {
        guard sequence > 0, previousHash.count == 32, !kind.isEmpty, kind.utf8.count <= 256, details.count <= 128 else { throw ProtocolError.invalidField("ledgerEvent") }
        var encoder = try CanonicalEncoder(domain: "authority-ledger-event-v1")
        encoder.append(sequence); encoder.append(timestamp)
        try encoder.append(kind)
        for value in [accountID, deviceID, actorDeviceID] {
            if let value, value.utf8.count > 256 { throw ProtocolError.fieldTooLarge }
            try encoder.appendOptional(value.map { Data($0.precomposedStringWithCanonicalMapping.utf8) })
        }
        encoder.append(UInt64(details.count))
        let normalizedKeys = details.keys.map { Data($0.precomposedStringWithCanonicalMapping.utf8) }
        guard Set(normalizedKeys).count == details.count else { throw ProtocolError.invalidField("duplicateLedgerDetailKey") }
        let orderedKeys = details.keys.sorted {
            $0.precomposedStringWithCanonicalMapping.utf8.lexicographicallyPrecedes($1.precomposedStringWithCanonicalMapping.utf8)
        }
        var total = 0
        for key in orderedKeys {
            let value = details[key]!
            guard !key.isEmpty, key.utf8.count <= 256, value.utf8.count <= 4096 else { throw ProtocolError.fieldTooLarge }
            total += key.utf8.count + value.utf8.count
            guard total <= 65_536 else { throw ProtocolError.fieldTooLarge }
            try encoder.append(key); try encoder.append(value)
        }
        try encoder.append(previousHash)
        return encoder.data
    }
}
