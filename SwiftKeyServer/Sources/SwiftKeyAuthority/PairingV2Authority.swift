import Foundation
import SwiftKeyCore

extension Authority {
    func v2State() throws -> PairingV2State {
        try healthy()
        guard let config = configuration.pairingV2, config.enabled else {
            throw AuthorityError.protocolFailure(code: "v2Unavailable", message: "V2 pairing is not enabled on this authority")
        }
        return state.pairingV2 ?? PairingV2State(origin: config.origin, audience: PairingV2.audience)
    }
    private var v2AuthorityID: Data { ProtocolCrypto.sha256(signingKey.publicKey) }
    private func v2Context(_ authorityID: Data, _ origin: String, _ audience: String) throws {
        let v2 = try v2State()
        try require(authorityID == v2AuthorityID && origin == v2.origin && audience == v2.audience,
            "Wrong authority context", code: "contextMismatch")
    }
    private func v2Commit(_ v2: PairingV2State, events: [LedgerEventDraft], next: PersistedState? = nil) throws {
        var snapshot = next ?? state; snapshot.pairingV2 = v2
        try commit(snapshot, events: events)
    }
    private func v2CapabilityHash(_ domain: String, _ id: String, _ secret: Data) throws -> Data {
        try require(secret.count == 32, "Invalid capability", code: "unauthorized")
        var encoder = try CanonicalEncoder(domain: domain)
        try encoder.append(id); try encoder.append(secret)
        return ProtocolCrypto.sha256(encoder.data)
    }
    private func v2Identifier(_ value: String) throws {
        try require(!value.isEmpty && value.utf8.count <= 128 && value == value.precomposedStringWithCanonicalMapping
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
            "Invalid operation identifier", code: "invalidRequest")
    }
    private func v2Limit(_ key: String, limit: Int, window: UInt64, state v2: inout PairingV2State) throws {
        let now = clock()
        v2.admissionWindows = v2.admissionWindows.filter { now < $0.value.start + $0.value.duration }
        var budget = v2.admissionWindows[key] ?? V2RateWindow(start: now, count: 0, duration: window)
        try require(budget.count < limit, "Request budget exhausted", code: "rateLimited")
        budget.count += 1; v2.admissionWindows[key] = budget
    }

    public func prepareIdentityV2(_ request: PairingV2.PreparationRequest, source: String = "local-transport") throws -> PairingV2.PreparationResponse {
        var v2 = try v2State()
        try request.validate()
        try require(request.rootKind == .androidStrongBox, "Unsupported hardware root", code: "unsupportedRoot")
        try require(v2.preparations[request.requestID] == nil, "Preparation request already allocated; recover the original preparation", code: "requestConflict")
        try require(v2.preparations.count < 10_000 && v2.identities.count < 10_000, "Identity registry capacity reached", code: "rateLimited")
        try v2Limit("prepare:all", limit: 64, window: 900, state: &v2)
        try v2Limit("prepare:" + hex(ProtocolCrypto.sha256(Data(source.utf8))), limit: 8, window: 900, state: &v2)
        let now = clock(), deviceID = UUID().uuidString.lowercased()
        let challenge = PairingV2.PreEnrollmentChallenge(authorityID: v2AuthorityID, origin: v2.origin, audience: v2.audience,
            challengeID: UUID().uuidString.lowercased(), requestID: request.requestID, deviceID: deviceID,
            rootKind: request.rootKind, trustPolicyID: hex(try configuration.policyFingerprint()), nonce: randomBytes(32),
            issuedAt: now, expiresAt: now + 900)
        let capability = randomBytes(32)
        v2.preparations[request.requestID] = V2Preparation(challenge: challenge,
            capabilityHash: try v2CapabilityHash("preparation-capability-v2", request.requestID, capability))
        try v2Commit(v2, events: [event("v2.identity.prepared", device: deviceID)])
        return PairingV2.PreparationResponse(challenge: .init(payload: challenge,
            signature: try signingKey.sign(message: challenge.canonicalBytes())), preparationCapability: capability)
    }

    public func attestIdentityV2(_ request: PairingV2.AttestationRequest) async throws -> PairingV2.Signed<PairingV2.DeviceTrustReceipt> {
        var v2 = try v2State()
        try request.validate()
        let challenge = request.challenge
        guard let preparation = v2.preparations[challenge.requestID] else { throw AuthorityError.protocolFailure(code: "unauthorized", message: "Unknown preparation") }
        try require(try preparation.challenge.canonicalBytes() == challenge.canonicalBytes()
            && preparation.capabilityHash == v2CapabilityHash("preparation-capability-v2", challenge.requestID, request.preparationCapability),
            "Preparation does not match", code: "unauthorized")
        let evidenceHash = ProtocolCrypto.sha256(try request.evidence.canonicalBytes())
        if let admitted = v2.identities[challenge.deviceID] {
            try require(preparation.evidenceHash == evidenceHash && request.evidence.rootKind == .androidStrongBox,
                "An admitted identity cannot change its evidence", code: "requestConflict")
            try require(ProtocolCrypto.verify(signature: request.proof, message: try challenge.canonicalBytes(), publicKey: admitted.identity.publicKey),
                "Admission possession proof failed", code: "invalidSignature")
            return preparation.originalReceipt ?? admitted.receipt
        }
        try require(clock() < challenge.expiresAt && request.evidence.rootKind == challenge.rootKind,
            "Admission challenge expired or platform changed", code: "expired")
        let identity = try await verifier.verify(certificates: request.evidence.certificates,
            challenge: ProtocolCrypto.sha256(try challenge.canonicalBytes()), now: clock())
        v2 = try v2State()
        if let admitted = v2.identities[challenge.deviceID] {
            try require(v2.preparations[challenge.requestID]?.evidenceHash == evidenceHash
                && ProtocolCrypto.verify(signature: request.proof, message: try challenge.canonicalBytes(), publicKey: admitted.identity.publicKey),
                "Concurrent admission used another root", code: "requestConflict")
            return v2.preparations[challenge.requestID]?.originalReceipt ?? admitted.receipt
        }
        try require(clock() < challenge.expiresAt, "Admission expired during trust verification", code: "expired")
        try require(!v2.identities.values.contains { $0.identity.publicKey == identity.publicKey }
            && !state.devices.values.contains { $0.publicKey == identity.publicKey }, "Hardware root is already admitted", code: "rootAlreadyBound")
        try require(ProtocolCrypto.verify(signature: request.proof, message: try challenge.canonicalBytes(), publicKey: identity.publicKey),
            "Admission possession proof failed", code: "invalidSignature")
        let receipt = PairingV2.DeviceTrustReceipt(authorityID: v2AuthorityID, origin: v2.origin, audience: v2.audience,
            deviceID: challenge.deviceID, rootKind: challenge.rootKind, rootKeyEpoch: 1, rootPublicKey: identity.publicKey,
            originalChallengeHash: ProtocolCrypto.sha256(try challenge.canonicalBytes()), evidenceHash: evidenceHash,
            trustPolicyID: challenge.trustPolicyID, verifiedAt: clock(), leaseExpiresAt: clock() + 900)
        let signed = PairingV2.Signed(payload: receipt, signature: try signingKey.sign(message: receipt.canonicalBytes()))
        v2.identities[challenge.deviceID] = V2Identity(receipt: signed, identity: identity)
        v2.preparations[challenge.requestID]?.evidenceHash = evidenceHash
        v2.preparations[challenge.requestID]?.originalReceipt = signed
        try v2Commit(v2, events: [event("v2.identity.admitted", device: challenge.deviceID, actor: challenge.deviceID,
            details: ["publicKey": hex(identity.publicKey), "certificateSHA256": hex(identity.certificateSHA256)])])
        return signed
    }

