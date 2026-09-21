import Foundation
import SwiftKeyCore

/// Public, verified values for application projection. No invitation, session
/// bearer, preparation capability, attestation chain, or private leaf is exposed.
public struct PairingClientSnapshot: Sendable {
    public let configuration: PairingClientConfiguration
    public let identity: PairingV2.Signed<PairingV2.DeviceTrustReceipt>?
    public let operation: PairingV2.OperationResponse?
    public let committedOperation: PairingV2.OperationResponse?
    public let inspection: PairingV2.Signed<PairingV2.PairingInspection>?
    public let roster: PairingV2.Signed<PairingV2.AccountRoster>?
    public let accountReceipt: PairingV2.Signed<PairingV2.AccountReceipt>?
    public let membershipReceipt: PairingV2.Signed<PairingV2.MembershipReceipt>?
    public let pendingRequestID: String?
    public let admissionFailure: String?
    public let signedIn: Bool
    public let credential: EpochCredential?
    public let invitationAvailable: Bool
    public let now: UInt64
}

/// App-private durable state. Do not serialize it into a browser/UI tree.
private struct PairingClientState: Codable, Sendable {
    var version = 2
    let configuration: PairingClientConfiguration
    var preparation: PairingV2.PreparationResponse?
    var admissionPending: Bool?
    var admissionFailure: String?
    var evidence: AndroidEnrollmentEvidence?
    var identity: PairingV2.Signed<PairingV2.DeviceTrustReceipt>?
    var operation: PairingV2.OperationResponse?
    var inspection: PairingV2.Signed<PairingV2.PairingInspection>?
    var roster: PairingV2.Signed<PairingV2.AccountRoster>?
    var accountReceipt: PairingV2.Signed<PairingV2.AccountReceipt>?
    var membershipReceipt: PairingV2.Signed<PairingV2.MembershipReceipt>?
    var committedEvidence: PairingV2.OperationResponse?
    var pending: PairingV2.OperationRequest?
    var lastRequest: PairingV2.OperationRequest?
    var localApprovals: [String: PairingV2.RootProof] = [:]
    var sequence: UInt64 = 0
    var ledgerSequence: UInt64 = 0
    var ledgerHash: Data?
    var epochSnapshot: EpochManagerSnapshot?
}

