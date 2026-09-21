import Foundation
import Testing
import SwiftKeyCore
@testable import SwiftKeyApplication

// Isolated service fixture. Production application code has no fallback service.
private actor ServiceFixture: WorkspaceService {
    let key = SoftwareSigningKey()
    let now: UInt64 = 1_800_000_100
    var accounts: [AccountSummary] = []
    var failRead = false
    var failReadAfterMutation = false
    var verificationError: WorkspaceFailure?
    var wrongReceipt = false
    var pauseRead = false
    var paused: CheckedContinuation<Void, Never>?
    var started: CheckedContinuation<Void, Never>?
    var enteredRead = false
    var queries: [WorkspaceQuery] = []
    var createCount = 0
    var reissueCount = 0
    var legacyProvisioningAllowed: Bool?
    var verified: [EpochCredential] = []
    func configure(failRead: Bool = false, failReadAfterMutation: Bool = false, wrongReceipt: Bool = false, pauseRead: Bool = false) {
        self.failRead = failRead; self.failReadAfterMutation = failReadAfterMutation
        self.wrongReceipt = wrongReceipt; self.pauseRead = pauseRead
    }
    func rejectVerification(_ code: String) { verificationError = WorkspaceFailure(code: code, message: "Credential is not currently authorized.") }
    func waitUntilReadStarts() async { if enteredRead { return }; await withCheckedContinuation { started = $0 } }
    func resumeRead() { paused?.resume(); paused = nil }
    func setAccounts(_ accounts: [AccountSummary]) { self.accounts = accounts }
    func setLegacyProvisioning(_ allowed: Bool?) { legacyProvisioningAllowed = allowed }
    func loadWorkspace(_ query: WorkspaceQuery) async throws -> WorkspaceOverview {
        queries.append(query)
        if pauseRead {
            pauseRead = false; enteredRead = true; started?.resume(); started = nil
            await withCheckedContinuation { paused = $0 }
        }
        if failRead { throw WorkspaceFailure(code: "unavailable", message: "Storage unavailable.") }
        let head = SignedLedgerHead(sequence: 3, hash: Data(repeating: 7, count: 32), signature: Data())
        let status = AuthorityStatus(serverPublicKey: key.publicKey, unixTime: now, epoch: now / Epoch.duration,
            epochStart: now / Epoch.duration * Epoch.duration, epochEnd: (now / Epoch.duration + 1) * Epoch.duration,
            accountCount: accounts.count, activeDeviceCount: 0, revokedDeviceCount: 0, credentialCount: 0,
            ledgerHead: head, storage: "fixture", schemaVersion: 2, legacyProvisioningAllowed: legacyProvisioningAllowed)
        let rows = (UInt64(1)...3).filter { $0 > query.after }.prefix(query.limit).map {
            LedgerEvent(sequence: $0, timestamp: now, kind: "fixture.event", accountID: nil, deviceID: nil, actorDeviceID: nil,
                details: [:], previousHash: Data(repeating: 0, count: 32), hash: Data(repeating: 7, count: 32))
        }
        return WorkspaceOverview(status: status, accounts: accounts, selectedAccountID: query.accountID ?? accounts.first?.accountID,
            devices: [], epochs: [], ledger: LedgerPage(events: rows, nextAfter: rows.last?.sequence ?? query.after,
                hasMore: (rows.last?.sequence ?? query.after) < 3, head: head),
            serverURL: "http://127.0.0.1:18088", audience: "swiftkey.local", workloadDomain: "workspace.test")
    }
    func createAccount(_ request: CreateAccountRequest) async throws -> CreateAccountResponse {
        createCount += 1
        let account = Self.account("account-\(createCount)", label: request.label)
        accounts.append(account)
        if failReadAfterMutation { failRead = true }
        return CreateAccountResponse(account: account, enrollmentToken: String(repeating: "private-invitation-", count: 3), expiresAt: now + 900)
    }
    func reissueEnrollmentInvitation(accountID: String) async throws -> CreateAccountResponse {
        reissueCount += 1
        guard let account = accounts.first(where: { $0.accountID == accountID }) else { throw WorkspaceFailure(code: "notFound", message: "Missing account.") }
        if failReadAfterMutation { failRead = true }
        return CreateAccountResponse(account: account, enrollmentToken: String(repeating: "new-private-token-", count: 3), expiresAt: now + 900)
    }
    func verifyCredential(_ request: VerifyCredentialRequest) async throws -> CredentialVerificationResponse {
        verified.append(request.credential)
        if let verificationError { throw verificationError }
        let d = request.credential.delegation
        return CredentialVerificationResponse(accountID: d.accountID, deviceID: d.deviceID, epoch: d.epoch,
            checkedAt: now, validUntil: try Epoch.bounds(for: d.epoch).end,
            credentialHash: wrongReceipt ? Data(repeating: 0, count: 32) : ProtocolCrypto.sha256(try request.credential.canonicalBytes()))
    }
    static func account(_ id: String, label: String = "Test account", eligible: Bool = true) -> AccountSummary {
        AccountSummary(accountID: id, label: label, createdAt: 1, status: "pending", deviceCount: 0,
            activeDeviceCount: 0, imported: false, canReissueInvitation: eligible)
    }
}

