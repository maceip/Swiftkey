import Foundation
import SwiftKeyCore

struct DeviceRecord: Codable, Sendable {
    var accountID: String
    var deviceID: String
    var publicKey: Data
    var sequence: UInt64
    var revoked: Bool
    var identity: VerifiedAndroidIdentity
    var enrolledAt: UInt64? = nil
    var revokedAt: UInt64? = nil
}
struct CandidateRecord: Codable, Sendable {
    var candidate: PairingCandidate
    var identity: VerifiedAndroidIdentity
}
struct PersistedState: Codable, Sendable {
    var formatVersion = 2
    var signingKey: Data
    var bootstrapTokenHash: Data
    var policyFingerprint: Data?
    var bootstrap: ChallengeEnvelope?
    var bootstrapEnrollment: EnrollResponse?
    var bootstrapCertificateHash: Data?
    var devices: [String: DeviceRecord] = [:]
    var challenges: [String: ChallengeEnvelope] = [:]
    var pairingChallenges: [String: ChallengeEnvelope] = [:]
    var candidates: [String: CandidateRecord] = [:]
    var workloadNonces: [String: UInt64] = [:]
    var issuedEpochs: [String: UInt64] = [:]
    var issuedEpochCredentials: [String: EpochCredential] = [:]
    var lastEpochPublicKeyHashes: [String: Data] = [:]
    // Optional decoding preserves the original v1 JSON migration path. Every
    // committed v2 snapshot contains these registries, even when empty.
    var accounts: [String: AccountRecord]? = [:]
    var enrollmentInvitations: [String: EnrollmentInvitation]? = [:]
    var epochHistory: [String: HistoricalEpoch]? = [:]
    var pairingV2: PairingV2State?
    var legacyProvisioningRetired: Bool?
}

