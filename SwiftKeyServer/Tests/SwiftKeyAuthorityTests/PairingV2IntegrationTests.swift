import Foundation
import Testing
import SwiftKeyCore
import SwiftKeyClient
import SwiftKeyApplication
@testable import SwiftKeyAuthority

private actor V2TestVerifier: EnrollmentVerifier {
    private var pauseKey: Data?
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var pauseWaiter: CheckedContinuation<Void, Never>?
    func pause(for key: Data) { pauseKey = key; entered = false }
    func waitUntilPaused() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }
    func resume() { pauseWaiter?.resume(); pauseWaiter = nil }
    func verify(certificates: [Data], challenge: Data, now: UInt64) async throws -> VerifiedAndroidIdentity {
        guard certificates.count == 1, let key = certificates.first else { throw AuthorityError.rejected("Test-only attestation fixture") }
        try ProtocolCrypto.validatePublicKey(key)
        return VerifiedAndroidIdentity(publicKey: key, certificateSHA256: ProtocolCrypto.sha256(key), packageName: "v2.test", packageVersion: 1,
            certificateChain: certificates, attestationChallenge: challenge)
    }
    func revalidate(_ identity: VerifiedAndroidIdentity, now: UInt64) async throws {
        if pauseKey == identity.publicKey {
            pauseKey = nil; entered = true; enteredWaiter?.resume(); enteredWaiter = nil
            await withCheckedContinuation { pauseWaiter = $0 }
        }
    }
}
private final class V2Clock: @unchecked Sendable {
    private let lock = NSLock(); private var value: UInt64 = 1_800_000_100
    func now() -> UInt64 { lock.withLock { value } }
    func advance(_ amount: UInt64) { lock.withLock { value += amount } }
}
private final class V2ResultBox<T: Sendable>: @unchecked Sendable {
    let lock = NSLock(); var result: Result<T, any Error>?
}
private func blockingV2<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
    let box = V2ResultBox<T>(), ready = DispatchSemaphore(value: 0)
    Task.detached { let result: Result<T, any Error>; do { result = .success(try await work()) } catch { result = .failure(error) }
        box.lock.withLock { box.result = result }; ready.signal()
    }
    ready.wait(); return try box.lock.withLock { try box.result!.get() }
}
private final class V2Transport: @unchecked Sendable {
    enum Failure: Error { case responseLost }
    let directory: URL
    let configuration: ServerConfiguration
    let clock = V2Clock()
    let verifier = V2TestVerifier()
    let key: Data
    private let lock = NSLock()
    private var authority: Authority?
    private var droppedPurpose: PairingV2.RootPurpose?
    private var unsentPurpose: PairingV2.RootPurpose?
    private var lostAttestation = false
    private var requests: [PairingV2.OperationRequest] = []
    private var bearers: [String] = []
    private var publicResponses: [String: PairingV2.OperationResponse] = [:]
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-v2-" + UUID().uuidString)
        configuration = ServerConfiguration(stateDirectory: directory.path, androidPackage: "v2.test",
            androidSigningCertificateSHA256: String(repeating: "00", count: 32), pairingV2: .init(origin: "https://authority.test"))
        let clock = self.clock
        let instance = try Authority(configuration: configuration, bootstrapToken: String(repeating: "v2-fixture-token", count: 3), verifier: verifier, clock: { clock.now() })
        authority = instance; key = try blockingV2 { await instance.publicKey }
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
    func server() -> Authority { lock.withLock { authority! } }
    func restart() throws {
        lock.withLock { authority = nil }
        let clock = self.clock
        let next = try Authority(configuration: configuration, bootstrapToken: String(repeating: "v2-fixture-token", count: 3), verifier: verifier, clock: { clock.now() })
        lock.withLock { authority = next }
    }
    func failBeforeSending(_ purpose: PairingV2.RootPurpose) { lock.withLock { unsentPurpose = purpose } }
    func loseAdmissionResponse() { lock.withLock { lostAttestation = true } }
    func lose(_ purpose: PairingV2.RootPurpose) { lock.withLock { droppedPurpose = purpose } }
    func operations() -> [PairingV2.OperationRequest] { lock.withLock { requests } }
    func sessionTokens() -> [String] { lock.withLock { bearers } }
    func response(for requestID: String) -> PairingV2.OperationResponse? { lock.withLock { publicResponses[requestID] } }
    func post(_ url: String, body: Data, bearer: String) throws -> Data {
        try blockingV2 { try await self.route(url, body: body, bearer: bearer) }
    }
    private func route(_ url: String, body: Data, bearer: String) async throws -> Data {
        let authority = server(), path = URL(string: url)!.path
        do {
            switch path {
            case "/v2/identities/prepare": return try JSONEncoder().encode(await authority.prepareIdentityV2(PairingV2JSON.decode(PairingV2.PreparationRequest.self, from: body)))
            case "/v2/identities/attest":
                let receipt = try await authority.attestIdentityV2(PairingV2JSON.decode(PairingV2.AttestationRequest.self, from: body))
                let drop = lock.withLock { if lostAttestation { lostAttestation = false; return true }; return false }
                if drop { throw Failure.responseLost }
                return try JSONEncoder().encode(receipt)
            case "/v2/challenges": return try JSONEncoder().encode(await authority.rootChallengeV2(PairingV2JSON.decode(PairingV2.RootChallengeRequest.self, from: body)))
            case "/v2/pairings/inspect": return try JSONEncoder().encode(await authority.inspectPairingV2(PairingV2JSON.decode(PairingV2.InspectionRequest.self, from: body)))
            case "/v2/operations":
                let request = try PairingV2JSON.decode(PairingV2.OperationRequest.self, from: body)
                lock.withLock { requests.append(request) }
                let unsent = lock.withLock { if unsentPurpose == request.payload.purpose { unsentPurpose = nil; return true }; return false }
                if unsent { throw Failure.responseLost }
                let response = try await authority.executeV2(request)
                lock.withLock { publicResponses[request.proof.challenge.requestID] = response.operation }
                if let token = response.sessionToken { lock.withLock { bearers.append(token) } }
                let drop = lock.withLock { if droppedPurpose == request.payload.purpose { droppedPurpose = nil; return true }; return false }
                if drop { throw Failure.responseLost }
                return try JSONEncoder().encode(response)
            case "/v2/accounts/roster":
                struct Request: Decodable { let accountID: String }
                let request = try JSONDecoder().decode(Request.self, from: body)
                return try JSONEncoder().encode(await authority.accountRosterV2(accountID: request.accountID, bearer: bearer))
            case "/v1/challenges": return try JSONEncoder().encode(await authority.challenge(JSONDecoder().decode(ChallengeRequest.self, from: body)))
            case "/v1/epochs": return try JSONEncoder().encode(await authority.issueEpoch(JSONDecoder().decode(IssueEpochRequest.self, from: body)))
            default: throw AuthorityError.protocolFailure(code: "notFound", message: "Unknown test route")
            }
        } catch let error as AuthorityError {
            return try JSONEncoder().encode(AuthorityErrorResponse(code: error.code, error: error.description))
        }
    }
}
private final class V2Phone: @unchecked Sendable {
    let key = SoftwareSigningKey()
    let transport: V2Transport
    private let lock = NSLock()
    private var bytes: Data?
    private var generations = 0
    init(_ transport: V2Transport) { self.transport = transport }
    func generationCount() -> Int { lock.withLock { generations } }
    func client() throws -> PairingClient {
        let platform = ClientPlatform(enroll: { challenge in
            self.lock.withLock { self.generations += 1 }
            return AndroidEnrollmentEvidence(publicKey: self.key.publicKey, certificateChain: [self.key.publicKey], platform: "androidStrongBox")
        }, signRootMessage: { try self.key.sign(message: $0) }, post: { try self.transport.post($0, body: $1, bearer: $2) },
            readState: { self.lock.withLock { self.bytes } }, writeState: { data in self.lock.withLock { self.bytes = data } },
            now: { self.transport.clock.now() })
        return try PairingClient(configuration: .init(serverURL: "https://authority.test", serverPublicKey: transport.key,
            audience: PairingV2.audience), platform: platform)
    }
}
private func v2ID() -> String { UUID().uuidString.lowercased() }
private func pairV2(_ a: PairingClient, _ b: PairingClient, create: Bool = true) async throws {
    if create { try await a.createPairing(requestID: v2ID()) }
    try await b.inspectInvitation(a.invitationLink())
    try await b.join(requestID: v2ID())
    try await a.refresh(); try await a.confirmPair(requestID: v2ID())
    try await b.refresh(); try await b.confirmPair(requestID: v2ID())
    try await a.refresh()
    #expect(await a.snapshot().operation?.state.status == .paired)
}
private func accountV2(_ transport: V2Transport) async throws -> (V2Phone, V2Phone, PairingClient, PairingClient) {
    let aPhone = V2Phone(transport), bPhone = V2Phone(transport)
    let a = try aPhone.client(), b = try bPhone.client()
    try await a.prepareIdentity(requestID: v2ID()); try await b.prepareIdentity(requestID: v2ID())
    try await pairV2(a, b)
    #expect(try await transport.server().listAccounts().accounts.isEmpty)
    try await a.proposeAccount(label: "Two phones", requestID: v2ID())
    try await b.refresh(); try await a.approveGenesis(requestID: v2ID())
    #expect(try await transport.server().listAccounts().accounts.isEmpty)
    try await b.refresh(); try await b.approveGenesis(requestID: v2ID()); try await a.refresh()
    return (aPhone, bPhone, a, b)
}

