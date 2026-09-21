import Foundation

extension PairingV2 {
    public enum OperationPayload: PairingV2CanonicalRecord {
        case createPairing(CreatePairingIntent)
        case joinPairing(JoinPairingIntent)
        case confirmPair(PairTranscript)
        case proposeAccount(ProposeAccountIntent)
        case replaceGenesis(ReplaceGenesisIntent)
        case approveGenesis(AccountGenesis)
        case proposeMembership(ProposeMembershipIntent)
        case approveMembership(MembershipProposal)
        case control(ControlIntent)
        case renewIdentityLease(RenewLeaseIntent)
        case authenticateOwner(OwnerSessionIntent)
        case getResult(ResultLookupIntent)
        public var purpose: RootPurpose {
            switch self {
            case .createPairing: .createPairing
            case .joinPairing: .joinPairing
            case .confirmPair: .confirmPair
            case .proposeAccount: .proposeAccount
            case .replaceGenesis: .replaceGenesis
            case .approveGenesis: .approveGenesis
            case .proposeMembership: .proposeMembership
            case .approveMembership: .approveMembership
            case .control: .control
            case .renewIdentityLease: .renewIdentityLease
            case .authenticateOwner: .authenticateOwner
            case .getResult: .getResult
            }
        }
        public var scopeID: String {
            switch self {
            case .createPairing(let value): value.initiator.deviceID
            case .joinPairing(let value): value.pairingID
            case .confirmPair(let value): value.pairingID
            case .proposeAccount(let value): value.pairingID
            case .replaceGenesis(let value): value.pairingID
            case .approveGenesis(let value): value.proposalID
            case .proposeMembership(let value): value.pairingID
            case .approveMembership(let value): value.proposalID
            case .control(let value): value.scopeID
            case .renewIdentityLease(let value): value.deviceID
            case .authenticateOwner(let value): value.accountID
            case .getResult(let value): value.operationID
            }
        }
        public func validate() throws {
            switch self {
            case .createPairing(let value): try value.validate()
            case .joinPairing(let value): try value.validate()
            case .confirmPair(let value): try value.validate()
            case .proposeAccount(let value): try value.validate()
            case .replaceGenesis(let value): try value.validate()
            case .approveGenesis(let value): try value.validate()
            case .proposeMembership(let value): try value.validate()
            case .approveMembership(let value): try value.validate()
            case .control(let value): try value.validate()
            case .renewIdentityLease(let value): try value.validate()
            case .authenticateOwner(let value): try value.validate()
            case .getResult(let value): try value.validate()
            }
        }
        public func canonicalBytes() throws -> Data {
            switch self {
            case .createPairing(let value): try value.canonicalBytes()
            case .joinPairing(let value): try value.canonicalBytes()
            case .confirmPair(let value): try value.canonicalBytes()
            case .proposeAccount(let value): try value.canonicalBytes()
            case .replaceGenesis(let value): try value.canonicalBytes()
            case .approveGenesis(let value): try value.canonicalBytes()
            case .proposeMembership(let value): try value.canonicalBytes()
            case .approveMembership(let value): try value.canonicalBytes()
            case .control(let value): try value.canonicalBytes()
            case .renewIdentityLease(let value): try value.canonicalBytes()
            case .authenticateOwner(let value): try value.canonicalBytes()
            case .getResult(let value): try value.canonicalBytes()
            }
        }
        private enum CodingKeys: String, CodingKey { case kind, payload }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: ["kind", "payload"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(RootPurpose.self, forKey: .kind) {
            case .createPairing: self = .createPairing(try c.decode(CreatePairingIntent.self, forKey: .payload))
            case .joinPairing: self = .joinPairing(try c.decode(JoinPairingIntent.self, forKey: .payload))
            case .confirmPair: self = .confirmPair(try c.decode(PairTranscript.self, forKey: .payload))
            case .proposeAccount: self = .proposeAccount(try c.decode(ProposeAccountIntent.self, forKey: .payload))
            case .replaceGenesis: self = .replaceGenesis(try c.decode(ReplaceGenesisIntent.self, forKey: .payload))
            case .approveGenesis: self = .approveGenesis(try c.decode(AccountGenesis.self, forKey: .payload))
            case .proposeMembership: self = .proposeMembership(try c.decode(ProposeMembershipIntent.self, forKey: .payload))
            case .approveMembership: self = .approveMembership(try c.decode(MembershipProposal.self, forKey: .payload))
            case .control: self = .control(try c.decode(ControlIntent.self, forKey: .payload))
            case .renewIdentityLease: self = .renewIdentityLease(try c.decode(RenewLeaseIntent.self, forKey: .payload))
            case .authenticateOwner: self = .authenticateOwner(try c.decode(OwnerSessionIntent.self, forKey: .payload))
            case .getResult: self = .getResult(try c.decode(ResultLookupIntent.self, forKey: .payload))
            }
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(purpose, forKey: .kind)
            switch self {
            case .createPairing(let value): try c.encode(value, forKey: .payload)
            case .joinPairing(let value): try c.encode(value, forKey: .payload)
            case .confirmPair(let value): try c.encode(value, forKey: .payload)
            case .proposeAccount(let value): try c.encode(value, forKey: .payload)
            case .replaceGenesis(let value): try c.encode(value, forKey: .payload)
            case .approveGenesis(let value): try c.encode(value, forKey: .payload)
            case .proposeMembership(let value): try c.encode(value, forKey: .payload)
            case .approveMembership(let value): try c.encode(value, forKey: .payload)
            case .control(let value): try c.encode(value, forKey: .payload)
            case .renewIdentityLease(let value): try c.encode(value, forKey: .payload)
            case .authenticateOwner(let value): try c.encode(value, forKey: .payload)
            case .getResult(let value): try c.encode(value, forKey: .payload)
            }
        }
    }