/// Real hardware-backed v2 orchestration. Calls are serialized per root. The
/// platform owns StrongBox, bounded transport and app-private atomic storage.
public actor PairingClient {
    public let configuration: PairingClientConfiguration
    private let platform: ClientPlatform
    private var state: PairingClientState
    private var invitation: PairingInvitation?
    private var createdCapability: Data?
    private var sessionToken: String?
    private var sessionExpiresAt: UInt64 = 0
    private var manager: EpochManager?
    private var busy = false

    public init(configuration: PairingClientConfiguration, platform: ClientPlatform) throws {
        try configuration.validate()
        self.configuration = configuration; self.platform = platform
        if let bytes = try platform.readState() {
            let restored = try JSONDecoder().decode(PairingClientState.self, from: bytes)
            guard restored.version == 2, restored.configuration == configuration else { throw ClientError.storedStateMismatch }
            try Self.verifyRestored(restored, configuration: configuration)
            state = restored
        } else { state = .init(configuration: configuration) }
    }

    public func snapshot() -> PairingClientSnapshot {
        .init(configuration: configuration, identity: state.identity, operation: state.operation, committedOperation: state.committedEvidence,
              inspection: state.inspection, roster: state.roster, accountReceipt: state.accountReceipt,
              membershipReceipt: state.membershipReceipt, pendingRequestID: state.pending?.proof.challenge.requestID ?? (state.identity == nil && state.admissionPending == true ? state.preparation?.challenge.payload.requestID : nil),
              admissionFailure: state.admissionFailure,
              signedIn: sessionToken != nil && platform.now() < sessionExpiresAt,
              credential: state.epochSnapshot?.credential, invitationAvailable: createdCapability != nil,
              now: platform.now())
    }

    public func prepareIdentity(requestID: String) throws {
        try idle()
        if state.identity != nil { return }
        do {
        if state.preparation == nil {
            let prepared: PairingV2.PreparationResponse = try post("/v2/identities/prepare",
                PairingV2.PreparationRequest(requestID: requestID, rootKind: .androidStrongBox))
            try prepared.challenge.verify(authorityPublicKey: configuration.serverPublicKey)
            let c = prepared.challenge.payload
            try context(c.authorityID, c.origin, c.audience)
            guard c.requestID == requestID, c.rootKind == .androidStrongBox,
                  prepared.preparationCapability.count == 32 else { throw ClientError.invalidServerResponse }
            try live(c.issuedAt, c.expiresAt)
            var next = state; next.preparation = prepared; try persist(next)
        }
        guard let prepared = state.preparation else { throw ClientError.storedStateMismatch }
        if state.evidence == nil {
            try live(prepared.challenge.payload.issuedAt, prepared.challenge.payload.expiresAt)
            let evidence = try platform.enroll(prepared.challenge.payload.digest())
            guard evidence.platform == "androidStrongBox", !evidence.certificateChain.isEmpty else { throw ClientError.unsupportedHardware }
            try ProtocolCrypto.validatePublicKey(evidence.publicKey)
            var next = state; next.evidence = evidence; try persist(next)
        }
        guard let evidence = state.evidence else { throw ClientError.storedStateMismatch }
        let message = try prepared.challenge.payload.canonicalBytes()
        let signature = try platform.signRootMessage(message)
        guard ProtocolCrypto.verify(signature: signature, message: message, publicKey: evidence.publicKey) else { throw ClientError.enrollmentIdentityMismatch }
        var submitting = state; submitting.admissionPending = true; submitting.admissionFailure = nil; try persist(submitting)
        let receipt: PairingV2.Signed<PairingV2.DeviceTrustReceipt> = try post("/v2/identities/attest",
            PairingV2.AttestationRequest(challenge: prepared.challenge.payload,
                preparationCapability: prepared.preparationCapability,
                evidence: .init(rootKind: .androidStrongBox, certificates: evidence.certificateChain), proof: signature))
        try verifyIdentity(receipt, requireLiveLease: false)
        guard receipt.payload.rootKeyEpoch == 1, receipt.payload.deviceID == prepared.challenge.payload.deviceID,
              receipt.payload.originalChallengeHash == (try prepared.challenge.payload.digest()),
              receipt.payload.evidenceHash == (try PairingV2.AttestationEvidence(rootKind: .androidStrongBox, certificates: evidence.certificateChain).digest()),
              receipt.payload.rootPublicKey == evidence.publicKey else { throw ClientError.enrollmentIdentityMismatch }
        var next = state; next.identity = receipt; next.admissionPending = false; next.admissionFailure = nil; try persist(next)
        } catch {
            let definitiveCode: String?
            if case ClientError.serverRejected(let code) = error, Self.definitiveRejections.contains(code) { definitiveCode = code }
            else { definitiveCode = nil }
            if state.admissionPending != true || definitiveCode != nil {
                var next = state; next.admissionPending = false
                // A lost preparation response precedes all hardware generation; its orphan
                // allocation may expire and the app can safely obtain a new preparation.
                next.admissionFailure = state.preparation == nil && state.evidence == nil ? nil
                    : definitiveCode ?? (error as? ClientError == .unsupportedHardware ? "unsupportedHardware" : "admissionBlocked")
                try? persist(next)
            }
            throw error
        }
    }

    public func renewIdentity(requestID: String) throws {
        let identity = try owner()
        let intent = PairingV2.RenewLeaseIntent(authorityID: configuration.authorityID, origin: configuration.serverURL,
            audience: configuration.audience, deviceID: identity.deviceID, rootKeyEpoch: identity.rootKeyEpoch,
            existingTrustReceiptHash: try state.identity!.payload.digest())
        try execute(.renewIdentityLease(intent), scopeID: identity.deviceID, requestID: requestID)
    }

    public func createPairing(context pairContext: PairingV2.PairingContext = .init(purpose: .createAccount), requestID: String) throws {
        try idle(); try noPending()
        let descriptor = try owner()
        if pairContext.purpose == .createAccount, accountID != nil { throw PairingClientError.alreadyOwned }
        let intent = PairingV2.CreatePairingIntent(authorityID: configuration.authorityID, origin: configuration.serverURL,
            audience: configuration.audience, requestID: requestID, initiator: descriptor, context: pairContext)
        try execute(.createPairing(intent), scopeID: descriptor.deviceID, requestID: requestID)
    }

    public func inspectInvitation(_ link: String) throws {
        try idle(); try noPending()
        guard accountID == nil else { throw PairingClientError.alreadyOwned }
        let imported = try PairingInvitation(link: link, configuration: configuration)
        let inspected: PairingV2.Signed<PairingV2.PairingInspection> = try post("/v2/pairings/inspect",
            PairingV2.InspectionRequest(pairingID: imported.pairingID, capability: imported.capability))
        try inspected.verify(authorityPublicKey: configuration.serverPublicKey)
        let p = inspected.payload
        try context(p.authorityID, p.origin, p.audience); try live(p.issuedAt, p.expiresAt)
        guard p.pairingID == imported.pairingID,
              p.initiator.deviceID != state.identity?.payload.deviceID,
              p.initiator.rootPublicKey != state.identity?.payload.rootPublicKey else { throw PairingClientError.invalidInvitation }
        var next = state; next.inspection = inspected; next.operation = nil; try persist(next)
        invitation = imported; createdCapability = nil
    }

    public func join(requestID: String) throws {
        guard let inspection = state.inspection?.payload, let invitation,
              invitation.pairingID == inspection.pairingID else { throw PairingClientError.invitationMustBeScannedAgain }
        let intent = PairingV2.JoinPairingIntent(authorityID: configuration.authorityID, origin: configuration.serverURL,
            audience: configuration.audience, pairingID: inspection.pairingID, expectedRevision: inspection.revision,
            inspectionHash: try inspection.digest(), initiatorHash: try inspection.initiator.digest(), candidate: try owner())
        try execute(.joinPairing(intent), scopeID: inspection.pairingID, requestID: requestID, capability: invitation.capability)
        self.invitation = nil
    }

    public func confirmPair(requestID: String) throws {
        guard let transcript = state.operation?.transcript?.payload else { throw PairingClientError.invalidState }
        try execute(.confirmPair(transcript), scopeID: transcript.pairingID, requestID: requestID)
    }

    public func proposeAccount(label: String, requestID: String) throws {
        guard let response = state.operation, let receipt = response.pairReceipt?.payload,
              receipt.transcript.context.purpose == .createAccount else { throw PairingClientError.invalidState }
        let intent = PairingV2.ProposeAccountIntent(authorityID: configuration.authorityID, origin: configuration.serverURL,
            audience: configuration.audience, pairingID: receipt.transcript.pairingID, expectedRevision: response.state.revision,
            pairReceiptHash: try receipt.digest(), label: normalized(label), ownershipPolicyID: PairingV2.ownershipPolicy)
        try execute(.proposeAccount(intent), scopeID: receipt.transcript.pairingID, requestID: requestID)
    }

    public func replaceGenesis(label: String, requestID: String) throws {
        guard let response = state.operation, let proposal = response.genesis?.payload else { throw PairingClientError.invalidState }
        let intent = PairingV2.ReplaceGenesisIntent(authorityID: configuration.authorityID, origin: configuration.serverURL,
            audience: configuration.audience, pairingID: proposal.pairingID, expectedRevision: response.state.revision,
            oldProposalHash: try proposal.digest(), newLabel: normalized(label), newOwnershipPolicyID: PairingV2.ownershipPolicy)
        try execute(.replaceGenesis(intent), scopeID: proposal.pairingID, requestID: requestID)
    }

    public func approveGenesis(requestID: String) throws {
        guard let genesis = state.operation?.genesis?.payload else { throw PairingClientError.invalidState }
        try execute(.approveGenesis(genesis), scopeID: genesis.proposalID, requestID: requestID)
    }

    public func beginOwnerChange(replacing deviceID: String? = nil, requestID: String) throws {
        try idle(); try noPending(); try refreshRoster()
        guard let roster = state.roster?.payload else { throw PairingClientError.invalidState }
        let local = try owner()
        let lost = deviceID.flatMap { id in roster.owners.first { $0.deviceID == id } }
        if let deviceID, lost == nil || deviceID == local.deviceID { throw PairingClientError.staleReview }
        let context = PairingV2.ExistingAccountContext(accountID: roster.accountID, accountLabel: roster.accountLabel,
            ownershipPolicyID: roster.ownershipPolicyID, membershipRevision: roster.membershipRevision,
            existingOwners: roster.owners, lostOwner: lost)
        try createPairing(context: .init(purpose: lost == nil ? .addOwner : .replaceOwner, existingAccount: context), requestID: requestID)
    }

    public func proposeMembership(requestID: String) throws {
        guard let response = state.operation, let receipt = response.pairReceipt?.payload,
              receipt.transcript.context.purpose != .createAccount else { throw PairingClientError.invalidState }
        let intent = PairingV2.ProposeMembershipIntent(authorityID: configuration.authorityID, origin: configuration.serverURL,
            audience: configuration.audience, pairingID: receipt.transcript.pairingID, expectedPairingRevision: response.state.revision,
            pairReceiptHash: try receipt.digest(), context: receipt.transcript.context)
        try execute(.proposeMembership(intent), scopeID: receipt.transcript.pairingID, requestID: requestID)
    }

    public func approveMembership(requestID: String) throws {
        guard let proposal = state.operation?.membershipProposal?.payload else { throw PairingClientError.invalidState }
        try execute(.approveMembership(proposal), scopeID: proposal.proposalID, requestID: requestID)
    }

    public func control(_ operation: PairingV2.ControlOperation, requestID: String) throws {
        guard let current = state.operation else { throw PairingClientError.invalidState }
        let intent = PairingV2.ControlIntent(authorityID: configuration.authorityID, origin: configuration.serverURL,
            audience: configuration.audience, scopeKind: current.state.scopeKind, scopeID: current.state.scopeID,
            expectedRevision: current.state.revision, operation: operation, actorDeviceID: try owner().deviceID)
        try execute(.control(intent), scopeID: current.state.scopeID, requestID: requestID)
        if operation != .rotateUnjoinedSecret { createdCapability = nil; invitation = nil }
    }

    /// A lost reply never creates a second mutation. Poll the original request
    /// or bound scope with fresh root proof and keep all original approvals.
    public func refresh() throws {
        try idle()
        if state.identity == nil { return }
        if let request = state.pending ?? state.lastRequest {
            // The pairing points to its current proposal. Polling an old proposal ID
            // would strand the peer after an explicitly replaced genesis.
            let pairingID = state.operation?.transcript?.payload.pairingID ?? state.operation?.pairReceipt?.payload.transcript.pairingID
                ?? state.operation?.inspection?.payload.pairingID ?? state.inspection?.payload.pairingID
            let id = state.pending?.proof.challenge.requestID ?? pairingID ?? state.operation?.state.scopeID ?? request.proof.challenge.requestID
            let lookup = PairingV2.ResultLookupIntent(authorityID: configuration.authorityID, origin: configuration.serverURL,
                audience: configuration.audience, operationID: id, originalActorDeviceID: try owner().deviceID,
                originalPurpose: request.payload.purpose)
            try execute(.getResult(lookup), scopeID: id, requestID: UUID().uuidString.lowercased(), allowPending: true)
        }
        if sessionToken != nil, accountID != nil { try refreshRoster() }
    }

    public func recover(requestID: String) throws {
        if state.identity == nil, requestID == state.preparation?.challenge.payload.requestID {
            try prepareIdentity(requestID: requestID); return
        }
        guard requestID == state.pending?.proof.challenge.requestID else { throw PairingClientError.staleReview }
        try refresh()
    }

    public func discardInspection() throws {
        try idle(); try noPending()
        guard state.operation == nil else { throw PairingClientError.invalidState }
        var next = state; next.inspection = nil; try persist(next)
        invitation = nil; createdCapability = nil
    }

    public func restart() throws {
        try idle(); try noPending()
        if state.operation == nil, let inspection = state.inspection,
           platform.now() >= inspection.payload.expiresAt { try discardInspection(); return }
        guard let operation = state.operation, operation.state.status.isTerminal,
              operation.state.status != .committed else { throw PairingClientError.invalidState }
        var next = state; next.operation = nil; next.inspection = nil; next.lastRequest = nil; try persist(next)
        invitation = nil; createdCapability = nil
    }

    public func invitationLink() throws -> String {
        guard let capability = createdCapability, let p = state.operation?.inspection?.payload,
              state.operation?.state.status == .open, platform.now() < p.expiresAt else { throw PairingClientError.invalidState }
        return try PairingInvitation.link(pairingID: p.pairingID, capability: capability, configuration: configuration)
    }
    public func dismissInvitation() { createdCapability = nil; invitation = nil }

    public func signIn(requestID: String) throws {
        guard let accountID else { throw PairingClientError.identityRequired }
        let local = try owner(), now = platform.now()
        let intent = PairingV2.OwnerSessionIntent(authorityID: configuration.authorityID, origin: configuration.serverURL,
            audience: configuration.audience, accountID: accountID, deviceID: local.deviceID, rootKeyEpoch: local.rootKeyEpoch,
            clientRequestID: requestID, requestedScopes: ["account:read"], requestedExpiresAt: now + 900)
        try execute(.authenticateOwner(intent), scopeID: accountID, requestID: requestID)
        try refreshRoster()
    }

    public func refreshRoster() throws {
        try idle()
        guard let accountID, let sessionToken, platform.now() < sessionExpiresAt else { throw PairingClientError.signingUnavailable }
        let roster: PairingV2.Signed<PairingV2.AccountRoster>
        do { roster = try post("/v2/accounts/roster", PairingV2.RosterRequest(accountID: accountID), bearer: sessionToken) }
        catch {
            if case ClientError.serverRejected(let code) = error, ["unauthorized", "revokedDevice"].contains(code) {
                self.sessionToken = nil; sessionExpiresAt = 0
            }
            throw error
        }
        try roster.verify(authorityPublicKey: configuration.serverPublicKey)
        let p = roster.payload; try context(p.authorityID, p.origin, p.audience); try live(p.issuedAt, p.expiresAt)
        guard p.accountID == accountID, p.membershipRevision >= (state.roster?.payload.membershipRevision ?? 0),
              p.owners.contains(where: { $0.deviceID == state.identity?.payload.deviceID && $0.rootPublicKey == state.identity?.payload.rootPublicKey && $0.rootKeyEpoch == state.identity?.payload.rootKeyEpoch && $0.rootKind == state.identity?.payload.rootKind })
        else { throw PairingClientError.membershipRevoked }
        var next = state; next.roster = roster; try persist(next)
    }

    public func ensureCurrentCredential() async throws -> EpochCredential {
        try idle(); try noPending()
        busy = true; defer { busy = false }
        guard let accountID else { throw PairingClientError.identityRequired }
        let local = try owner()
        let epoch: EpochManager
        if let manager { epoch = manager }
        else {
            epoch = EpochManager(accountID: accountID, deviceID: local.deviceID, rootPublicKey: local.rootPublicKey,
                serverPublicKey: configuration.serverPublicKey, audience: configuration.workloadAudience)
            if let snapshot = state.epochSnapshot { try await epoch.restore(snapshot, now: platform.now()) }
            manager = epoch
        }
        if try await epoch.currentCredential(now: platform.now()) == nil {
            let delegation = try await epoch.prepareDelegation(now: platform.now())
            var next = state; next.epochSnapshot = await epoch.snapshot(); try persist(next)
            let request = ChallengeRequest(accountID: accountID, deviceID: local.deviceID, operation: .issueEpoch,
                payloadHash: ProtocolCrypto.sha256(try delegation.canonicalBytes()))
            let challenge: ChallengeEnvelope = try legacyPost("/v1/challenges", request)
            try challenge.validate(now: platform.now())
            guard challenge.accountID == accountID, challenge.deviceID == local.deviceID, challenge.operation == .issueEpoch,
                  challenge.payloadHash == request.payloadHash, challenge.sequence > state.sequence else { throw ClientError.invalidServerResponse }
            let auth = RootAuthorization(kind: .androidStrongBoxP256, challenge: challenge,
                signature: try platform.signRootMessage(challenge.canonicalBytes()))
            let credential: EpochCredential = try legacyPost("/v1/epochs", IssueEpochRequest(delegation: delegation, authorization: auth))
            try await epoch.acceptCredential(credential, now: platform.now())
            next = state; next.sequence = challenge.sequence; next.epochSnapshot = await epoch.snapshot(); try persist(next)
        }
        guard let credential = try await epoch.currentCredential(now: platform.now()) else { throw ProtocolError.credentialRequired }
        return credential
    }

    private var accountID: String? { state.membershipReceipt?.payload.proposal.context.existingAccount?.accountID ?? state.accountReceipt?.payload.genesis.accountID }
    private func idle() throws { if busy { throw ClientError.operationInProgress } }
    private func noPending() throws { if state.pending != nil { throw PairingClientError.outcomeUnknown } }
    private func owner() throws -> PairingV2.OwnerDescriptor {
        guard let receipt = state.identity else { throw PairingClientError.identityRequired }
        let p = receipt.payload
        return .init(deviceID: p.deviceID, rootKind: p.rootKind, rootKeyEpoch: p.rootKeyEpoch,
            rootPublicKey: p.rootPublicKey, attestationReceiptHash: try p.digest())
    }
    private func execute(_ payload: PairingV2.OperationPayload, scopeID: String, requestID: String,
                         capability: Data? = nil, allowPending: Bool = false) throws {
        try idle(); if !allowPending { try noPending() }
        let local = try owner(), hash = try payload.canonicalBytes().sha256ForPairing
        guard scopeID == payload.scopeID else { throw PairingClientError.staleReview }
        if [.confirmPair, .approveGenesis, .approveMembership].contains(payload.purpose),
           let accepted = state.localApprovals[approvalKey(payload.purpose, hash)] {
            if accepted.challenge.requestID == requestID { try refresh(); return }
            throw PairingClientError.staleReview // Keep the first signed consent as immutable receipt evidence.
        }
        let requested = PairingV2.RootChallengeRequest(deviceID: local.deviceID, rootKeyEpoch: local.rootKeyEpoch,
            requestID: requestID, purpose: payload.purpose, scopeID: scopeID, payloadHash: hash, capability: capability)
        let signed: PairingV2.Signed<PairingV2.RootChallenge> = try post("/v2/challenges", requested)
        try signed.verify(authorityPublicKey: configuration.serverPublicKey)
        let c = signed.payload
        try context(c.authorityID, c.origin, c.audience); try live(c.issuedAt, c.expiresAt)
        guard c.deviceID == local.deviceID, c.rootKeyEpoch == local.rootKeyEpoch, c.requestID == requestID,
              c.purpose == payload.purpose, c.scopeID == scopeID, c.payloadHash == hash, c.sequence > state.sequence else {
            throw ClientError.invalidServerResponse
        }
        let proof = PairingV2.RootProof(rootKind: local.rootKind, challenge: c, proof: try platform.signRootMessage(c.canonicalBytes()))
        try verifyProof(proof, owner: local, purpose: payload.purpose, hash: hash, scope: scopeID)
        let persisted = PairingV2.OperationRequest(payload: payload, proof: proof, capability: nil)
        if payload.purpose != .getResult {
            var next = state; next.pending = persisted
            if [.confirmPair, .approveGenesis, .approveMembership].contains(payload.purpose) {
                next.localApprovals[approvalKey(payload.purpose, hash)] = proof
            }
            try persist(next) // Never transmit a mutation before its retry identity is durable.
        }
        let result = try mutationResponse(PairingV2.OperationRequest(payload: payload, proof: proof, capability: capability))
        let expected = state.pending ?? (payload.purpose == .getResult ? state.lastRequest : nil) ?? persisted
        try finish(result, transmitted: persisted, expected: expected, allowProgress: payload.purpose == .getResult && state.pending == nil)
    }

    private static let definitiveRejections: Set<String> = ["unauthorized", "invalidRequest", "invalidSignature", "bindingMismatch", "contextMismatch",
        "expired", "identityReserved", "requestConflict", "revokedDevice", "rootAlreadyBound", "staleChallenge", "staleMembership", "staleState", "trustExpired", "unsupportedRoot"]

    private func mutationResponse(_ request: PairingV2.OperationRequest) throws -> PairingV2.ExecutionResponse {
        do { return try post("/v2/operations", request) }
        catch {
            // A typed rejection received from the configured HTTPS authority is definitive.
            // Transport/decoding/verification errors keep the durable pending request intact.
            if case ClientError.serverRejected(let code) = error, Self.definitiveRejections.contains(code),
               state.pending?.proof.challenge.requestID == request.proof.challenge.requestID {
                var next = state; next.pending = nil
                let key = approvalKey(request.payload.purpose, request.proof.challenge.payloadHash)
                if next.localApprovals[key] == request.proof { next.localApprovals.removeValue(forKey: key) }
                try persist(next)
            }
            throw error
        }
    }

    private func finish(_ result: PairingV2.ExecutionResponse, transmitted: PairingV2.OperationRequest,
                        expected: PairingV2.OperationRequest, allowProgress: Bool) throws {
        if case .getResult(let lookup) = transmitted.payload,
           result.operation.state.scopeKind == .operation && result.operation.state.status == .rejected {
            guard let pending = state.pending, lookup.operationID == pending.proof.challenge.requestID,
                  lookup.originalActorDeviceID == pending.proof.challenge.deviceID,
                  lookup.originalPurpose == pending.payload.purpose,
                  result.operation.state.scopeID == lookup.operationID,
                  result.operation.state.objectHash == (try lookup.digest()),
                  result.operation.state.receiptHash == nil, result.operation.state.approvedSignerIDs.isEmpty,
                  result.operation.proofs.isEmpty, result.operation.inspection == nil, result.operation.transcript == nil,
                  result.operation.pairReceipt == nil, result.operation.genesis == nil, result.operation.membershipProposal == nil,
                  result.operation.accountReceipt == nil, result.operation.membershipReceipt == nil,
                  result.operation.trustReceipt == nil, result.operation.roster == nil,
                  result.secret == nil, result.sessionToken == nil else { throw PairingClientError.receiptMismatch }
            try result.operation.verify(authorityPublicKey: configuration.serverPublicKey, expectedOrigin: configuration.serverURL, now: platform.now())
            var next = state; next.pending = nil; next.sequence = max(next.sequence, transmitted.proof.challenge.sequence)
            let key = approvalKey(pending.payload.purpose, pending.proof.challenge.payloadHash)
            if next.localApprovals[key] == pending.proof { next.localApprovals.removeValue(forKey: key) }
            if next.operation == nil { next.operation = result.operation }
            try persist(next)
            return
        }
        if let secret = result.secret {
            guard secret.count == 32, result.operation.state.status == .open,
                  transmitted.payload.purpose == .createPairing || transmitted.payload.purpose == .control else { throw ClientError.invalidServerResponse }
        }
        if let token = result.sessionToken {
            guard transmitted.payload.purpose == .authenticateOwner, token.utf8.count >= 32,
                  let expires = result.sessionExpiresAt, expires > platform.now(),
                  expires - platform.now() <= 900 else { throw ClientError.invalidServerResponse }
        }
        let resolvedMutation = state.pending ?? (transmitted.payload.purpose == .getResult ? nil : transmitted)
        try accept(result.operation, expected: expected, allowProgress: allowProgress, isResultLookup: transmitted.payload.purpose == .getResult)
        var next = state; next.sequence = max(next.sequence, transmitted.proof.challenge.sequence); next.pending = nil
        if let resolvedMutation, ![PairingV2.RootPurpose.getResult, .authenticateOwner, .renewIdentityLease].contains(resolvedMutation.payload.purpose) {
            next.lastRequest = resolvedMutation
        }
        try persist(next)
        if let secret = result.secret { createdCapability = secret }
        else if result.operation.state.status != .open { createdCapability = nil }
        if let token = result.sessionToken, let expires = result.sessionExpiresAt { sessionToken = token; sessionExpiresAt = expires }
    }

    private func normalized(_ label: String) -> String { label.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping }
    private func context(_ authority: Data, _ origin: String, _ audience: String) throws {
        guard authority == configuration.authorityID, origin == configuration.serverURL, audience == configuration.audience else { throw ClientError.serverIdentityMismatch }
    }
    private func live(_ issued: UInt64, _ expires: UInt64) throws {
        guard issued <= platform.now() + 5, platform.now() < expires else { throw PairingClientError.expired }
    }
    private func persist(_ next: PairingClientState) throws {
        try platform.writeState(JSONEncoder().encode(next)); state = next
    }
    private func post<Request: Encodable, Response: Decodable>(_ path: String, _ body: Request, bearer: String = "") throws -> Response {
        let data = try platform.post(configuration.serverURL + path, PairingV2JSON.encode(body), bearer)
        if let error = try? JSONDecoder().decode(AuthorityErrorResponse.self, from: data) { throw ClientError.serverRejected(error.code) }
        return try PairingV2JSON.decode(Response.self, from: data)
    }
    private func legacyPost<Request: Encodable, Response: Decodable>(_ path: String, _ body: Request) throws -> Response {
        let data = try platform.post(configuration.serverURL + path, JSONEncoder().encode(body), "")
        if let error = try? JSONDecoder().decode(AuthorityErrorResponse.self, from: data) { throw ClientError.serverRejected(error.code) }
        return try JSONDecoder().decode(Response.self, from: data)
    }
    private func approvalKey(_ purpose: PairingV2.RootPurpose, _ hash: Data) -> String { purpose.rawValue + "." + hash.base64EncodedString() }
}