@Test func realV2ClientsRequireBothConsentsThenRestoreOwnerSessionAndIssueEpoch() async throws {
    let t = try V2Transport()
    let (aPhone, bPhone, a, b) = try await accountV2(t)
    let first = await a.snapshot(), second = await b.snapshot()
    #expect(first.accountReceipt == second.accountReceipt && first.operation?.proofs.count == 4)
    #expect(first.accountReceipt?.payload.genesis.owners.count == 2)
    #expect(aPhone.generationCount() == 1 && bPhone.generationCount() == 1)
    try t.restart()
    let restored = try aPhone.client()
    #expect(await restored.snapshot().accountReceipt == first.accountReceipt)
    try await restored.signIn(requestID: v2ID()); try await restored.refreshRoster()
    let credential = try await restored.ensureCurrentCredential()
    #expect(credential.delegation.accountID == first.accountReceipt?.payload.genesis.accountID)
    try await restored.renewIdentity(requestID: v2ID())
    let persisted = await t.server().state
    let id = try #require(first.identity?.payload.deviceID)
    #expect(persisted.devices[id]?.sequence == persisted.pairingV2?.identities[id]?.sequence)
    let legacy = ChallengeRequest(accountID: credential.delegation.accountID, deviceID: id, operation: .addDevice, payloadHash: Data(repeating: 0, count: 32))
    await #expect(throws: (any Error).self) { try await t.server().challenge(legacy) }
}