public actor Authority {
    var state: PersistedState
    let store: LedgerStore
    let configuration: ServerConfiguration
    let verifier: any EnrollmentVerifier
    let clock: @Sendable () -> UInt64
    let signingKey: SoftwareSigningKey
    private var persistenceFailed = false

    public init(configuration: ServerConfiguration, bootstrapToken: String, verifier: any EnrollmentVerifier, clock: @escaping @Sendable () -> UInt64 = { UInt64(Date().timeIntervalSince1970) }) throws {
        try require(bootstrapToken.utf8.count >= 32, "Bootstrap token must contain at least32 bytes")
        self.configuration = configuration; self.verifier = verifier; self.clock = clock
        self.store = try LedgerStore(directory: URL(fileURLWithPath: configuration.stateDirectory))
        let tokenHash = ProtocolCrypto.sha256(Data(bootstrapToken.utf8))
        if let data = try store.loadState() {
            var stored = try JSONDecoder().decode(PersistedState.self, from: data)
            try require([1, 2, 3].contains(stored.formatVersion), "Unsupported authority state version")
            if stored.formatVersion == 3 {
                try require(stored.legacyProvisioningRetired == true && stored.pairingV2 != nil,
                    "Incomplete pairing-first authority state")
            } else {
                try require(stored.legacyProvisioningRetired != true && stored.pairingV2 == nil,
                    "Pairing-first authority state requires format version 3")
            }
            try require(stored.bootstrapTokenHash == tokenHash, "Bootstrap token does not match existing state")
            let policy = try configuration.policyFingerprint()
            if stored.policyFingerprint == nil {
                try require(stored.devices.isEmpty && stored.bootstrap == nil && stored.bootstrapEnrollment == nil && stored.candidates.isEmpty, "Existing provisioned state needs an explicit policy migration")
                stored.policyFingerprint = policy
            }
            try require(stored.policyFingerprint == policy, "Security policy changed; explicit state migration is required")
            if stored.formatVersion == 1 {
                let now = clock()
                var accounts: [String: AccountRecord] = [:]
                var ids = Set(stored.devices.values.map(\.accountID))
                if let pending = stored.bootstrap { ids.insert(pending.accountID) }
                for id in ids {
                    accounts[id] = AccountRecord(accountID: id, label: "Imported account", createdAt: now, imported: true)
                }
                stored.accounts = accounts
                stored.enrollmentInvitations = [:]
                stored.epochHistory = Dictionary(uniqueKeysWithValues: stored.issuedEpochCredentials.values.map {
                    ($0.delegation.deviceID + ":" + String($0.delegation.epoch), HistoricalEpoch(credential: $0, issuedAt: nil))
                })
                stored.formatVersion = 2
                // Historical operations were never logged in v1. Record one
                // honest import checkpoint instead of inventing past events.
                try store.commit(state: JSONEncoder().encode(stored), events: [LedgerEventDraft(timestamp: now, kind: "authority.imported", accountID: nil, deviceID: nil, actorDeviceID: nil, details: ["source": "authority.json.v1", "accounts": String(accounts.count), "devices": String(stored.devices.count), "epochCredentials": String(stored.issuedEpochCredentials.count)])])
            }
            try require(stored.accounts != nil && stored.enrollmentInvitations != nil && stored.epochHistory != nil, "Incomplete authority registries")
            self.state = stored
            self.signingKey = try SoftwareSigningKey(rawRepresentation: stored.signingKey)
        } else {
            let key = SoftwareSigningKey()
            self.signingKey = key
            self.state = PersistedState(signingKey: key.rawRepresentation, bootstrapTokenHash: tokenHash)
            self.state.policyFingerprint = try configuration.policyFingerprint()
            try store.commit(state: JSONEncoder().encode(self.state), events: [LedgerEventDraft(timestamp: clock(), kind: "authority.created", accountID: nil, deviceID: nil, actorDeviceID: nil, details: ["schemaVersion": "2"])])
        }
        if let configured = configuration.pairingV2, configured.enabled {
            guard let origin = URLComponents(string: configured.origin),
                  origin.scheme == "https" || (origin.scheme == "http" && origin.host == "127.0.0.1"),
                  origin.host?.isEmpty == false, origin.user == nil, origin.password == nil,
                  origin.path.isEmpty, origin.query == nil, origin.fragment == nil else {
                throw AuthorityError.rejected("V2 requires a canonical HTTPS origin or explicit loopback development origin")
            }
            if let previous = state.pairingV2 {
                try require(previous.origin == configured.origin && previous.audience == PairingV2.audience,
                    "V2 authority context changed; explicit migration is required")
            }
            if state.legacyProvisioningRetired != true {
                // Explicit v2 enablement is a durable cutover. Keep historical
                // invitations/accounts as evidence; never make their secrets
                // usable again by later disabling the feature configuration.
                // Old authority binaries accept only versions 1 and 2. Advancing
                // the durable format makes a downgrade fail before it can ignore
                // v2 membership and reopen legacy governance routes.
                state.formatVersion = 3
                state.legacyProvisioningRetired = true
                state.pairingV2 = state.pairingV2 ?? PairingV2State(origin: configured.origin, audience: PairingV2.audience)
                try store.commit(state: JSONEncoder().encode(state), events: [LedgerEventDraft(timestamp: clock(),
                    kind: "v2.provisioning.enabled", details: ["legacyFirstEnrollment": "retired", "origin": configured.origin, "schemaVersion": "3"])])
            }
        }
        try store.writePublicKeyPin(signingKey.publicKey)
    }

    public var publicKey: Data { signingKey.publicKey }

    private func authenticateBootstrap(_ token: String) throws {
        try healthy()
        try require(ProtocolCrypto.sha256(Data(token.utf8)) == state.bootstrapTokenHash, "Invalid bootstrap authorization")
    }
    func commit(_ next: PersistedState, events: [LedgerEventDraft]) throws {
        try healthy()
        try require(!events.isEmpty, "Every authority state change requires a ledger event")
        do { try store.commit(state: JSONEncoder().encode(next), events: events) }
        catch { persistenceFailed = true; throw error }
        state = next
    }
    func event(_ kind: String, account: String? = nil, device: String? = nil, actor: String? = nil, details: [String: String] = [:]) -> LedgerEventDraft {
        LedgerEventDraft(timestamp: clock(), kind: kind, accountID: account, deviceID: device, actorDeviceID: actor, details: details)
    }
    func healthy() throws {
        try require(!persistenceFailed, "Persistence failed; restart authority before further operations", code: "unavailable")
    }

    // The HTTP layer protects these administrative operations with a separate
    // admin bearer. Mobile enrollment tokens cannot read this registry.
    public func createAccount(_ request: CreateAccountRequest) throws -> CreateAccountResponse {
        try require(state.legacyProvisioningRetired != true, "Pairing-first provisioning requires two hardware owners", code: "v2Required")
        try healthy()
        let label = request.label.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        try require(!label.isEmpty && label.utf8.count <= 120 && !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains), "Account label must contain 1 to 120 UTF-8 bytes without control characters", code: "invalidRequest")
        let now = clock()
        let account = AccountRecord(accountID: UUID().uuidString.lowercased(), label: label, createdAt: now, imported: false)
        let token = hex(randomBytes(32))
        let expiresAt = now + 900
        let invitation = EnrollmentInvitation(accountID: account.accountID, deviceID: UUID().uuidString.lowercased(), expiresAt: expiresAt)
        var next = state
        next.accounts?[account.accountID] = account
        next.enrollmentInvitations?[hex(ProtocolCrypto.sha256(Data(token.utf8)))] = invitation
        try commit(next, events: [event("account.created", account: account.accountID, details: ["label": label, "provisioning": "admin"]), event("enrollment.invited", account: account.accountID, device: invitation.deviceID, details: ["expiresAt": String(expiresAt)])])
        return CreateAccountResponse(account: summary(account), enrollmentToken: token, expiresAt: expiresAt)
    }

    /// Replaces only an unused administrative invitation. Existing membership,
    /// including an account whose devices are all revoked, cannot be reset here.
    public func reissueEnrollmentInvitation(accountID: String) throws -> CreateAccountResponse {
        try require(state.legacyProvisioningRetired != true, "Legacy first-enrollment invitations are retired", code: "v2Required")
        let account = try accountRecord(accountID)
        try require(!state.devices.values.contains { $0.accountID == accountID }, "An account with enrolled devices cannot receive a new enrollment invitation", code: "accountNotPending")
        // The initial bootstrap uses a separate bearer and challenge lifecycle.
        // Retiring it requires explicit provisioning recovery, not invitation
        // replacement that could leave two independent first-device authorities.
        try require(state.bootstrap?.accountID != accountID, "The initial bootstrap account does not use administrative invitations", code: "accountNotPending")
        let token = hex(randomBytes(32))
        let expiresAt = clock() + 900
        let invitation = EnrollmentInvitation(accountID: accountID, deviceID: UUID().uuidString.lowercased(), expiresAt: expiresAt)
        var next = state
        next.enrollmentInvitations = next.enrollmentInvitations?.filter {
            $0.value.accountID != accountID || $0.value.enrollment != nil
        }
        next.enrollmentInvitations?[hex(ProtocolCrypto.sha256(Data(token.utf8)))] = invitation
        try commit(next, events: [event("enrollment.invited", account: accountID, device: invitation.deviceID, details: ["reason": "reissued", "expiresAt": String(expiresAt)])])
        return CreateAccountResponse(account: summary(account), enrollmentToken: token, expiresAt: expiresAt)
    }

    private func summary(_ account: AccountRecord) -> AccountSummary {
        let devices = state.devices.values.filter { $0.accountID == account.accountID }
        let active = devices.filter { !$0.revoked }.count
        let status = active > 0 ? "active" : (devices.isEmpty ? "pending" : "inactive")
        return AccountSummary(accountID: account.accountID, label: account.label, createdAt: account.createdAt, status: status, deviceCount: devices.count, activeDeviceCount: active, imported: account.imported, canReissueInvitation: state.legacyProvisioningRetired != true && devices.isEmpty && state.bootstrap?.accountID != account.accountID)
    }

    private func accountRecord(_ id: String) throws -> AccountRecord {
        try healthy()
        guard let account = state.accounts?[id] else { throw AuthorityError.protocolFailure(code: "notFound", message: "Account does not exist") }
        return account
    }

    public func listAccounts() throws -> AccountListResponse {
        try healthy()
        let accounts = (state.accounts ?? [:]).values.sorted { ($0.createdAt, $0.accountID) < ($1.createdAt, $1.accountID) }.map(summary)
        return AccountListResponse(accounts: accounts)
    }

    public func account(id: String) throws -> AccountSummary { summary(try accountRecord(id)) }

    public func devices(accountID: String) throws -> DeviceListResponse {
        _ = try accountRecord(accountID)
        return DeviceListResponse(devices: state.devices.values.filter { $0.accountID == accountID }.sorted { $0.deviceID < $1.deviceID }.map {
            DeviceSummary(accountID: $0.accountID, deviceID: $0.deviceID, publicKey: $0.publicKey, sequence: $0.sequence, status: $0.revoked ? "revoked" : "active", enrolledAt: $0.enrolledAt, revokedAt: $0.revokedAt, lastEpoch: state.issuedEpochs[$0.deviceID])
        })
    }

    public func epochs(accountID: String) throws -> EpochListResponse {
        _ = try accountRecord(accountID)
        let now = clock()
        let history = (state.epochHistory ?? [:]).values.filter { $0.credential.delegation.accountID == accountID }.sorted {
            if $0.credential.delegation.epoch == $1.credential.delegation.epoch { return $0.credential.delegation.deviceID < $1.credential.delegation.deviceID }
            return $0.credential.delegation.epoch > $1.credential.delegation.epoch
        }
        return EpochListResponse(epochs: try history.map {
            let delegation = $0.credential.delegation
            let bounds = try Epoch.bounds(for: delegation.epoch)
            let status = state.devices[delegation.deviceID]?.revoked == true ? "revoked" : (now >= bounds.start && now < bounds.end ? "current" : "expired")
            return EpochSummary(accountID: accountID, deviceID: delegation.deviceID, epoch: delegation.epoch, publicKey: delegation.publicKey, previousPublicKeyHash: delegation.previousPublicKeyHash, validFrom: bounds.start, validUntil: bounds.end, issuedAt: $0.issuedAt, status: status, credential: $0.credential)
        })
    }

    private func signedHead() throws -> SignedLedgerHead {
        let head = try store.head()
        let unsigned = SignedLedgerHead(sequence: head.sequence, hash: head.hash, signature: Data())
        return SignedLedgerHead(sequence: head.sequence, hash: head.hash, signature: try signingKey.sign(message: unsigned.signingBytes()))
    }

    public func ledger(after: UInt64 = 0, limit: Int = 100, accountID: String? = nil) throws -> LedgerPage {
        try healthy()
        try require((1...200).contains(limit) && after <= UInt64(Int64.max), "Ledger cursor or page size is invalid", code: "invalidRequest")
        if let accountID { _ = try accountRecord(accountID) }
        let rows = try store.events(after: after, limit: limit + 1, accountID: accountID)
        let page = Array(rows.prefix(limit))
        return LedgerPage(events: page, nextAfter: page.last?.sequence ?? after, hasMore: rows.count > limit, head: try signedHead())
    }

    public func status() throws -> AuthorityStatus {
        try healthy()
        let now = clock(), epoch = now / Epoch.duration
        let bounds = try Epoch.bounds(for: epoch)
        let active = state.devices.values.filter { !$0.revoked }.count
        return AuthorityStatus(serverPublicKey: signingKey.publicKey, unixTime: now, epoch: epoch, epochStart: bounds.start, epochEnd: bounds.end, accountCount: state.accounts?.count ?? 0, activeDeviceCount: active, revokedDeviceCount: state.devices.count - active, credentialCount: state.epochHistory?.count ?? 0, ledgerHead: try signedHead(), storage: "sqlite", schemaVersion: state.formatVersion, legacyProvisioningAllowed: state.legacyProvisioningRetired != true)
    }
    /// One actor turn produces a consistent registry/ledger snapshot. The web
    /// and native application layer consume this same public model.
    public func workspace(_ query: WorkspaceQuery) throws -> WorkspaceOverview {
        let accounts = try listAccounts().accounts
        let selected = query.accountID ?? accounts.first?.accountID
        if let selected { _ = try accountRecord(selected) }
        return WorkspaceOverview(status: try status(), accounts: accounts,
            selectedAccountID: selected,
            devices: try selected.map { try devices(accountID: $0).devices } ?? [],
            epochs: try selected.map { try epochs(accountID: $0).epochs } ?? [],
            ledger: try ledger(after: query.after, limit: query.limit, accountID: selected),
            serverURL: "http://\(configuration.host):\(configuration.port)",
            audience: configuration.workloadAudience,
            workloadDomain: configuration.workloadDomain)
    }

    /// Read-only authorization at the server's current time. Unlike workload
    /// submission, checking a credential consumes no nonce and executes no work.
    public func verifyCredential(_ request: VerifyCredentialRequest) async throws -> CredentialVerificationResponse {
        let credential = request.credential
        let delegation = credential.delegation
        try await revalidateDevice(delegation.accountID, delegation.deviceID)
        let device = try activeDevice(delegation.accountID, delegation.deviceID)
        let now = clock()
        try require(delegation.audience == configuration.workloadAudience, "Delegation audience is not accepted", code: "invalidAudience")
        try require(state.issuedEpochCredentials[device.deviceID] == credential, "Credential is not the device's issued credential", code: "unknownCredential")
        try ProtocolValidation.verifyCredential(credential, rootPublicKey: device.publicKey,
            serverPublicKey: signingKey.publicKey, accountID: device.accountID,
            deviceID: device.deviceID, now: now)
        return CredentialVerificationResponse(accountID: device.accountID,
            deviceID: device.deviceID, epoch: delegation.epoch, checkedAt: now,
            validUntil: try Epoch.bounds(for: delegation.epoch).end,
            credentialHash: ProtocolCrypto.sha256(try credential.canonicalBytes()))
    }

    private func activeDevice(_ account: String, _ device: String) throws -> DeviceRecord {
        try healthy()
        guard let record = state.devices[device], record.accountID == account else { throw AuthorityError.protocolFailure(code: "unknownDevice", message: "Device is not an account member") }
        try require(!record.revoked, "Device was revoked", code: "revokedDevice")
        return record
    }
    private func activeAccount(_ account: String) throws {
        try healthy()
        try require(state.devices.values.contains { $0.accountID == account && !$0.revoked }, "Account has no active devices")
    }
    private func revalidateDevice(_ account: String, _ device: String) async throws {
        let record = try activeDevice(account, device)
        try await verifier.revalidate(record.identity, now: clock())
        _ = try activeDevice(account, device)
    }

    public func bootstrapChallenge(token: String) throws -> BootstrapChallengeResponse {
        try require(state.legacyProvisioningRetired != true, "Legacy first-enrollment provisioning is retired", code: "v2Required")
        if ProtocolCrypto.sha256(Data(token.utf8)) != state.bootstrapTokenHash {
            return try invitedBootstrapChallenge(token: token)
        }
        try authenticateBootstrap(token)
        try require(state.bootstrapEnrollment == nil, "Bootstrap token has already been consumed")
        if let pending = state.bootstrap {
            try require(clock() < pending.expiresAt, "Bootstrap challenge expired; explicit provisioning reset is required before generating a replacement key")
            return BootstrapChallengeResponse(challenge: pending, attestationChallenge: ProtocolCrypto.sha256(try pending.canonicalBytes()))
        }
        let challenge = ChallengeEnvelope(accountID: UUID().uuidString.lowercased(), deviceID: UUID().uuidString.lowercased(), operation: .enroll, sequence: 1, nonce: randomBytes(32), expiresAt: clock() + 900, payloadHash: ProtocolCrypto.sha256(Data("swiftkey-bootstrap-v1".utf8)))
        var next = state; next.bootstrap = challenge
        next.accounts?[challenge.accountID] = AccountRecord(accountID: challenge.accountID, label: "Initial account", createdAt: clock(), imported: false)
        try commit(next, events: [event("account.created", account: challenge.accountID, details: ["label": "Initial account", "provisioning": "initial-bootstrap"]), event("enrollment.challenged", account: challenge.accountID, device: challenge.deviceID)])
        return BootstrapChallengeResponse(challenge: challenge, attestationChallenge: ProtocolCrypto.sha256(try challenge.canonicalBytes()))
    }

    public func bootstrapEnroll(_ request: EnrollRequest, token: String) async throws -> EnrollResponse {
        if ProtocolCrypto.sha256(Data(token.utf8)) != state.bootstrapTokenHash {
            return try await invitedBootstrapEnroll(request, token: token)
        }
        try authenticateBootstrap(token)
        guard let expected = state.bootstrap else { throw AuthorityError.rejected("No bootstrap challenge was issued") }
        try require(try request.challenge.canonicalBytes() == expected.canonicalBytes(), "Bootstrap challenge does not match")
        if let completed = state.bootstrapEnrollment {
            try require(request.certificates.first.map(ProtocolCrypto.sha256) == state.bootstrapCertificateHash, "Bootstrap token cannot enroll a second key")
            try require(ProtocolCrypto.verify(signature: request.proof, message: try expected.canonicalBytes(), publicKey: completed.publicKey), "Enrollment possession proof failed")
            return completed
        }
        try require(state.legacyProvisioningRetired != true, "Legacy first-enrollment provisioning is retired", code: "v2Required")
        try require(clock() < expected.expiresAt, "Bootstrap challenge expired")
        let identity = try await verifier.verify(certificates: request.certificates, challenge: ProtocolCrypto.sha256(try expected.canonicalBytes()), now: clock())
        // The actor can re-enter while the certificate verifier awaits; recheck
        // one-time state immediately before the synchronous commit.
        try authenticateBootstrap(token)
        try require(state.bootstrapEnrollment == nil && clock() < expected.expiresAt, "Bootstrap challenge has expired or was consumed concurrently")
        try require(ProtocolCrypto.verify(signature: request.proof, message: try expected.canonicalBytes(), publicKey: identity.publicKey), "Enrollment possession proof failed")
        try require(!state.devices.values.contains { $0.publicKey == identity.publicKey }, "Hardware key is already associated with an account")
        let response = EnrollResponse(accountID: expected.accountID, deviceID: expected.deviceID, publicKey: identity.publicKey, serverPublicKey: signingKey.publicKey)
        var next = state
        next.devices[expected.deviceID] = DeviceRecord(accountID: expected.accountID, deviceID: expected.deviceID, publicKey: identity.publicKey, sequence: expected.sequence, revoked: false, identity: identity, enrolledAt: clock())
        next.bootstrapEnrollment = response; next.bootstrapCertificateHash = identity.certificateSHA256
        try commit(next, events: [event("device.enrolled", account: expected.accountID, device: expected.deviceID, actor: expected.deviceID, details: ["publicKey": hex(identity.publicKey), "certificateSHA256": hex(identity.certificateSHA256), "platform": "androidStrongBox"])])
        return response
    }

    private func invitation(token: String) throws -> (String, EnrollmentInvitation) {
        try healthy()
        try require((32...512).contains(token.utf8.count), "Invalid enrollment authorization", code: "unauthorized")
        let id = hex(ProtocolCrypto.sha256(Data(token.utf8)))
        guard let record = state.enrollmentInvitations?[id] else {
            throw AuthorityError.protocolFailure(code: "unauthorized", message: "Invalid enrollment authorization")
        }
        return (id, record)
    }

    private func invitedBootstrapChallenge(token: String) throws -> BootstrapChallengeResponse {
        let (id, record) = try invitation(token: token)
        try require(record.enrollment == nil, "Enrollment invitation has already been consumed")
        try require(clock() < record.expiresAt, "Enrollment invitation expired")
        if let challenge = record.challenge {
            return BootstrapChallengeResponse(challenge: challenge, attestationChallenge: ProtocolCrypto.sha256(try challenge.canonicalBytes()))
        }
        let challenge = ChallengeEnvelope(accountID: record.accountID, deviceID: record.deviceID, operation: .enroll, sequence: 1, nonce: randomBytes(32), expiresAt: record.expiresAt, payloadHash: ProtocolCrypto.sha256(Data("swiftkey-bootstrap-v1".utf8)))
        var next = state
        next.enrollmentInvitations?[id]?.challenge = challenge
        try commit(next, events: [event("enrollment.challenged", account: record.accountID, device: record.deviceID)])
        return BootstrapChallengeResponse(challenge: challenge, attestationChallenge: ProtocolCrypto.sha256(try challenge.canonicalBytes()))
    }

    private func invitedBootstrapEnroll(_ request: EnrollRequest, token: String) async throws -> EnrollResponse {
        let (id, record) = try invitation(token: token)
        guard let expected = record.challenge else { throw AuthorityError.rejected("No enrollment challenge was issued") }
        try require(try request.challenge.canonicalBytes() == expected.canonicalBytes(), "Enrollment challenge does not match this invitation")
        if let completed = record.enrollment {
            try require(request.certificates.first.map(ProtocolCrypto.sha256) == record.certificateHash, "Enrollment invitation cannot enroll a second key")
            try require(ProtocolCrypto.verify(signature: request.proof, message: try expected.canonicalBytes(), publicKey: completed.publicKey), "Enrollment possession proof failed")
            return completed
        }
        try require(state.legacyProvisioningRetired != true, "Legacy first-enrollment provisioning is retired", code: "v2Required")
        try require(clock() < record.expiresAt && clock() < expected.expiresAt, "Enrollment invitation expired")
        let identity = try await verifier.verify(certificates: request.certificates, challenge: ProtocolCrypto.sha256(try expected.canonicalBytes()), now: clock())
        let (_, latest) = try invitation(token: token)
        try require(latest.enrollment == nil && latest.challenge == expected && clock() < latest.expiresAt && clock() < expected.expiresAt, "Enrollment invitation expired or was consumed concurrently")
        try require(!state.devices.values.contains { $0.accountID == record.accountID }, "An enrollment invitation cannot add a device to an enrolled account", code: "accountNotPending")
        try require(ProtocolCrypto.verify(signature: request.proof, message: try expected.canonicalBytes(), publicKey: identity.publicKey), "Enrollment possession proof failed")
        try require(!state.devices.values.contains { $0.publicKey == identity.publicKey }, "Hardware key is already associated with an account")
        let response = EnrollResponse(accountID: record.accountID, deviceID: record.deviceID, publicKey: identity.publicKey, serverPublicKey: signingKey.publicKey)
        var next = state
        next.devices[record.deviceID] = DeviceRecord(accountID: record.accountID, deviceID: record.deviceID, publicKey: identity.publicKey, sequence: 1, revoked: false, identity: identity, enrolledAt: clock())
        next.enrollmentInvitations?[id]?.enrollment = response
        next.enrollmentInvitations?[id]?.certificateHash = identity.certificateSHA256
        try commit(next, events: [event("device.enrolled", account: record.accountID, device: record.deviceID, actor: record.deviceID, details: ["publicKey": hex(identity.publicKey), "certificateSHA256": hex(identity.certificateSHA256), "platform": "androidStrongBox"])])
        return response
    }

    public func challenge(_ request: ChallengeRequest) throws -> ChallengeEnvelope {
        try require(state.pairingV2?.accounts[request.accountID] == nil || request.operation == .issueEpoch,
            "V2 account governance requires v2 authorization", code: "v2Required")
        let device = try activeDevice(request.accountID, request.deviceID)
        try require(request.payloadHash.count == 32, "Invalid device operation challenge")
        try require(device.sequence < UInt64.max, "Device sequence exhausted")
        let now = clock()
        if let existing = state.challenges.values.first(where: { $0.accountID == request.accountID && $0.deviceID == request.deviceID && $0.operation == request.operation && $0.payloadHash == request.payloadHash && $0.sequence == device.sequence + 1 && now < $0.expiresAt }) { return existing }
        var next = state
        next.challenges = next.challenges.filter { now < $0.value.expiresAt }
        try require(next.challenges.values.filter { $0.deviceID == request.deviceID }.count < 16, "Too many pending device challenges")
        let challenge = ChallengeEnvelope(accountID: request.accountID, deviceID: request.deviceID, operation: request.operation, sequence: device.sequence + 1, nonce: randomBytes(32), expiresAt: now + 300, payloadHash: request.payloadHash)
        next.challenges[challenge.nonce.base64EncodedString()] = challenge
        try commit(next, events: [event("challenge.issued", account: request.accountID, device: request.deviceID, details: ["operation": String(describing: request.operation), "sequence": String(challenge.sequence), "payloadHash": hex(request.payloadHash)])]); return challenge
    }

    private func validateAuthorization(_ authorization: RootAuthorization, account: String, operation: SwiftKeyCore.Operation, payload: Data) throws -> DeviceRecord {
        try require(state.pairingV2?.accounts[account] == nil || operation == .issueEpoch,
            "V2 account governance requires v2 authorization", code: "v2Required")
        try require(authorization.kind == .androidStrongBoxP256, "Unsupported hardware authorization platform")
        let challenge = authorization.challenge
        let device = try activeDevice(account, challenge.deviceID)
        try require(challenge.accountID == account && challenge.operation == operation && challenge.payloadHash == ProtocolCrypto.sha256(payload), "Authorization does not bind this operation payload")
        try require(clock() < challenge.expiresAt && device.sequence < UInt64.max && challenge.sequence == device.sequence + 1, "Authorization is expired or replayed")
        guard let pending = state.challenges[challenge.nonce.base64EncodedString()] else { throw AuthorityError.rejected("Unknown or consumed challenge") }
        try require(try pending.canonicalBytes() == challenge.canonicalBytes(), "Challenge fields were altered")
        try require(ProtocolCrypto.verify(signature: authorization.signature, message: try challenge.canonicalBytes(), publicKey: device.publicKey), "Hardware signature verification failed")
        return device
    }
    private func consume(_ authorization: RootAuthorization, next: inout PersistedState) {
        next.devices[authorization.challenge.deviceID]?.sequence = authorization.challenge.sequence
        next.pairingV2?.identities[authorization.challenge.deviceID]?.sequence = authorization.challenge.sequence
        if let challenges = next.pairingV2?.challenges {
            next.pairingV2?.challenges = challenges.filter { $0.value.deviceID != authorization.challenge.deviceID }
        }
        next.challenges = next.challenges.filter { $0.value.deviceID != authorization.challenge.deviceID }
    }

    public func issueEpoch(_ request: IssueEpochRequest) async throws -> EpochCredential {
        let delegation = request.delegation
        try await revalidateDevice(delegation.accountID, request.authorization.challenge.deviceID)
        let device = try validateAuthorization(request.authorization, account: delegation.accountID, operation: .issueEpoch, payload: delegation.canonicalBytes())
        try require(device.deviceID == delegation.deviceID, "A device can only delegate its own epoch key")
        try require(delegation.epoch == clock() / 14_400, "Only the current server epoch may be delegated")
        try require(delegation.audience == configuration.workloadAudience, "Delegation audience is not accepted", code: "invalidAudience")
        if let previous = state.issuedEpochCredentials[device.deviceID], previous.delegation.epoch == delegation.epoch {
            try require(try previous.delegation.canonicalBytes() == delegation.canonicalBytes(), "This device already delegated a different key for the current epoch")
            var next = state; consume(request.authorization, next: &next)
            try commit(next, events: [event("epoch.reused", account: delegation.accountID, device: device.deviceID, actor: device.deviceID, details: ["epoch": String(delegation.epoch), "publicKey": hex(delegation.publicKey)])])
            return previous
        }
        try require(delegation.previousPublicKeyHash == state.lastEpochPublicKeyHashes[device.deviceID], "Delegation does not extend the last accepted epoch key")
        try ProtocolCrypto.validatePublicKey(delegation.publicKey)
        try require(state.issuedEpochs[device.deviceID] != delegation.epoch, "This device already has an epoch credential for the current epoch")
        let unsigned = EpochCredential(delegation: delegation, authorization: request.authorization, serverSignature: Data())
        let credential = EpochCredential(delegation: delegation, authorization: request.authorization, serverSignature: try signingKey.sign(message: unsigned.unsignedCanonicalBytes()))
        var next = state; consume(request.authorization, next: &next); next.issuedEpochs[device.deviceID] = delegation.epoch
        next.lastEpochPublicKeyHashes[device.deviceID] = ProtocolCrypto.sha256(delegation.publicKey)
        next.issuedEpochCredentials[device.deviceID] = credential
        next.epochHistory?[device.deviceID + ":" + String(delegation.epoch)] = HistoricalEpoch(credential: credential, issuedAt: clock())
        var details = ["epoch": String(delegation.epoch), "publicKey": hex(delegation.publicKey), "audience": delegation.audience]
        if let previous = delegation.previousPublicKeyHash { details["previousPublicKeyHash"] = hex(previous) }
        try commit(next, events: [event("epoch.issued", account: delegation.accountID, device: device.deviceID, actor: device.deviceID, details: details)]); return credential
    }

    public func verifyWorkload(_ request: VerifyWorkloadRequest) async throws -> VerifyWorkloadResponse {
        let credential = request.credential; let message = request.workload.message; let delegation = credential.delegation
        try await revalidateDevice(message.accountID, message.deviceID)
        let device = try activeDevice(message.accountID, message.deviceID)
        try require(message.accountID == delegation.accountID && message.deviceID == delegation.deviceID && message.epoch == delegation.epoch, "Workload does not match its credential")
        try require(message.epoch == clock() / 14_400, "Workload epoch is not current", code: "invalidEpoch")
        try require(message.audience == configuration.workloadAudience, "Workload audience is not accepted", code: "invalidAudience")
        try require(message.domain == configuration.workloadDomain, "Workload domain is not accepted", code: "invalidDomain")
        try require(ProtocolCrypto.verify(signature: credential.serverSignature, message: try credential.unsignedCanonicalBytes(), publicKey: signingKey.publicKey), "Authority credential signature failed")
        try require(ProtocolCrypto.verify(signature: request.workload.signature, message: try message.canonicalBytes(), publicKey: delegation.publicKey), "Workload signature failed", code: "invalidSignature")
        try ProtocolValidation.verifyWorkload(AuthenticatedWorkload(credential: credential, workload: request.workload), rootPublicKey: device.publicKey, serverPublicKey: signingKey.publicKey, expectedDomain: configuration.workloadDomain, expectedAudience: configuration.workloadAudience, accountID: device.accountID, deviceID: device.deviceID, now: clock())
        try require(message.nonce.count >= 16 && message.nonce.count <= 64 && message.payload.count <= 1_048_576, "Invalid workload bounds")
        let nonceID = message.accountID + ":" + message.deviceID + ":" + message.nonce.base64EncodedString()
        let now = clock()
        try require(state.workloadNonces[nonceID].map { $0 <= now } ?? true, "Workload nonce was already consumed", code: "replayedWorkload")
        var next = state; next.workloadNonces = next.workloadNonces.filter { $0.value > now }
        try require(next.workloadNonces.count < 100_000, "Workload replay ledger is full for this epoch")
        next.workloadNonces[nonceID] = try Epoch.bounds(for: message.epoch).end
        try commit(next, events: [event("workload.accepted", account: message.accountID, device: message.deviceID, actor: message.deviceID, details: ["epoch": String(message.epoch), "domain": message.domain, "audience": message.audience, "payloadHash": hex(ProtocolCrypto.sha256(message.payload)), "nonceHash": hex(ProtocolCrypto.sha256(message.nonce))])])
        return VerifyWorkloadResponse(accepted: true, payloadHash: ProtocolCrypto.sha256(message.payload))
    }

    public func pairingChallenge(_ request: PairingChallengeRequest) throws -> BootstrapChallengeResponse {
        try require(state.pairingV2?.accounts[request.accountID] == nil,
            "V2 account governance requires v2 authorization", code: "v2Required")
        try activeAccount(request.accountID)
        var next = state; let now = clock()
        next.pairingChallenges = next.pairingChallenges.filter { $0.value.expiresAt > now }
        next.candidates = next.candidates.filter { $0.value.candidate.expiresAt > now }
        try require(next.pairingChallenges.values.filter { $0.accountID == request.accountID }.count < 16, "Too many pending pairing challenges")
        let challenge = ChallengeEnvelope(accountID: request.accountID, deviceID: UUID().uuidString.lowercased(), operation: .enroll, sequence: 1, nonce: randomBytes(32), expiresAt: now + 900, payloadHash: ProtocolCrypto.sha256(Data("swiftkey-pairing-v1".utf8)))
        next.pairingChallenges[challenge.deviceID] = challenge
        try commit(next, events: [event("pairing.requested", account: challenge.accountID, device: challenge.deviceID, details: ["expiresAt": String(challenge.expiresAt)])])
        return BootstrapChallengeResponse(challenge: challenge, attestationChallenge: ProtocolCrypto.sha256(try challenge.canonicalBytes()))
    }
    public func pairingEnroll(_ request: EnrollRequest) async throws -> PairingCandidate {
        let challenge = request.challenge
        try require(state.pairingV2?.accounts[challenge.accountID] == nil,
            "V2 account governance requires v2 authorization", code: "v2Required")
        try activeAccount(challenge.accountID)
        guard let expected = state.pairingChallenges[challenge.deviceID] else { throw AuthorityError.rejected("No pairing challenge exists") }
        try require(try expected.canonicalBytes() == challenge.canonicalBytes(), "Pairing challenge mismatch")
        try require(clock() < expected.expiresAt, "Pairing challenge expired")
        let identity = try await verifier.verify(certificates: request.certificates, challenge: ProtocolCrypto.sha256(try expected.canonicalBytes()), now: clock())
        try activeAccount(challenge.accountID)
        try require(clock() < expected.expiresAt && state.pairingChallenges[challenge.deviceID] == expected, "Pairing challenge expired or consumed")
        try require(!state.devices.values.contains { $0.publicKey == identity.publicKey }, "Hardware key is already associated with an account")
        try require(ProtocolCrypto.verify(signature: request.proof, message: try expected.canonicalBytes(), publicKey: identity.publicKey), "Pairing possession proof failed")
        let candidate = PairingCandidate(accountID: challenge.accountID, deviceID: challenge.deviceID, publicKey: identity.publicKey, expiresAt: expected.expiresAt)
        // A challenge selects one immutable candidate. Check after the verifier
        // suspension too: another enrollment may have won while it was running.
        // An exact retry returns the durable receipt without adding audit noise.
        if let existing = state.candidates[challenge.deviceID] {
            try require(existing.candidate.accountID == candidate.accountID && existing.candidate.deviceID == candidate.deviceID
                && existing.candidate.publicKey == candidate.publicKey && existing.candidate.expiresAt == candidate.expiresAt
                && existing.identity.certificateSHA256 == identity.certificateSHA256,
                "Pairing challenge is already bound to another hardware identity")
            return existing.candidate
        }
        var next = state; next.candidates[challenge.deviceID] = CandidateRecord(candidate: candidate, identity: identity)
        try commit(next, events: [event("pairing.candidate_attested", account: candidate.accountID, device: candidate.deviceID, actor: candidate.deviceID, details: ["publicKey": hex(candidate.publicKey), "certificateSHA256": hex(identity.certificateSHA256)])]); return candidate
    }
    private func candidate(_ account: String, _ device: String, _ key: Data?) throws -> CandidateRecord {
        guard let record = state.candidates[device], record.candidate.accountID == account, record.candidate.publicKey == key, clock() < record.candidate.expiresAt else { throw AuthorityError.rejected("No matching verified pairing candidate") }
        try require(state.devices[device] == nil && !state.devices.values.contains { $0.publicKey == record.candidate.publicKey }, "Candidate hardware key is already enrolled")
        return record
    }
    private func add(_ record: CandidateRecord, next: inout PersistedState) {
        let candidate = record.candidate
        next.devices[candidate.deviceID] = DeviceRecord(accountID: candidate.accountID, deviceID: candidate.deviceID, publicKey: candidate.publicKey, sequence: 1, revoked: false, identity: record.identity, enrolledAt: clock())
        next.candidates.removeValue(forKey: candidate.deviceID); next.pairingChallenges.removeValue(forKey: candidate.deviceID)
    }
    public func approvePairing(_ request: MembershipRequest) async throws -> MutationResponse {
        let change = request.change
        try await revalidateDevice(change.accountID, request.authorization.challenge.deviceID)
        try require(change.operation == .addDevice, "Expected addDevice payload")
        _ = try validateAuthorization(request.authorization, account: change.accountID, operation: .addDevice, payload: change.canonicalBytes())
        let pending = try candidate(change.accountID, change.deviceID, change.publicKey)
        try await verifier.revalidate(pending.identity, now: clock())
        // Trust verification can suspend. Recheck the authorizer, its sequence,
        // and the candidate immediately before the atomic membership commit.
        _ = try validateAuthorization(request.authorization, account: change.accountID, operation: .addDevice, payload: change.canonicalBytes())
        let record = try candidate(change.accountID, change.deviceID, change.publicKey)
        var next = state; consume(request.authorization, next: &next); add(record, next: &next)
        try commit(next, events: [event("device.paired", account: change.accountID, device: change.deviceID, actor: request.authorization.challenge.deviceID, details: ["publicKey": hex(record.candidate.publicKey), "authorizationHash": hex(ProtocolCrypto.sha256(try request.authorization.challenge.canonicalBytes()))])]); return MutationResponse()
    }
    public func confirmPairing(_ request: MembershipRequest) async throws -> EnrollResponse {
        let change = request.change
        try await revalidateDevice(change.accountID, request.authorization.challenge.deviceID)
        try require(change.operation == .enroll, "Expected enrollment confirmation payload")
        let device = try validateAuthorization(request.authorization, account: change.accountID, operation: .enroll, payload: change.canonicalBytes())
        try require(device.deviceID == change.deviceID && device.publicKey == change.publicKey, "Confirmation must bind this enrolled hardware key")
        var next = state; consume(request.authorization, next: &next)
        try commit(next, events: [event("pairing.confirmed", account: device.accountID, device: device.deviceID, actor: device.deviceID)])
        return EnrollResponse(accountID: device.accountID, deviceID: device.deviceID, publicKey: device.publicKey, serverPublicKey: signingKey.publicKey)
    }
    public func revoke(_ request: MembershipRequest) async throws -> MutationResponse {
        let change = request.change
        try await revalidateDevice(change.accountID, request.authorization.challenge.deviceID)
        try require(change.operation == .revokeDevice && change.publicKey == nil, "Expected revokeDevice payload without a public key")
        let actor = try validateAuthorization(request.authorization, account: change.accountID, operation: .revokeDevice, payload: change.canonicalBytes())
        _ = try activeDevice(change.accountID, change.deviceID)
        try require(actor.deviceID != change.deviceID, "A recovery operation must be authorized by another active device")
        var next = state; consume(request.authorization, next: &next); next.devices[change.deviceID]?.revoked = true
        next.devices[change.deviceID]?.revokedAt = clock()
        next.challenges = next.challenges.filter { $0.value.deviceID != change.deviceID }
        try commit(next, events: [event("device.revoked", account: change.accountID, device: change.deviceID, actor: actor.deviceID, details: ["authorizationHash": hex(ProtocolCrypto.sha256(try request.authorization.challenge.canonicalBytes()))])]); return MutationResponse()
    }
    public func recover(_ request: RecoveryRequest) async throws -> MutationResponse {
        let change = request.change
        try await revalidateDevice(change.accountID, request.authorization.challenge.deviceID)
        var actor = try validateAuthorization(request.authorization, account: change.accountID, operation: .recoverDevice, payload: change.canonicalBytes())
        _ = try activeDevice(change.accountID, change.lostDeviceID)
        try require(actor.deviceID != change.lostDeviceID, "Recovery requires a surviving enrolled device")
        let pending = try candidate(change.accountID, change.replacementDeviceID, change.publicKey)
        try await verifier.revalidate(pending.identity, now: clock())
        actor = try validateAuthorization(request.authorization, account: change.accountID, operation: .recoverDevice, payload: change.canonicalBytes())
        _ = try activeDevice(change.accountID, change.lostDeviceID)
        let record = try candidate(change.accountID, change.replacementDeviceID, change.publicKey)
        var next = state; consume(request.authorization, next: &next); add(record, next: &next)
        next.devices[change.lostDeviceID]?.revoked = true
        next.devices[change.lostDeviceID]?.revokedAt = clock()
        next.challenges = next.challenges.filter { $0.value.deviceID != change.lostDeviceID }
        try commit(next, events: [event("device.revoked", account: change.accountID, device: change.lostDeviceID, actor: actor.deviceID, details: ["reason": "recovery", "replacementDeviceID": change.replacementDeviceID]), event("device.recovered", account: change.accountID, device: change.replacementDeviceID, actor: actor.deviceID, details: ["lostDeviceID": change.lostDeviceID, "publicKey": hex(change.publicKey), "authorizationHash": hex(ProtocolCrypto.sha256(try request.authorization.challenge.canonicalBytes()))])]); return MutationResponse()
    }
}