private extension Data { var sha256ForPairing: Data { ProtocolCrypto.sha256(self) } }

private extension PairingClient {
    func verifyIdentity(_ receipt: PairingV2.Signed<PairingV2.DeviceTrustReceipt>, requireLiveLease: Bool = true) throws {
        try PairingV2.verifyTrustReceipt(receipt, authorityPublicKey: configuration.serverPublicKey,
            expectedOrigin: configuration.serverURL, expectedRootPublicKey: state.evidence?.publicKey, now: requireLiveLease ? platform.now() : nil)
        try context(receipt.payload.authorityID, receipt.payload.origin, receipt.payload.audience)
        if let old = state.identity {
            guard receipt.payload.deviceID == old.payload.deviceID,
                  receipt.payload.rootKeyEpoch == old.payload.rootKeyEpoch,
                  receipt.payload.verifiedAt >= old.payload.verifiedAt else { throw PairingClientError.rollback }
        }
    }

    func verifyProof(_ proof: PairingV2.RootProof, owner: PairingV2.OwnerDescriptor,
                     purpose: PairingV2.RootPurpose, hash: Data, scope: String) throws {
        let c = proof.challenge
        try context(c.authorityID, c.origin, c.audience)
        guard proof.rootKind == owner.rootKind, c.deviceID == owner.deviceID, c.rootKeyEpoch == owner.rootKeyEpoch,
              c.purpose == purpose, c.payloadHash == hash, c.scopeID == scope,
              ProtocolCrypto.verify(signature: proof.proof, message: try c.canonicalBytes(), publicKey: owner.rootPublicKey)
        else { throw PairingClientError.receiptMismatch }
    }

