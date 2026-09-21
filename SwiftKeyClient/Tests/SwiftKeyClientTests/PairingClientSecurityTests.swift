import Foundation
import Testing
import SwiftKeyCore
@testable import SwiftKeyClient

/// Software-only transport double. It never verifies attestation and is not a production trust adapter.
private final class PairingSecurityFixture: @unchecked Sendable {
    enum Failure: Error { case droppedBeforeSubmit, droppedAfterCommit, invalidRequest }
    enum MutationMode { case normal, dropBeforeSubmit, dropAfterCommit, reject(String) }
    let root = SoftwareSigningKey(), peer = SoftwareSigningKey(), authority = SoftwareSigningKey()
    let localID = "00000000-0000-0000-0000-000000000001", peerID = "00000000-0000-0000-0000-000000000002"
    let pairID = "00000000-0000-0000-0000-000000000010"
    let origin = "https://client-test.example"
    let lock = NSRecursiveLock()
    var now: UInt64 = 1000, sequence: UInt64 = 0
    var bytes: Data?, prepared: PairingV2.PreparationResponse?, identity: PairingV2.Signed<PairingV2.DeviceTrustReceipt>?
    var inspection: PairingV2.PairingInspection?, transcript: PairingV2.PairTranscript?
    var response: PairingV2.OperationResponse?
    var mutationMode: MutationMode = .normal
    var forgedProgress = false
    var dropAdmissionReply = false
    var dropPreparationReply = false
    var admissionRejection: String?
    var dropSessionReply = false, dropRenewalReply = false
    var identityResults: [String: PairingV2.OperationResponse] = [:]
    var accountRoster: PairingV2.Signed<PairingV2.AccountRoster>?
    var mutationSubmissions = 0, hardwareGenerations = 0
    var pairProofs: [PairingV2.RootProof] = []
    private let fakeChain = [Data("TEST ONLY: not a certificate or hardware evidence".utf8)]
    var config: PairingClientConfiguration { .init(serverURL: origin, serverPublicKey: authority.publicKey) }
    var platform: ClientPlatform {
        .init(enroll: { _ in
            self.synchronized { self.hardwareGenerations += 1 }
            return .init(publicKey: self.root.publicKey, certificateChain: self.fakeChain, platform: "androidStrongBox")
        }, signRootMessage: { try self.root.sign(message: $0) }, post: { url, body, _ in try self.post(url, body) },
        readState: { self.synchronized { self.bytes } }, writeState: { value in self.synchronized { self.bytes = value } },
        now: { self.synchronized { self.now } })
    }
    func synchronized<T>(_ operation: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try operation() }
    func client() throws -> PairingClient { try PairingClient(configuration: config, platform: platform) }
    func uuid() -> String { UUID().uuidString.lowercased() }
    func signed<T: PairingV2CanonicalRecord>(_ value: T) throws -> PairingV2.Signed<T> { try .sign(value, using: authority) }
    func projection(_ state: PairingV2.OperationState, transcript: PairingV2.PairTranscript? = nil,
                    pair: PairingV2.PairReceipt? = nil, genesis: PairingV2.AccountGenesis? = nil,
                    proofs: [PairingV2.RootProof] = []) throws -> PairingV2.OperationResponse {
        let header = PairingV2.SignedState(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
            scopeKind: state.scopeKind, scopeID: state.scopeID, revision: state.revision, payloadHash: try state.digest(), issuedAt: now, expiresAt: now + 60)
        return .init(state: state, signedState: try signed(header), inspection: try inspection.map(signed),
                     transcript: try transcript.map(signed), pairReceipt: try pair.map(signed), genesis: try genesis.map(signed), proofs: proofs)
    }
    func bindPeer() throws {
        try synchronized {
            let local = try #require(identity).payload.ownerDescriptor()
            let other = PairingV2.OwnerDescriptor(deviceID: peerID, rootKind: .androidStrongBox, rootKeyEpoch: 1,
                rootPublicKey: peer.publicKey, attestationReceiptHash: Data(repeating: 2, count: 32))
            let t = PairingV2.PairTranscript(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
                pairingID: pairID, revision: 2, context: .init(purpose: .createAccount), owners: [local, other], nonce: Data(repeating: 3, count: 32), issuedAt: 1000, expiresAt: 1120)
            transcript = t
            let state = PairingV2.OperationState(scopeKind: .pairing, scopeID: pairID, revision: 2, status: .peerBound,
                objectHash: try t.digest(), approvedSignerIDs: forgedProgress ? [localID] : [], phaseExpiresAt: 1120)
            response = try projection(state, transcript: t)
        }
    }
    func progressToGenesis() throws {
        try synchronized {
            let old = try #require(response), pair = try #require(old.pairReceipt).payload, t = pair.transcript
            let genesis = PairingV2.AccountGenesis(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
                proposalID: uuid(), pairingID: pairID, pairTranscriptHash: try t.digest(), accountID: uuid(), label: "Peer-proposed account",
                owners: t.owners, ownershipPolicyID: PairingV2.ownershipPolicy, initialMembershipRevision: 1,
                nonce: Data(repeating: 9, count: 32), issuedAt: now, expiresAt: pair.expiresAt)
            let state = PairingV2.OperationState(scopeKind: .genesisProposal, scopeID: genesis.proposalID, revision: 4,
                status: .proposed, objectHash: try genesis.digest(), approvedSignerIDs: [], phaseExpiresAt: genesis.expiresAt)
            let full = try projection(state, transcript: t, pair: pair, genesis: genesis, proofs: pairProofs)
            response = .init(state: full.state, signedState: full.signedState, transcript: full.transcript, pairReceipt: full.pairReceipt,
                             genesis: full.genesis, proofs: full.proofs) // No old inspection accompanies a proposal.
        }
    }
    func post(_ url: String, _ body: Data) throws -> Data {
        try synchronized {
            switch url.replacingOccurrences(of: origin, with: "") {
            case "/v2/identities/prepare":
                let request = try PairingV2JSON.decode(PairingV2.PreparationRequest.self, from: body)
                let c = PairingV2.PreEnrollmentChallenge(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
                    challengeID: uuid(), requestID: request.requestID, deviceID: localID, rootKind: .androidStrongBox,
                    trustPolicyID: "test-only", nonce: Data(repeating: 1, count: 32), issuedAt: now, expiresAt: now + 900)
                let result = PairingV2.PreparationResponse(challenge: try signed(c), preparationCapability: Data(repeating: 4, count: 32))
                prepared = result
                if dropPreparationReply { throw Failure.droppedAfterCommit }
                return try PairingV2JSON.encode(result)
            case "/v2/identities/attest":
                if let admissionRejection { return try JSONEncoder().encode(AuthorityErrorResponse(code: admissionRejection, error: "test rejection")) }
                if let identity { return try PairingV2JSON.encode(identity) }
                let request = try PairingV2JSON.decode(PairingV2.AttestationRequest.self, from: body)
                let r = PairingV2.DeviceTrustReceipt(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
                    deviceID: localID, rootKind: .androidStrongBox, rootKeyEpoch: 1, rootPublicKey: root.publicKey,
                    originalChallengeHash: try request.challenge.digest(), evidenceHash: try request.evidence.digest(), trustPolicyID: "test-only",
                    verifiedAt: now, leaseExpiresAt: now + 900)
                let result = try signed(r); identity = result
                if dropAdmissionReply { throw Failure.droppedAfterCommit }
                return try PairingV2JSON.encode(result)
            case "/v2/challenges":
                let request = try PairingV2JSON.decode(PairingV2.RootChallengeRequest.self, from: body)
                let c = PairingV2.RootChallenge(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
                    challengeID: uuid(), requestID: request.requestID, deviceID: localID, rootKeyEpoch: 1, purpose: request.purpose,
                    scopeID: request.scopeID, payloadHash: request.payloadHash, sequence: sequence + 1, issuedAt: now,
                    expiresAt: now + 120, nonce: Data(repeating: 5, count: 32))
                return try PairingV2JSON.encode(signed(c))
            case "/v2/operations":
                let request = try PairingV2JSON.decode(PairingV2.OperationRequest.self, from: body)
                if request.payload.purpose != .getResult {
                    mutationSubmissions += 1
                    switch mutationMode {
                    case .dropBeforeSubmit: throw Failure.droppedBeforeSubmit
                    case .reject(let code): return try JSONEncoder().encode(AuthorityErrorResponse(code: code, error: "test-only rejection"))
                    default: break
                    }
                }
                sequence = request.proof.challenge.sequence
                switch request.payload {
                case .createPairing(let p):
                    let i = PairingV2.PairingInspection(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
                        pairingID: pairID, revision: 1, initiator: p.initiator, context: p.context, issuedAt: now, expiresAt: now + 120)
                    inspection = i
                    let state = PairingV2.OperationState(scopeKind: .pairing, scopeID: pairID, revision: 1, status: .open,
                        objectHash: try i.digest(), approvedSignerIDs: [], phaseExpiresAt: i.expiresAt)
                    response = try projection(state)
                    if case .dropAfterCommit = mutationMode { throw Failure.droppedAfterCommit }
                    return try PairingV2JSON.encode(PairingV2.ExecutionResponse(operation: response!, secret: Data(repeating: 8, count: 32)))
                case .confirmPair(let t):
                    let peerChallenge = PairingV2.RootChallenge(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
                        challengeID: uuid(), requestID: uuid(), deviceID: peerID, rootKeyEpoch: 1, purpose: .confirmPair, scopeID: pairID,
                        payloadHash: try t.digest(), sequence: 1, issuedAt: now, expiresAt: t.expiresAt, nonce: Data(repeating: 9, count: 32))
                    let peerProof = PairingV2.RootProof(rootKind: .androidStrongBox, challenge: peerChallenge, proof: try peer.sign(message: peerChallenge.canonicalBytes()))
                    pairProofs = [request.proof, peerProof]
                    let pair = PairingV2.PairReceipt(transcript: t, aConsentDigest: try request.proof.digest(), bConsentDigest: try peerProof.digest(), confirmedAt: now, expiresAt: now + 300)
                    let state = PairingV2.OperationState(scopeKind: .pairing, scopeID: pairID, revision: 3, status: .paired,
                        objectHash: try t.digest(), approvedSignerIDs: [localID, peerID], phaseExpiresAt: pair.expiresAt, receiptHash: try pair.digest())
                    response = try projection(state, transcript: t, pair: pair, proofs: pairProofs)
                    return try PairingV2JSON.encode(PairingV2.ExecutionResponse(operation: response!))
                case .approveGenesis(let genesis):
                    let pair = try #require(response?.pairReceipt)
                    let peerChallenge = PairingV2.RootChallenge(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
                        challengeID: uuid(), requestID: uuid(), deviceID: peerID, rootKeyEpoch: 1, purpose: .approveGenesis,
                        scopeID: genesis.proposalID, payloadHash: try genesis.digest(), sequence: 2, issuedAt: now,
                        expiresAt: min(now + 120, genesis.expiresAt), nonce: Data(repeating: 7, count: 32))
                    let peerProof = PairingV2.RootProof(rootKind: .androidStrongBox, challenge: peerChallenge, proof: try peer.sign(message: peerChallenge.canonicalBytes()))
                    let receipt = PairingV2.AccountReceipt(genesis: genesis, pairReceiptHash: try pair.payload.digest(),
                        aApprovalDigest: try request.proof.digest(), bApprovalDigest: try peerProof.digest(), createdAt: now,
                        membershipRevision: 1, ledgerFirstSequence: 1, ledgerLastSequence: 4, ledgerHeadHash: Data(repeating: 6, count: 32))
                    let state = PairingV2.OperationState(scopeKind: .genesisProposal, scopeID: genesis.proposalID, revision: 5,
                        status: .committed, objectHash: try genesis.digest(), approvedSignerIDs: [localID, peerID],
                        phaseExpiresAt: genesis.expiresAt, receiptHash: try receipt.digest())
                    let shell = try projection(state)
                    accountRoster = try signed(.init(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
                        accountID: genesis.accountID, accountLabel: genesis.label, ownershipPolicyID: PairingV2.ownershipPolicy,
                        membershipRevision: 1, owners: genesis.owners, issuedAt: now, expiresAt: now + 60))
                    response = .init(state: state, signedState: shell.signedState, transcript: try signed(pair.payload.transcript),
                        pairReceipt: pair, genesis: try signed(genesis), accountReceipt: try signed(receipt), roster: accountRoster,
                        proofs: pairProofs + [request.proof, peerProof])
                    return try PairingV2JSON.encode(PairingV2.ExecutionResponse(operation: response!))
                case .authenticateOwner(let intent):
                    let trust = try #require(identity)
                    let state = PairingV2.OperationState(scopeKind: .identity, scopeID: localID, revision: sequence + 1, status: .committed,
                        objectHash: try trust.payload.digest(), approvedSignerIDs: [], phaseExpiresAt: trust.payload.leaseExpiresAt,
                        receiptHash: try trust.payload.digest())
                    let shell = try projection(state)
                    let result = PairingV2.OperationResponse(state: state, signedState: shell.signedState, trustReceipt: trust, roster: accountRoster)
                    identityResults[request.proof.challenge.requestID] = result
                    if dropSessionReply { throw Failure.droppedAfterCommit }
                    return try PairingV2JSON.encode(PairingV2.ExecutionResponse(operation: result,
                        sessionToken: String(repeating: "s", count: 44), sessionExpiresAt: intent.requestedExpiresAt))
                case .renewIdentityLease:
                    let old = try #require(identity).payload
                    let renewed = PairingV2.DeviceTrustReceipt(authorityID: old.authorityID, origin: old.origin, audience: old.audience,
                        deviceID: old.deviceID, rootKind: old.rootKind, rootKeyEpoch: old.rootKeyEpoch, rootPublicKey: old.rootPublicKey,
                        originalChallengeHash: old.originalChallengeHash, evidenceHash: old.evidenceHash, trustPolicyID: old.trustPolicyID,
                        verifiedAt: now, leaseExpiresAt: now + 900)
                    identity = try signed(renewed)
                    let state = PairingV2.OperationState(scopeKind: .identity, scopeID: localID, revision: sequence + 1, status: .committed,
                        objectHash: try renewed.digest(), approvedSignerIDs: [], phaseExpiresAt: renewed.leaseExpiresAt, receiptHash: try renewed.digest())
                    let shell = try projection(state)
                    let result = PairingV2.OperationResponse(state: state, signedState: shell.signedState, trustReceipt: identity)
                    identityResults[request.proof.challenge.requestID] = result
                    if dropRenewalReply { throw Failure.droppedAfterCommit }
                    return try PairingV2JSON.encode(PairingV2.ExecutionResponse(operation: result))
                case .getResult(let lookup):
                    if let identityResult = identityResults[lookup.operationID] {
                        let shell = try projection(identityResult.state)
                        let result = PairingV2.OperationResponse(state: identityResult.state, signedState: shell.signedState, trustReceipt: identityResult.trustReceipt)
                        return try PairingV2JSON.encode(PairingV2.ExecutionResponse(operation: result))
                    }
                    if let response { return try PairingV2JSON.encode(PairingV2.ExecutionResponse(operation: response)) }
                    let state = PairingV2.OperationState(scopeKind: .operation, scopeID: lookup.operationID, revision: 1, status: .rejected,
                        objectHash: try lookup.digest(), approvedSignerIDs: [], phaseExpiresAt: now)
                    return try PairingV2JSON.encode(PairingV2.ExecutionResponse(operation: projection(state)))
                default: throw Failure.invalidRequest
                }
            case "/v2/accounts/roster": return try PairingV2JSON.encode(#require(accountRoster))
            default: throw Failure.invalidRequest
            }
        }
    }
}

@Test func pairingClientSignedNegativeResolvesNeverSubmittedWithoutDuplicateMutation() async throws {
    let f = PairingSecurityFixture(), client = try f.client()
    try await client.prepareIdentity(requestID: f.uuid())
    f.mutationMode = .dropBeforeSubmit
    let id = f.uuid()
    await #expect(throws: (any Error).self) { try await client.createPairing(requestID: id) }
    #expect(await client.snapshot().pendingRequestID == id)
    try await client.recover(requestID: id)
    let result = await client.snapshot()
    #expect(result.pendingRequestID == nil && result.operation?.state.status == .rejected)
    #expect(f.mutationSubmissions == 1 && f.hardwareGenerations == 1)
    try await client.restart()
    #expect(await client.snapshot().operation == nil)
}

@Test func pairingClientReconcilesCommittedLostReplyAndObservesPeerProgressWithoutNewRequest() async throws {
    let f = PairingSecurityFixture(), client = try f.client()
    try await client.prepareIdentity(requestID: f.uuid()); f.mutationMode = .dropAfterCommit
    let request = f.uuid()
    await #expect(throws: (any Error).self) { try await client.createPairing(requestID: request) }
    try await client.recover(requestID: request)
    #expect(await client.snapshot().pendingRequestID == nil)
    #expect(await client.snapshot().invitationAvailable == false)
    f.mutationMode = .normal
    try f.bindPeer(); try await client.refresh()
    #expect(await client.snapshot().operation?.state.status == .peerBound)
    try await client.confirmPair(requestID: f.uuid())
    try f.progressToGenesis(); try await client.refresh()
    #expect(await client.snapshot().operation?.genesis?.payload.label == "Peer-proposed account")
    #expect(f.mutationSubmissions == 2)
    _ = try f.client() // Restored accepted pair proofs survive restart.
}

@Test func pairingClientNeverRendersFabricatedPartialConsent() async throws {
    let f = PairingSecurityFixture(), client = try f.client()
    try await client.prepareIdentity(requestID: f.uuid()); try await client.createPairing(requestID: f.uuid())
    f.forgedProgress = true; try f.bindPeer()
    await #expect(throws: PairingClientError.receiptMismatch) { try await client.refresh() }
    #expect(await client.snapshot().operation?.state.approvedSignerIDs == [])
}

@Test func pairingClientDefinitiveRejectionClearsPendingButServiceFailureDoesNot() async throws {
    for (code, remainsUnknown) in [("staleMembership", false), ("internalError", true), ("unavailable", true)] {
        let f = PairingSecurityFixture(), client = try f.client()
        try await client.prepareIdentity(requestID: f.uuid()); f.mutationMode = .reject(code)
        let id = f.uuid()
        await #expect(throws: ClientError.serverRejected(code)) { try await client.createPairing(requestID: id) }
        #expect((await client.snapshot().pendingRequestID != nil) == remainsUnknown)
    }
}

@Test func pairingClientRestoreRejectsForgedInspectionAndPendingProof() async throws {
    let f = PairingSecurityFixture(), client = try f.client()
    try await client.prepareIdentity(requestID: f.uuid()); try await client.createPairing(requestID: f.uuid())
    let original = try #require(f.bytes)
    var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
    var inspection = try #require(object["inspection"] as? [String: Any])
    inspection["signature"] = Data(repeating: 0, count: 70).base64EncodedString(); object["inspection"] = inspection
    f.bytes = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: (any Error).self) { try f.client() }
    f.bytes = original
    f.mutationMode = .dropBeforeSubmit
    try f.bindPeer(); try await client.refresh()
    await #expect(throws: (any Error).self) { try await client.confirmPair(requestID: f.uuid()) }
    let pendingBytes = try #require(f.bytes)
    object = try #require(JSONSerialization.jsonObject(with: pendingBytes) as? [String: Any])
    var pending = try #require(object["pending"] as? [String: Any]), proof = try #require(pending["proof"] as? [String: Any])
    proof["proof"] = Data(repeating: 0, count: 70).base64EncodedString(); pending["proof"] = proof; object["pending"] = pending
    f.bytes = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: (any Error).self) { try f.client() }
}