private func credential() throws -> EpochCredential {
    let now: UInt64 = 1_800_000_100
    let root = SoftwareSigningKey(), server = SoftwareSigningKey(), leaf = SoftwareSigningKey()
    let delegation = EpochDelegation(accountID: "account-1", deviceID: "device-1", epoch: now / Epoch.duration, publicKey: leaf.publicKey)
    let challenge = ChallengeEnvelope(accountID: delegation.accountID, deviceID: delegation.deviceID, operation: .issueEpoch,
        sequence: 2, nonce: Data(repeating: 3, count: 32), expiresAt: now + 300, payloadHash: ProtocolCrypto.sha256(try delegation.canonicalBytes()))
    let authorization = RootAuthorization(kind: .androidStrongBoxP256, challenge: challenge, signature: try root.sign(message: challenge.canonicalBytes()))
    let unsigned = EpochCredential(delegation: delegation, authorization: authorization, serverSignature: Data())
    return EpochCredential(delegation: delegation, authorization: authorization, serverSignature: try server.sign(message: unsigned.unsignedCanonicalBytes()))
}

@Test func realActionsUseServiceAndSecretsStayOutOfSnapshot() async throws {
    let service = ServiceFixture(), store = WorkspaceStore(service: ServiceFixture(), clock: { 1_800_000_100 })
    #expect(await store.snapshot().phase == .idle)
    let workspace = WorkspaceStore(service: service, clock: { 1_800_000_100 })
    _ = await workspace.send(.refresh)
    let created = await workspace.send(.createAccount("  My account  "))
    let invitation = try #require(created.invitation), bundle = try #require(created.enrollmentBundle)
    #expect(created.snapshot.phase == .ready)
    #expect(created.operationCommitted)
    #expect(created.snapshot.workspace?.selectedAccountID == invitation.account.accountID)
    #expect(bundle.configuration.bootstrapToken == invitation.enrollmentToken)
    #expect(bundle.configuration.expectedAccountID == invitation.account.accountID)
    #expect(bundle.configuration.serverPublicKey == created.snapshot.workspace?.status.serverPublicKey)
    let encoded = String(decoding: try JSONEncoder().encode(created.snapshot), as: UTF8.self)
    #expect(!encoded.contains(invitation.enrollmentToken) && !encoded.contains("bootstrapToken") && !encoded.contains("privateKey"))
    #expect(await service.createCount == 1)
    let refreshed = await workspace.send(.refresh)
    #expect(refreshed.invitation == nil && refreshed.enrollmentBundle == nil)
    #expect(!refreshed.operationCommitted)
    #expect(await workspace.send(.exportEnrollmentBundle).enrollmentBundle == bundle)
    _ = await workspace.send(.dismissInvitation)
    #expect(await workspace.invitation() == nil)
    #expect(await workspace.enrollmentBundle() == nil)
    #expect(await workspace.send(.exportEnrollmentBundle).snapshot.error?.code == "invitationUnavailable")
}