    static func verifyEvidence(_ response: PairingV2.OperationResponse, state: PairingClientState,
                               configuration: PairingClientConfiguration, now: UInt64? = nil) throws {
        try response.verify(authorityPublicKey: configuration.serverPublicKey, expectedOrigin: configuration.serverURL, now: now)
        guard response.signedState.payload.audience == configuration.audience else { throw PairingClientError.receiptMismatch }
        let key = configuration.serverPublicKey, origin = configuration.serverURL
        if let pair = response.pairReceipt {
            try PairingV2.verifyPairReceipt(pair, proofs: response.proofs, authorityPublicKey: key, expectedOrigin: origin)
        }
        if let receipt = response.accountReceipt {
            guard let pair = response.pairReceipt else { throw PairingClientError.receiptMismatch }
            try PairingV2.verifyAccountReceipt(receipt, pairReceipt: pair, proofs: response.proofs, authorityPublicKey: key, expectedOrigin: origin)
        }
        if let receipt = response.membershipReceipt {
            guard let pair = response.pairReceipt else { throw PairingClientError.receiptMismatch }
            try PairingV2.verifyMembershipReceipt(receipt, pairReceipt: pair, proofs: response.proofs, authorityPublicKey: key, expectedOrigin: origin)
        }
        // Partial progress is also cryptographic evidence, not a server-selected boolean.
        let reviewed: (PairingV2.OperationPayload, [PairingV2.OwnerDescriptor])?
        switch response.state.scopeKind {
        case .pairing:
            reviewed = response.transcript.map { (.confirmPair($0.payload), $0.payload.owners) }
        case .genesisProposal:
            reviewed = response.genesis.map { (.approveGenesis($0.payload), $0.payload.owners) }
        case .membershipProposal:
            reviewed = response.membershipProposal.map { (.approveMembership($0.payload), [$0.payload.authorizingOwner, $0.payload.candidate]) }
        default: reviewed = nil
        }
        if let (payload, owners) = reviewed {
            let hash = try payload.digest()
            guard response.state.objectHash == hash, response.state.scopeID == payload.scopeID else { throw PairingClientError.receiptMismatch }
            for signerID in response.state.approvedSignerIDs {
                guard let owner = owners.first(where: { $0.deviceID == signerID }) else { throw PairingClientError.receiptMismatch }
                let matching = response.proofs.filter { $0.challenge.deviceID == signerID && $0.challenge.purpose == payload.purpose && $0.challenge.payloadHash == hash }
                guard matching.count == 1, let proof = matching.first else { throw PairingClientError.receiptMismatch }
                try PairingV2.verifyRootProof(proof, payload: payload, owner: owner, authorityPublicKey: key,
                                              expectedOrigin: origin, purpose: payload.purpose, scopeID: payload.scopeID)
                if signerID == state.identity?.payload.deviceID {
                    let localKey = payload.purpose.rawValue + "." + hash.base64EncodedString()
                    guard state.localApprovals[localKey] == proof else { throw PairingClientError.receiptMismatch }
                }
            }
            let count = response.state.approvedSignerIDs.count
            if response.state.status == .partiallyApproved && count != 1 { throw PairingClientError.receiptMismatch }
            if response.state.status == .proposed && count != 0 { throw PairingClientError.receiptMismatch }
            if [.paired, .committed].contains(response.state.status) && count != 2 { throw PairingClientError.receiptMismatch }
        } else if !response.state.approvedSignerIDs.isEmpty { throw PairingClientError.receiptMismatch }
        // A signed server assertion must never manufacture this phone's consent.
        let finalHashes: [(PairingV2.RootPurpose, Data?)] = [
            (.confirmPair, try response.pairReceipt?.payload.transcript.digest()),
            (.approveGenesis, try response.accountReceipt?.payload.genesis.digest()),
            (.approveMembership, try response.membershipReceipt?.payload.proposal.digest())]
        for (purpose, optionalHash) in finalHashes {
            guard let hash = optionalHash else { continue }
            let localKey = purpose.rawValue + "." + hash.base64EncodedString()
            guard let saved = state.localApprovals[localKey],
                  response.proofs.contains(where: { $0 == saved }),
                  saved.challenge.deviceID == state.identity?.payload.deviceID else { throw PairingClientError.receiptMismatch }
        }
        if response.state.status == .committed && response.state.scopeKind != .identity {
            guard response.accountReceipt != nil || response.membershipReceipt != nil else { throw PairingClientError.receiptMismatch }
        }
    }

