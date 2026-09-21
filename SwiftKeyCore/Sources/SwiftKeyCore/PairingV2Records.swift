import Foundation

/// Canonical v2 records. JSON transport is deliberately distinct from signed bytes.
public protocol PairingV2CanonicalRecord: Codable, Sendable, Equatable {
    func validate() throws
    func canonicalBytes() throws -> Data
}
public extension PairingV2CanonicalRecord {
    func digest() throws -> Data { ProtocolCrypto.sha256(try canonicalBytes()) }
}

public enum PairingV2 {
    public static let audience = "swiftkey-authority-v2"
    public static let ownershipPolicy = "two-owner-survivor-v1"
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidField(String), unknownField(String), duplicateKey(String), invalidJSON, unsupportedRootKind, invalidSignature, bindingMismatch, expired
    }
    public enum RootKind: String, Codable, Sendable {
        case androidStrongBox = "android-strongbox-p256", appleAppAttest = "apple-app-attest"
        public func validate() throws { guard self == .androidStrongBox else { throw Error.unsupportedRootKind } }
    }
    public enum PairingPurpose: String, Codable, Sendable { case createAccount, addOwner, replaceOwner }
    public enum RootPurpose: String, Codable, Sendable {
        case createPairing, joinPairing, confirmPair, proposeAccount, replaceGenesis, approveGenesis, proposeMembership, approveMembership, control, renewIdentityLease, authenticateOwner, getResult
    }
    public enum ScopeKind: String, Codable, Sendable { case identity, pairing, genesisProposal, membershipProposal, operation }
    public enum OperationStatus: String, Codable, Sendable {
        case open = "OPEN", peerBound = "PEER_BOUND", paired = "PAIRED", proposed = "PROPOSED", partiallyApproved = "PARTIALLY_APPROVED", pending = "PENDING", committed = "COMMITTED", cancelled = "CANCELLED", rejected = "REJECTED", expired = "EXPIRED", invalidated = "INVALIDATED"
        public var isTerminal: Bool { [.committed, .cancelled, .rejected, .expired, .invalidated].contains(self) }
    }
    public enum ControlOperation: String, Codable, Sendable { case cancel, reject, rotateUnjoinedSecret }
}