@Test func pairingConfigurationSeparatesFixedProtocolAudienceFromWorkloadAudience() throws {
    let key = SoftwareSigningKey().publicKey
    let data = try JSONSerialization.data(withJSONObject: ["serverURL": "https://authority.example", "serverPublicKey": key.base64EncodedString(), "audience": PairingV2.audience])
    let config = try JSONDecoder().decode(PairingClientConfiguration.self, from: data)
    #expect(config.workloadAudience == "swiftkey.local")
    #expect(throws: ClientError.invalidConfiguration) { try PairingClientConfiguration(serverURL: config.serverURL, serverPublicKey: key, audience: "custom-workload").validate() }
    try PairingClientConfiguration(serverURL: config.serverURL, serverPublicKey: key, workloadAudience: "custom-workload").validate()
}

@Test func pairingClientLateAdmissionRecoveryRetainsRootThenRenewsExpiredLease() async throws {
    let f = PairingSecurityFixture(); var client = try f.client()
    f.dropAdmissionReply = true
    let id = f.uuid()
    await #expect(throws: PairingSecurityFixture.Failure.droppedAfterCommit) { try await client.prepareIdentity(requestID: id) }
    #expect(await client.snapshot().pendingRequestID == id)
    f.now = 1901
    client = try f.client()
    try await client.recover(requestID: id)
    #expect(await client.snapshot().identity?.payload.leaseExpiresAt == 1900)
    #expect(await client.snapshot().pendingRequestID == nil)
    try await client.renewIdentity(requestID: f.uuid())
    #expect(await client.snapshot().identity?.payload.leaseExpiresAt == 2801)
    #expect(f.hardwareGenerations == 1)
}