    private func v2Identity(_ deviceID: String, state v2: PairingV2State, allowExpiredLease: Bool = false, allowRevokedHistorical: Bool = false) throws -> V2Identity {
        guard let identity = v2.identities[deviceID] else { throw AuthorityError.protocolFailure(code: "unknownDevice", message: "Unknown admitted identity") }
        try require(!identity.revoked || allowRevokedHistorical, "Device was revoked", code: "revokedDevice")
        if !allowExpiredLease { try require(clock() < identity.receipt.payload.leaseExpiresAt, "Identity lease expired", code: "trustExpired") }
        if !allowRevokedHistorical, let accountID = identity.accountID {
            try require(v2.accounts[accountID]?.owners.contains { $0.deviceID == deviceID } == true,
                "Identity is no longer an owner", code: "revokedDevice")
        }
        return identity
    }
    private func v2Descriptor(_ identity: V2Identity) throws -> PairingV2.OwnerDescriptor {
        let r = identity.receipt.payload
        return PairingV2.OwnerDescriptor(deviceID: r.deviceID, rootKind: r.rootKind, rootKeyEpoch: r.rootKeyEpoch,
            rootPublicKey: r.rootPublicKey, attestationReceiptHash: ProtocolCrypto.sha256(try r.canonicalBytes()), role: "owner")
    }
    private func v2Matches(_ descriptor: PairingV2.OwnerDescriptor, _ identity: V2Identity, requireCurrentReceipt: Bool = false) throws -> Bool {
        let r = identity.receipt.payload
        return try descriptor.deviceID == r.deviceID && descriptor.rootKind == r.rootKind && descriptor.rootKeyEpoch == r.rootKeyEpoch
            && descriptor.rootPublicKey == r.rootPublicKey && descriptor.role == "owner"
            && (!requireCurrentReceipt || descriptor.attestationReceiptHash == ProtocolCrypto.sha256(try r.canonicalBytes()))
    }

    public func rootChallengeV2(_ request: PairingV2.RootChallengeRequest) throws -> PairingV2.Signed<PairingV2.RootChallenge> {
        var v2 = try v2State()
        try request.validate()
        let identity = try v2Identity(request.deviceID, state: v2, allowExpiredLease: request.purpose == .renewIdentityLease || request.purpose == .getResult, allowRevokedHistorical: request.purpose == .getResult)
        try require(v2.rejectedRequests[request.deviceID + ":" + request.requestID] == nil,
            "Request was definitively rejected by authenticated recovery", code: "requestConflict")
        try require(request.rootKeyEpoch == identity.receipt.payload.rootKeyEpoch && request.payloadHash.count == 32,
            "Invalid root challenge binding", code: "invalidRequest")
        if let accepted = v2.operations[request.requestID] {
            try require(accepted.actor == request.deviceID && accepted.purpose == request.purpose && accepted.payloadHash == request.payloadHash
                && accepted.proof.challenge.scopeID == request.scopeID,
                "Request ID is bound to another operation", code: "requestConflict")
            let c = accepted.proof.challenge
            return .init(payload: c, signature: try signingKey.sign(message: c.canonicalBytes()))
        }
        let sequence = state.devices[request.deviceID]?.sequence ?? identity.sequence
        try require(sequence < UInt64.max, "Root sequence exhausted")
        let now = clock()
        var deadline = now + 120
        switch request.purpose {
        case .createPairing, .renewIdentityLease:
            try require(request.scopeID == request.deviceID, "Identity challenge scope mismatch", code: "unauthorized")
        case .joinPairing:
            guard let pair = v2.pairings[request.scopeID], let capability = request.capability else {
                throw AuthorityError.protocolFailure(code: "unauthorized", message: "Invitation is unavailable")
            }
            try require(pair.status == .open && identity.accountID == nil && pair.inspection.initiator.deviceID != request.deviceID
                && pair.secretHash == v2CapabilityHash("pair-secret-v2", request.scopeID, capability),
                "Invitation is unavailable", code: "unauthorized")
            deadline = min(deadline, pair.inspection.expiresAt)
        case .confirmPair, .proposeAccount, .replaceGenesis, .proposeMembership:
            guard let pair = v2.pairings[request.scopeID], v2PairMembers(pair).contains(request.deviceID) else {
                throw AuthorityError.protocolFailure(code: "unauthorized", message: "Root is not bound to pairing")
            }
            deadline = min(deadline, v2PairDeadline(pair))
        case .approveGenesis:
            guard let proposal = v2.genesis[request.scopeID], proposal.genesis.payload.owners.contains(where: { $0.deviceID == request.deviceID }) else {
                throw AuthorityError.protocolFailure(code: "unauthorized", message: "Root is not a genesis owner")
            }
            deadline = min(deadline, proposal.genesis.payload.expiresAt)
        case .approveMembership:
            guard let p = v2.memberships[request.scopeID]?.proposal.payload,
                  [p.authorizingOwner.deviceID, p.candidate.deviceID].contains(request.deviceID) else {
                throw AuthorityError.protocolFailure(code: "unauthorized", message: "Root is not a membership participant")
            }
            deadline = min(deadline, p.expiresAt)
        case .authenticateOwner:
            try require(identity.accountID == request.scopeID, "Root is not an account owner", code: "unauthorized")
        case .getResult, .control:
            let allowed = v2.operations[request.scopeID]?.actor == request.deviceID
                || v2.pairings[request.scopeID].map { v2PairMembers($0).contains(request.deviceID) } == true
                || v2.genesis[request.scopeID]?.genesis.payload.owners.contains { $0.deviceID == request.deviceID } == true
                || v2.memberships[request.scopeID].map { [$0.proposal.payload.authorizingOwner.deviceID, $0.proposal.payload.candidate.deviceID].contains(request.deviceID) } == true
                || request.scopeID == request.deviceID
            if !allowed {
                let known = v2.operations[request.scopeID] != nil || v2.pairings[request.scopeID] != nil
                    || v2.genesis[request.scopeID] != nil || v2.memberships[request.scopeID] != nil || v2.identities[request.scopeID] != nil
                try require(request.purpose == .getResult && !known,
                    "Root is not bound to requested result or control", code: "unauthorized")
                let original = v2.challenges.values.first { $0.requestID == request.scopeID }
                try require(original == nil || original?.deviceID == request.deviceID,
                    "Request belongs to another root", code: "unauthorized")
            }
        }
        try require(now < deadline, "Operation phase expired", code: "expired")
        v2.challenges = v2.challenges.filter { $0.value.expiresAt > now }
        if let existing = v2.challenges.values.first(where: { $0.requestID == request.requestID }) {
            try require(existing.deviceID == request.deviceID && existing.purpose == request.purpose
                && existing.scopeID == request.scopeID && existing.payloadHash == request.payloadHash, "Challenge request changed", code: "requestConflict")
            if existing.sequence == sequence + 1 { return .init(payload: existing, signature: try signingKey.sign(message: existing.canonicalBytes())) }
            v2.challenges.removeValue(forKey: existing.challengeID)
        }
        try require(v2.challenges.values.filter { $0.deviceID == request.deviceID }.count < 16 && v2.challenges.count < 10_000,
            "Too many root challenges", code: "rateLimited")
        let challenge = PairingV2.RootChallenge(authorityID: v2AuthorityID, origin: v2.origin, audience: v2.audience,
            challengeID: UUID().uuidString.lowercased(), requestID: request.requestID, deviceID: request.deviceID,
            rootKeyEpoch: request.rootKeyEpoch, purpose: request.purpose, scopeID: request.scopeID,
            payloadHash: request.payloadHash, sequence: sequence + 1, issuedAt: now, expiresAt: deadline, nonce: randomBytes(32))
        v2.challenges[challenge.challengeID] = challenge
        try v2Commit(v2, events: [event("v2.challenge.issued", device: request.deviceID, details: ["purpose": request.purpose.rawValue])])
        return .init(payload: challenge, signature: try signingKey.sign(message: challenge.canonicalBytes()))
    }