extension PairingV2 {
    public final class OwnerDescriptor: PairingV2CanonicalRecord {
        public let deviceID: String
        public let rootKind: RootKind
        public let rootKeyEpoch: UInt64
        public let rootPublicKey: Data
        public let attestationReceiptHash: Data
        public let role: String
        public init(deviceID: String, rootKind: RootKind, rootKeyEpoch: UInt64, rootPublicKey: Data, attestationReceiptHash: Data, role: String = "owner") {
            self.deviceID = deviceID
            self.rootKind = rootKind
            self.rootKeyEpoch = rootKeyEpoch
            self.rootPublicKey = rootPublicKey
            self.attestationReceiptHash = attestationReceiptHash
            self.role = role
        }
        public static func == (lhs: OwnerDescriptor, rhs: OwnerDescriptor) -> Bool {
            if lhs === rhs { return true }
            guard lhs.deviceID == rhs.deviceID else { return false }
            guard lhs.rootKind == rhs.rootKind else { return false }
            guard lhs.rootKeyEpoch == rhs.rootKeyEpoch else { return false }
            guard lhs.rootPublicKey == rhs.rootPublicKey else { return false }
            guard lhs.attestationReceiptHash == rhs.attestationReceiptHash else { return false }
            guard lhs.role == rhs.role else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(deviceID, forKey: .deviceID)
            try c.encode(rootKind, forKey: .rootKind)
            try c.encode(V2UInt64(wrappedValue: rootKeyEpoch), forKey: .rootKeyEpoch)
            try c.encode(rootPublicKey, forKey: .rootPublicKey)
            try c.encode(attestationReceiptHash, forKey: .attestationReceiptHash)
            try c.encode(role, forKey: .role)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case deviceID, rootKind, rootKeyEpoch, rootPublicKey, attestationReceiptHash, role }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.deviceID = try c.decode(String.self, forKey: .deviceID)
            self.rootKind = try c.decode(RootKind.self, forKey: .rootKind)
            self.rootKeyEpoch = try c.decode(V2UInt64.self, forKey: .rootKeyEpoch).wrappedValue
            self.rootPublicKey = try PairingV2.decodeData(c.decode(String.self, forKey: .rootPublicKey))
            self.attestationReceiptHash = try PairingV2.decodeData(c.decode(String.self, forKey: .attestationReceiptHash))
            self.role = try c.decode(String.self, forKey: .role)
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateID(deviceID)
            try PairingV2.validateHash(attestationReceiptHash)
            try PairingV2.validateID(deviceID); try rootKind.validate(); try PairingV2.require(rootKeyEpoch > 0, "rootKeyEpoch"); try ProtocolCrypto.validatePublicKey(rootPublicKey); try PairingV2.validateHash(attestationReceiptHash); try PairingV2.require(role == "owner", "role")
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "owner-descriptor-v2")
            try encoder.append(deviceID)
            try encoder.append(rootKind.rawValue)
            encoder.append(rootKeyEpoch)
            try encoder.append(rootPublicKey)
            try encoder.append(attestationReceiptHash)
            try encoder.append(role)
            return encoder.data
        }
    }

    public final class PreEnrollmentChallenge: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let challengeID: String
        public let requestID: String
        public let deviceID: String
        public let rootKind: RootKind
        public let trustPolicyID: String
        public let nonce: Data
        public let issuedAt: UInt64
        public let expiresAt: UInt64
        public init(authorityID: Data, origin: String, audience: String, challengeID: String, requestID: String, deviceID: String, rootKind: RootKind, trustPolicyID: String, nonce: Data, issuedAt: UInt64, expiresAt: UInt64) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.challengeID = challengeID
            self.requestID = requestID
            self.deviceID = deviceID
            self.rootKind = rootKind
            self.trustPolicyID = trustPolicyID
            self.nonce = nonce
            self.issuedAt = issuedAt
            self.expiresAt = expiresAt
        }
        public static func == (lhs: PreEnrollmentChallenge, rhs: PreEnrollmentChallenge) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.challengeID == rhs.challengeID else { return false }
            guard lhs.requestID == rhs.requestID else { return false }
            guard lhs.deviceID == rhs.deviceID else { return false }
            guard lhs.rootKind == rhs.rootKind else { return false }
            guard lhs.trustPolicyID == rhs.trustPolicyID else { return false }
            guard lhs.nonce == rhs.nonce else { return false }
            guard lhs.issuedAt == rhs.issuedAt else { return false }
            guard lhs.expiresAt == rhs.expiresAt else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(challengeID, forKey: .challengeID)
            try c.encode(requestID, forKey: .requestID)
            try c.encode(deviceID, forKey: .deviceID)
            try c.encode(rootKind, forKey: .rootKind)
            try c.encode(trustPolicyID, forKey: .trustPolicyID)
            try c.encode(nonce, forKey: .nonce)
            try c.encode(V2UInt64(wrappedValue: issuedAt), forKey: .issuedAt)
            try c.encode(V2UInt64(wrappedValue: expiresAt), forKey: .expiresAt)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, challengeID, requestID, deviceID, rootKind, trustPolicyID, nonce, issuedAt, expiresAt }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.challengeID = try c.decode(String.self, forKey: .challengeID)
            self.requestID = try c.decode(String.self, forKey: .requestID)
            self.deviceID = try c.decode(String.self, forKey: .deviceID)
            self.rootKind = try c.decode(RootKind.self, forKey: .rootKind)
            self.trustPolicyID = try c.decode(String.self, forKey: .trustPolicyID)
            self.nonce = try PairingV2.decodeData(c.decode(String.self, forKey: .nonce))
            self.issuedAt = try c.decode(V2UInt64.self, forKey: .issuedAt).wrappedValue
            self.expiresAt = try c.decode(V2UInt64.self, forKey: .expiresAt).wrappedValue
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(challengeID)
            try PairingV2.validateID(requestID)
            try PairingV2.validateID(deviceID)
            try PairingV2.validateHash(nonce)
            try rootKind.validate(); try PairingV2.validateText(trustPolicyID); try PairingV2.validateLifetime(issuedAt, expiresAt, maximum: 900)
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "preaccount-enrollment-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(challengeID)
            try encoder.append(requestID)
            try encoder.append(deviceID)
            try encoder.append(rootKind.rawValue)
            try encoder.append(trustPolicyID)
            try encoder.append(nonce)
            encoder.append(issuedAt)
            encoder.append(expiresAt)
            return encoder.data
        }
    }

    public final class AttestationEvidence: PairingV2CanonicalRecord {
        public let rootKind: RootKind
        public let certificates: [Data]
        public init(rootKind: RootKind, certificates: [Data]) {
            self.rootKind = rootKind
            self.certificates = certificates
        }
        public static func == (lhs: AttestationEvidence, rhs: AttestationEvidence) -> Bool {
            if lhs === rhs { return true }
            guard lhs.rootKind == rhs.rootKind else { return false }
            guard lhs.certificates == rhs.certificates else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(rootKind, forKey: .rootKind)
            try c.encode(certificates, forKey: .certificates)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case rootKind, certificates }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.rootKind = try c.decode(RootKind.self, forKey: .rootKind)
            self.certificates = try c.decode([String].self, forKey: .certificates).map(PairingV2.decodeData)
            try validate()
        }
        public func validate() throws {
            try rootKind.validate(); try PairingV2.require(!certificates.isEmpty && certificates.count <= 8 && certificates.allSatisfy { !$0.isEmpty && $0.count <= 65536 }, "certificates")
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "attestation-evidence-v2")
            try encoder.append(rootKind.rawValue)
            encoder.append(UInt64(certificates.count)); for value in certificates { try encoder.append(value) }
            return encoder.data
        }
    }

    public final class DeviceTrustReceipt: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let deviceID: String
        public let rootKind: RootKind
        public let rootKeyEpoch: UInt64
        public let rootPublicKey: Data
        public let originalChallengeHash: Data
        public let evidenceHash: Data
        public let trustPolicyID: String
        public let verifiedAt: UInt64
        public let leaseExpiresAt: UInt64
        public init(authorityID: Data, origin: String, audience: String, deviceID: String, rootKind: RootKind, rootKeyEpoch: UInt64, rootPublicKey: Data, originalChallengeHash: Data, evidenceHash: Data, trustPolicyID: String, verifiedAt: UInt64, leaseExpiresAt: UInt64) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.deviceID = deviceID
            self.rootKind = rootKind
            self.rootKeyEpoch = rootKeyEpoch
            self.rootPublicKey = rootPublicKey
            self.originalChallengeHash = originalChallengeHash
            self.evidenceHash = evidenceHash
            self.trustPolicyID = trustPolicyID
            self.verifiedAt = verifiedAt
            self.leaseExpiresAt = leaseExpiresAt
        }
        public static func == (lhs: DeviceTrustReceipt, rhs: DeviceTrustReceipt) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.deviceID == rhs.deviceID else { return false }
            guard lhs.rootKind == rhs.rootKind else { return false }
            guard lhs.rootKeyEpoch == rhs.rootKeyEpoch else { return false }
            guard lhs.rootPublicKey == rhs.rootPublicKey else { return false }
            guard lhs.originalChallengeHash == rhs.originalChallengeHash else { return false }
            guard lhs.evidenceHash == rhs.evidenceHash else { return false }
            guard lhs.trustPolicyID == rhs.trustPolicyID else { return false }
            guard lhs.verifiedAt == rhs.verifiedAt else { return false }
            guard lhs.leaseExpiresAt == rhs.leaseExpiresAt else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(deviceID, forKey: .deviceID)
            try c.encode(rootKind, forKey: .rootKind)
            try c.encode(V2UInt64(wrappedValue: rootKeyEpoch), forKey: .rootKeyEpoch)
            try c.encode(rootPublicKey, forKey: .rootPublicKey)
            try c.encode(originalChallengeHash, forKey: .originalChallengeHash)
            try c.encode(evidenceHash, forKey: .evidenceHash)
            try c.encode(trustPolicyID, forKey: .trustPolicyID)
            try c.encode(V2UInt64(wrappedValue: verifiedAt), forKey: .verifiedAt)
            try c.encode(V2UInt64(wrappedValue: leaseExpiresAt), forKey: .leaseExpiresAt)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, deviceID, rootKind, rootKeyEpoch, rootPublicKey, originalChallengeHash, evidenceHash, trustPolicyID, verifiedAt, leaseExpiresAt }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.deviceID = try c.decode(String.self, forKey: .deviceID)
            self.rootKind = try c.decode(RootKind.self, forKey: .rootKind)
            self.rootKeyEpoch = try c.decode(V2UInt64.self, forKey: .rootKeyEpoch).wrappedValue
            self.rootPublicKey = try PairingV2.decodeData(c.decode(String.self, forKey: .rootPublicKey))
            self.originalChallengeHash = try PairingV2.decodeData(c.decode(String.self, forKey: .originalChallengeHash))
            self.evidenceHash = try PairingV2.decodeData(c.decode(String.self, forKey: .evidenceHash))
            self.trustPolicyID = try c.decode(String.self, forKey: .trustPolicyID)
            self.verifiedAt = try c.decode(V2UInt64.self, forKey: .verifiedAt).wrappedValue
            self.leaseExpiresAt = try c.decode(V2UInt64.self, forKey: .leaseExpiresAt).wrappedValue
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(deviceID)
            try PairingV2.validateHash(originalChallengeHash)
            try PairingV2.validateHash(evidenceHash)
            try rootKind.validate(); try PairingV2.require(rootKeyEpoch > 0, "rootKeyEpoch"); try ProtocolCrypto.validatePublicKey(rootPublicKey); try PairingV2.validateText(trustPolicyID); try PairingV2.validateLifetime(verifiedAt, leaseExpiresAt, maximum: 900)
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "device-trust-receipt-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(deviceID)
            try encoder.append(rootKind.rawValue)
            encoder.append(rootKeyEpoch)
            try encoder.append(rootPublicKey)
            try encoder.append(originalChallengeHash)
            try encoder.append(evidenceHash)
            try encoder.append(trustPolicyID)
            encoder.append(verifiedAt)
            encoder.append(leaseExpiresAt)
            return encoder.data
        }
    }

    public final class AccountRoster: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let accountID: String
        public let accountLabel: String
        public let ownershipPolicyID: String
        public let membershipRevision: UInt64
        public let owners: [OwnerDescriptor]
        public let issuedAt: UInt64
        public let expiresAt: UInt64
        public init(authorityID: Data, origin: String, audience: String, accountID: String, accountLabel: String, ownershipPolicyID: String, membershipRevision: UInt64, owners: [OwnerDescriptor], issuedAt: UInt64, expiresAt: UInt64) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.accountID = accountID
            self.accountLabel = accountLabel
            self.ownershipPolicyID = ownershipPolicyID
            self.membershipRevision = membershipRevision
            self.owners = owners
            self.issuedAt = issuedAt
            self.expiresAt = expiresAt
        }
        public static func == (lhs: AccountRoster, rhs: AccountRoster) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.accountID == rhs.accountID else { return false }
            guard lhs.accountLabel == rhs.accountLabel else { return false }
            guard lhs.ownershipPolicyID == rhs.ownershipPolicyID else { return false }
            guard lhs.membershipRevision == rhs.membershipRevision else { return false }
            guard lhs.owners == rhs.owners else { return false }
            guard lhs.issuedAt == rhs.issuedAt else { return false }
            guard lhs.expiresAt == rhs.expiresAt else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(accountID, forKey: .accountID)
            try c.encode(accountLabel, forKey: .accountLabel)
            try c.encode(ownershipPolicyID, forKey: .ownershipPolicyID)
            try c.encode(V2UInt64(wrappedValue: membershipRevision), forKey: .membershipRevision)
            try c.encode(owners, forKey: .owners)
            try c.encode(V2UInt64(wrappedValue: issuedAt), forKey: .issuedAt)
            try c.encode(V2UInt64(wrappedValue: expiresAt), forKey: .expiresAt)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, accountID, accountLabel, ownershipPolicyID, membershipRevision, owners, issuedAt, expiresAt }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.accountID = try c.decode(String.self, forKey: .accountID)
            self.accountLabel = try c.decode(String.self, forKey: .accountLabel)
            self.ownershipPolicyID = try c.decode(String.self, forKey: .ownershipPolicyID)
            self.membershipRevision = try c.decode(V2UInt64.self, forKey: .membershipRevision).wrappedValue
            self.owners = try c.decode([OwnerDescriptor].self, forKey: .owners)
            self.issuedAt = try c.decode(V2UInt64.self, forKey: .issuedAt).wrappedValue
            self.expiresAt = try c.decode(V2UInt64.self, forKey: .expiresAt).wrappedValue
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(accountID)
            try PairingV2.validateLabel(accountLabel); try PairingV2.validatePolicy(ownershipPolicyID); try PairingV2.require(membershipRevision > 0, "membershipRevision"); try PairingV2.validateOwners(owners, minimum: 2); try PairingV2.validateLifetime(issuedAt, expiresAt, maximum: 60)
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "account-roster-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(accountID)
            try encoder.append(accountLabel)
            try encoder.append(ownershipPolicyID)
            encoder.append(membershipRevision)
            encoder.append(UInt64(owners.count)); for value in owners { try encoder.append(value.canonicalBytes()) }
            encoder.append(issuedAt)
            encoder.append(expiresAt)
            return encoder.data
        }
    }

    public final class ExistingAccountContext: PairingV2CanonicalRecord {
        public let accountID: String
        public let accountLabel: String
        public let ownershipPolicyID: String
        public let membershipRevision: UInt64
        public let existingOwners: [OwnerDescriptor]
        public let lostOwner: OwnerDescriptor?
        public init(accountID: String, accountLabel: String, ownershipPolicyID: String, membershipRevision: UInt64, existingOwners: [OwnerDescriptor], lostOwner: OwnerDescriptor? = nil) {
            self.accountID = accountID
            self.accountLabel = accountLabel
            self.ownershipPolicyID = ownershipPolicyID
            self.membershipRevision = membershipRevision
            self.existingOwners = existingOwners
            self.lostOwner = lostOwner
        }
        public static func == (lhs: ExistingAccountContext, rhs: ExistingAccountContext) -> Bool {
            if lhs === rhs { return true }
            guard lhs.accountID == rhs.accountID else { return false }
            guard lhs.accountLabel == rhs.accountLabel else { return false }
            guard lhs.ownershipPolicyID == rhs.ownershipPolicyID else { return false }
            guard lhs.membershipRevision == rhs.membershipRevision else { return false }
            guard lhs.existingOwners == rhs.existingOwners else { return false }
            guard lhs.lostOwner == rhs.lostOwner else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(accountID, forKey: .accountID)
            try c.encode(accountLabel, forKey: .accountLabel)
            try c.encode(ownershipPolicyID, forKey: .ownershipPolicyID)
            try c.encode(V2UInt64(wrappedValue: membershipRevision), forKey: .membershipRevision)
            try c.encode(existingOwners, forKey: .existingOwners)
            try c.encodeIfPresent(lostOwner, forKey: .lostOwner)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case accountID, accountLabel, ownershipPolicyID, membershipRevision, existingOwners, lostOwner }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.accountID = try c.decode(String.self, forKey: .accountID)
            self.accountLabel = try c.decode(String.self, forKey: .accountLabel)
            self.ownershipPolicyID = try c.decode(String.self, forKey: .ownershipPolicyID)
            self.membershipRevision = try c.decode(V2UInt64.self, forKey: .membershipRevision).wrappedValue
            self.existingOwners = try c.decode([OwnerDescriptor].self, forKey: .existingOwners)
            self.lostOwner = try c.decodeIfPresent(OwnerDescriptor.self, forKey: .lostOwner)
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateID(accountID)
            try lostOwner?.validate()
            try PairingV2.validateLabel(accountLabel); try PairingV2.validatePolicy(ownershipPolicyID); try PairingV2.require(membershipRevision > 0, "membershipRevision"); try PairingV2.validateOwners(existingOwners, minimum: 2); if let lostOwner { try PairingV2.require(existingOwners.contains(lostOwner), "lostOwner") }
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "existing-account-context-v2")
            try encoder.append(accountID)
            try encoder.append(accountLabel)
            try encoder.append(ownershipPolicyID)
            encoder.append(membershipRevision)
            encoder.append(UInt64(existingOwners.count)); for value in existingOwners { try encoder.append(value.canonicalBytes()) }
            try encoder.appendOptional(lostOwner?.canonicalBytes())
            return encoder.data
        }
    }

    public final class PairingContext: PairingV2CanonicalRecord {
        public let purpose: PairingPurpose
        public let existingAccount: ExistingAccountContext?
        public init(purpose: PairingPurpose, existingAccount: ExistingAccountContext? = nil) {
            self.purpose = purpose
            self.existingAccount = existingAccount
        }
        public static func == (lhs: PairingContext, rhs: PairingContext) -> Bool {
            if lhs === rhs { return true }
            guard lhs.purpose == rhs.purpose else { return false }
            guard lhs.existingAccount == rhs.existingAccount else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(purpose, forKey: .purpose)
            try c.encodeIfPresent(existingAccount, forKey: .existingAccount)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case purpose, existingAccount }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.purpose = try c.decode(PairingPurpose.self, forKey: .purpose)
            self.existingAccount = try c.decodeIfPresent(ExistingAccountContext.self, forKey: .existingAccount)
            try validate()
        }
        public func validate() throws {
            try existingAccount?.validate()
            switch purpose { case .createAccount: try PairingV2.require(existingAccount == nil, "existingAccount"); case .addOwner: try PairingV2.require(existingAccount != nil && existingAccount?.lostOwner == nil, "existingAccount"); case .replaceOwner: try PairingV2.require(existingAccount?.lostOwner != nil, "lostOwner") }
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "pairing-context-v2")
            try encoder.append(purpose.rawValue)
            try encoder.appendOptional(existingAccount?.canonicalBytes())
            return encoder.data
        }
    }

    public final class CreatePairingIntent: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let requestID: String
        public let initiator: OwnerDescriptor
        public let context: PairingContext
        public init(authorityID: Data, origin: String, audience: String, requestID: String, initiator: OwnerDescriptor, context: PairingContext) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.requestID = requestID
            self.initiator = initiator
            self.context = context
        }
        public static func == (lhs: CreatePairingIntent, rhs: CreatePairingIntent) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.requestID == rhs.requestID else { return false }
            guard lhs.initiator == rhs.initiator else { return false }
            guard lhs.context == rhs.context else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(requestID, forKey: .requestID)
            try c.encode(initiator, forKey: .initiator)
            try c.encode(context, forKey: .context)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, requestID, initiator, context }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.requestID = try c.decode(String.self, forKey: .requestID)
            self.initiator = try c.decode(OwnerDescriptor.self, forKey: .initiator)
            self.context = try c.decode(PairingContext.self, forKey: .context)
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(requestID)
            try initiator.validate()
            try context.validate()
            if let account = context.existingAccount { try PairingV2.require(account.existingOwners.contains { $0.hasSameRoot(as: initiator) } && account.lostOwner?.deviceID != initiator.deviceID, "initiator") }
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "create-pairing-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(requestID)
            try encoder.append(initiator.canonicalBytes())
            try encoder.append(context.canonicalBytes())
            return encoder.data
        }
    }

    public final class PairingInspection: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let pairingID: String
        public let revision: UInt64
        public let initiator: OwnerDescriptor
        public let context: PairingContext
        public let issuedAt: UInt64
        public let expiresAt: UInt64
        public init(authorityID: Data, origin: String, audience: String, pairingID: String, revision: UInt64, initiator: OwnerDescriptor, context: PairingContext, issuedAt: UInt64, expiresAt: UInt64) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.pairingID = pairingID
            self.revision = revision
            self.initiator = initiator
            self.context = context
            self.issuedAt = issuedAt
            self.expiresAt = expiresAt
        }
        public static func == (lhs: PairingInspection, rhs: PairingInspection) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.pairingID == rhs.pairingID else { return false }
            guard lhs.revision == rhs.revision else { return false }
            guard lhs.initiator == rhs.initiator else { return false }
            guard lhs.context == rhs.context else { return false }
            guard lhs.issuedAt == rhs.issuedAt else { return false }
            guard lhs.expiresAt == rhs.expiresAt else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(pairingID, forKey: .pairingID)
            try c.encode(V2UInt64(wrappedValue: revision), forKey: .revision)
            try c.encode(initiator, forKey: .initiator)
            try c.encode(context, forKey: .context)
            try c.encode(V2UInt64(wrappedValue: issuedAt), forKey: .issuedAt)
            try c.encode(V2UInt64(wrappedValue: expiresAt), forKey: .expiresAt)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, pairingID, revision, initiator, context, issuedAt, expiresAt }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.pairingID = try c.decode(String.self, forKey: .pairingID)
            self.revision = try c.decode(V2UInt64.self, forKey: .revision).wrappedValue
            self.initiator = try c.decode(OwnerDescriptor.self, forKey: .initiator)
            self.context = try c.decode(PairingContext.self, forKey: .context)
            self.issuedAt = try c.decode(V2UInt64.self, forKey: .issuedAt).wrappedValue
            self.expiresAt = try c.decode(V2UInt64.self, forKey: .expiresAt).wrappedValue
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(pairingID)
            try initiator.validate()
            try context.validate()
            try PairingV2.require(revision > 0, "revision"); try PairingV2.validateLifetime(issuedAt, expiresAt, maximum: 120); if let account = context.existingAccount { try PairingV2.require(account.existingOwners.contains { $0.hasSameRoot(as: initiator) } && account.lostOwner?.deviceID != initiator.deviceID, "initiator") }
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "pairing-inspection-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(pairingID)
            encoder.append(revision)
            try encoder.append(initiator.canonicalBytes())
            try encoder.append(context.canonicalBytes())
            encoder.append(issuedAt)
            encoder.append(expiresAt)
            return encoder.data
        }
    }

    public final class JoinPairingIntent: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let pairingID: String
        public let expectedRevision: UInt64
        public let inspectionHash: Data
        public let initiatorHash: Data
        public let candidate: OwnerDescriptor
        public init(authorityID: Data, origin: String, audience: String, pairingID: String, expectedRevision: UInt64, inspectionHash: Data, initiatorHash: Data, candidate: OwnerDescriptor) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.pairingID = pairingID
            self.expectedRevision = expectedRevision
            self.inspectionHash = inspectionHash
            self.initiatorHash = initiatorHash
            self.candidate = candidate
        }
        public static func == (lhs: JoinPairingIntent, rhs: JoinPairingIntent) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.pairingID == rhs.pairingID else { return false }
            guard lhs.expectedRevision == rhs.expectedRevision else { return false }
            guard lhs.inspectionHash == rhs.inspectionHash else { return false }
            guard lhs.initiatorHash == rhs.initiatorHash else { return false }
            guard lhs.candidate == rhs.candidate else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(pairingID, forKey: .pairingID)
            try c.encode(V2UInt64(wrappedValue: expectedRevision), forKey: .expectedRevision)
            try c.encode(inspectionHash, forKey: .inspectionHash)
            try c.encode(initiatorHash, forKey: .initiatorHash)
            try c.encode(candidate, forKey: .candidate)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, pairingID, expectedRevision, inspectionHash, initiatorHash, candidate }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.pairingID = try c.decode(String.self, forKey: .pairingID)
            self.expectedRevision = try c.decode(V2UInt64.self, forKey: .expectedRevision).wrappedValue
            self.inspectionHash = try PairingV2.decodeData(c.decode(String.self, forKey: .inspectionHash))
            self.initiatorHash = try PairingV2.decodeData(c.decode(String.self, forKey: .initiatorHash))
            self.candidate = try c.decode(OwnerDescriptor.self, forKey: .candidate)
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(pairingID)
            try PairingV2.validateHash(inspectionHash)
            try PairingV2.validateHash(initiatorHash)
            try candidate.validate()
            try PairingV2.require(expectedRevision > 0, "expectedRevision")
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "join-pairing-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(pairingID)
            encoder.append(expectedRevision)
            try encoder.append(inspectionHash)
            try encoder.append(initiatorHash)
            try encoder.append(candidate.canonicalBytes())
            return encoder.data
        }
    }

    public final class PairTranscript: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let pairingID: String
        public let revision: UInt64
        public let context: PairingContext
        public let owners: [OwnerDescriptor]
        public let nonce: Data
        public let issuedAt: UInt64
        public let expiresAt: UInt64
        public init(authorityID: Data, origin: String, audience: String, pairingID: String, revision: UInt64, context: PairingContext, owners: [OwnerDescriptor], nonce: Data, issuedAt: UInt64, expiresAt: UInt64) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.pairingID = pairingID
            self.revision = revision
            self.context = context
            self.owners = owners
            self.nonce = nonce
            self.issuedAt = issuedAt
            self.expiresAt = expiresAt
        }
        public static func == (lhs: PairTranscript, rhs: PairTranscript) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.pairingID == rhs.pairingID else { return false }
            guard lhs.revision == rhs.revision else { return false }
            guard lhs.context == rhs.context else { return false }
            guard lhs.owners == rhs.owners else { return false }
            guard lhs.nonce == rhs.nonce else { return false }
            guard lhs.issuedAt == rhs.issuedAt else { return false }
            guard lhs.expiresAt == rhs.expiresAt else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(pairingID, forKey: .pairingID)
            try c.encode(V2UInt64(wrappedValue: revision), forKey: .revision)
            try c.encode(context, forKey: .context)
            try c.encode(owners, forKey: .owners)
            try c.encode(nonce, forKey: .nonce)
            try c.encode(V2UInt64(wrappedValue: issuedAt), forKey: .issuedAt)
            try c.encode(V2UInt64(wrappedValue: expiresAt), forKey: .expiresAt)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, pairingID, revision, context, owners, nonce, issuedAt, expiresAt }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.pairingID = try c.decode(String.self, forKey: .pairingID)
            self.revision = try c.decode(V2UInt64.self, forKey: .revision).wrappedValue
            self.context = try c.decode(PairingContext.self, forKey: .context)
            self.owners = try c.decode([OwnerDescriptor].self, forKey: .owners)
            self.nonce = try PairingV2.decodeData(c.decode(String.self, forKey: .nonce))
            self.issuedAt = try c.decode(V2UInt64.self, forKey: .issuedAt).wrappedValue
            self.expiresAt = try c.decode(V2UInt64.self, forKey: .expiresAt).wrappedValue
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(pairingID)
            try context.validate()
            try PairingV2.validateHash(nonce)
            try PairingV2.require(revision > 0, "revision"); try PairingV2.validateOwners(owners, minimum: 2, maximum: 2); try PairingV2.validateLifetime(issuedAt, expiresAt, maximum: 120)
            if let account = context.existingAccount { let existing = owners.filter { owner in account.existingOwners.contains { $0.hasSameRoot(as: owner) } }; try PairingV2.require(existing.count == 1 && existing.first?.deviceID != account.lostOwner?.deviceID, "pairParticipants") }
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "pair-transcript-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(pairingID)
            encoder.append(revision)
            try encoder.append(context.canonicalBytes())
            encoder.append(UInt64(owners.count)); for value in owners { try encoder.append(value.canonicalBytes()) }
            try encoder.append(nonce)
            encoder.append(issuedAt)
            encoder.append(expiresAt)
            return encoder.data
        }
    }

    public final class ProposeAccountIntent: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let pairingID: String
        public let expectedRevision: UInt64
        public let pairReceiptHash: Data
        public let label: String
        public let ownershipPolicyID: String
        public init(authorityID: Data, origin: String, audience: String, pairingID: String, expectedRevision: UInt64, pairReceiptHash: Data, label: String, ownershipPolicyID: String) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.pairingID = pairingID
            self.expectedRevision = expectedRevision
            self.pairReceiptHash = pairReceiptHash
            self.label = label
            self.ownershipPolicyID = ownershipPolicyID
        }
        public static func == (lhs: ProposeAccountIntent, rhs: ProposeAccountIntent) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.pairingID == rhs.pairingID else { return false }
            guard lhs.expectedRevision == rhs.expectedRevision else { return false }
            guard lhs.pairReceiptHash == rhs.pairReceiptHash else { return false }
            guard lhs.label == rhs.label else { return false }
            guard lhs.ownershipPolicyID == rhs.ownershipPolicyID else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(pairingID, forKey: .pairingID)
            try c.encode(V2UInt64(wrappedValue: expectedRevision), forKey: .expectedRevision)
            try c.encode(pairReceiptHash, forKey: .pairReceiptHash)
            try c.encode(label, forKey: .label)
            try c.encode(ownershipPolicyID, forKey: .ownershipPolicyID)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, pairingID, expectedRevision, pairReceiptHash, label, ownershipPolicyID }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.pairingID = try c.decode(String.self, forKey: .pairingID)
            self.expectedRevision = try c.decode(V2UInt64.self, forKey: .expectedRevision).wrappedValue
            self.pairReceiptHash = try PairingV2.decodeData(c.decode(String.self, forKey: .pairReceiptHash))
            self.label = try c.decode(String.self, forKey: .label)
            self.ownershipPolicyID = try c.decode(String.self, forKey: .ownershipPolicyID)
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(pairingID)
            try PairingV2.validateHash(pairReceiptHash)
            try PairingV2.require(expectedRevision > 0, "expectedRevision"); try PairingV2.validateLabel(label); try PairingV2.validatePolicy(ownershipPolicyID)
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "propose-account-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(pairingID)
            encoder.append(expectedRevision)
            try encoder.append(pairReceiptHash)
            try encoder.append(label)
            try encoder.append(ownershipPolicyID)
            return encoder.data
        }
    }

    public final class ReplaceGenesisIntent: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let pairingID: String
        public let expectedRevision: UInt64
        public let oldProposalHash: Data
        public let newLabel: String
        public let newOwnershipPolicyID: String
        public init(authorityID: Data, origin: String, audience: String, pairingID: String, expectedRevision: UInt64, oldProposalHash: Data, newLabel: String, newOwnershipPolicyID: String) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.pairingID = pairingID
            self.expectedRevision = expectedRevision
            self.oldProposalHash = oldProposalHash
            self.newLabel = newLabel
            self.newOwnershipPolicyID = newOwnershipPolicyID
        }
        public static func == (lhs: ReplaceGenesisIntent, rhs: ReplaceGenesisIntent) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.pairingID == rhs.pairingID else { return false }
            guard lhs.expectedRevision == rhs.expectedRevision else { return false }
            guard lhs.oldProposalHash == rhs.oldProposalHash else { return false }
            guard lhs.newLabel == rhs.newLabel else { return false }
            guard lhs.newOwnershipPolicyID == rhs.newOwnershipPolicyID else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(pairingID, forKey: .pairingID)
            try c.encode(V2UInt64(wrappedValue: expectedRevision), forKey: .expectedRevision)
            try c.encode(oldProposalHash, forKey: .oldProposalHash)
            try c.encode(newLabel, forKey: .newLabel)
            try c.encode(newOwnershipPolicyID, forKey: .newOwnershipPolicyID)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, pairingID, expectedRevision, oldProposalHash, newLabel, newOwnershipPolicyID }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.pairingID = try c.decode(String.self, forKey: .pairingID)
            self.expectedRevision = try c.decode(V2UInt64.self, forKey: .expectedRevision).wrappedValue
            self.oldProposalHash = try PairingV2.decodeData(c.decode(String.self, forKey: .oldProposalHash))
            self.newLabel = try c.decode(String.self, forKey: .newLabel)
            self.newOwnershipPolicyID = try c.decode(String.self, forKey: .newOwnershipPolicyID)
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(pairingID)
            try PairingV2.validateHash(oldProposalHash)
            try PairingV2.require(expectedRevision > 0, "expectedRevision"); try PairingV2.validateLabel(newLabel); try PairingV2.validatePolicy(newOwnershipPolicyID)
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "replace-genesis-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(pairingID)
            encoder.append(expectedRevision)
            try encoder.append(oldProposalHash)
            try encoder.append(newLabel)
            try encoder.append(newOwnershipPolicyID)
            return encoder.data
        }
    }

    public final class RenewLeaseIntent: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let deviceID: String
        public let rootKeyEpoch: UInt64
        public let existingTrustReceiptHash: Data
        public init(authorityID: Data, origin: String, audience: String, deviceID: String, rootKeyEpoch: UInt64, existingTrustReceiptHash: Data) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.deviceID = deviceID
            self.rootKeyEpoch = rootKeyEpoch
            self.existingTrustReceiptHash = existingTrustReceiptHash
        }
        public static func == (lhs: RenewLeaseIntent, rhs: RenewLeaseIntent) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.deviceID == rhs.deviceID else { return false }
            guard lhs.rootKeyEpoch == rhs.rootKeyEpoch else { return false }
            guard lhs.existingTrustReceiptHash == rhs.existingTrustReceiptHash else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(deviceID, forKey: .deviceID)
            try c.encode(V2UInt64(wrappedValue: rootKeyEpoch), forKey: .rootKeyEpoch)
            try c.encode(existingTrustReceiptHash, forKey: .existingTrustReceiptHash)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, deviceID, rootKeyEpoch, existingTrustReceiptHash }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.deviceID = try c.decode(String.self, forKey: .deviceID)
            self.rootKeyEpoch = try c.decode(V2UInt64.self, forKey: .rootKeyEpoch).wrappedValue
            self.existingTrustReceiptHash = try PairingV2.decodeData(c.decode(String.self, forKey: .existingTrustReceiptHash))
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(deviceID)
            try PairingV2.validateHash(existingTrustReceiptHash)
            try PairingV2.require(rootKeyEpoch > 0, "rootKeyEpoch")
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "renew-identity-lease-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(deviceID)
            encoder.append(rootKeyEpoch)
            try encoder.append(existingTrustReceiptHash)
            return encoder.data
        }
    }

    public final class AccountGenesis: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let proposalID: String
        public let pairingID: String
        public let pairTranscriptHash: Data
        public let accountID: String
        public let label: String
        public let owners: [OwnerDescriptor]
        public let ownershipPolicyID: String
        public let initialMembershipRevision: UInt64
        public let nonce: Data
        public let issuedAt: UInt64
        public let expiresAt: UInt64
        public init(authorityID: Data, origin: String, audience: String, proposalID: String, pairingID: String, pairTranscriptHash: Data, accountID: String, label: String, owners: [OwnerDescriptor], ownershipPolicyID: String, initialMembershipRevision: UInt64, nonce: Data, issuedAt: UInt64, expiresAt: UInt64) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.proposalID = proposalID
            self.pairingID = pairingID
            self.pairTranscriptHash = pairTranscriptHash
            self.accountID = accountID
            self.label = label
            self.owners = owners
            self.ownershipPolicyID = ownershipPolicyID
            self.initialMembershipRevision = initialMembershipRevision
            self.nonce = nonce
            self.issuedAt = issuedAt
            self.expiresAt = expiresAt
        }
        public static func == (lhs: AccountGenesis, rhs: AccountGenesis) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.proposalID == rhs.proposalID else { return false }
            guard lhs.pairingID == rhs.pairingID else { return false }
            guard lhs.pairTranscriptHash == rhs.pairTranscriptHash else { return false }
            guard lhs.accountID == rhs.accountID else { return false }
            guard lhs.label == rhs.label else { return false }
            guard lhs.owners == rhs.owners else { return false }
            guard lhs.ownershipPolicyID == rhs.ownershipPolicyID else { return false }
            guard lhs.initialMembershipRevision == rhs.initialMembershipRevision else { return false }
            guard lhs.nonce == rhs.nonce else { return false }
            guard lhs.issuedAt == rhs.issuedAt else { return false }
            guard lhs.expiresAt == rhs.expiresAt else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(proposalID, forKey: .proposalID)
            try c.encode(pairingID, forKey: .pairingID)
            try c.encode(pairTranscriptHash, forKey: .pairTranscriptHash)
            try c.encode(accountID, forKey: .accountID)
            try c.encode(label, forKey: .label)
            try c.encode(owners, forKey: .owners)
            try c.encode(ownershipPolicyID, forKey: .ownershipPolicyID)
            try c.encode(V2UInt64(wrappedValue: initialMembershipRevision), forKey: .initialMembershipRevision)
            try c.encode(nonce, forKey: .nonce)
            try c.encode(V2UInt64(wrappedValue: issuedAt), forKey: .issuedAt)
            try c.encode(V2UInt64(wrappedValue: expiresAt), forKey: .expiresAt)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, proposalID, pairingID, pairTranscriptHash, accountID, label, owners, ownershipPolicyID, initialMembershipRevision, nonce, issuedAt, expiresAt }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.proposalID = try c.decode(String.self, forKey: .proposalID)
            self.pairingID = try c.decode(String.self, forKey: .pairingID)
            self.pairTranscriptHash = try PairingV2.decodeData(c.decode(String.self, forKey: .pairTranscriptHash))
            self.accountID = try c.decode(String.self, forKey: .accountID)
            self.label = try c.decode(String.self, forKey: .label)
            self.owners = try c.decode([OwnerDescriptor].self, forKey: .owners)
            self.ownershipPolicyID = try c.decode(String.self, forKey: .ownershipPolicyID)
            self.initialMembershipRevision = try c.decode(V2UInt64.self, forKey: .initialMembershipRevision).wrappedValue
            self.nonce = try PairingV2.decodeData(c.decode(String.self, forKey: .nonce))
            self.issuedAt = try c.decode(V2UInt64.self, forKey: .issuedAt).wrappedValue
            self.expiresAt = try c.decode(V2UInt64.self, forKey: .expiresAt).wrappedValue
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(proposalID)
            try PairingV2.validateID(pairingID)
            try PairingV2.validateHash(pairTranscriptHash)
            try PairingV2.validateID(accountID)
            try PairingV2.validateHash(nonce)
            try PairingV2.validateLabel(label); try PairingV2.validatePolicy(ownershipPolicyID); try PairingV2.validateOwners(owners, minimum: 2, maximum: 2); try PairingV2.require(initialMembershipRevision == 1, "initialMembershipRevision"); try PairingV2.validateLifetime(issuedAt, expiresAt, maximum: 300)
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "account-genesis-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(proposalID)
            try encoder.append(pairingID)
            try encoder.append(pairTranscriptHash)
            try encoder.append(accountID)
            try encoder.append(label)
            encoder.append(UInt64(owners.count)); for value in owners { try encoder.append(value.canonicalBytes()) }
            try encoder.append(ownershipPolicyID)
            encoder.append(initialMembershipRevision)
            try encoder.append(nonce)
            encoder.append(issuedAt)
            encoder.append(expiresAt)
            return encoder.data
        }
    }

    public final class ProposeMembershipIntent: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let pairingID: String
        public let expectedPairingRevision: UInt64
        public let pairReceiptHash: Data
        public let context: PairingContext
        public init(authorityID: Data, origin: String, audience: String, pairingID: String, expectedPairingRevision: UInt64, pairReceiptHash: Data, context: PairingContext) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.pairingID = pairingID
            self.expectedPairingRevision = expectedPairingRevision
            self.pairReceiptHash = pairReceiptHash
            self.context = context
        }
        public static func == (lhs: ProposeMembershipIntent, rhs: ProposeMembershipIntent) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.pairingID == rhs.pairingID else { return false }
            guard lhs.expectedPairingRevision == rhs.expectedPairingRevision else { return false }
            guard lhs.pairReceiptHash == rhs.pairReceiptHash else { return false }
            guard lhs.context == rhs.context else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(pairingID, forKey: .pairingID)
            try c.encode(V2UInt64(wrappedValue: expectedPairingRevision), forKey: .expectedPairingRevision)
            try c.encode(pairReceiptHash, forKey: .pairReceiptHash)
            try c.encode(context, forKey: .context)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, pairingID, expectedPairingRevision, pairReceiptHash, context }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.pairingID = try c.decode(String.self, forKey: .pairingID)
            self.expectedPairingRevision = try c.decode(V2UInt64.self, forKey: .expectedPairingRevision).wrappedValue
            self.pairReceiptHash = try PairingV2.decodeData(c.decode(String.self, forKey: .pairReceiptHash))
            self.context = try c.decode(PairingContext.self, forKey: .context)
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(pairingID)
            try PairingV2.validateHash(pairReceiptHash)
            try context.validate()
            try PairingV2.require(expectedPairingRevision > 0 && context.purpose != .createAccount, "membershipContext")
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "propose-membership-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(pairingID)
            encoder.append(expectedPairingRevision)
            try encoder.append(pairReceiptHash)
            try encoder.append(context.canonicalBytes())
            return encoder.data
        }
    }

    public final class MembershipProposal: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let proposalID: String
        public let pairingID: String
        public let pairTranscriptHash: Data
        public let pairReceiptHash: Data
        public let context: PairingContext
        public let authorizingOwner: OwnerDescriptor
        public let candidate: OwnerDescriptor
        public let resultingOwners: [OwnerDescriptor]
        public let nextMembershipRevision: UInt64
        public let nonce: Data
        public let issuedAt: UInt64
        public let expiresAt: UInt64
        public init(authorityID: Data, origin: String, audience: String, proposalID: String, pairingID: String, pairTranscriptHash: Data, pairReceiptHash: Data, context: PairingContext, authorizingOwner: OwnerDescriptor, candidate: OwnerDescriptor, resultingOwners: [OwnerDescriptor], nextMembershipRevision: UInt64, nonce: Data, issuedAt: UInt64, expiresAt: UInt64) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.proposalID = proposalID
            self.pairingID = pairingID
            self.pairTranscriptHash = pairTranscriptHash
            self.pairReceiptHash = pairReceiptHash
            self.context = context
            self.authorizingOwner = authorizingOwner
            self.candidate = candidate
            self.resultingOwners = resultingOwners
            self.nextMembershipRevision = nextMembershipRevision
            self.nonce = nonce
            self.issuedAt = issuedAt
            self.expiresAt = expiresAt
        }
        public static func == (lhs: MembershipProposal, rhs: MembershipProposal) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.proposalID == rhs.proposalID else { return false }
            guard lhs.pairingID == rhs.pairingID else { return false }
            guard lhs.pairTranscriptHash == rhs.pairTranscriptHash else { return false }
            guard lhs.pairReceiptHash == rhs.pairReceiptHash else { return false }
            guard lhs.context == rhs.context else { return false }
            guard lhs.authorizingOwner == rhs.authorizingOwner else { return false }
            guard lhs.candidate == rhs.candidate else { return false }
            guard lhs.resultingOwners == rhs.resultingOwners else { return false }
            guard lhs.nextMembershipRevision == rhs.nextMembershipRevision else { return false }
            guard lhs.nonce == rhs.nonce else { return false }
            guard lhs.issuedAt == rhs.issuedAt else { return false }
            guard lhs.expiresAt == rhs.expiresAt else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(proposalID, forKey: .proposalID)
            try c.encode(pairingID, forKey: .pairingID)
            try c.encode(pairTranscriptHash, forKey: .pairTranscriptHash)
            try c.encode(pairReceiptHash, forKey: .pairReceiptHash)
            try c.encode(context, forKey: .context)
            try c.encode(authorizingOwner, forKey: .authorizingOwner)
            try c.encode(candidate, forKey: .candidate)
            try c.encode(resultingOwners, forKey: .resultingOwners)
            try c.encode(V2UInt64(wrappedValue: nextMembershipRevision), forKey: .nextMembershipRevision)
            try c.encode(nonce, forKey: .nonce)
            try c.encode(V2UInt64(wrappedValue: issuedAt), forKey: .issuedAt)
            try c.encode(V2UInt64(wrappedValue: expiresAt), forKey: .expiresAt)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, proposalID, pairingID, pairTranscriptHash, pairReceiptHash, context, authorizingOwner, candidate, resultingOwners, nextMembershipRevision, nonce, issuedAt, expiresAt }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.proposalID = try c.decode(String.self, forKey: .proposalID)
            self.pairingID = try c.decode(String.self, forKey: .pairingID)
            self.pairTranscriptHash = try PairingV2.decodeData(c.decode(String.self, forKey: .pairTranscriptHash))
            self.pairReceiptHash = try PairingV2.decodeData(c.decode(String.self, forKey: .pairReceiptHash))
            self.context = try c.decode(PairingContext.self, forKey: .context)
            self.authorizingOwner = try c.decode(OwnerDescriptor.self, forKey: .authorizingOwner)
            self.candidate = try c.decode(OwnerDescriptor.self, forKey: .candidate)
            self.resultingOwners = try c.decode([OwnerDescriptor].self, forKey: .resultingOwners)
            self.nextMembershipRevision = try c.decode(V2UInt64.self, forKey: .nextMembershipRevision).wrappedValue
            self.nonce = try PairingV2.decodeData(c.decode(String.self, forKey: .nonce))
            self.issuedAt = try c.decode(V2UInt64.self, forKey: .issuedAt).wrappedValue
            self.expiresAt = try c.decode(V2UInt64.self, forKey: .expiresAt).wrappedValue
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(proposalID)
            try PairingV2.validateID(pairingID)
            try PairingV2.validateHash(pairTranscriptHash)
            try PairingV2.validateHash(pairReceiptHash)
            try context.validate()
            try authorizingOwner.validate()
            try candidate.validate()
            try PairingV2.validateHash(nonce)
            guard let account = context.existingAccount else { throw PairingV2.Error.invalidField("existingAccount") }
            try PairingV2.require(context.purpose != .createAccount && account.membershipRevision < UInt64.max && nextMembershipRevision == account.membershipRevision + 1, "membershipRevision")
            try PairingV2.require(account.existingOwners.contains { $0.hasSameRoot(as: authorizingOwner) } && account.lostOwner?.deviceID != authorizingOwner.deviceID, "authorizingOwner")
            try PairingV2.require(!account.existingOwners.contains { $0.deviceID == candidate.deviceID || $0.rootPublicKey == candidate.rootPublicKey }, "candidate")
            let expected = (account.existingOwners.filter { $0.deviceID != account.lostOwner?.deviceID } + [candidate]).sorted { $0.deviceID < $1.deviceID }
            try PairingV2.require(resultingOwners == expected, "resultingOwners"); try PairingV2.validateOwners(resultingOwners, minimum: 2); try PairingV2.validateLifetime(issuedAt, expiresAt, maximum: 300)
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "membership-proposal-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(proposalID)
            try encoder.append(pairingID)
            try encoder.append(pairTranscriptHash)
            try encoder.append(pairReceiptHash)
            try encoder.append(context.canonicalBytes())
            try encoder.append(authorizingOwner.canonicalBytes())
            try encoder.append(candidate.canonicalBytes())
            encoder.append(UInt64(resultingOwners.count)); for value in resultingOwners { try encoder.append(value.canonicalBytes()) }
            encoder.append(nextMembershipRevision)
            try encoder.append(nonce)
            encoder.append(issuedAt)
            encoder.append(expiresAt)
            return encoder.data
        }
    }

    public final class RootChallenge: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let challengeID: String
        public let requestID: String
        public let deviceID: String
        public let rootKeyEpoch: UInt64
        public let purpose: RootPurpose
        public let scopeID: String
        public let payloadHash: Data
        public let sequence: UInt64
        public let issuedAt: UInt64
        public let expiresAt: UInt64
        public let nonce: Data
        public init(authorityID: Data, origin: String, audience: String, challengeID: String, requestID: String, deviceID: String, rootKeyEpoch: UInt64, purpose: RootPurpose, scopeID: String, payloadHash: Data, sequence: UInt64, issuedAt: UInt64, expiresAt: UInt64, nonce: Data) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.challengeID = challengeID
            self.requestID = requestID
            self.deviceID = deviceID
            self.rootKeyEpoch = rootKeyEpoch
            self.purpose = purpose
            self.scopeID = scopeID
            self.payloadHash = payloadHash
            self.sequence = sequence
            self.issuedAt = issuedAt
            self.expiresAt = expiresAt
            self.nonce = nonce
        }
        public static func == (lhs: RootChallenge, rhs: RootChallenge) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.challengeID == rhs.challengeID else { return false }
            guard lhs.requestID == rhs.requestID else { return false }
            guard lhs.deviceID == rhs.deviceID else { return false }
            guard lhs.rootKeyEpoch == rhs.rootKeyEpoch else { return false }
            guard lhs.purpose == rhs.purpose else { return false }
            guard lhs.scopeID == rhs.scopeID else { return false }
            guard lhs.payloadHash == rhs.payloadHash else { return false }
            guard lhs.sequence == rhs.sequence else { return false }
            guard lhs.issuedAt == rhs.issuedAt else { return false }
            guard lhs.expiresAt == rhs.expiresAt else { return false }
            guard lhs.nonce == rhs.nonce else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(challengeID, forKey: .challengeID)
            try c.encode(requestID, forKey: .requestID)
            try c.encode(deviceID, forKey: .deviceID)
            try c.encode(V2UInt64(wrappedValue: rootKeyEpoch), forKey: .rootKeyEpoch)
            try c.encode(purpose, forKey: .purpose)
            try c.encode(scopeID, forKey: .scopeID)
            try c.encode(payloadHash, forKey: .payloadHash)
            try c.encode(V2UInt64(wrappedValue: sequence), forKey: .sequence)
            try c.encode(V2UInt64(wrappedValue: issuedAt), forKey: .issuedAt)
            try c.encode(V2UInt64(wrappedValue: expiresAt), forKey: .expiresAt)
            try c.encode(nonce, forKey: .nonce)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, challengeID, requestID, deviceID, rootKeyEpoch, purpose, scopeID, payloadHash, sequence, issuedAt, expiresAt, nonce }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.challengeID = try c.decode(String.self, forKey: .challengeID)
            self.requestID = try c.decode(String.self, forKey: .requestID)
            self.deviceID = try c.decode(String.self, forKey: .deviceID)
            self.rootKeyEpoch = try c.decode(V2UInt64.self, forKey: .rootKeyEpoch).wrappedValue
            self.purpose = try c.decode(RootPurpose.self, forKey: .purpose)
            self.scopeID = try c.decode(String.self, forKey: .scopeID)
            self.payloadHash = try PairingV2.decodeData(c.decode(String.self, forKey: .payloadHash))
            self.sequence = try c.decode(V2UInt64.self, forKey: .sequence).wrappedValue
            self.issuedAt = try c.decode(V2UInt64.self, forKey: .issuedAt).wrappedValue
            self.expiresAt = try c.decode(V2UInt64.self, forKey: .expiresAt).wrappedValue
            self.nonce = try PairingV2.decodeData(c.decode(String.self, forKey: .nonce))
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(challengeID)
            try PairingV2.validateID(requestID)
            try PairingV2.validateID(deviceID)
            try PairingV2.validateID(scopeID)
            try PairingV2.validateHash(payloadHash)
            try PairingV2.validateHash(nonce)
            try PairingV2.require(rootKeyEpoch > 0 && sequence > 0, "rootSequence"); try PairingV2.validateLifetime(issuedAt, expiresAt, maximum: 120)
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "root-challenge-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(challengeID)
            try encoder.append(requestID)
            try encoder.append(deviceID)
            encoder.append(rootKeyEpoch)
            try encoder.append(purpose.rawValue)
            try encoder.append(scopeID)
            try encoder.append(payloadHash)
            encoder.append(sequence)
            encoder.append(issuedAt)
            encoder.append(expiresAt)
            try encoder.append(nonce)
            return encoder.data
        }
    }

    public final class RootProof: PairingV2CanonicalRecord {
        public let rootKind: RootKind
        public let challenge: RootChallenge
        public let proof: Data
        public init(rootKind: RootKind, challenge: RootChallenge, proof: Data) {
            self.rootKind = rootKind
            self.challenge = challenge
            self.proof = proof
        }
        public static func == (lhs: RootProof, rhs: RootProof) -> Bool {
            if lhs === rhs { return true }
            guard lhs.rootKind == rhs.rootKind else { return false }
            guard lhs.challenge == rhs.challenge else { return false }
            guard lhs.proof == rhs.proof else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(rootKind, forKey: .rootKind)
            try c.encode(challenge, forKey: .challenge)
            try c.encode(proof, forKey: .proof)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case rootKind, challenge, proof }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.rootKind = try c.decode(RootKind.self, forKey: .rootKind)
            self.challenge = try c.decode(RootChallenge.self, forKey: .challenge)
            self.proof = try PairingV2.decodeData(c.decode(String.self, forKey: .proof))
            try validate()
        }
        public func validate() throws {
            try challenge.validate()
            try rootKind.validate(); try PairingV2.require(proof.count >= 8 && proof.count <= 80, "proof")
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "root-proof-v2")
            try encoder.append(rootKind.rawValue)
            try encoder.append(challenge.canonicalBytes())
            try encoder.append(proof)
            return encoder.data
        }
    }

    public final class OwnerSessionIntent: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let accountID: String
        public let deviceID: String
        public let rootKeyEpoch: UInt64
        public let clientRequestID: String
        public let requestedScopes: [String]
        public let requestedExpiresAt: UInt64
        public init(authorityID: Data, origin: String, audience: String, accountID: String, deviceID: String, rootKeyEpoch: UInt64, clientRequestID: String, requestedScopes: [String], requestedExpiresAt: UInt64) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.accountID = accountID
            self.deviceID = deviceID
            self.rootKeyEpoch = rootKeyEpoch
            self.clientRequestID = clientRequestID
            self.requestedScopes = requestedScopes
            self.requestedExpiresAt = requestedExpiresAt
        }
        public static func == (lhs: OwnerSessionIntent, rhs: OwnerSessionIntent) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.accountID == rhs.accountID else { return false }
            guard lhs.deviceID == rhs.deviceID else { return false }
            guard lhs.rootKeyEpoch == rhs.rootKeyEpoch else { return false }
            guard lhs.clientRequestID == rhs.clientRequestID else { return false }
            guard lhs.requestedScopes == rhs.requestedScopes else { return false }
            guard lhs.requestedExpiresAt == rhs.requestedExpiresAt else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(accountID, forKey: .accountID)
            try c.encode(deviceID, forKey: .deviceID)
            try c.encode(V2UInt64(wrappedValue: rootKeyEpoch), forKey: .rootKeyEpoch)
            try c.encode(clientRequestID, forKey: .clientRequestID)
            try c.encode(requestedScopes, forKey: .requestedScopes)
            try c.encode(V2UInt64(wrappedValue: requestedExpiresAt), forKey: .requestedExpiresAt)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, accountID, deviceID, rootKeyEpoch, clientRequestID, requestedScopes, requestedExpiresAt }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.accountID = try c.decode(String.self, forKey: .accountID)
            self.deviceID = try c.decode(String.self, forKey: .deviceID)
            self.rootKeyEpoch = try c.decode(V2UInt64.self, forKey: .rootKeyEpoch).wrappedValue
            self.clientRequestID = try c.decode(String.self, forKey: .clientRequestID)
            self.requestedScopes = try c.decode([String].self, forKey: .requestedScopes)
            self.requestedExpiresAt = try c.decode(V2UInt64.self, forKey: .requestedExpiresAt).wrappedValue
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(accountID)
            try PairingV2.validateID(deviceID)
            try PairingV2.validateID(clientRequestID)
            try PairingV2.require(rootKeyEpoch > 0 && requestedExpiresAt > 0, "session"); try PairingV2.validateTexts(requestedScopes); try PairingV2.require(!requestedScopes.isEmpty, "requestedScopes")
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "owner-session-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(accountID)
            try encoder.append(deviceID)
            encoder.append(rootKeyEpoch)
            try encoder.append(clientRequestID)
            encoder.append(UInt64(requestedScopes.count)); for value in requestedScopes { try encoder.append(value) }
            encoder.append(requestedExpiresAt)
            return encoder.data
        }
    }

    public final class ResultLookupIntent: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let operationID: String
        public let originalActorDeviceID: String
        public let originalPurpose: RootPurpose
        public init(authorityID: Data, origin: String, audience: String, operationID: String, originalActorDeviceID: String, originalPurpose: RootPurpose) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.operationID = operationID
            self.originalActorDeviceID = originalActorDeviceID
            self.originalPurpose = originalPurpose
        }
        public static func == (lhs: ResultLookupIntent, rhs: ResultLookupIntent) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.operationID == rhs.operationID else { return false }
            guard lhs.originalActorDeviceID == rhs.originalActorDeviceID else { return false }
            guard lhs.originalPurpose == rhs.originalPurpose else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(operationID, forKey: .operationID)
            try c.encode(originalActorDeviceID, forKey: .originalActorDeviceID)
            try c.encode(originalPurpose, forKey: .originalPurpose)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, operationID, originalActorDeviceID, originalPurpose }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.operationID = try c.decode(String.self, forKey: .operationID)
            self.originalActorDeviceID = try c.decode(String.self, forKey: .originalActorDeviceID)
            self.originalPurpose = try c.decode(RootPurpose.self, forKey: .originalPurpose)
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(operationID)
            try PairingV2.validateID(originalActorDeviceID)
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "result-lookup-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(operationID)
            try encoder.append(originalActorDeviceID)
            try encoder.append(originalPurpose.rawValue)
            return encoder.data
        }
    }

    public final class OperationState: PairingV2CanonicalRecord {
        public let scopeKind: ScopeKind
        public let scopeID: String
        public let revision: UInt64
        public let status: OperationStatus
        public let objectHash: Data
        public let approvedSignerIDs: [String]
        public let phaseExpiresAt: UInt64
        public let receiptHash: Data?
        public init(scopeKind: ScopeKind, scopeID: String, revision: UInt64, status: OperationStatus, objectHash: Data, approvedSignerIDs: [String], phaseExpiresAt: UInt64, receiptHash: Data? = nil) {
            self.scopeKind = scopeKind
            self.scopeID = scopeID
            self.revision = revision
            self.status = status
            self.objectHash = objectHash
            self.approvedSignerIDs = approvedSignerIDs
            self.phaseExpiresAt = phaseExpiresAt
            self.receiptHash = receiptHash
        }
        public static func == (lhs: OperationState, rhs: OperationState) -> Bool {
            if lhs === rhs { return true }
            guard lhs.scopeKind == rhs.scopeKind else { return false }
            guard lhs.scopeID == rhs.scopeID else { return false }
            guard lhs.revision == rhs.revision else { return false }
            guard lhs.status == rhs.status else { return false }
            guard lhs.objectHash == rhs.objectHash else { return false }
            guard lhs.approvedSignerIDs == rhs.approvedSignerIDs else { return false }
            guard lhs.phaseExpiresAt == rhs.phaseExpiresAt else { return false }
            guard lhs.receiptHash == rhs.receiptHash else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(scopeKind, forKey: .scopeKind)
            try c.encode(scopeID, forKey: .scopeID)
            try c.encode(V2UInt64(wrappedValue: revision), forKey: .revision)
            try c.encode(status, forKey: .status)
            try c.encode(objectHash, forKey: .objectHash)
            try c.encode(approvedSignerIDs, forKey: .approvedSignerIDs)
            try c.encode(V2UInt64(wrappedValue: phaseExpiresAt), forKey: .phaseExpiresAt)
            try c.encodeIfPresent(receiptHash, forKey: .receiptHash)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case scopeKind, scopeID, revision, status, objectHash, approvedSignerIDs, phaseExpiresAt, receiptHash }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.scopeKind = try c.decode(ScopeKind.self, forKey: .scopeKind)
            self.scopeID = try c.decode(String.self, forKey: .scopeID)
            self.revision = try c.decode(V2UInt64.self, forKey: .revision).wrappedValue
            self.status = try c.decode(OperationStatus.self, forKey: .status)
            self.objectHash = try PairingV2.decodeData(c.decode(String.self, forKey: .objectHash))
            self.approvedSignerIDs = try c.decode([String].self, forKey: .approvedSignerIDs)
            self.phaseExpiresAt = try c.decode(V2UInt64.self, forKey: .phaseExpiresAt).wrappedValue
            self.receiptHash = try c.decodeIfPresent(String.self, forKey: .receiptHash).map(PairingV2.decodeData)
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateID(scopeID)
            try PairingV2.validateHash(objectHash)
            try PairingV2.validateTexts(approvedSignerIDs); for id in approvedSignerIDs { try PairingV2.validateID(id) }; if let receiptHash { try PairingV2.validateHash(receiptHash) }
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "operation-state-v2")
            try encoder.append(scopeKind.rawValue)
            try encoder.append(scopeID)
            encoder.append(revision)
            try encoder.append(status.rawValue)
            try encoder.append(objectHash)
            encoder.append(UInt64(approvedSignerIDs.count)); for value in approvedSignerIDs { try encoder.append(value) }
            encoder.append(phaseExpiresAt)
            try encoder.appendOptional(receiptHash)
            return encoder.data
        }
    }

    public final class SignedState: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let scopeKind: ScopeKind
        public let scopeID: String
        public let revision: UInt64
        public let payloadHash: Data
        public let issuedAt: UInt64
        public let expiresAt: UInt64
        public init(authorityID: Data, origin: String, audience: String, scopeKind: ScopeKind, scopeID: String, revision: UInt64, payloadHash: Data, issuedAt: UInt64, expiresAt: UInt64) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.scopeKind = scopeKind
            self.scopeID = scopeID
            self.revision = revision
            self.payloadHash = payloadHash
            self.issuedAt = issuedAt
            self.expiresAt = expiresAt
        }
        public static func == (lhs: SignedState, rhs: SignedState) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.scopeKind == rhs.scopeKind else { return false }
            guard lhs.scopeID == rhs.scopeID else { return false }
            guard lhs.revision == rhs.revision else { return false }
            guard lhs.payloadHash == rhs.payloadHash else { return false }
            guard lhs.issuedAt == rhs.issuedAt else { return false }
            guard lhs.expiresAt == rhs.expiresAt else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(scopeKind, forKey: .scopeKind)
            try c.encode(scopeID, forKey: .scopeID)
            try c.encode(V2UInt64(wrappedValue: revision), forKey: .revision)
            try c.encode(payloadHash, forKey: .payloadHash)
            try c.encode(V2UInt64(wrappedValue: issuedAt), forKey: .issuedAt)
            try c.encode(V2UInt64(wrappedValue: expiresAt), forKey: .expiresAt)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, scopeKind, scopeID, revision, payloadHash, issuedAt, expiresAt }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.scopeKind = try c.decode(ScopeKind.self, forKey: .scopeKind)
            self.scopeID = try c.decode(String.self, forKey: .scopeID)
            self.revision = try c.decode(V2UInt64.self, forKey: .revision).wrappedValue
            self.payloadHash = try PairingV2.decodeData(c.decode(String.self, forKey: .payloadHash))
            self.issuedAt = try c.decode(V2UInt64.self, forKey: .issuedAt).wrappedValue
            self.expiresAt = try c.decode(V2UInt64.self, forKey: .expiresAt).wrappedValue
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(scopeID)
            try PairingV2.validateHash(payloadHash)
            try PairingV2.validateLifetime(issuedAt, expiresAt, maximum: 60)
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "authority-state-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(scopeKind.rawValue)
            try encoder.append(scopeID)
            encoder.append(revision)
            try encoder.append(payloadHash)
            encoder.append(issuedAt)
            encoder.append(expiresAt)
            return encoder.data
        }
    }

    public final class ControlIntent: PairingV2CanonicalRecord {
        public let authorityID: Data
        public let origin: String
        public let audience: String
        public let scopeKind: ScopeKind
        public let scopeID: String
        public let expectedRevision: UInt64
        public let operation: ControlOperation
        public let actorDeviceID: String
        public init(authorityID: Data, origin: String, audience: String, scopeKind: ScopeKind, scopeID: String, expectedRevision: UInt64, operation: ControlOperation, actorDeviceID: String) {
            self.authorityID = authorityID
            self.origin = origin
            self.audience = audience
            self.scopeKind = scopeKind
            self.scopeID = scopeID
            self.expectedRevision = expectedRevision
            self.operation = operation
            self.actorDeviceID = actorDeviceID
        }
        public static func == (lhs: ControlIntent, rhs: ControlIntent) -> Bool {
            if lhs === rhs { return true }
            guard lhs.authorityID == rhs.authorityID else { return false }
            guard lhs.origin == rhs.origin else { return false }
            guard lhs.audience == rhs.audience else { return false }
            guard lhs.scopeKind == rhs.scopeKind else { return false }
            guard lhs.scopeID == rhs.scopeID else { return false }
            guard lhs.expectedRevision == rhs.expectedRevision else { return false }
            guard lhs.operation == rhs.operation else { return false }
            guard lhs.actorDeviceID == rhs.actorDeviceID else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(authorityID, forKey: .authorityID)
            try c.encode(origin, forKey: .origin)
            try c.encode(audience, forKey: .audience)
            try c.encode(scopeKind, forKey: .scopeKind)
            try c.encode(scopeID, forKey: .scopeID)
            try c.encode(V2UInt64(wrappedValue: expectedRevision), forKey: .expectedRevision)
            try c.encode(operation, forKey: .operation)
            try c.encode(actorDeviceID, forKey: .actorDeviceID)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case authorityID, origin, audience, scopeKind, scopeID, expectedRevision, operation, actorDeviceID }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.authorityID = try PairingV2.decodeData(c.decode(String.self, forKey: .authorityID))
            self.origin = try c.decode(String.self, forKey: .origin)
            self.audience = try c.decode(String.self, forKey: .audience)
            self.scopeKind = try c.decode(ScopeKind.self, forKey: .scopeKind)
            self.scopeID = try c.decode(String.self, forKey: .scopeID)
            self.expectedRevision = try c.decode(V2UInt64.self, forKey: .expectedRevision).wrappedValue
            self.operation = try c.decode(ControlOperation.self, forKey: .operation)
            self.actorDeviceID = try c.decode(String.self, forKey: .actorDeviceID)
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateContext(authorityID: authorityID, origin: origin, audience: audience)
            try PairingV2.validateID(scopeID)
            try PairingV2.validateID(actorDeviceID)
            try PairingV2.require(expectedRevision > 0, "expectedRevision"); try PairingV2.require([ScopeKind.pairing, .genesisProposal, .membershipProposal].contains(scopeKind), "scopeKind"); if operation == .rotateUnjoinedSecret { try PairingV2.require(scopeKind == .pairing, "rotationScope") }
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "control-v2")
            try encoder.append(authorityID)
            try encoder.append(origin)
            try encoder.append(audience)
            try encoder.append(scopeKind.rawValue)
            try encoder.append(scopeID)
            encoder.append(expectedRevision)
            try encoder.append(operation.rawValue)
            try encoder.append(actorDeviceID)
            return encoder.data
        }
    }

    public final class PairReceipt: PairingV2CanonicalRecord {
        public let transcript: PairTranscript
        public let aConsentDigest: Data
        public let bConsentDigest: Data
        public let confirmedAt: UInt64
        public let expiresAt: UInt64
        public init(transcript: PairTranscript, aConsentDigest: Data, bConsentDigest: Data, confirmedAt: UInt64, expiresAt: UInt64) {
            self.transcript = transcript
            self.aConsentDigest = aConsentDigest
            self.bConsentDigest = bConsentDigest
            self.confirmedAt = confirmedAt
            self.expiresAt = expiresAt
        }
        public static func == (lhs: PairReceipt, rhs: PairReceipt) -> Bool {
            if lhs === rhs { return true }
            guard lhs.transcript == rhs.transcript else { return false }
            guard lhs.aConsentDigest == rhs.aConsentDigest else { return false }
            guard lhs.bConsentDigest == rhs.bConsentDigest else { return false }
            guard lhs.confirmedAt == rhs.confirmedAt else { return false }
            guard lhs.expiresAt == rhs.expiresAt else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(transcript, forKey: .transcript)
            try c.encode(aConsentDigest, forKey: .aConsentDigest)
            try c.encode(bConsentDigest, forKey: .bConsentDigest)
            try c.encode(V2UInt64(wrappedValue: confirmedAt), forKey: .confirmedAt)
            try c.encode(V2UInt64(wrappedValue: expiresAt), forKey: .expiresAt)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case transcript, aConsentDigest, bConsentDigest, confirmedAt, expiresAt }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.transcript = try c.decode(PairTranscript.self, forKey: .transcript)
            self.aConsentDigest = try PairingV2.decodeData(c.decode(String.self, forKey: .aConsentDigest))
            self.bConsentDigest = try PairingV2.decodeData(c.decode(String.self, forKey: .bConsentDigest))
            self.confirmedAt = try c.decode(V2UInt64.self, forKey: .confirmedAt).wrappedValue
            self.expiresAt = try c.decode(V2UInt64.self, forKey: .expiresAt).wrappedValue
            try validate()
        }
        public func validate() throws {
            try transcript.validate()
            try PairingV2.validateHash(aConsentDigest)
            try PairingV2.validateHash(bConsentDigest)
            try PairingV2.require(confirmedAt >= transcript.issuedAt && confirmedAt < transcript.expiresAt, "confirmedAt"); try PairingV2.validateLifetime(confirmedAt, expiresAt, maximum: 300)
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "pair-receipt-v2")
            try encoder.append(transcript.canonicalBytes())
            try encoder.append(aConsentDigest)
            try encoder.append(bConsentDigest)
            encoder.append(confirmedAt)
            encoder.append(expiresAt)
            return encoder.data
        }
    }

    public final class AccountReceipt: PairingV2CanonicalRecord {
        public let genesis: AccountGenesis
        public let pairReceiptHash: Data
        public let aApprovalDigest: Data
        public let bApprovalDigest: Data
        public let createdAt: UInt64
        public let membershipRevision: UInt64
        public let ledgerFirstSequence: UInt64
        public let ledgerLastSequence: UInt64
        public let ledgerHeadHash: Data
        public init(genesis: AccountGenesis, pairReceiptHash: Data, aApprovalDigest: Data, bApprovalDigest: Data, createdAt: UInt64, membershipRevision: UInt64, ledgerFirstSequence: UInt64, ledgerLastSequence: UInt64, ledgerHeadHash: Data) {
            self.genesis = genesis
            self.pairReceiptHash = pairReceiptHash
            self.aApprovalDigest = aApprovalDigest
            self.bApprovalDigest = bApprovalDigest
            self.createdAt = createdAt
            self.membershipRevision = membershipRevision
            self.ledgerFirstSequence = ledgerFirstSequence
            self.ledgerLastSequence = ledgerLastSequence
            self.ledgerHeadHash = ledgerHeadHash
        }
        public static func == (lhs: AccountReceipt, rhs: AccountReceipt) -> Bool {
            if lhs === rhs { return true }
            guard lhs.genesis == rhs.genesis else { return false }
            guard lhs.pairReceiptHash == rhs.pairReceiptHash else { return false }
            guard lhs.aApprovalDigest == rhs.aApprovalDigest else { return false }
            guard lhs.bApprovalDigest == rhs.bApprovalDigest else { return false }
            guard lhs.createdAt == rhs.createdAt else { return false }
            guard lhs.membershipRevision == rhs.membershipRevision else { return false }
            guard lhs.ledgerFirstSequence == rhs.ledgerFirstSequence else { return false }
            guard lhs.ledgerLastSequence == rhs.ledgerLastSequence else { return false }
            guard lhs.ledgerHeadHash == rhs.ledgerHeadHash else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(genesis, forKey: .genesis)
            try c.encode(pairReceiptHash, forKey: .pairReceiptHash)
            try c.encode(aApprovalDigest, forKey: .aApprovalDigest)
            try c.encode(bApprovalDigest, forKey: .bApprovalDigest)
            try c.encode(V2UInt64(wrappedValue: createdAt), forKey: .createdAt)
            try c.encode(V2UInt64(wrappedValue: membershipRevision), forKey: .membershipRevision)
            try c.encode(V2UInt64(wrappedValue: ledgerFirstSequence), forKey: .ledgerFirstSequence)
            try c.encode(V2UInt64(wrappedValue: ledgerLastSequence), forKey: .ledgerLastSequence)
            try c.encode(ledgerHeadHash, forKey: .ledgerHeadHash)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case genesis, pairReceiptHash, aApprovalDigest, bApprovalDigest, createdAt, membershipRevision, ledgerFirstSequence, ledgerLastSequence, ledgerHeadHash }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.genesis = try c.decode(AccountGenesis.self, forKey: .genesis)
            self.pairReceiptHash = try PairingV2.decodeData(c.decode(String.self, forKey: .pairReceiptHash))
            self.aApprovalDigest = try PairingV2.decodeData(c.decode(String.self, forKey: .aApprovalDigest))
            self.bApprovalDigest = try PairingV2.decodeData(c.decode(String.self, forKey: .bApprovalDigest))
            self.createdAt = try c.decode(V2UInt64.self, forKey: .createdAt).wrappedValue
            self.membershipRevision = try c.decode(V2UInt64.self, forKey: .membershipRevision).wrappedValue
            self.ledgerFirstSequence = try c.decode(V2UInt64.self, forKey: .ledgerFirstSequence).wrappedValue
            self.ledgerLastSequence = try c.decode(V2UInt64.self, forKey: .ledgerLastSequence).wrappedValue
            self.ledgerHeadHash = try PairingV2.decodeData(c.decode(String.self, forKey: .ledgerHeadHash))
            try validate()
        }
        public func validate() throws {
            try genesis.validate()
            try PairingV2.validateHash(pairReceiptHash)
            try PairingV2.validateHash(aApprovalDigest)
            try PairingV2.validateHash(bApprovalDigest)
            try PairingV2.validateHash(ledgerHeadHash)
            try PairingV2.require(createdAt >= genesis.issuedAt && createdAt < genesis.expiresAt && membershipRevision == genesis.initialMembershipRevision, "createdAt"); try PairingV2.require(ledgerFirstSequence > 0 && ledgerLastSequence >= ledgerFirstSequence, "ledgerSequence")
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "account-receipt-v2")
            try encoder.append(genesis.canonicalBytes())
            try encoder.append(pairReceiptHash)
            try encoder.append(aApprovalDigest)
            try encoder.append(bApprovalDigest)
            encoder.append(createdAt)
            encoder.append(membershipRevision)
            encoder.append(ledgerFirstSequence)
            encoder.append(ledgerLastSequence)
            try encoder.append(ledgerHeadHash)
            return encoder.data
        }
    }

    public final class MembershipReceipt: PairingV2CanonicalRecord {
        public let proposal: MembershipProposal
        public let authorizerApprovalDigest: Data
        public let candidateApprovalDigest: Data
        public let committedAt: UInt64
        public let membershipRevision: UInt64
        public let ledgerFirstSequence: UInt64
        public let ledgerLastSequence: UInt64
        public let ledgerHeadHash: Data
        public init(proposal: MembershipProposal, authorizerApprovalDigest: Data, candidateApprovalDigest: Data, committedAt: UInt64, membershipRevision: UInt64, ledgerFirstSequence: UInt64, ledgerLastSequence: UInt64, ledgerHeadHash: Data) {
            self.proposal = proposal
            self.authorizerApprovalDigest = authorizerApprovalDigest
            self.candidateApprovalDigest = candidateApprovalDigest
            self.committedAt = committedAt
            self.membershipRevision = membershipRevision
            self.ledgerFirstSequence = ledgerFirstSequence
            self.ledgerLastSequence = ledgerLastSequence
            self.ledgerHeadHash = ledgerHeadHash
        }
        public static func == (lhs: MembershipReceipt, rhs: MembershipReceipt) -> Bool {
            if lhs === rhs { return true }
            guard lhs.proposal == rhs.proposal else { return false }
            guard lhs.authorizerApprovalDigest == rhs.authorizerApprovalDigest else { return false }
            guard lhs.candidateApprovalDigest == rhs.candidateApprovalDigest else { return false }
            guard lhs.committedAt == rhs.committedAt else { return false }
            guard lhs.membershipRevision == rhs.membershipRevision else { return false }
            guard lhs.ledgerFirstSequence == rhs.ledgerFirstSequence else { return false }
            guard lhs.ledgerLastSequence == rhs.ledgerLastSequence else { return false }
            guard lhs.ledgerHeadHash == rhs.ledgerHeadHash else { return false }
            return true
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(proposal, forKey: .proposal)
            try c.encode(authorizerApprovalDigest, forKey: .authorizerApprovalDigest)
            try c.encode(candidateApprovalDigest, forKey: .candidateApprovalDigest)
            try c.encode(V2UInt64(wrappedValue: committedAt), forKey: .committedAt)
            try c.encode(V2UInt64(wrappedValue: membershipRevision), forKey: .membershipRevision)
            try c.encode(V2UInt64(wrappedValue: ledgerFirstSequence), forKey: .ledgerFirstSequence)
            try c.encode(V2UInt64(wrappedValue: ledgerLastSequence), forKey: .ledgerLastSequence)
            try c.encode(ledgerHeadHash, forKey: .ledgerHeadHash)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case proposal, authorizerApprovalDigest, candidateApprovalDigest, committedAt, membershipRevision, ledgerFirstSequence, ledgerLastSequence, ledgerHeadHash }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.proposal = try c.decode(MembershipProposal.self, forKey: .proposal)
            self.authorizerApprovalDigest = try PairingV2.decodeData(c.decode(String.self, forKey: .authorizerApprovalDigest))
            self.candidateApprovalDigest = try PairingV2.decodeData(c.decode(String.self, forKey: .candidateApprovalDigest))
            self.committedAt = try c.decode(V2UInt64.self, forKey: .committedAt).wrappedValue
            self.membershipRevision = try c.decode(V2UInt64.self, forKey: .membershipRevision).wrappedValue
            self.ledgerFirstSequence = try c.decode(V2UInt64.self, forKey: .ledgerFirstSequence).wrappedValue
            self.ledgerLastSequence = try c.decode(V2UInt64.self, forKey: .ledgerLastSequence).wrappedValue
            self.ledgerHeadHash = try PairingV2.decodeData(c.decode(String.self, forKey: .ledgerHeadHash))
            try validate()
        }
        public func validate() throws {
            try proposal.validate()
            try PairingV2.validateHash(authorizerApprovalDigest)
            try PairingV2.validateHash(candidateApprovalDigest)
            try PairingV2.validateHash(ledgerHeadHash)
            try PairingV2.require(committedAt >= proposal.issuedAt && committedAt < proposal.expiresAt && membershipRevision == proposal.nextMembershipRevision, "committedAt"); try PairingV2.require(ledgerFirstSequence > 0 && ledgerLastSequence >= ledgerFirstSequence, "ledgerSequence")
        }
        public func canonicalBytes() throws -> Data {
            try validate()
            var encoder = try CanonicalEncoder(domain: "membership-receipt-v2")
            try encoder.append(proposal.canonicalBytes())
            try encoder.append(authorizerApprovalDigest)
            try encoder.append(candidateApprovalDigest)
            encoder.append(committedAt)
            encoder.append(membershipRevision)
            encoder.append(ledgerFirstSequence)
            encoder.append(ledgerLastSequence)
            try encoder.append(ledgerHeadHash)
            return encoder.data
        }
    }

}