@Test func committedInvitationSurvivesFailedFollowupReadWithoutAutomaticRetry() async throws {
    let service = ServiceFixture(), store: WorkspaceStore
    store = WorkspaceStore(service: service, clock: { 1_800_000_100 })
    _ = await store.send(.refresh)
    await service.configure(failReadAfterMutation: true)
    let result = await store.send(.createAccount("Created once"))
    #expect(result.invitation != nil && result.enrollmentBundle != nil)
    #expect(result.operationCommitted)
    #expect(result.snapshot.phase == .stale && result.snapshot.error?.code == "refreshAfterMutationFailed")
    #expect(result.snapshot.error?.message.hasPrefix("Account created; refreshing failed.") == true)
    #expect(await service.createCount == 1)
    #expect(await store.invitation() == result.invitation)
    #expect(await store.send(.exportEnrollmentBundle).enrollmentBundle == result.enrollmentBundle)
    await service.configure()
    _ = await store.send(.refresh)
    #expect(await service.createCount == 1)
}

@Test func committedReissueSurvivesFailedFollowupReadWithoutAutomaticRetry() async throws {
    let service = ServiceFixture(), store: WorkspaceStore
    store = WorkspaceStore(service: service, clock: { 1_800_000_100 })
    await service.setAccounts([ServiceFixture.account("one")])
    _ = await store.send(.refresh)
    await service.configure(failReadAfterMutation: true)
    let result = await store.send(.reissueInvitation("one"))
    #expect(result.operationCommitted && result.enrollmentBundle != nil)
    #expect(result.snapshot.error?.message.hasPrefix("Invitation reissued; refreshing failed.") == true)
    #expect(await store.send(.exportEnrollmentBundle).enrollmentBundle == result.enrollmentBundle)
    await service.configure()
    _ = await store.send(.refresh)
    #expect(await service.reissueCount == 1)
}

/// A synchronized test clock allows expiry to advance without sleeps.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 1_800_000_100
    func now() -> UInt64 { lock.withLock { value } }
    func set(_ value: UInt64) { lock.withLock { self.value = value } }
}

@Test func invitationExportRejectsExpirationAtExactBoundary() async throws {
    let clock = TestClock(), service = ServiceFixture()
    let store = WorkspaceStore(service: service, clock: { clock.now() })
    _ = await store.send(.refresh)
    let created = await store.send(.createAccount("Expiry"))
    let bundle = try #require(created.enrollmentBundle)
    clock.set(bundle.expiresAt - 1)
    #expect(await store.send(.exportEnrollmentBundle).enrollmentBundle == bundle)
    clock.set(bundle.expiresAt)
    let expired = await store.send(.exportEnrollmentBundle)
    #expect(expired.enrollmentBundle == nil && expired.invitation == nil && !expired.operationCommitted)
    #expect(expired.snapshot.error?.code == "invitationExpired")
    #expect(await store.invitation() == nil)
    #expect(await store.enrollmentBundle() == nil)
    #expect(await service.createCount == 1)
    #expect(await service.reissueCount == 0)
}

@Test func serverEligibilityControlsReissueAndSelectionDismissesSecret() async throws {
    let service = ServiceFixture(), store: WorkspaceStore
    store = WorkspaceStore(service: service, clock: { 1_800_000_100 })
    await service.setAccounts([ServiceFixture.account("one", eligible: false), ServiceFixture.account("two")])
    _ = await store.send(.refresh)
    #expect(await store.send(.reissueInvitation("one")).snapshot.error?.code == "accountNotPending")
    #expect(await service.reissueCount == 0)
    let result = await store.send(.reissueInvitation("two"))
    #expect(result.snapshot.workspace?.selectedAccountID == "two" && result.invitation != nil)
    _ = await store.send(.selectAccount("one"))
    #expect(await store.invitation() == nil)
}