    func accept(_ response: PairingV2.OperationResponse, expected: PairingV2.OperationRequest, allowProgress: Bool = false, isResultLookup: Bool = false) throws {
        try Self.verifyEvidence(response, state: state, configuration: configuration, now: platform.now())
        let local = try owner()
        let transcript = response.transcript?.payload ?? response.pairReceipt?.payload.transcript
        let genesis = response.genesis?.payload ?? response.accountReceipt?.payload.genesis
        let membership = response.membershipProposal?.payload ?? response.membershipReceipt?.payload.proposal
        let pairID = transcript?.pairingID ?? response.inspection?.payload.pairingID ?? genesis?.pairingID ?? membership?.pairingID
        let roots = transcript?.owners ?? genesis?.owners ?? membership.map { [$0.authorizingOwner, $0.candidate] }
            ?? response.inspection.map { [$0.payload.initiator] } ?? []
        let pairContext = transcript?.context ?? response.inspection?.payload.context ?? membership?.context
        if !roots.isEmpty {
            guard roots.contains(where: { $0.hasSameRoot(as: local) }) else { throw PairingClientError.receiptMismatch }
        }
        if allowProgress {
            let oldPairID = state.operation?.transcript?.payload.pairingID ?? state.operation?.pairReceipt?.payload.transcript.pairingID
                ?? state.operation?.inspection?.payload.pairingID ?? state.inspection?.payload.pairingID
            guard oldPairID != nil, pairID == oldPairID else { throw PairingClientError.receiptMismatch }
            let oldContext = state.operation?.transcript?.payload.context ?? state.operation?.pairReceipt?.payload.transcript.context
                ?? state.inspection?.payload.context
            guard oldContext == pairContext else { throw PairingClientError.receiptMismatch }
        }
        switch expected.payload {
        case .createPairing(let p):
            guard pairContext == p.context, roots.contains(p.initiator) else { throw PairingClientError.receiptMismatch }
        case .joinPairing(let p):
            guard pairID == p.pairingID, roots.contains(p.candidate),
                  try roots.contains(where: { try $0.digest() == p.initiatorHash }) else { throw PairingClientError.receiptMismatch }
        case .confirmPair(let p):
            guard transcript == p else { throw PairingClientError.receiptMismatch }
        case .proposeAccount(let p):
            guard pairID == p.pairingID,
                  allowProgress || (genesis?.label == p.label && genesis?.ownershipPolicyID == p.ownershipPolicyID) else { throw PairingClientError.receiptMismatch }
        case .replaceGenesis(let p):
            guard pairID == p.pairingID, allowProgress || genesis?.label == p.newLabel else { throw PairingClientError.receiptMismatch }
        case .approveGenesis(let p):
            guard pairID == p.pairingID, allowProgress || genesis == p else { throw PairingClientError.receiptMismatch }
        case .proposeMembership(let p):
            guard pairID == p.pairingID, membership?.context == p.context else { throw PairingClientError.receiptMismatch }
        case .approveMembership(let p):
            guard pairID == p.pairingID, allowProgress || membership == p else { throw PairingClientError.receiptMismatch }
        case .control(let p):
            guard allowProgress || response.state.scopeID == p.scopeID || pairID == p.scopeID else { throw PairingClientError.receiptMismatch }
        case .renewIdentityLease(let p):
            guard response.trustReceipt?.payload.deviceID == p.deviceID else { throw PairingClientError.receiptMismatch }
        case .authenticateOwner(let p):
            guard p.accountID == accountID, p.deviceID == local.deviceID, p.rootKeyEpoch == local.rootKeyEpoch,
                  response.trustReceipt?.payload.deviceID == local.deviceID,
                  response.trustReceipt?.payload.rootKeyEpoch == local.rootKeyEpoch,
                  response.trustReceipt?.payload.rootPublicKey == local.rootPublicKey,
                  response.roster?.payload.accountID == p.accountID || (isResultLookup && response.roster == nil) else { throw PairingClientError.receiptMismatch }
        case .getResult: throw PairingClientError.invalidState
        }
        if let old = state.operation, old.state.scopeID == response.state.scopeID {
            guard response.state.revision >= old.state.revision,
                  response.state.revision != old.state.revision || response.state.objectHash == old.state.objectHash
            else { throw PairingClientError.rollback }
        }
        var next = state
        if let receipt = response.trustReceipt { try verifyIdentity(receipt, requireLiveLease: !isResultLookup); next.identity = receipt }
        if let roster = response.roster {
            let p = roster.payload
            try context(p.authorityID, p.origin, p.audience)
            guard p.membershipRevision >= (state.roster?.payload.membershipRevision ?? 0) else { throw PairingClientError.rollback }
            next.roster = roster
        }
        var checkpoint: (UInt64, Data)?
        if let receipt = response.accountReceipt {
            next.accountReceipt = receipt; next.committedEvidence = response
            checkpoint = (receipt.payload.ledgerLastSequence, receipt.payload.ledgerHeadHash)
        }
        if let receipt = response.membershipReceipt {
            next.membershipReceipt = receipt; next.committedEvidence = response
            checkpoint = (receipt.payload.ledgerLastSequence, receipt.payload.ledgerHeadHash)
        }
        if let (sequence, hash) = checkpoint {
            guard sequence >= next.ledgerSequence,
                  sequence != next.ledgerSequence || next.ledgerHash == hash else { throw PairingClientError.rollback }
            next.ledgerSequence = sequence; next.ledgerHash = hash
        }
        if response.state.scopeKind != .identity { next.operation = response }
        if let inspection = response.inspection { next.inspection = inspection }
        let previousMembershipRevision = max(state.roster?.payload.membershipRevision ?? 0,
            state.membershipReceipt?.payload.membershipRevision ?? state.accountReceipt?.payload.membershipRevision ?? 0)
        let invalidatesSession = response.membershipReceipt.map { $0.payload.membershipRevision > previousMembershipRevision } ?? false
        try persist(next)
        if invalidatesSession { sessionToken = nil; sessionExpiresAt = 0 }
    }