    private func v2ValidateProof(_ request: PairingV2.OperationRequest, state v2: PairingV2State, replay: Bool = false) throws -> V2Identity {
        let proof = request.proof, c = proof.challenge
        try v2Context(c.authorityID, c.origin, c.audience)
        guard let identity = v2.identities[c.deviceID] else { throw AuthorityError.protocolFailure(code: "unknownDevice", message: "Unknown root") }
        try require(proof.rootKind == .androidStrongBox && c.rootKeyEpoch == identity.receipt.payload.rootKeyEpoch,
            "Unsupported or changed root", code: "invalidSignature")
        try require(c.purpose == request.payload.purpose && c.payloadHash == ProtocolCrypto.sha256(try request.payload.canonicalBytes()),
            "Root proof does not bind this exact operation", code: "bindingMismatch")
        try require(ProtocolCrypto.verify(signature: proof.proof, message: try c.canonicalBytes(), publicKey: identity.identity.publicKey),
            "Hardware root proof failed", code: "invalidSignature")
        if !replay {
            _ = try v2Identity(c.deviceID, state: v2, allowExpiredLease: c.purpose == .renewIdentityLease || c.purpose == .getResult, allowRevokedHistorical: c.purpose == .getResult)
            let sequence = state.devices[c.deviceID]?.sequence ?? identity.sequence
            try require(clock() < c.expiresAt && sequence < UInt64.max && c.sequence == sequence + 1,
                "Root challenge expired or stale", code: "staleChallenge")
            try require(try v2.challenges[c.challengeID]?.canonicalBytes() == c.canonicalBytes(),
                "Unknown root challenge", code: "staleChallenge")
        }
        return identity
    }
    private func v2Consume(_ proof: PairingV2.RootProof, v2: inout PairingV2State, next: inout PersistedState) {
        let c = proof.challenge
        v2.identities[c.deviceID]?.sequence = c.sequence
        next.devices[c.deviceID]?.sequence = c.sequence
        v2.challenges = v2.challenges.filter { $0.value.deviceID != c.deviceID }
        next.challenges = next.challenges.filter { $0.value.deviceID != c.deviceID }
    }
}

