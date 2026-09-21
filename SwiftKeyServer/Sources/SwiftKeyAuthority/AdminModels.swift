import Foundation
import SwiftKeyCore

struct AccountRecord: Codable, Sendable {
    let accountID: String
    let label: String
    let createdAt: UInt64
    let imported: Bool
}

struct EnrollmentInvitation: Codable, Sendable {
    let accountID: String
    let deviceID: String
    let expiresAt: UInt64
    var challenge: ChallengeEnvelope?
    var enrollment: EnrollResponse?
    var certificateHash: Data?
}

struct HistoricalEpoch: Codable, Sendable {
    let credential: EpochCredential
    let issuedAt: UInt64?
}