@Test func lostV2CreateAndJoinResponsesRecoverOriginalOperationWithoutRevealingSecretAgain() async throws {
    let t = try V2Transport()
    let firstPhone = V2Phone(t), secondPhone = V2Phone(t)
    var a = try firstPhone.client(); let b = try secondPhone.client()
    try await a.prepareIdentity(requestID: v2ID()); try await b.prepareIdentity(requestID: v2ID())
    let createID = v2ID(); t.lose(.createPairing)
    await #expect(throws: V2Transport.Failure.responseLost) { try await a.createPairing(requestID: createID) }
    a = try firstPhone.client(); try await a.recover(requestID: createID)
    #expect(await a.snapshot().operation?.state.status == .open)
    #expect(await a.snapshot().invitationAvailable == false)
    try await a.control(.rotateUnjoinedSecret, requestID: v2ID())
    let link = try await a.invitationLink()
    try await b.inspectInvitation(link)
    let joinID = v2ID(); t.lose(.joinPairing)
    await #expect(throws: V2Transport.Failure.responseLost) { try await b.join(requestID: joinID) }
    let restoredB = try secondPhone.client(); try await restoredB.recover(requestID: joinID)
    #expect(await restoredB.snapshot().operation?.state.status == .peerBound)
    let original = try #require(t.operations().first { $0.payload.purpose == .createPairing })
    let repeated = try await t.server().executeV2(original)
    #expect(repeated.secret == nil && repeated.sessionToken == nil)
    #expect(await t.server().state.pairingV2?.pairings.count == 1)
}