    public struct PreparationRequest: Codable, Equatable, Sendable {
        public let requestID: String
        public let rootKind: RootKind
        public init(requestID: String, rootKind: RootKind = .androidStrongBox) {
            self.requestID = requestID
            self.rootKind = rootKind
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case requestID, rootKind }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.requestID = try c.decode(String.self, forKey: .requestID)
            self.rootKind = try c.decode(RootKind.self, forKey: .rootKind)
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateID(requestID); try rootKind.validate()
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(requestID, forKey: .requestID)
            try c.encode(rootKind, forKey: .rootKind)
        }
    }

    public struct PreparationResponse: Codable, Equatable, Sendable {
        public let challenge: Signed<PreEnrollmentChallenge>
        public let preparationCapability: Data
        public init(challenge: Signed<PreEnrollmentChallenge>, preparationCapability: Data) {
            self.challenge = challenge
            self.preparationCapability = preparationCapability
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case challenge, preparationCapability }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.challenge = try c.decode(Signed<PreEnrollmentChallenge>.self, forKey: .challenge)
            self.preparationCapability = try PairingV2.decodeData(c.decode(String.self, forKey: .preparationCapability))
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateHash(preparationCapability)
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(challenge, forKey: .challenge)
            try c.encode(preparationCapability, forKey: .preparationCapability)
        }
    }

    public struct AttestationRequest: Codable, Equatable, Sendable {
        public let challenge: PreEnrollmentChallenge
        public let preparationCapability: Data
        public let evidence: AttestationEvidence
        public let proof: Data
        public init(challenge: PreEnrollmentChallenge, preparationCapability: Data, evidence: AttestationEvidence, proof: Data) {
            self.challenge = challenge
            self.preparationCapability = preparationCapability
            self.evidence = evidence
            self.proof = proof
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case challenge, preparationCapability, evidence, proof }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.challenge = try c.decode(PreEnrollmentChallenge.self, forKey: .challenge)
            self.preparationCapability = try PairingV2.decodeData(c.decode(String.self, forKey: .preparationCapability))
            self.evidence = try c.decode(AttestationEvidence.self, forKey: .evidence)
            self.proof = try PairingV2.decodeData(c.decode(String.self, forKey: .proof))
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateHash(preparationCapability); try PairingV2.require(proof.count >= 8 && proof.count <= 80, "proof")
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(challenge, forKey: .challenge)
            try c.encode(preparationCapability, forKey: .preparationCapability)
            try c.encode(evidence, forKey: .evidence)
            try c.encode(proof, forKey: .proof)
        }
    }

    public struct RootChallengeRequest: Codable, Equatable, Sendable {
        public let deviceID: String
        @V2UInt64 public var rootKeyEpoch: UInt64
        public let requestID: String
        public let purpose: RootPurpose
        public let scopeID: String
        public let payloadHash: Data
        public let capability: Data?
        public init(deviceID: String, rootKeyEpoch: UInt64, requestID: String, purpose: RootPurpose, scopeID: String, payloadHash: Data, capability: Data? = nil) {
            self.deviceID = deviceID
            self._rootKeyEpoch = V2UInt64(wrappedValue: rootKeyEpoch)
            self.requestID = requestID
            self.purpose = purpose
            self.scopeID = scopeID
            self.payloadHash = payloadHash
            self.capability = capability
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case deviceID, rootKeyEpoch, requestID, purpose, scopeID, payloadHash, capability }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.deviceID = try c.decode(String.self, forKey: .deviceID)
            self._rootKeyEpoch = try c.decode(V2UInt64.self, forKey: .rootKeyEpoch)
            self.requestID = try c.decode(String.self, forKey: .requestID)
            self.purpose = try c.decode(RootPurpose.self, forKey: .purpose)
            self.scopeID = try c.decode(String.self, forKey: .scopeID)
            self.payloadHash = try PairingV2.decodeData(c.decode(String.self, forKey: .payloadHash))
            self.capability = try c.decodeIfPresent(String.self, forKey: .capability).map(PairingV2.decodeData)
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateID(deviceID); try PairingV2.validateID(requestID); try PairingV2.validateID(scopeID); try PairingV2.validateHash(payloadHash); try PairingV2.require(rootKeyEpoch > 0, "rootKeyEpoch"); if let capability { try PairingV2.validateHash(capability) }
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(deviceID, forKey: .deviceID)
            try c.encode(_rootKeyEpoch, forKey: .rootKeyEpoch)
            try c.encode(requestID, forKey: .requestID)
            try c.encode(purpose, forKey: .purpose)
            try c.encode(scopeID, forKey: .scopeID)
            try c.encode(payloadHash, forKey: .payloadHash)
            try c.encodeIfPresent(capability, forKey: .capability)
        }
    }

    public struct OperationRequest: Codable, Equatable, Sendable {
        public let payload: OperationPayload
        public let proof: RootProof
        public let capability: Data?
        public init(payload: OperationPayload, proof: RootProof, capability: Data? = nil) {
            self.payload = payload
            self.proof = proof
            self.capability = capability
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case payload, proof, capability }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.payload = try c.decode(OperationPayload.self, forKey: .payload)
            self.proof = try c.decode(RootProof.self, forKey: .proof)
            self.capability = try c.decodeIfPresent(String.self, forKey: .capability).map(PairingV2.decodeData)
            try validate()
        }
        public func validate() throws {
            if let capability { try PairingV2.validateHash(capability) }; try PairingV2.require(proof.challenge.purpose == payload.purpose && proof.challenge.scopeID == payload.scopeID, "operationBinding"); guard try proof.challenge.payloadHash == payload.digest() else { throw Error.bindingMismatch }
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(payload, forKey: .payload)
            try c.encode(proof, forKey: .proof)
            try c.encodeIfPresent(capability, forKey: .capability)
        }
    }

    public struct InspectionRequest: Codable, Equatable, Sendable {
        public let pairingID: String
        public let capability: Data
        public init(pairingID: String, capability: Data) {
            self.pairingID = pairingID
            self.capability = capability
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case pairingID, capability }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.pairingID = try c.decode(String.self, forKey: .pairingID)
            self.capability = try PairingV2.decodeData(c.decode(String.self, forKey: .capability))
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateID(pairingID); try PairingV2.validateHash(capability)
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pairingID, forKey: .pairingID)
            try c.encode(capability, forKey: .capability)
        }
    }

    public struct RosterRequest: Codable, Equatable, Sendable {
        public let accountID: String
        public init(accountID: String) {
            self.accountID = accountID
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case accountID }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.accountID = try c.decode(String.self, forKey: .accountID)
            try validate()
        }
        public func validate() throws {
            try PairingV2.validateID(accountID)
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(accountID, forKey: .accountID)
        }
    }

    /// Immutable heap storage avoids copying the complete nested proof/receipt bundle through every client stack frame.
    public final class OperationResponse: Codable, Equatable, Sendable {
        public static func == (lhs: OperationResponse, rhs: OperationResponse) -> Bool {
            if lhs === rhs { return true }
            return lhs.state == rhs.state && lhs.signedState == rhs.signedState
                && lhs.inspection == rhs.inspection && lhs.transcript == rhs.transcript
                && lhs.pairReceipt == rhs.pairReceipt && lhs.genesis == rhs.genesis
                && lhs.membershipProposal == rhs.membershipProposal && lhs.accountReceipt == rhs.accountReceipt
                && lhs.membershipReceipt == rhs.membershipReceipt && lhs.trustReceipt == rhs.trustReceipt
                && lhs.roster == rhs.roster && lhs.proofs == rhs.proofs
        }
        public let state: OperationState
        public let signedState: Signed<SignedState>
        public let inspection: Signed<PairingInspection>?
        public let transcript: Signed<PairTranscript>?
        public let pairReceipt: Signed<PairReceipt>?
        public let genesis: Signed<AccountGenesis>?
        public let membershipProposal: Signed<MembershipProposal>?
        public let accountReceipt: Signed<AccountReceipt>?
        public let membershipReceipt: Signed<MembershipReceipt>?
        public let trustReceipt: Signed<DeviceTrustReceipt>?
        public let roster: Signed<AccountRoster>?
        public let proofs: [RootProof]
        public init(state: OperationState, signedState: Signed<SignedState>, inspection: Signed<PairingInspection>? = nil, transcript: Signed<PairTranscript>? = nil, pairReceipt: Signed<PairReceipt>? = nil, genesis: Signed<AccountGenesis>? = nil, membershipProposal: Signed<MembershipProposal>? = nil, accountReceipt: Signed<AccountReceipt>? = nil, membershipReceipt: Signed<MembershipReceipt>? = nil, trustReceipt: Signed<DeviceTrustReceipt>? = nil, roster: Signed<AccountRoster>? = nil, proofs: [RootProof] = []) {
            self.state = state
            self.signedState = signedState
            self.inspection = inspection
            self.transcript = transcript
            self.pairReceipt = pairReceipt
            self.genesis = genesis
            self.membershipProposal = membershipProposal
            self.accountReceipt = accountReceipt
            self.membershipReceipt = membershipReceipt
            self.trustReceipt = trustReceipt
            self.roster = roster
            self.proofs = proofs
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case state, signedState, inspection, transcript, pairReceipt, genesis, membershipProposal, accountReceipt, membershipReceipt, trustReceipt, roster, proofs }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.state = try c.decode(OperationState.self, forKey: .state)
            self.signedState = try c.decode(Signed<SignedState>.self, forKey: .signedState)
            self.inspection = try c.decodeIfPresent(Signed<PairingInspection>.self, forKey: .inspection)
            self.transcript = try c.decodeIfPresent(Signed<PairTranscript>.self, forKey: .transcript)
            self.pairReceipt = try c.decodeIfPresent(Signed<PairReceipt>.self, forKey: .pairReceipt)
            self.genesis = try c.decodeIfPresent(Signed<AccountGenesis>.self, forKey: .genesis)
            self.membershipProposal = try c.decodeIfPresent(Signed<MembershipProposal>.self, forKey: .membershipProposal)
            self.accountReceipt = try c.decodeIfPresent(Signed<AccountReceipt>.self, forKey: .accountReceipt)
            self.membershipReceipt = try c.decodeIfPresent(Signed<MembershipReceipt>.self, forKey: .membershipReceipt)
            self.trustReceipt = try c.decodeIfPresent(Signed<DeviceTrustReceipt>.self, forKey: .trustReceipt)
            self.roster = try c.decodeIfPresent(Signed<AccountRoster>.self, forKey: .roster)
            self.proofs = try c.decodeIfPresent([RootProof].self, forKey: .proofs) ?? []
            try validate()
        }
        public func validate() throws {
            try PairingV2.require(proofs.count <= 4, "proofCount")
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(state, forKey: .state)
            try c.encode(signedState, forKey: .signedState)
            try c.encodeIfPresent(inspection, forKey: .inspection)
            try c.encodeIfPresent(transcript, forKey: .transcript)
            try c.encodeIfPresent(pairReceipt, forKey: .pairReceipt)
            try c.encodeIfPresent(genesis, forKey: .genesis)
            try c.encodeIfPresent(membershipProposal, forKey: .membershipProposal)
            try c.encodeIfPresent(accountReceipt, forKey: .accountReceipt)
            try c.encodeIfPresent(membershipReceipt, forKey: .membershipReceipt)
            try c.encodeIfPresent(trustReceipt, forKey: .trustReceipt)
            try c.encodeIfPresent(roster, forKey: .roster)
            try c.encode(proofs, forKey: .proofs)
        }
    }

    public struct ExecutionResponse: Codable, Equatable, Sendable {
        public let operation: OperationResponse
        public let secret: Data?
        public let sessionToken: String?
        public let sessionExpiresAt: UInt64?
        public init(operation: OperationResponse, secret: Data? = nil, sessionToken: String? = nil, sessionExpiresAt: UInt64? = nil) {
            self.operation = operation
            self.secret = secret
            self.sessionToken = sessionToken
            self.sessionExpiresAt = sessionExpiresAt
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case operation, secret, sessionToken, sessionExpiresAt }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.operation = try c.decode(OperationResponse.self, forKey: .operation)
            self.secret = try c.decodeIfPresent(String.self, forKey: .secret).map(PairingV2.decodeData)
            self.sessionToken = try c.decodeIfPresent(String.self, forKey: .sessionToken)
            self.sessionExpiresAt = try c.decodeIfPresent(V2UInt64.self, forKey: .sessionExpiresAt)?.wrappedValue
            try validate()
        }
        public func validate() throws {
            if let secret { try PairingV2.validateHash(secret) }; if let sessionToken { try PairingV2.validateText(sessionToken); try PairingV2.require(sessionExpiresAt != nil, "sessionExpiry") }; try PairingV2.require((sessionToken == nil) == (sessionExpiresAt == nil), "session")
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(operation, forKey: .operation)
            try c.encodeIfPresent(secret, forKey: .secret)
            try c.encodeIfPresent(sessionToken, forKey: .sessionToken)
            try c.encodeIfPresent(sessionExpiresAt.map { V2UInt64(wrappedValue: $0) }, forKey: .sessionExpiresAt)
        }
    }

    public struct PairingCreatedResponse: Codable, Equatable, Sendable {
        public let operation: OperationResponse
        public let secret: Data?
        public init(operation: OperationResponse, secret: Data? = nil) {
            self.operation = operation
            self.secret = secret
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case operation, secret }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.operation = try c.decode(OperationResponse.self, forKey: .operation)
            self.secret = try c.decodeIfPresent(String.self, forKey: .secret).map(PairingV2.decodeData)
            try validate()
        }
        public func validate() throws {
            if let secret { try PairingV2.validateHash(secret) }
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(operation, forKey: .operation)
            try c.encodeIfPresent(secret, forKey: .secret)
        }
    }

    public struct OwnerSessionResponse: Codable, Equatable, Sendable {
        public let operation: OperationResponse
        public let token: String?
        @V2UInt64 public var expiresAt: UInt64
        public init(operation: OperationResponse, token: String? = nil, expiresAt: UInt64) {
            self.operation = operation
            self.token = token
            self._expiresAt = V2UInt64(wrappedValue: expiresAt)
        }
        private enum CodingKeys: String, CodingKey, CaseIterable { case operation, token, expiresAt }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.operation = try c.decode(OperationResponse.self, forKey: .operation)
            self.token = try c.decodeIfPresent(String.self, forKey: .token)
            self._expiresAt = try c.decode(V2UInt64.self, forKey: .expiresAt)
            try validate()
        }
        public func validate() throws {
            if let token { try PairingV2.validateText(token) }
        }
        public func encode(to encoder: Encoder) throws {
            try validate()
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(operation, forKey: .operation)
            try c.encodeIfPresent(token, forKey: .token)
            try c.encode(_expiresAt, forKey: .expiresAt)
        }
    }

}