@Test func pairingClientDefinitiveAdmissionRejectionPreservesRootWithoutUnknownOutcome() async throws {
    let f = PairingSecurityFixture(), client = try f.client()
    f.admissionRejection = "expired"
    await #expect(throws: ClientError.serverRejected("expired")) { try await client.prepareIdentity(requestID: f.uuid()) }
    let snapshot = await client.snapshot()
    #expect(snapshot.identity == nil && snapshot.pendingRequestID == nil && snapshot.admissionFailure == "expired")
    #expect(f.hardwareGenerations == 1)
    _ = try f.client()
}

@Test func pairingClientDuplicateConsentCannotOverwriteOriginalReceiptProof() async throws {
    let f = PairingSecurityFixture(), client = try f.client()
    try await client.prepareIdentity(requestID: f.uuid()); try await client.createPairing(requestID: f.uuid())
    try f.bindPeer(); try await client.refresh()
    let id = f.uuid(); try await client.confirmPair(requestID: id)
    await #expect(throws: PairingClientError.staleReview) { try await client.confirmPair(requestID: f.uuid()) }
    try await client.confirmPair(requestID: id)
    _ = try f.client()
    #expect(f.mutationSubmissions == 2)
}

@Test func pairingClientPreparationTimeoutBeforeRootGenerationAllowsFreshPreparation() async throws {
    let f = PairingSecurityFixture(), client = try f.client()
    f.dropPreparationReply = true
    await #expect(throws: (any Error).self) { try await client.prepareIdentity(requestID: f.uuid()) }
    let failed = await client.snapshot()
    #expect(failed.identity == nil && failed.pendingRequestID == nil && failed.admissionFailure == nil)
    #expect(f.hardwareGenerations == 0)
    f.dropPreparationReply = false
    try await client.prepareIdentity(requestID: f.uuid())
    #expect(await client.snapshot().identity != nil)
    #expect(f.hardwareGenerations == 1)
}