@Test func lostFinalV2ApprovalSurvivesAuthorityRestartWithoutDuplicateAccount() async throws {
    let t = try V2Transport()
    let phoneA = V2Phone(t), phoneB = V2Phone(t), a = try phoneA.client(), b = try phoneB.client()
    try await a.prepareIdentity(requestID: v2ID()); try await b.prepareIdentity(requestID: v2ID()); try await pairV2(a, b)
    try await a.proposeAccount(label: "Atomic account", requestID: v2ID()); try await b.refresh()
    try await a.approveGenesis(requestID: v2ID()); try await b.refresh()
    let requestID = v2ID(); t.lose(.approveGenesis)
    await #expect(throws: V2Transport.Failure.responseLost) { try await b.approveGenesis(requestID: requestID) }
    let head = try await t.server().status().ledgerHead.sequence
    try t.restart()
    let restored = try phoneB.client(); try await restored.recover(requestID: requestID)
    #expect(await restored.snapshot().operation?.state.status == .committed)
    #expect(try await t.server().listAccounts().accounts.count == 1)
    let original = try #require(t.operations().last { $0.proof.challenge.requestID == requestID })
    let beforeReplay = try await t.server().status().ledgerHead.sequence
    let replay = try await t.server().executeV2(original)
    let recoveredReceipt = await restored.snapshot().accountReceipt
    #expect(replay.operation.accountReceipt == recoveredReceipt)
    #expect(try await t.server().status().ledgerHead.sequence == beforeReplay)
    #expect(beforeReplay > head) // Only the fresh authenticated result lookup writes.
}

@Test func unsentMutationRecoveryIsSignedAndPermanentlyInvalidatesOriginalProof() async throws {
    let t = try V2Transport(), phone = V2Phone(t)
    var client = try phone.client()
    try await client.prepareIdentity(requestID: v2ID())
    let requestID = v2ID(); t.failBeforeSending(.createPairing)
    await #expect(throws: V2Transport.Failure.responseLost) { try await client.createPairing(requestID: requestID) }
    let unsent = try #require(t.operations().last)
    #expect(await t.server().state.pairingV2?.pairings.isEmpty == true)
    client = try phone.client(); try await client.recover(requestID: requestID)
    let recovered = await client.snapshot()
    #expect(recovered.pendingRequestID == nil)
    #expect(recovered.operation?.state.status == .rejected)
    #expect(recovered.operation?.state.scopeID == requestID)
    await #expect(throws: (any Error).self) { try await t.server().executeV2(unsent) }
    try t.restart()
    await #expect(throws: (any Error).self) { try await t.server().executeV2(unsent) }
    try await client.restart(); try await client.createPairing(requestID: v2ID())
    #expect(await t.server().state.pairingV2?.pairings.count == 1)
}

private func approveMembershipV2(_ first: PairingClient, _ second: PairingClient) async throws {
    try await first.proposeMembership(requestID: v2ID()); try await second.refresh()
    try await second.approveMembership(requestID: v2ID()); try await first.refresh()
    try await first.approveMembership(requestID: v2ID()); try await second.refresh()
}

