import Foundation
import SwiftKeyCore

/// V2 shares the authority's FULL-sync SQLite snapshot and public ledger commit.
/// Capability and session plaintext never enter these durable records.
struct PairingV2State: Codable, Sendable {
    var origin: String
    var audience: String
    var preparations: [String: V2Preparation] = [:]
    var identities: [String: V2Identity] = [:]
    var pairings: [String: V2Pairing] = [:]
    var genesis: [String: V2Genesis] = [:]
    var memberships: [String: V2Membership] = [:]
    var accounts: [String: V2Account] = [:]
    var challenges: [String: PairingV2.RootChallenge] = [:]
    var operations: [String: V2Operation] = [:]
    var rejectedRequests: [String: PairingV2.RootPurpose] = [:]
    var sessions: [String: V2Session] = [:]
    var admissionWindows: [String: V2RateWindow] = [:]
}
struct V2Preparation: Codable, Sendable {
    var challenge: PairingV2.PreEnrollmentChallenge
    var capabilityHash: Data
    var evidenceHash: Data?
    var originalReceipt: PairingV2.Signed<PairingV2.DeviceTrustReceipt>?
}
struct V2Identity: Codable, Sendable {
    var receipt: PairingV2.Signed<PairingV2.DeviceTrustReceipt>
    var identity: VerifiedAndroidIdentity
    var sequence: UInt64 = 0
    var accountID: String?
    var revoked = false
    var reservation: String?
}
struct V2Pairing: Codable, Sendable {
    var inspection: PairingV2.PairingInspection
    var revision: UInt64 = 1
    var status: PairingV2.OperationStatus = .open
    var secretHash: Data?
    var capturedLeaseExpiries: [String: UInt64] = [:]
    var transcript: PairingV2.Signed<PairingV2.PairTranscript>?
    var consents: [String: PairingV2.RootProof] = [:]
    var receipt: PairingV2.Signed<PairingV2.PairReceipt>?
    var proposalID: String?
}
struct V2Genesis: Codable, Sendable {
    var genesis: PairingV2.Signed<PairingV2.AccountGenesis>
    var revision: UInt64 = 1
    var status: PairingV2.OperationStatus = .proposed
    var approvals: [String: PairingV2.RootProof] = [:]
    var receipt: PairingV2.Signed<PairingV2.AccountReceipt>?
}
struct V2Membership: Codable, Sendable {
    var proposal: PairingV2.Signed<PairingV2.MembershipProposal>
    var revision: UInt64 = 1
    var status: PairingV2.OperationStatus = .proposed
    var approvals: [String: PairingV2.RootProof] = [:]
    var receipt: PairingV2.Signed<PairingV2.MembershipReceipt>?
}
struct V2Account: Codable, Sendable {
    var accountID: String
    var label: String
    var policy: String
    var revision: UInt64
    var owners: [PairingV2.OwnerDescriptor]
}
struct V2Operation: Codable, Sendable {
    var actor: String
    var purpose: PairingV2.RootPurpose
    var payloadHash: Data
    var proof: PairingV2.RootProof
    var scopeKind: PairingV2.ScopeKind
    var scopeID: String
    var response: PairingV2.OperationResponse
}
struct V2Session: Codable, Sendable {
    var accountID: String
    var deviceID: String
    var rootKeyEpoch: UInt64
    var membershipRevision: UInt64
    var expiresAt: UInt64
    var scopes: [String]
}
struct V2RateWindow: Codable, Sendable { var start: UInt64; var count: Int; var duration: UInt64 }