extension Authority {
    private func v2Sign<T: PairingV2CanonicalRecord>(_ value: T) throws -> PairingV2.Signed<T> {
        try .sign(value, using: signingKey)
    }
    private func v2PairDeadline(_ pair: V2Pairing) -> UInt64 { pair.receipt?.payload.expiresAt ?? pair.inspection.expiresAt }
    private func v2PairMembers(_ pair: V2Pairing) -> [String] {
        pair.transcript?.payload.owners.map(\.deviceID) ?? [pair.inspection.initiator.deviceID]
    }
    private func v2CheckAccount(_ context: PairingV2.PairingContext, actor: String, state v2: PairingV2State) throws {
        if context.purpose == .createAccount {
            try require(context.existingAccount == nil && v2.identities[actor]?.accountID == nil,
                "Account creation requires an unowned root", code: "rootAlreadyBound")
            return
        }
        guard let expected = context.existingAccount, let account = v2.accounts[expected.accountID] else {
            throw AuthorityError.protocolFailure(code: "unknownAccount", message: "Unknown v2 account")
        }
        try require(account.label == expected.accountLabel && account.policy == expected.ownershipPolicyID
            && account.revision == expected.membershipRevision && account.owners == expected.existingOwners,
            "Account membership changed; obtain a new roster", code: "staleMembership")
        try require(account.owners.contains { $0.deviceID == actor } && v2.identities[actor]?.accountID == account.accountID,
            "Operation requires a current owner", code: "unauthorized")
        if context.purpose == .replaceOwner {
            guard let lost = expected.lostOwner else { throw AuthorityError.protocolFailure(code: "invalidRequest", message: "Replacement needs its exact lost owner") }
            try require(lost.deviceID != actor && account.owners.contains(lost), "Cannot replace the authorizing owner", code: "invalidRequest")
        } else { try require(expected.lostOwner == nil, "Addition cannot remove an owner", code: "invalidRequest") }
    }
    private func v2PairIsStale(_ pair: V2Pairing, state v2: PairingV2State) -> Bool {
        guard pair.inspection.context.purpose != .createAccount else { return false }
        return (try? v2CheckAccount(pair.inspection.context, actor: pair.inspection.initiator.deviceID, state: v2)) == nil
    }
    private func v2Reserve(_ deviceID: String, pairID: String, state v2: inout PairingV2State) throws {
        let identity = try v2Identity(deviceID, state: v2)
        if let existingID = identity.reservation, existingID != pairID, let existing = v2.pairings[existingID] {
            try require(existing.status.isTerminal || clock() >= v2PairDeadline(existing) || v2PairIsStale(existing, state: v2),
                "Identity is reserved by another live operation", code: "identityReserved")
        }
        v2.identities[deviceID]?.reservation = pairID
    }
    private func v2Pair(_ id: String, participant: String, state v2: PairingV2State, statuses: [PairingV2.OperationStatus]) throws -> V2Pairing {
        guard let pair = v2.pairings[id] else { throw AuthorityError.protocolFailure(code: "notFound", message: "Unknown pairing") }
        try require(v2PairMembers(pair).contains(participant), "Root is not a pairing participant", code: "unauthorized")
        try require(!v2PairIsStale(pair, state: v2), "Account context is no longer current", code: "staleMembership")
        try require(clock() < v2PairDeadline(pair), "Pairing phase expired", code: "expired")
        try require(statuses.contains(pair.status), "Pairing phase changed", code: "staleState")
        return pair
    }
    private func v2Roster(_ account: V2Account, state v2: PairingV2State) throws -> PairingV2.Signed<PairingV2.AccountRoster> {
        try v2Sign(PairingV2.AccountRoster(authorityID: v2AuthorityID, origin: v2.origin, audience: v2.audience,
            accountID: account.accountID, accountLabel: account.label, ownershipPolicyID: account.policy,
            membershipRevision: account.revision, owners: account.owners, issuedAt: clock(), expiresAt: clock() + 60))
    }
    private func v2Status(_ status: PairingV2.OperationStatus, deadline: UInt64) -> PairingV2.OperationStatus {
        status.isTerminal ? status : (clock() < deadline ? status : .expired)
    }
    private func v2Response(_ kind: PairingV2.ScopeKind, _ id: String, state v2: PairingV2State, includeRoster: Bool = true) throws -> PairingV2.OperationResponse {
        var inspection: PairingV2.Signed<PairingV2.PairingInspection>?
        var transcript: PairingV2.Signed<PairingV2.PairTranscript>?
        var pairReceipt: PairingV2.Signed<PairingV2.PairReceipt>?
        var genesis: PairingV2.Signed<PairingV2.AccountGenesis>?
        var membership: PairingV2.Signed<PairingV2.MembershipProposal>?
        var accountReceipt: PairingV2.Signed<PairingV2.AccountReceipt>?
        var membershipReceipt: PairingV2.Signed<PairingV2.MembershipReceipt>?
        var trust: PairingV2.Signed<PairingV2.DeviceTrustReceipt>?
        var roster: PairingV2.Signed<PairingV2.AccountRoster>?
        var proofs: [PairingV2.RootProof] = []
        let operation: PairingV2.OperationState
        switch kind {
        case .identity:
            guard let identity = v2.identities[id] else { throw AuthorityError.protocolFailure(code: "notFound", message: "Unknown identity") }
            trust = identity.receipt
            if includeRoster, let accountID = identity.accountID, let account = v2.accounts[accountID] { roster = try v2Roster(account, state: v2) }
            operation = .init(scopeKind: kind, scopeID: id, revision: max(identity.sequence, 1),
                status: identity.revoked ? .invalidated : .committed, objectHash: try identity.receipt.payload.digest(),
                approvedSignerIDs: [], phaseExpiresAt: identity.receipt.payload.leaseExpiresAt, receiptHash: try identity.receipt.payload.digest())
        case .pairing:
            guard let pair = v2.pairings[id] else { throw AuthorityError.protocolFailure(code: "notFound", message: "Unknown pairing") }
            if let proposal = pair.proposalID {
                return try v2Response(v2.genesis[proposal] == nil ? .membershipProposal : .genesisProposal, proposal, state: v2, includeRoster: includeRoster)
            }
            inspection = try v2Sign(pair.inspection); transcript = pair.transcript; pairReceipt = pair.receipt
            proofs = pair.consents.values.sorted { $0.challenge.deviceID < $1.challenge.deviceID }
            let status = !pair.status.isTerminal && v2PairIsStale(pair, state: v2) ? PairingV2.OperationStatus.invalidated : v2Status(pair.status, deadline: v2PairDeadline(pair))
            operation = .init(scopeKind: kind, scopeID: id, revision: pair.revision, status: status,
                objectHash: try pair.transcript?.payload.digest() ?? pair.inspection.digest(), approvedSignerIDs: pair.consents.keys.sorted(),
                phaseExpiresAt: v2PairDeadline(pair), receiptHash: try pair.receipt?.payload.digest())
        case .genesisProposal:
            guard let proposal = v2.genesis[id], let pair = v2.pairings[proposal.genesis.payload.pairingID] else { throw AuthorityError.protocolFailure(code: "notFound", message: "Unknown genesis proposal") }
            genesis = proposal.genesis; transcript = pair.transcript; pairReceipt = pair.receipt; accountReceipt = proposal.receipt
            proofs = (Array(pair.consents.values) + Array(proposal.approvals.values)).sorted { $0.challenge.challengeID < $1.challenge.challengeID }
            if includeRoster, let account = v2.accounts[proposal.genesis.payload.accountID] { roster = try v2Roster(account, state: v2) }
            operation = .init(scopeKind: kind, scopeID: id, revision: proposal.revision,
                status: v2Status(proposal.status, deadline: proposal.genesis.payload.expiresAt), objectHash: try proposal.genesis.payload.digest(),
                approvedSignerIDs: proposal.approvals.keys.sorted(), phaseExpiresAt: proposal.genesis.payload.expiresAt,
                receiptHash: try proposal.receipt?.payload.digest())
        case .membershipProposal:
            guard let proposal = v2.memberships[id], let pair = v2.pairings[proposal.proposal.payload.pairingID] else { throw AuthorityError.protocolFailure(code: "notFound", message: "Unknown membership proposal") }
            membership = proposal.proposal; transcript = pair.transcript; pairReceipt = pair.receipt; membershipReceipt = proposal.receipt
            proofs = (Array(pair.consents.values) + Array(proposal.approvals.values)).sorted { $0.challenge.challengeID < $1.challenge.challengeID }
            if includeRoster, let accountID = proposal.proposal.payload.context.existingAccount?.accountID, let account = v2.accounts[accountID] { roster = try v2Roster(account, state: v2) }
            let status = !proposal.status.isTerminal && v2PairIsStale(pair, state: v2) ? PairingV2.OperationStatus.invalidated : v2Status(proposal.status, deadline: proposal.proposal.payload.expiresAt)
            operation = .init(scopeKind: kind, scopeID: id, revision: proposal.revision, status: status,
                objectHash: try proposal.proposal.payload.digest(), approvedSignerIDs: proposal.approvals.keys.sorted(),
                phaseExpiresAt: proposal.proposal.payload.expiresAt, receiptHash: try proposal.receipt?.payload.digest())
        case .operation: throw AuthorityError.protocolFailure(code: "notFound", message: "Operation receipt not found")
        }
        let signedState = PairingV2.SignedState(authorityID: v2AuthorityID, origin: v2.origin, audience: v2.audience,
            scopeKind: operation.scopeKind, scopeID: operation.scopeID, revision: operation.revision,
            payloadHash: try operation.digest(), issuedAt: clock(), expiresAt: clock() + 60)
        return PairingV2.OperationResponse(state: operation, signedState: try v2Sign(signedState), inspection: inspection,
            transcript: transcript, pairReceipt: pairReceipt, genesis: genesis, membershipProposal: membership,
            accountReceipt: accountReceipt, membershipReceipt: membershipReceipt, trustReceipt: trust, roster: roster, proofs: proofs)
    }

    public func inspectPairingV2(_ request: PairingV2.InspectionRequest) throws -> PairingV2.Signed<PairingV2.PairingInspection> {
        let v2 = try v2State()
        try request.validate()
        guard let pair = v2.pairings[request.pairingID], pair.status == .open,
              let secretHash = pair.secretHash else { throw AuthorityError.protocolFailure(code: "unauthorized", message: "Invitation is unavailable") }
        try require(clock() < pair.inspection.expiresAt && !v2PairIsStale(pair, state: v2)
            && secretHash == v2CapabilityHash("pair-secret-v2", request.pairingID, request.capability),
            "Invitation is unavailable", code: "unauthorized")
        return try v2Sign(pair.inspection)
    }

    private func v2PredictHead(_ events: [LedgerEventDraft]) throws -> (UInt64, LedgerHead) {
        var head = try store.head()
        let first = head.sequence + 1
        for draft in events {
            let addition = try LedgerEvent(sequence: head.sequence + 1, draft: draft, previousHash: head.hash)
            head = LedgerHead(sequence: addition.sequence, hash: addition.hash)
        }
        return (first, head)
    }
    private func v2Promote(_ owners: [PairingV2.OwnerDescriptor], accountID: String, v2: inout PairingV2State, next: inout PersistedState) throws {
        for descriptor in owners {
            let identity = try v2Identity(descriptor.deviceID, state: v2)
            try require(identity.accountID == nil || identity.accountID == accountID, "Root already belongs to another account", code: "rootAlreadyBound")
            v2.identities[descriptor.deviceID]?.accountID = accountID
            v2.identities[descriptor.deviceID]?.reservation = nil
            if next.devices[descriptor.deviceID] == nil {
                next.devices[descriptor.deviceID] = DeviceRecord(accountID: accountID, deviceID: descriptor.deviceID,
                    publicKey: descriptor.rootPublicKey, sequence: identity.sequence, revoked: false,
                    identity: identity.identity, enrolledAt: clock())
            }
        }
    }
}

