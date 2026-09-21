import Foundation
import SwiftKeyCore

/// Public audit metadata only. Never put tokens, private keys, full state,
/// signatures, certificate chains, or workload payloads in details.
public struct LedgerEventDraft: Codable, Sendable, Equatable {
    public let timestamp: UInt64
    public let kind: String
    public let accountID: String?
    public let deviceID: String?
    public let actorDeviceID: String?
    public let details: [String: String]

    public init(timestamp: UInt64, kind: String, accountID: String? = nil, deviceID: String? = nil, actorDeviceID: String? = nil, details: [String: String] = [:]) {
        self.timestamp = timestamp; self.kind = kind; self.accountID = accountID
        self.deviceID = deviceID; self.actorDeviceID = actorDeviceID; self.details = details
    }
}

extension LedgerEvent {
    init(sequence: UInt64, draft: LedgerEventDraft, previousHash: Data) throws {
        let unsigned = LedgerEvent(sequence: sequence, timestamp: draft.timestamp, kind: draft.kind, accountID: draft.accountID, deviceID: draft.deviceID, actorDeviceID: draft.actorDeviceID, details: draft.details, previousHash: previousHash, hash: Data())
        self.init(sequence: sequence, timestamp: draft.timestamp, kind: draft.kind, accountID: draft.accountID, deviceID: draft.deviceID, actorDeviceID: draft.actorDeviceID, details: draft.details, previousHash: previousHash, hash: ProtocolCrypto.sha256(try unsigned.canonicalBytes()))
    }

}
