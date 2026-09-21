import Foundation

public struct BootstrapChallengeResponse: Codable, Sendable {
    public let challenge: ChallengeEnvelope
    public let attestationChallenge: Data
    public init(challenge: ChallengeEnvelope, attestationChallenge: Data) { self.challenge = challenge; self.attestationChallenge = attestationChallenge }
}
public struct EnrollRequest: Codable, Sendable {
    public let challenge: ChallengeEnvelope
    public let certificates: [Data]
    public let proof: Data
    public init(challenge: ChallengeEnvelope, certificates: [Data], proof: Data) { self.challenge = challenge; self.certificates = certificates; self.proof = proof }
}
public struct EnrollResponse: Codable, Sendable {
    public let accountID: String
    public let deviceID: String
    public let publicKey: Data
    public let serverPublicKey: Data
    public init(accountID: String, deviceID: String, publicKey: Data, serverPublicKey: Data) { self.accountID = accountID; self.deviceID = deviceID; self.publicKey = publicKey; self.serverPublicKey = serverPublicKey }
}
public struct ChallengeRequest: Codable, Sendable {
    public let accountID: String
    public let deviceID: String
    public let operation: Operation
    public let payloadHash: Data
    public init(accountID: String, deviceID: String, operation: Operation, payloadHash: Data) { self.accountID = accountID; self.deviceID = deviceID; self.operation = operation; self.payloadHash = payloadHash }
}
public typealias ChallengeResponse = ChallengeEnvelope
public struct IssueEpochRequest: Codable, Sendable {
    public let delegation: EpochDelegation
    public let authorization: RootAuthorization
    public init(delegation: EpochDelegation, authorization: RootAuthorization) { self.delegation = delegation; self.authorization = authorization }
}
public struct VerifyWorkloadRequest: Codable, Sendable {
    public let credential: EpochCredential
    public let workload: SignedWorkload
    public init(credential: EpochCredential, workload: SignedWorkload) { self.credential = credential; self.workload = workload }
}
public struct VerifyWorkloadResponse: Codable, Sendable {
    public let accepted: Bool
    public let payloadHash: Data
    public init(accepted: Bool, payloadHash: Data) { self.accepted = accepted; self.payloadHash = payloadHash }
}
public struct PairingChallengeRequest: Codable, Sendable {
    public let accountID: String
    public init(accountID: String) { self.accountID = accountID }
}
public struct PairingCandidate: Codable, Sendable {
    public let accountID: String
    public let deviceID: String
    public let publicKey: Data
    public let expiresAt: UInt64
    public init(accountID: String, deviceID: String, publicKey: Data, expiresAt: UInt64) { self.accountID = accountID; self.deviceID = deviceID; self.publicKey = publicKey; self.expiresAt = expiresAt }
}
public struct MembershipRequest: Codable, Sendable {
    public let change: DeviceMembershipChange
    public let authorization: RootAuthorization
    public init(change: DeviceMembershipChange, authorization: RootAuthorization) { self.change = change; self.authorization = authorization }
}
public struct RecoveryRequest: Codable, Sendable {
    public let change: RecoveryChange
    public let authorization: RootAuthorization
    public init(change: RecoveryChange, authorization: RootAuthorization) { self.change = change; self.authorization = authorization }
}
public struct MutationResponse: Codable, Sendable {
    public let accepted: Bool
    public init(accepted: Bool = true) { self.accepted = accepted }
}
public struct AuthorityErrorResponse: Codable, Sendable {
    public let code: String
    public let error: String
    public init(code: String, error: String) { self.code = code; self.error = error }
}