@Test func realV2AddAndReplaceWithBothApprovalOrdersInvalidateRemovedRootAndAllowHistoricalReceipt() async throws {
    let t = try V2Transport()
    let (_, bPhone, a, b) = try await accountV2(t)
    try await a.signIn(requestID: v2ID()); try await b.signIn(requestID: v2ID())
    let oldBearer = try #require(t.sessionTokens().last)
    let initial = await b.snapshot(), account = try #require(initial.accountReceipt?.payload.genesis.accountID)
    let removedID = try #require(initial.identity?.payload.deviceID)
    let originalApproval = try #require(t.operations().last { $0.payload.purpose == .approveGenesis && $0.proof.challenge.deviceID == removedID })
    let cPhone = V2Phone(t), c = try cPhone.client()
    try await c.prepareIdentity(requestID: v2ID())
    try await a.beginOwnerChange(requestID: v2ID()); try await pairV2(a, c, create: false)
    try await approveMembershipV2(a, c)
    #expect(await c.snapshot().membershipReceipt?.payload.proposal.resultingOwners.count == 3)
    try await a.signIn(requestID: v2ID()); try await a.refreshRoster()
    let dPhone = V2Phone(t), d = try dPhone.client()
    try await d.prepareIdentity(requestID: v2ID())
    try await a.beginOwnerChange(replacing: removedID, requestID: v2ID())
    try await pairV2(a, d, create: false)
    try await approveMembershipV2(d, a)
    let final = try #require(await d.snapshot().membershipReceipt?.payload)
    #expect(final.membershipRevision == 3 && final.proposal.resultingOwners.count == 3)
    #expect(!final.proposal.resultingOwners.contains { $0.deviceID == removedID })
    #expect(await t.server().state.devices[removedID]?.revoked == true)
    await #expect(throws: (any Error).self) { try await t.server().accountRosterV2(accountID: account, bearer: oldBearer) }
    await #expect(throws: (any Error).self) { try await t.server().challenge(.init(accountID: account, deviceID: removedID, operation: .issueEpoch, payloadHash: Data(repeating: 0, count: 32))) }
    let replay = try await t.server().executeV2(originalApproval)
    #expect(replay.operation.accountReceipt == initial.accountReceipt && replay.sessionToken == nil)
    t.clock.advance(1_000) // Historical root possession remains sufficient after lease expiry.
    let restoredRevoked = try bPhone.client()
    try await restoredRevoked.refresh()
    #expect(await restoredRevoked.snapshot().accountReceipt == initial.accountReceipt)
    #expect(await restoredRevoked.snapshot().signedIn == false)
    let lookup = PairingV2.ResultLookupIntent(authorityID: ProtocolCrypto.sha256(t.key), origin: "https://authority.test", audience: PairingV2.audience,
        operationID: originalApproval.proof.challenge.requestID, originalActorDeviceID: removedID, originalPurpose: .approveGenesis)
    let payload = PairingV2.OperationPayload.getResult(lookup)
    let challenge = try await t.server().rootChallengeV2(.init(deviceID: removedID, rootKeyEpoch: 1, requestID: v2ID(), purpose: .getResult,
        scopeID: payload.scopeID, payloadHash: ProtocolCrypto.sha256(payload.canonicalBytes())))
    let proof = PairingV2.RootProof(rootKind: .androidStrongBox, challenge: challenge.payload, proof: try bPhone.key.sign(message: challenge.payload.canonicalBytes()))
    let history = try await t.server().executeV2(.init(payload: payload, proof: proof))
    #expect(history.operation.accountReceipt == initial.accountReceipt)
    #expect(history.operation.roster == nil && history.sessionToken == nil)
}