@Test func pairingClientLostSessionResultDoesNotNeedPrivateRosterOrReissueBearer() async throws {
    let f = PairingSecurityFixture(), client = try f.client()
    try await client.prepareIdentity(requestID: f.uuid()); try await client.createPairing(requestID: f.uuid())
    try f.bindPeer(); try await client.refresh(); try await client.confirmPair(requestID: f.uuid())
    try f.progressToGenesis(); try await client.refresh(); try await client.approveGenesis(requestID: f.uuid())
    f.dropSessionReply = true
    let id = f.uuid()
    await #expect(throws: (any Error).self) { try await client.signIn(requestID: id) }
    try await client.recover(requestID: id)
    let recovered = await client.snapshot()
    #expect(recovered.pendingRequestID == nil && recovered.signedIn == false && recovered.accountReceipt != nil)
    f.dropSessionReply = false
    try await client.signIn(requestID: f.uuid())
    #expect(await client.snapshot().signedIn)
}

@Test func pairingClientLateRenewalResultResolvesHistoricallyBeforeExplicitNewRenewal() async throws {
    let f = PairingSecurityFixture(); var client = try f.client()
    try await client.prepareIdentity(requestID: f.uuid())
    f.dropRenewalReply = true
    let id = f.uuid()
    await #expect(throws: (any Error).self) { try await client.renewIdentity(requestID: id) }
    f.now = 1901
    client = try f.client()
    try await client.recover(requestID: id)
    let recovered = await client.snapshot()
    #expect(recovered.pendingRequestID == nil && recovered.identity?.payload.leaseExpiresAt == 1900)
    f.dropRenewalReply = false
    try await client.renewIdentity(requestID: f.uuid())
    #expect(await client.snapshot().identity?.payload.leaseExpiresAt == 2801)
    #expect(f.hardwareGenerations == 1)
}