extension Authority {
    private func v2Fresh(_ saved: PairingV2.OperationResponse, state v2: PairingV2State) throws -> PairingV2.OperationResponse {
        let signed = PairingV2.SignedState(authorityID: v2AuthorityID, origin: v2.origin, audience: v2.audience,
            scopeKind: saved.state.scopeKind, scopeID: saved.state.scopeID, revision: saved.state.revision,
            payloadHash: try saved.state.digest(), issuedAt: clock(), expiresAt: clock() + 60)
        return .init(state: saved.state, signedState: try v2Sign(signed), inspection: saved.inspection,
            transcript: saved.transcript, pairReceipt: saved.pairReceipt, genesis: saved.genesis,
            membershipProposal: saved.membershipProposal, accountReceipt: saved.accountReceipt,
            membershipReceipt: saved.membershipReceipt, trustReceipt: saved.trustReceipt, roster: saved.roster, proofs: saved.proofs)
    }
    private func v2PayloadContext(_ payload: PairingV2.OperationPayload) throws {
        switch payload {
        case .createPairing(let p): try v2Context(p.authorityID, p.origin, p.audience)
        case .joinPairing(let p): try v2Context(p.authorityID, p.origin, p.audience)
        case .confirmPair(let p): try v2Context(p.authorityID, p.origin, p.audience)
        case .proposeAccount(let p): try v2Context(p.authorityID, p.origin, p.audience)
        case .replaceGenesis(let p): try v2Context(p.authorityID, p.origin, p.audience)
        case .approveGenesis(let p): try v2Context(p.authorityID, p.origin, p.audience)
        case .proposeMembership(let p): try v2Context(p.authorityID, p.origin, p.audience)
        case .approveMembership(let p): try v2Context(p.authorityID, p.origin, p.audience)
        case .control(let p): try v2Context(p.authorityID, p.origin, p.audience)
        case .renewIdentityLease(let p): try v2Context(p.authorityID, p.origin, p.audience)
        case .authenticateOwner(let p): try v2Context(p.authorityID, p.origin, p.audience)
        case .getResult(let p): try v2Context(p.authorityID, p.origin, p.audience)
        }
    }
    public func executeV2(_ request: PairingV2.OperationRequest) async throws -> PairingV2.ExecutionResponse {
        var v2 = try v2State()
        try request.validate()
        try v2PayloadContext(request.payload)
        let proof = request.proof, challenge = proof.challenge, actor = challenge.deviceID
        try require(v2.rejectedRequests[actor + ":" + challenge.requestID] == nil,
            "Request was definitively rejected by authenticated recovery", code: "requestConflict")
        try require(challenge.scopeID == request.payload.scopeID, "Root challenge scope changed", code: "bindingMismatch")
        let payloadHash = ProtocolCrypto.sha256(try request.payload.canonicalBytes())
        if let accepted = v2.operations[challenge.requestID] {
            _ = try v2ValidateProof(request, state: v2, replay: true)
            try require(accepted.actor == actor && accepted.purpose == challenge.purpose && accepted.payloadHash == payloadHash
                && accepted.proof.challenge == challenge, "Request ID has another accepted operation", code: "requestConflict")
            return .init(operation: try v2Fresh(accepted.response, state: v2))
        }
        _ = try v2ValidateProof(request, state: v2)
        // Validate all relevant participants before the no-suspension commit
        // section; afterwards reload every sequence, reservation and proposal.
        var participants = Set([actor])
        switch request.payload {
        case .joinPairing(let p): if let pair = v2.pairings[p.pairingID] { participants.insert(pair.inspection.initiator.deviceID) }
        case .confirmPair(let p): participants.formUnion(p.owners.map(\.deviceID))
        case .approveGenesis(let p): participants.formUnion(p.owners.map(\.deviceID))
        case .approveMembership(let p): participants.formUnion([p.authorizingOwner.deviceID, p.candidate.deviceID])
        default: break
        }
        for id in participants.sorted() {
            let identity = try v2Identity(id, state: v2, allowExpiredLease: challenge.purpose == .renewIdentityLease || challenge.purpose == .getResult, allowRevokedHistorical: challenge.purpose == .getResult)
            if challenge.purpose != .getResult { try await verifier.revalidate(identity.identity, now: clock()) }
        }
        v2 = try v2State()
        try require(v2.rejectedRequests[actor + ":" + challenge.requestID] == nil,
            "Request was definitively rejected while trust verification awaited", code: "requestConflict")
        // An exact duplicate may have committed while attestation suspended.
        if let accepted = v2.operations[challenge.requestID] {
            _ = try v2ValidateProof(request, state: v2, replay: true)
            try require(accepted.actor == actor && accepted.payloadHash == payloadHash && accepted.proof.challenge == challenge,
                "Concurrent request differs", code: "requestConflict")
            return .init(operation: try v2Fresh(accepted.response, state: v2))
        }
        let identity = try v2ValidateProof(request, state: v2)
        for id in participants { _ = try v2Identity(id, state: v2, allowExpiredLease: challenge.purpose == .renewIdentityLease || challenge.purpose == .getResult, allowRevokedHistorical: challenge.purpose == .getResult) }
        if challenge.purpose != .getResult {
            try require(v2.operations.count < 100_000, "Operation retention capacity reached", code: "rateLimited")
        } else {
            try v2Limit("read:" + actor, limit: 30, window: 60, state: &v2)
        }
        var next = state
        v2Consume(proof, v2: &v2, next: &next)
        var events = [event("v2.operation.accepted", device: actor, actor: actor, details: ["purpose": challenge.purpose.rawValue, "payloadHash": hex(payloadHash)])]
        var scope: PairingV2.ScopeKind = .identity, scopeID = actor
        var secret: Data?, sessionToken: String?, sessionExpiresAt: UInt64?
        var responseOverride: PairingV2.OperationResponse?
        switch request.payload {
        case .createPairing(let p):
            try require(p.requestID == challenge.requestID && p.initiator.deviceID == actor
                && v2Matches(p.initiator, identity, requireCurrentReceipt: true), "Wrong pairing initiator", code: "bindingMismatch")
            try v2CheckAccount(p.context, actor: actor, state: v2)
            try require(v2.pairings.count < 10_000, "Pairing registry capacity reached", code: "rateLimited")
            let pairID = UUID().uuidString.lowercased(), bytes = randomBytes(32)
            try v2Reserve(actor, pairID: pairID, state: &v2)
            let inspection = PairingV2.PairingInspection(authorityID: v2AuthorityID, origin: v2.origin, audience: v2.audience,
                pairingID: pairID, revision: 1, initiator: p.initiator, context: p.context, issuedAt: clock(),
                expiresAt: min(clock() + 120, identity.receipt.payload.leaseExpiresAt))
            v2.pairings[pairID] = V2Pairing(inspection: inspection,
                secretHash: try v2CapabilityHash("pair-secret-v2", pairID, bytes), capturedLeaseExpiries: [actor: identity.receipt.payload.leaseExpiresAt])
            secret = bytes; scope = .pairing; scopeID = pairID
            events.append(event("v2.pairing.created", device: actor, actor: actor, details: ["purpose": p.context.purpose.rawValue]))
        case .joinPairing(let p):
            guard var pair = v2.pairings[p.pairingID], let capability = request.capability else { throw AuthorityError.protocolFailure(code: "unauthorized", message: "Invitation is unavailable") }
            try require(pair.status == .open && clock() < pair.inspection.expiresAt && !v2PairIsStale(pair, state: v2), "Invitation is unavailable", code: "staleState")
            try require(pair.secretHash == v2CapabilityHash("pair-secret-v2", p.pairingID, capability), "Invitation capability failed", code: "unauthorized")
            try require(p.expectedRevision == pair.revision && p.inspectionHash == pair.inspection.digest()
                && p.initiatorHash == pair.inspection.initiator.digest(), "Invitation review changed", code: "bindingMismatch")
            try require(actor == p.candidate.deviceID && actor != pair.inspection.initiator.deviceID
                && identity.accountID == nil && v2Matches(p.candidate, identity, requireCurrentReceipt: true), "Candidate root is not eligible", code: "rootAlreadyBound")
            try require(p.candidate.rootPublicKey != pair.inspection.initiator.rootPublicKey, "Pairing requires distinct hardware roots")
            try v2Reserve(actor, pairID: p.pairingID, state: &v2)
            pair.revision += 1; pair.status = .peerBound; pair.capturedLeaseExpiries[actor] = identity.receipt.payload.leaseExpiresAt
            let transcript = PairingV2.PairTranscript(authorityID: v2AuthorityID, origin: v2.origin, audience: v2.audience,
                pairingID: p.pairingID, revision: pair.revision, context: pair.inspection.context,
                owners: [pair.inspection.initiator, p.candidate].sorted { $0.deviceID < $1.deviceID }, nonce: randomBytes(32),
                issuedAt: pair.inspection.issuedAt, expiresAt: pair.inspection.expiresAt)
            pair.transcript = try v2Sign(transcript); pair.secretHash = nil
            v2.pairings[p.pairingID] = pair; scope = .pairing; scopeID = p.pairingID
            events.append(event("v2.pairing.peer_bound", device: actor, actor: actor))
        case .confirmPair(let p):
            var pair = try v2Pair(p.pairingID, participant: actor, state: v2, statuses: [.peerBound])
            try require(pair.transcript?.payload == p, "Pair transcript changed", code: "bindingMismatch")
            try require(pair.consents[actor] == nil, "This root already confirmed", code: "alreadyAccepted")
            pair.consents[actor] = proof; pair.revision += 1
            if pair.consents.count == 2 {
                let ids = p.owners.map(\.deviceID)
                let expires = min(clock() + 300, pair.capturedLeaseExpiries.values.min() ?? clock())
                try require(clock() < expires, "Captured identity lease expired", code: "trustExpired")
                let receipt = PairingV2.PairReceipt(transcript: p, aConsentDigest: try pair.consents[ids[0]]!.digest(),
                    bConsentDigest: try pair.consents[ids[1]]!.digest(), confirmedAt: clock(), expiresAt: expires)
                pair.receipt = try v2Sign(receipt); pair.status = .paired
            }
            v2.pairings[p.pairingID] = pair; scope = .pairing; scopeID = p.pairingID
            events.append(event("v2.pairing.confirmed", device: actor, actor: actor))
        case .proposeAccount(let p):
            var pair = try v2Pair(p.pairingID, participant: actor, state: v2, statuses: [.paired])
            try require(pair.inspection.context.purpose == .createAccount && pair.proposalID == nil
                && pair.revision == p.expectedRevision && pair.receipt?.payload.digest() == p.pairReceiptHash,
                "Pairing or account proposal changed", code: "staleState")
            let created = try v2NewGenesis(pair: pair, label: p.label, policy: p.ownershipPolicyID, state: v2)
            pair.proposalID = created.genesis.payload.proposalID; pair.revision += 1
            v2.genesis[created.genesis.payload.proposalID] = created; v2.pairings[p.pairingID] = pair
            scope = .genesisProposal; scopeID = created.genesis.payload.proposalID
            events.append(event("v2.genesis.proposed", actor: actor))
        case .replaceGenesis(let p):
            var pair = try v2Pair(p.pairingID, participant: actor, state: v2, statuses: [.paired])
            guard let oldID = pair.proposalID, var old = v2.genesis[oldID] else { throw AuthorityError.protocolFailure(code: "notFound", message: "No genesis proposal") }
            try require(!old.status.isTerminal && pair.revision == p.expectedRevision && old.genesis.payload.digest() == p.oldProposalHash,
                "Genesis proposal changed", code: "staleState")
            old.status = .cancelled; old.revision += 1; v2.genesis[oldID] = old
            let created = try v2NewGenesis(pair: pair, label: p.newLabel, policy: p.newOwnershipPolicyID, state: v2)
            pair.proposalID = created.genesis.payload.proposalID; pair.revision += 1
            v2.genesis[created.genesis.payload.proposalID] = created; v2.pairings[p.pairingID] = pair
            scope = .genesisProposal; scopeID = created.genesis.payload.proposalID
            events.append(event("v2.genesis.replaced", actor: actor))
        case .approveGenesis(let p):
            guard var proposal = v2.genesis[p.proposalID] else { throw AuthorityError.protocolFailure(code: "notFound", message: "Unknown genesis") }
            var pair = try v2Pair(p.pairingID, participant: actor, state: v2, statuses: [.paired])
            try require(proposal.genesis.payload == p && pair.proposalID == p.proposalID && !proposal.status.isTerminal,
                "Genesis proposal changed", code: "staleState")
            try require(clock() < p.expiresAt && proposal.approvals[actor] == nil, "Genesis expired or already accepted", code: "expired")
            for owner in p.owners {
                let current = try v2Identity(owner.deviceID, state: v2)
                try require(current.accountID == nil && current.reservation == p.pairingID && v2Matches(owner, current),
                    "Genesis owner is no longer eligible", code: "rootAlreadyBound")
            }
            proposal.approvals[actor] = proof; proposal.revision += 1; pair.revision += 1; proposal.status = .partiallyApproved
            if proposal.approvals.count == 2 {
                try require(v2.accounts[p.accountID] == nil && next.accounts?[p.accountID] == nil, "Account already exists", code: "requestConflict")
                v2.accounts[p.accountID] = V2Account(accountID: p.accountID, label: p.label, policy: p.ownershipPolicyID,
                    revision: 1, owners: p.owners)
                next.accounts?[p.accountID] = AccountRecord(accountID: p.accountID, label: p.label, createdAt: clock(), imported: false)
                try v2Promote(p.owners, accountID: p.accountID, v2: &v2, next: &next)
                proposal.status = .committed; pair.status = .committed
                events.append(event("v2.account.created", account: p.accountID, actor: actor, details: ["policy": p.ownershipPolicyID, "owners": "2"]))
                let (first, head) = try v2PredictHead(events), ids = p.owners.map(\.deviceID)
                let receipt = PairingV2.AccountReceipt(genesis: p, pairReceiptHash: try pair.receipt!.payload.digest(),
                    aApprovalDigest: try proposal.approvals[ids[0]]!.digest(), bApprovalDigest: try proposal.approvals[ids[1]]!.digest(),
                    createdAt: clock(), membershipRevision: 1, ledgerFirstSequence: first, ledgerLastSequence: head.sequence, ledgerHeadHash: head.hash)
                proposal.receipt = try v2Sign(receipt)
            }
            v2.genesis[p.proposalID] = proposal; v2.pairings[p.pairingID] = pair
            scope = .genesisProposal; scopeID = p.proposalID
        case .proposeMembership(let p):
            var pair = try v2Pair(p.pairingID, participant: actor, state: v2, statuses: [.paired])
            try require(pair.proposalID == nil && pair.revision == p.expectedPairingRevision && pair.inspection.context == p.context
                && pair.receipt?.payload.digest() == p.pairReceiptHash, "Membership pairing changed", code: "staleState")
            guard let context = p.context.existingAccount, let transcript = pair.transcript?.payload,
                  let authorizer = context.existingOwners.first(where: { $0.deviceID == pair.inspection.initiator.deviceID }),
                  let candidate = transcript.owners.first(where: { $0.deviceID != authorizer.deviceID }) else {
                throw AuthorityError.protocolFailure(code: "invalidRequest", message: "Invalid membership pairing")
            }
            try v2CheckAccount(p.context, actor: authorizer.deviceID, state: v2)
            let result = (context.existingOwners.filter { $0.deviceID != context.lostOwner?.deviceID } + [candidate]).sorted { $0.deviceID < $1.deviceID }
            let proposal = PairingV2.MembershipProposal(authorityID: v2AuthorityID, origin: v2.origin, audience: v2.audience,
                proposalID: UUID().uuidString.lowercased(), pairingID: p.pairingID, pairTranscriptHash: try transcript.digest(),
                pairReceiptHash: p.pairReceiptHash, context: p.context, authorizingOwner: authorizer, candidate: candidate,
                resultingOwners: result, nextMembershipRevision: context.membershipRevision + 1, nonce: randomBytes(32),
                issuedAt: clock(), expiresAt: min(clock() + 300, pair.receipt!.payload.expiresAt))
            v2.memberships[proposal.proposalID] = V2Membership(proposal: try v2Sign(proposal), revision: pair.revision + 1)
            pair.proposalID = proposal.proposalID; pair.revision += 1; v2.pairings[p.pairingID] = pair
            scope = .membershipProposal; scopeID = proposal.proposalID
            events.append(event("v2.membership.proposed", account: context.accountID, actor: actor))
        case .approveMembership(let p):
            guard var proposal = v2.memberships[p.proposalID], let context = p.context.existingAccount else {
                throw AuthorityError.protocolFailure(code: "notFound", message: "Unknown membership proposal")
            }
            var pair = try v2Pair(p.pairingID, participant: actor, state: v2, statuses: [.paired])
            try require(proposal.proposal.payload == p && pair.proposalID == p.proposalID && !proposal.status.isTerminal
                && [p.authorizingOwner.deviceID, p.candidate.deviceID].contains(actor), "Membership proposal changed", code: "staleState")
            try v2CheckAccount(p.context, actor: p.authorizingOwner.deviceID, state: v2)
            let candidate = try v2Identity(p.candidate.deviceID, state: v2)
            try require(clock() < p.expiresAt && proposal.approvals[actor] == nil && candidate.accountID == nil
                && candidate.reservation == p.pairingID && v2Matches(p.candidate, candidate), "Candidate is no longer eligible", code: "staleState")
            proposal.approvals[actor] = proof; proposal.status = .partiallyApproved; proposal.revision += 1; pair.revision += 1
            if proposal.approvals.count == 2 {
                v2.accounts[context.accountID]?.owners = p.resultingOwners; v2.accounts[context.accountID]?.revision = p.nextMembershipRevision
                try v2Promote([p.candidate], accountID: context.accountID, v2: &v2, next: &next)
                if let lost = context.lostOwner {
                    v2.identities[lost.deviceID]?.revoked = true
                    next.devices[lost.deviceID]?.revoked = true; next.devices[lost.deviceID]?.revokedAt = clock()
                    next.challenges = next.challenges.filter { $0.value.deviceID != lost.deviceID }
                    v2.challenges = v2.challenges.filter { $0.value.deviceID != lost.deviceID }
                    events.append(event("device.revoked", account: context.accountID, device: lost.deviceID, actor: p.authorizingOwner.deviceID, details: ["reason": "v2.replacement"]))
                }
                v2.sessions = v2.sessions.filter { $0.value.accountID != context.accountID }
                v2.identities[p.authorizingOwner.deviceID]?.reservation = nil
                pair.status = .committed; proposal.status = .committed
                events.append(event("v2.membership.committed", account: context.accountID, device: p.candidate.deviceID,
                    actor: p.authorizingOwner.deviceID, details: ["revision": String(p.nextMembershipRevision), "purpose": p.context.purpose.rawValue]))
                let (first, head) = try v2PredictHead(events)
                let receipt = PairingV2.MembershipReceipt(proposal: p,
                    authorizerApprovalDigest: try proposal.approvals[p.authorizingOwner.deviceID]!.digest(),
                    candidateApprovalDigest: try proposal.approvals[p.candidate.deviceID]!.digest(), committedAt: clock(),
                    membershipRevision: p.nextMembershipRevision, ledgerFirstSequence: first, ledgerLastSequence: head.sequence, ledgerHeadHash: head.hash)
                proposal.receipt = try v2Sign(receipt)
            }
            v2.memberships[p.proposalID] = proposal; v2.pairings[p.pairingID] = pair
            scope = .membershipProposal; scopeID = p.proposalID
        case .control(let p):
            try require(p.actorDeviceID == actor, "Wrong control actor", code: "bindingMismatch")
            let pairID: String
            switch p.scopeKind {
            case .pairing: pairID = p.scopeID
            case .genesisProposal: guard let proposal = v2.genesis[p.scopeID] else { throw AuthorityError.rejected("Unknown genesis") }; pairID = proposal.genesis.payload.pairingID
            case .membershipProposal: guard let proposal = v2.memberships[p.scopeID] else { throw AuthorityError.rejected("Unknown membership") }; pairID = proposal.proposal.payload.pairingID
            default: throw AuthorityError.rejected("Unsupported control scope")
            }
            guard var pair = v2.pairings[pairID], v2PairMembers(pair).contains(actor) else { throw AuthorityError.protocolFailure(code: "unauthorized", message: "Not a participant") }
            let current = try v2Response(p.scopeKind, p.scopeID, state: v2)
            // A cancellation that loses to commit only acknowledges the receipt.
            if current.state.status == .committed { scope = current.state.scopeKind; scopeID = current.state.scopeID; break }
            try require(p.expectedRevision == current.state.revision && !current.state.status.isTerminal,
                "Control review changed", code: "staleState")
            if p.operation == .rotateUnjoinedSecret {
                try require(pair.status == .open && p.scopeKind == .pairing && actor == pair.inspection.initiator.deviceID,
                    "Only an unjoined initiator can rotate its invitation", code: "staleState")
                let bytes = randomBytes(32); pair.revision += 1
                let old = pair.inspection
                pair.inspection = .init(authorityID: old.authorityID, origin: old.origin, audience: old.audience,
                    pairingID: pairID, revision: pair.revision, initiator: old.initiator, context: old.context, issuedAt: old.issuedAt, expiresAt: old.expiresAt)
                pair.secretHash = try v2CapabilityHash("pair-secret-v2", pairID, bytes); secret = bytes
            } else {
                pair.status = p.operation == .reject ? .rejected : .cancelled; pair.secretHash = nil; pair.revision += 1
                if let id = pair.proposalID {
                    if v2.genesis[id] != nil { v2.genesis[id]?.status = pair.status; v2.genesis[id]?.revision += 1 }
                    if v2.memberships[id] != nil { v2.memberships[id]?.status = pair.status; v2.memberships[id]?.revision += 1 }
                }
                for member in v2PairMembers(pair) where v2.identities[member]?.reservation == pairID { v2.identities[member]?.reservation = nil }
            }
            v2.pairings[pairID] = pair; scope = p.scopeKind; scopeID = p.scopeID
            events.append(event("v2.operation.controlled", actor: actor, details: ["control": p.operation.rawValue]))
        case .renewIdentityLease(let p):
            try require(p.deviceID == actor && p.rootKeyEpoch == identity.receipt.payload.rootKeyEpoch
                && p.existingTrustReceiptHash == identity.receipt.payload.digest(), "Renewal identity changed", code: "bindingMismatch")
            let old = identity.receipt.payload
            let renewed = PairingV2.DeviceTrustReceipt(authorityID: old.authorityID, origin: old.origin, audience: old.audience,
                deviceID: actor, rootKind: old.rootKind, rootKeyEpoch: old.rootKeyEpoch, rootPublicKey: old.rootPublicKey,
                originalChallengeHash: old.originalChallengeHash, evidenceHash: old.evidenceHash, trustPolicyID: old.trustPolicyID,
                verifiedAt: clock(), leaseExpiresAt: clock() + 900)
            v2.identities[actor]?.receipt = try v2Sign(renewed)
            events.append(event("v2.identity.renewed", device: actor, actor: actor))
        case .authenticateOwner(let p):
            try require(p.deviceID == actor && p.clientRequestID == challenge.requestID
                && p.rootKeyEpoch == identity.receipt.payload.rootKeyEpoch && identity.accountID == p.accountID,
                "Session identity mismatch", code: "unauthorized")
            guard let account = v2.accounts[p.accountID], account.owners.contains(where: { $0.deviceID == actor }) else { throw AuthorityError.protocolFailure(code: "unauthorized", message: "Not an account owner") }
            try require(p.requestedScopes == ["account:read"] && p.requestedExpiresAt > clock()
                && p.requestedExpiresAt <= clock() + 900, "Unsupported session scope or lifetime", code: "invalidRequest")
            v2.sessions = v2.sessions.filter { $0.value.expiresAt > clock() }
            try require(v2.sessions.count < 10_000, "Session capacity reached", code: "rateLimited")
            let token = randomBytes(32).base64EncodedString(), expiry = min(p.requestedExpiresAt, identity.receipt.payload.leaseExpiresAt)
            v2.sessions[hex(ProtocolCrypto.sha256(Data(token.utf8)))] = V2Session(accountID: p.accountID, deviceID: actor,
                rootKeyEpoch: p.rootKeyEpoch, membershipRevision: account.revision, expiresAt: expiry, scopes: p.requestedScopes)
            sessionToken = token; sessionExpiresAt = expiry
            events.append(event("v2.owner.authenticated", account: p.accountID, device: actor, actor: actor))
        case .getResult(let p):
            try require(p.originalActorDeviceID == actor, "Result actor mismatch", code: "unauthorized")
            if let original = v2.operations[p.operationID] {
                try require(original.actor == actor && original.purpose == p.originalPurpose, "Not the original operation actor", code: "unauthorized")
                scope = original.scopeKind; scopeID = original.scopeID
            } else if let pair = v2.pairings[p.operationID], v2PairMembers(pair).contains(actor) {
                scope = .pairing; scopeID = p.operationID
            } else if let proposal = v2.genesis[p.operationID], proposal.genesis.payload.owners.contains(where: { $0.deviceID == actor }) {
                scope = .genesisProposal; scopeID = p.operationID
            } else if let proposal = v2.memberships[p.operationID], [proposal.proposal.payload.authorizingOwner.deviceID, proposal.proposal.payload.candidate.deviceID].contains(actor) {
                scope = .membershipProposal; scopeID = p.operationID
            } else if p.operationID == actor { scope = .identity; scopeID = actor }
            else {
                try require(v2.operations[p.operationID] == nil && v2.pairings[p.operationID] == nil
                    && v2.genesis[p.operationID] == nil && v2.memberships[p.operationID] == nil && v2.identities[p.operationID] == nil,
                    "Result is not bound to this root", code: "unauthorized")
                // The lookup sequence has already been consumed in this local
                // transaction. Every older original challenge becomes stale;
                // retain an actor-scoped tombstone so no fresh challenge may
                // revive the request after this signed negative result.
                let original = state.pairingV2?.challenges.values.first { $0.requestID == p.operationID }
                try require(original == nil || (original?.deviceID == actor && original?.purpose == p.originalPurpose),
                    "Result request does not match the original actor/purpose", code: "unauthorized")
                let tombstone = actor + ":" + p.operationID
                if let purpose = v2.rejectedRequests[tombstone] {
                    try require(purpose == p.originalPurpose, "Rejected request purpose changed", code: "requestConflict")
                }
                try require(v2.rejectedRequests.count < 100_000, "Recovery retention capacity reached", code: "rateLimited")
                v2.rejectedRequests[tombstone] = p.originalPurpose
                let rejected = PairingV2.OperationState(scopeKind: .operation, scopeID: p.operationID,
                    revision: challenge.sequence, status: .rejected, objectHash: try p.digest(), approvedSignerIDs: [],
                    phaseExpiresAt: clock(), receiptHash: nil)
                let envelope = PairingV2.SignedState(authorityID: v2AuthorityID, origin: v2.origin, audience: v2.audience,
                    scopeKind: .operation, scopeID: p.operationID, revision: challenge.sequence, payloadHash: try rejected.digest(),
                    issuedAt: clock(), expiresAt: clock() + 60)
                responseOverride = .init(state: rejected, signedState: try v2Sign(envelope))
                events.append(event("v2.operation.rejected_by_recovery", device: actor, actor: actor,
                    details: ["purpose": p.originalPurpose.rawValue]))
            }
        }
        let response = try responseOverride ?? v2Response(scope, scopeID, state: v2, includeRoster: challenge.purpose != .getResult)
        // Fresh read proofs advance the root sequence but are not retained as
        // permanent mutation outcomes. Clients recover with another fresh read.
        if challenge.purpose != .getResult {
            v2.operations[challenge.requestID] = V2Operation(actor: actor, purpose: challenge.purpose, payloadHash: payloadHash,
                proof: proof, scopeKind: scope, scopeID: scopeID, response: response)
        }
        try v2Commit(v2, events: events, next: next)
        return .init(operation: response, secret: secret, sessionToken: sessionToken, sessionExpiresAt: sessionExpiresAt)
    }