@Test func nativePhoneStoreDrivesFullAccountAndOwnerChangeCeremony() async throws {
    let t = try V2Transport(), phoneA = V2Phone(t), phoneB = V2Phone(t)
    let aClient = try phoneA.client(), bClient = try phoneB.client()
    let serviceA = NativePhoneProtocolService(client: aClient), serviceB = NativePhoneProtocolService(client: bClient)
    let a = PhoneProtocolStore(service: serviceA, clock: { t.clock.now() }), b = PhoneProtocolStore(service: serviceB, clock: { t.clock.now() })
    #expect(await a.send(.refresh).phase == .introduction)
    #expect(await a.send(.prepareIdentity).phase == .invitation)
    var av = await a.send(.createPairing)
    #expect(av.failure == nil)
    let invitation = try await serviceA.invitation(for: #require(av.binding))
    _ = await b.send(.refresh)
    var bv = await b.send(.inspectInvitation(.init(secretLink: invitation)))
    #expect(bv.phase == .inspectInvitation)
    bv = await b.send(.prepareIdentity)
    bv = await b.send(.join(try #require(bv.binding)))
    av = await a.send(.refresh)
    av = await a.send(.confirmPeers(try #require(av.binding)))
    bv = await b.send(.refresh)
    bv = await b.send(.confirmPeers(try #require(bv.binding)))
    av = await a.send(.refresh)
    #expect(av.phase == .paired && bv.phase == .paired)
    av = await a.send(.proposeAccount(try #require(av.binding), label: "Native two phones", policy: .survivor))
    bv = await b.send(.refresh)
    av = await a.send(.approveGenesis(try #require(av.binding)))
    bv = await b.send(.refresh)
    bv = await b.send(.approveGenesis(try #require(bv.binding)))
    av = await a.send(.refresh)
    #expect(av.phase == .committed && bv.phase == .committed)
    #expect(av.hasVerifiedReceipt && bv.hasVerifiedReceipt)
    av = await a.send(.signIn(accountID: try #require(av.accountID), membershipRevision: av.membershipRevision))
    #expect(av.phase == .owners && av.failure == nil)
    #expect(av.credentialStatus?.contains("verified") == true)
    av = await a.send(.beginOwnerChange(.add, accountID: try #require(av.accountID), membershipRevision: av.membershipRevision, targetOwnerID: nil))
    #expect(av.phase == .invitation && av.change?.kind == .add && av.failure == nil)
}

@Test func replacingGenesisDiscardsOldApprovalAndRotatingInvitationRetiresOldSecret() async throws {
    let t = try V2Transport(), phoneA = V2Phone(t), phoneB = V2Phone(t)
    let a = try phoneA.client(), b = try phoneB.client()
    try await a.prepareIdentity(requestID: v2ID()); try await b.prepareIdentity(requestID: v2ID())
    try await a.createPairing(requestID: v2ID())
    let oldLink = try await a.invitationLink()
    try await a.control(.rotateUnjoinedSecret, requestID: v2ID())
    await #expect(throws: (any Error).self) { try await b.inspectInvitation(oldLink) }
    try await pairV2(a, b, create: false)
    try await a.proposeAccount(label: "Discard this label", requestID: v2ID()); try await b.refresh()
    let oldID = try #require(await a.snapshot().operation?.genesis?.payload.proposalID)
    try await a.approveGenesis(requestID: v2ID()); try await b.refresh()
    try await b.replaceGenesis(label: "Approved label", requestID: v2ID()); try await a.refresh()
    let replacement = try #require(await a.snapshot().operation)
    #expect(replacement.genesis?.payload.label == "Approved label")
    #expect(replacement.genesis?.payload.proposalID != oldID && replacement.state.approvedSignerIDs.isEmpty)
    #expect(replacement.proofs.filter { $0.challenge.purpose == .approveGenesis }.isEmpty)
    try await a.approveGenesis(requestID: v2ID()); try await b.refresh()
    #expect(try await t.server().listAccounts().accounts.isEmpty)
    try await b.approveGenesis(requestID: v2ID())
    #expect(try await t.server().listAccounts().accounts.map(\.label) == ["Approved label"])
    #expect(await t.server().state.pairingV2?.genesis[oldID]?.status == .cancelled)
}

@Test func v2CutoverDurablyRetiresExportedLegacyEnrollmentWithoutDeletingHistory() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-cutover-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let token = String(repeating: "cutover-fixture", count: 3), clock = V2Clock()
    let legacyConfig = ServerConfiguration(stateDirectory: directory.path, androidPackage: "v2.test", androidSigningCertificateSHA256: String(repeating: "00", count: 32))
    var authority: Authority? = try Authority(configuration: legacyConfig, bootstrapToken: token, verifier: V2TestVerifier(), clock: { clock.now() })
    #expect(try await authority!.status().schemaVersion == 2)
    let invitation = try await authority!.createAccount(.init(label: "Preserved pending history"))
    let exported = try await authority!.bootstrapChallenge(token: invitation.enrollmentToken)
    let global = try await authority!.bootstrapChallenge(token: token)
    authority = nil
    let enabled = ServerConfiguration(stateDirectory: directory.path, androidPackage: "v2.test", androidSigningCertificateSHA256: String(repeating: "00", count: 32), pairingV2: .init(origin: "https://authority.test"))
    authority = try Authority(configuration: enabled, bootstrapToken: token, verifier: V2TestVerifier(), clock: { clock.now() })
    #expect(try await authority!.status().schemaVersion == 3)
    let key = SoftwareSigningKey()
    for challenge in [exported.challenge, global.challenge] {
        let request = EnrollRequest(challenge: challenge, certificates: [key.publicKey], proof: try key.sign(message: challenge.canonicalBytes()))
        await #expect(throws: (any Error).self) { try await authority!.bootstrapEnroll(request, token: challenge == exported.challenge ? invitation.enrollmentToken : token) }
    }
    #expect(try await authority!.listAccounts().accounts.contains { $0.accountID == invitation.account.accountID })
    #expect(try await authority!.account(id: invitation.account.accountID).canReissueInvitation == false)
    #expect(try await authority!.status().legacyProvisioningAllowed == false)
    authority = nil
    authority = try Authority(configuration: enabled, bootstrapToken: token, verifier: V2TestVerifier(), clock: { clock.now() })
    #expect(try await authority!.status().schemaVersion == 3)
    authority = nil
    authority = try Authority(configuration: legacyConfig, bootstrapToken: token, verifier: V2TestVerifier(), clock: { clock.now() })
    #expect(try await authority!.status().schemaVersion == 3)
    await #expect(throws: (any Error).self) { try await authority!.bootstrapChallenge(token: token) }
    await #expect(throws: (any Error).self) { try await authority!.bootstrapChallenge(token: invitation.enrollmentToken) }
    await #expect(throws: (any Error).self) { try await authority!.createAccount(.init(label: "Cannot reopen old route")) }
    await #expect(throws: (any Error).self) { try await authority!.reissueEnrollmentInvitation(accountID: invitation.account.accountID) }
}

@Test func concurrentV2MembershipCommitRechecksRevisionAfterTrustSuspends() async throws {
    let t = try V2Transport()
    let (_, _, a, b) = try await accountV2(t)
    try await a.signIn(requestID: v2ID()); try await b.signIn(requestID: v2ID())
    let cPhone = V2Phone(t), dPhone = V2Phone(t), c = try cPhone.client(), d = try dPhone.client()
    try await c.prepareIdentity(requestID: v2ID()); try await d.prepareIdentity(requestID: v2ID())
    try await a.beginOwnerChange(requestID: v2ID()); try await pairV2(a, c, create: false)
    try await a.proposeMembership(requestID: v2ID()); try await c.refresh(); try await c.approveMembership(requestID: v2ID())
    try await b.beginOwnerChange(requestID: v2ID()); try await pairV2(b, d, create: false)
    try await b.proposeMembership(requestID: v2ID()); try await d.refresh(); try await b.approveMembership(requestID: v2ID()); try await d.refresh()
    let requestID = v2ID(); t.failBeforeSending(.approveMembership)
    await #expect(throws: V2Transport.Failure.responseLost) { try await d.approveMembership(requestID: requestID) }
    let delayed = try #require(t.operations().last { $0.proof.challenge.requestID == requestID })
    await t.verifier.pause(for: dPhone.key.publicKey)
    let server = t.server()
    let suspended = Task { try await server.executeV2(delayed) }
    await t.verifier.waitUntilPaused()
    try await a.refresh(); try await a.approveMembership(requestID: v2ID())
    await t.verifier.resume()
    await #expect(throws: (any Error).self) { try await suspended.value }
    let snapshot = await t.server().state
    let account = try #require(snapshot.pairingV2?.accounts.values.first)
    #expect(account.revision == 2 && account.owners.count == 3)
    #expect(account.owners.contains { $0.rootPublicKey == cPhone.key.publicKey })
    #expect(!account.owners.contains { $0.rootPublicKey == dPhone.key.publicKey })
    #expect(snapshot.pairingV2?.operations[requestID] == nil)
}

@Test func v2RootProofTamperingAndExpiredPairingCannotMutateState() async throws {
    let t = try V2Transport(), phone = V2Phone(t), client = try phone.client()
    try await client.prepareIdentity(requestID: v2ID())
    let requestID = v2ID(); t.failBeforeSending(.createPairing)
    await #expect(throws: V2Transport.Failure.responseLost) { try await client.createPairing(requestID: requestID) }
    let original = try #require(t.operations().last)
    let wrongKey = SoftwareSigningKey()
    let badProof = PairingV2.RootProof(rootKind: .androidStrongBox, challenge: original.proof.challenge,
        proof: try wrongKey.sign(message: original.proof.challenge.canonicalBytes()))
    await #expect(throws: (any Error).self) { try await t.server().executeV2(.init(payload: original.payload, proof: badProof)) }
    #expect(await t.server().state.pairingV2?.operations[requestID] == nil)
    let created = try await t.server().executeV2(original)
    let inspection = try #require(created.operation.inspection?.payload), secret = try #require(created.secret)
    let before = try await t.server().status().ledgerHead
    let replay = try await t.server().executeV2(original)
    #expect(replay.secret == nil && replay.operation.inspection == created.operation.inspection)
    #expect(try await t.server().status().ledgerHead.sequence == before.sequence)
    #expect(try await t.server().status().ledgerHead.hash == before.hash)
    let json = String(decoding: try JSONEncoder().encode(await t.server().state), as: UTF8.self)
    #expect(!json.contains(secret.base64EncodedString()))
    t.clock.advance(121)
    await #expect(throws: (any Error).self) { try await t.server().inspectPairingV2(.init(pairingID: inspection.pairingID, capability: secret)) }
    #expect(try await t.server().listAccounts().accounts.isEmpty)
}

@Test func lostAdmissionResponseRetriesPersistedHardwareEvidenceWithoutGeneratingAnotherRoot() async throws {
    let t = try V2Transport(), phone = V2Phone(t)
    let client = try phone.client(), requestID = v2ID()
    t.loseAdmissionResponse()
    await #expect(throws: V2Transport.Failure.responseLost) { try await client.prepareIdentity(requestID: requestID) }
    #expect(phone.generationCount() == 1)
    let before = await t.server().state.pairingV2
    #expect(before?.identities.count == 1)
    try t.restart()
    let restored = try phone.client(); try await restored.prepareIdentity(requestID: requestID)
    #expect(phone.generationCount() == 1)
    #expect(await restored.snapshot().identity == before?.identities.values.first?.receipt)
    #expect(try await t.server().listAccounts().accounts.isEmpty)
    let head = try await t.server().status().ledgerHead.sequence
    await #expect(throws: (any Error).self) { try await t.server().prepareIdentityV2(.init(requestID: "invalid-id")) }
    #expect(try await t.server().status().ledgerHead.sequence == head)
}

@Test func lostOwnerSessionResponseRecoversPublicIdentityThenRequiresFreshSignIn() async throws {
    let t = try V2Transport()
    let (_, bPhone, _, b) = try await accountV2(t)
    let requestID = v2ID(); t.lose(.authenticateOwner)
    await #expect(throws: V2Transport.Failure.responseLost) { try await b.signIn(requestID: requestID) }
    let original = try #require(t.operations().last { $0.proof.challenge.requestID == requestID })
    let restored = try bPhone.client(); try await restored.recover(requestID: requestID)
    #expect(await restored.snapshot().pendingRequestID == nil)
    #expect(await restored.snapshot().signedIn == false)
    #expect(await restored.snapshot().accountReceipt != nil)
    let lookup = try #require(t.operations().last { $0.payload.purpose == .getResult })
    #expect(lookup.proof.challenge.scopeID == requestID)
    let recoveredPublic = try #require(t.response(for: lookup.proof.challenge.requestID))
    #expect(recoveredPublic.roster == nil && recoveredPublic.trustReceipt != nil)
    #expect(t.sessionTokens().count == 1)
    let replay = try await t.server().executeV2(original)
    #expect(replay.sessionToken == nil && replay.secret == nil)
    try await restored.signIn(requestID: v2ID()); try await restored.refreshRoster()
    #expect(await restored.snapshot().signedIn == true)
    #expect(await restored.snapshot().roster?.payload.owners.count == 2)
    #expect(t.sessionTokens().count == 2)
}

@Test func expiredLostRenewalResponseRecoversHistoricalTrustBeforeExplicitRenewal() async throws {
    let t = try V2Transport(), phone = V2Phone(t), client = try phone.client()
    try await client.prepareIdentity(requestID: v2ID())
    t.clock.advance(850)
    let requestID = v2ID(); t.lose(.renewIdentityLease)
    await #expect(throws: V2Transport.Failure.responseLost) { try await client.renewIdentity(requestID: requestID) }
    let accepted = try #require(await t.server().state.pairingV2?.identities.values.first?.receipt)
    t.clock.advance(901)
    try t.restart()
    let restored = try phone.client(); try await restored.recover(requestID: requestID)
    let recovered = await restored.snapshot()
    #expect(recovered.identity == accepted && recovered.pendingRequestID == nil)
    #expect(try #require(recovered.identity?.payload.leaseExpiresAt) < t.clock.now())
    #expect(recovered.signedIn == false)
    try await restored.renewIdentity(requestID: v2ID())
    #expect(try #require(await restored.snapshot().identity?.payload.leaseExpiresAt) > t.clock.now())
    #expect(phone.generationCount() == 1)
}

private extension Authority {
    // Test-only coherent ledger writes let startup validation be exercised
    // independently of the existing database/ledger tamper-detection tests.
    func corruptV2MarkerForTest(_ fault: String) throws {
        var next = state
        if fault == "registry" { next.pairingV2 = nil }
        if fault == "retirement" { next.legacyProvisioningRetired = nil }
        if fault == "legacyFormat" { next.formatVersion = 2 }
        try commit(next, events: [event("test.v2.marker_corrupted")])
    }
}

@Test(arguments: ["registry", "retirement", "legacyFormat"])
func v2StateFormatRefusesMissingCutoverMarkersOrLegacyDowngrade(_ fault: String) async throws {
    let t = try V2Transport()
    #expect(try await t.server().status().schemaVersion == 3)
    try await t.server().corruptV2MarkerForTest(fault)
    #expect(throws: (any Error).self) { try t.restart() }
}