@Test func paginationDoesNotAdvanceCursorOnFailedRead() async throws {
    let service = ServiceFixture(), store: WorkspaceStore
    store = WorkspaceStore(service: service, pageSize: 1, clock: { 1_800_000_100 })
    #expect(await store.send(.refresh).snapshot.workspace?.ledger.events.first?.sequence == 1)
    await service.configure(failRead: true)
    let failed = await store.send(.nextLedgerPage)
    #expect(failed.snapshot.phase == .stale && !failed.snapshot.canGoBack)
    await service.configure()
    let next = await store.send(.nextLedgerPage)
    #expect(next.snapshot.workspace?.ledger.events.first?.sequence == 2 && next.snapshot.canGoBack)
    #expect(await store.send(.previousLedgerPage).snapshot.workspace?.ledger.events.first?.sequence == 1)
    #expect(await store.send(.firstLedgerPage).snapshot.canGoBack == false)
}

@Test func verificationRequiresServiceReceiptForExactCredentialAndClearsOnFailure() async throws {
    let service = ServiceFixture(), store: WorkspaceStore
    store = WorkspaceStore(service: service, clock: { 1_800_000_100 })
    _ = await store.send(.refresh)
    let input = try credential()
    let valid = await store.send(.verifyCredential(input))
    #expect(valid.snapshot.verification?.credentialHash == ProtocolCrypto.sha256(try input.canonicalBytes()))
    await service.configure(wrongReceipt: true)
    let wrong = await store.send(.verifyCredential(input))
    #expect(wrong.snapshot.verification == nil && wrong.snapshot.error?.code == "invalidResponse")
    await service.rejectVerification("revokedDevice")
    let revoked = await store.send(.verifyCredential(input))
    #expect(revoked.snapshot.verification == nil && revoked.snapshot.error?.code == "revokedDevice")
    #expect(await service.verified.count == 3)
}

@Test func sessionClearRejectsLateResponseAndBusyActionDoesNotStartMutation() async throws {
    let service = ServiceFixture(), store: WorkspaceStore
    store = WorkspaceStore(service: service, clock: { 1_800_000_100 })
    await service.configure(pauseRead: true)
    let waiting = Task { await store.send(.refresh) }
    await service.waitUntilReadStarts()
    #expect(await store.send(.createAccount("Must not run")).snapshot.error?.code == "operationInProgress")
    #expect(await service.createCount == 0)
    await store.clearSession()
    await service.resumeRead()
    _ = await waiting.value
    let cleared = await store.snapshot()
    #expect(cleared.phase == .idle && cleared.workspace == nil)
}

@Test func accountLabelValidationRunsBeforeMutation() async throws {
    let service = ServiceFixture(), store: WorkspaceStore
    store = WorkspaceStore(service: service, clock: { 1_800_000_100 })
    _ = await store.send(.refresh)
    for label in ["  ", "new\naccount", String(repeating: "😀", count: 31)] {
        #expect(await store.send(.createAccount(label)).snapshot.error?.code == "invalidRequest")
    }
    #expect(await service.createCount == 0)
}

@Test func cutoverCapabilityRejectsStaleLegacyCreateActionBeforeCallingService() async {
    let service = ServiceFixture()
    let currentStore = WorkspaceStore(service: service, clock: { 1_800_000_100 })
    _ = await currentStore.send(.refresh)
    let oldFormAction = WorkspaceAction.createAccount("Old form submitted after refresh")
    await service.setLegacyProvisioning(false)
    _ = await currentStore.send(.refresh)
    let refused = await currentStore.send(oldFormAction)
    #expect(refused.snapshot.error?.code == "legacyProvisioningDisabled")
    #expect(!refused.operationCommitted && refused.invitation == nil)
    #expect(await service.createCount == 0)
    await service.setLegacyProvisioning(true)
    _ = await currentStore.send(.refresh)
    #expect(await currentStore.send(.createAccount("Explicit legacy authority")).operationCommitted)
    #expect(await service.createCount == 1)
}