    static func verifyRestored(_ restored: PairingClientState, configuration: PairingClientConfiguration) throws {
        guard restored.pending?.capability == nil, restored.lastRequest?.capability == nil else { throw ClientError.storedStateMismatch }
        if let preparation = restored.preparation {
            try preparation.challenge.verify(authorityPublicKey: configuration.serverPublicKey)
            let p = preparation.challenge.payload
            guard p.authorityID == configuration.authorityID, p.origin == configuration.serverURL,
                  p.audience == configuration.audience else { throw ClientError.storedStateMismatch }
        }
        if let identity = restored.identity {
            guard let prepared = restored.preparation, let evidence = restored.evidence else { throw ClientError.storedStateMismatch }
            try PairingV2.verifyTrustReceipt(identity, authorityPublicKey: configuration.serverPublicKey,
                expectedOrigin: configuration.serverURL, challenge: prepared.challenge.payload,
                evidence: .init(rootKind: .androidStrongBox, certificates: evidence.certificateChain), expectedRootPublicKey: evidence.publicKey)
        }
        if let operation = restored.operation { try verifyEvidence(operation, state: restored, configuration: configuration) }
        if let evidence = restored.committedEvidence {
            try verifyEvidence(evidence, state: restored, configuration: configuration)
            if let membership = restored.membershipReceipt {
                guard evidence.membershipReceipt == membership else { throw ClientError.storedStateMismatch }
            } else {
                guard let account = restored.accountReceipt, evidence.accountReceipt == account else { throw ClientError.storedStateMismatch }
            }
            let checkpoint = evidence.membershipReceipt.map { ($0.payload.ledgerLastSequence, $0.payload.ledgerHeadHash) }
                ?? evidence.accountReceipt.map { ($0.payload.ledgerLastSequence, $0.payload.ledgerHeadHash) }
            guard let checkpoint, checkpoint.0 == restored.ledgerSequence, checkpoint.1 == restored.ledgerHash else { throw ClientError.storedStateMismatch }
        } else if restored.accountReceipt != nil || restored.membershipReceipt != nil { throw ClientError.storedStateMismatch }
        if let inspection = restored.inspection {
            try inspection.verify(authorityPublicKey: configuration.serverPublicKey)
            let p = inspection.payload
            guard p.authorityID == configuration.authorityID, p.origin == configuration.serverURL,
                  p.audience == configuration.audience else { throw ClientError.storedStateMismatch }
        }
        for request in [restored.pending, restored.lastRequest].compactMap({ $0 }) {
            guard let identity = restored.identity else { throw ClientError.storedStateMismatch }
            try request.validate()
            try PairingV2.verifyRootProof(request.proof, payload: request.payload, owner: identity.payload.ownerDescriptor(),
                authorityPublicKey: configuration.serverPublicKey, expectedOrigin: configuration.serverURL,
                purpose: request.payload.purpose, scopeID: request.payload.scopeID)
        }
        if let receipt = restored.accountReceipt {
            try receipt.verify(authorityPublicKey: configuration.serverPublicKey)
            let p = receipt.payload.genesis
            guard p.authorityID == configuration.authorityID, p.origin == configuration.serverURL,
                  p.audience == configuration.audience, p.owners.contains(where: { $0.deviceID == restored.identity?.payload.deviceID }),
                  restored.membershipReceipt?.payload.proposal.context.existingAccount?.accountID ?? p.accountID == p.accountID else { throw ClientError.storedStateMismatch }
        }
        if let roster = restored.roster {
            try roster.verify(authorityPublicKey: configuration.serverPublicKey)
            guard roster.payload.authorityID == configuration.authorityID, roster.payload.origin == configuration.serverURL,
                  roster.payload.audience == configuration.audience else { throw ClientError.storedStateMismatch }
        }
    }
}