    private func v2NewGenesis(pair: V2Pairing, label: String, policy: String, state v2: PairingV2State) throws -> V2Genesis {
        guard let transcript = pair.transcript?.payload, let receipt = pair.receipt?.payload else { throw AuthorityError.rejected("Pairing has no mutual receipt") }
        try require(policy == PairingV2.ownershipPolicy, "Unsupported ownership policy")
        let genesis = PairingV2.AccountGenesis(authorityID: v2AuthorityID, origin: v2.origin, audience: v2.audience,
            proposalID: UUID().uuidString.lowercased(), pairingID: transcript.pairingID, pairTranscriptHash: try transcript.digest(),
            accountID: UUID().uuidString.lowercased(), label: label, owners: transcript.owners, ownershipPolicyID: policy,
            initialMembershipRevision: 1, nonce: randomBytes(32), issuedAt: clock(), expiresAt: min(clock() + 300, receipt.expiresAt))
        return V2Genesis(genesis: try v2Sign(genesis), revision: pair.revision + 1)
    }

    public func accountRosterV2(accountID: String, bearer: String) async throws -> PairingV2.Signed<PairingV2.AccountRoster> {
        var v2 = try v2State()
        try require(bearer.utf8.count <= 256, "Invalid owner session", code: "unauthorized")
        let hash = hex(ProtocolCrypto.sha256(Data(bearer.utf8)))
        guard let session = v2.sessions[hash], session.accountID == accountID else { throw AuthorityError.protocolFailure(code: "unauthorized", message: "Invalid owner session") }
        let identity = try v2Identity(session.deviceID, state: v2)
        try await verifier.revalidate(identity.identity, now: clock())
        v2 = try v2State()
        guard let current = v2.sessions[hash], let account = v2.accounts[accountID] else { throw AuthorityError.protocolFailure(code: "unauthorized", message: "Owner session was invalidated") }
        _ = try v2Identity(session.deviceID, state: v2)
        try require(current.expiresAt > clock() && current.membershipRevision == account.revision
            && current.rootKeyEpoch == identity.receipt.payload.rootKeyEpoch && current.scopes.contains("account:read"),
            "Owner session expired or membership changed", code: "unauthorized")
        return try v2Roster(account, state: v2)
    }
}
