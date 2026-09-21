import Foundation
import SwiftKeyCore

public struct ClientState: Codable, Sendable {
    public var version: Int = 1
    public let serverURL: String
    public let serverPublicKey: Data
    public var pendingBootstrap: BootstrapChallengeResponse?
    public var pendingEvidence: AndroidEnrollmentEvidence?
    public var pendingPairing: BootstrapChallengeResponse?
    public var pendingPairingEvidence: AndroidEnrollmentEvidence?
    public var pairingCandidate: PairingCandidate?
    public var enrollment: EnrollResponse?
    public var epochSnapshot: EpochManagerSnapshot?

    public init(configuration: ClientConfiguration) {
        serverURL = configuration.serverURL
        serverPublicKey = configuration.serverPublicKey
    }
}

public struct ClientRunResult: Codable, Sendable {
    public let accountID: String
    public let deviceID: String
    public let rootPublicKey: Data
    public let epoch: UInt64
    public let epochPublicKey: Data
    public let workloadAccepted: Bool
    public let replayRejected: Bool
}

/// Shared client state machine. Platform hooks supply only secure-hardware
/// operations, transport, a clock, and app-private atomic persistence.
public actor ProtocolClient {
    private let configuration: ClientConfiguration
    private let platform: ClientPlatform
    private let progress: @Sendable (String) -> Void
    private var state: ClientState
    private var manager: EpochManager?
    private var busy = false

    public init(configuration: ClientConfiguration, platform: ClientPlatform,
                progress: @escaping @Sendable (String) -> Void = { _ in }) throws {
        guard let url = URLComponents(string: configuration.serverURL),
              url.scheme == "https" || (url.scheme == "http" && url.host == "127.0.0.1"),
              url.host?.isEmpty == false, url.url != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", !configuration.audience.isEmpty else {
            throw ClientError.invalidConfiguration
        }
        try ProtocolCrypto.validatePublicKey(configuration.serverPublicKey)
        if let expected = configuration.expectedAccountID, expected.isEmpty || expected.utf8.count > 256 {
            throw ClientError.invalidConfiguration
        }
        self.configuration = configuration
        self.platform = platform
        self.progress = progress
        if let bytes = try platform.readState() {
            let loaded = try JSONDecoder().decode(ClientState.self, from: bytes)
            guard loaded.version == 1, loaded.serverURL == configuration.serverURL,
                  loaded.serverPublicKey == configuration.serverPublicKey else { throw ClientError.storedStateMismatch }
            if let expected = configuration.expectedAccountID {
                let accounts = [loaded.enrollment?.accountID, loaded.pendingBootstrap?.challenge.accountID,
                                loaded.pendingPairing?.challenge.accountID, loaded.pairingCandidate?.accountID,
                                loaded.epochSnapshot?.delegation.accountID].compactMap { $0 }
                guard accounts.allSatisfy({ $0 == expected }) else { throw ClientError.storedStateMismatch }
            }
            guard !(loaded.pendingBootstrap != nil && loaded.pendingPairing != nil),
                  loaded.pendingEvidence == nil || loaded.pendingBootstrap != nil,
                  loaded.pendingPairingEvidence == nil || loaded.pendingPairing != nil,
                  loaded.pairingCandidate == nil || loaded.pendingPairingEvidence != nil,
                  loaded.enrollment == nil || (loaded.pendingBootstrap == nil && loaded.pendingPairing == nil),
                  loaded.epochSnapshot == nil || loaded.enrollment != nil else { throw ClientError.storedStateMismatch }
            if let enrollment = loaded.enrollment {
                guard enrollment.serverPublicKey == configuration.serverPublicKey else { throw ClientError.serverIdentityMismatch }
                try ProtocolCrypto.validatePublicKey(enrollment.publicKey)
            }
            state = loaded
        } else {
            state = ClientState(configuration: configuration)
        }
    }

    /// Idempotent completed enrollment; unfinished enrollment reuses the exact
    /// original server challenge because the hardware certificate is immutable.
    public func enroll() throws -> EnrollResponse {
        guard !busy else { throw ClientError.operationInProgress }
        return try ensureEnrollment()
    }

    /// Existing members request an invitation to transfer to a new device.
    /// Approval later binds the exact candidate key with a root signature.
    public func requestPairing() throws -> BootstrapChallengeResponse {
        guard !busy else { throw ClientError.operationInProgress }
        let enrolled = try ensureEnrollment()
        let invitation: BootstrapChallengeResponse = try post("/v1/pairings/challenge",
            body: PairingChallengeRequest(accountID: enrolled.accountID))
        try validateInvitation(invitation, purpose: "swiftkey-pairing-v1")
        guard invitation.challenge.accountID == enrolled.accountID,
              invitation.challenge.deviceID != enrolled.deviceID else { throw ClientError.invalidServerResponse }
        return invitation
    }

    /// New-device phase. A candidate is not enrollment: an existing active
    /// member must approve it, then this device must call completePairing().
    /// The original invitation/evidence survive retries and are never replaced.
    public func preparePairing(_ invitation: BootstrapChallengeResponse) throws -> PairingCandidate {
        guard !busy else { throw ClientError.operationInProgress }
        guard state.enrollment == nil, state.pendingBootstrap == nil, state.pendingEvidence == nil else {
            throw ClientError.storedStateMismatch
        }
        if let pending = state.pendingPairing {
            guard pending.challenge == invitation.challenge,
                  pending.attestationChallenge == invitation.attestationChallenge else {
                throw ClientError.storedStateMismatch
            }
        }
        try validateInvitation(invitation, purpose: "swiftkey-pairing-v1")
        if state.pendingPairing == nil {
            var next = state
            next.pendingPairing = invitation
            try persist(next) // Before an immutable challenge-bound key can exist.
        }
        if state.pendingPairingEvidence == nil {
            let evidence = try platform.enroll(invitation.attestationChallenge)
            try validateEvidence(evidence)
            var next = state
            next.pendingPairingEvidence = evidence
            try persist(next)
        }
        guard let evidence = state.pendingPairingEvidence else { throw ClientError.storedStateMismatch }
        try validateEvidence(evidence)
        if let candidate = state.pairingCandidate {
            try validateCandidate(candidate, invitation: invitation, evidence: evidence)
            return candidate
        }
        let message = try invitation.challenge.canonicalBytes()
        let proof = try platform.signRootMessage(message)
        guard ProtocolCrypto.verify(signature: proof, message: message, publicKey: evidence.publicKey) else {
            throw ClientError.enrollmentIdentityMismatch
        }
        let candidate: PairingCandidate = try post("/v1/pairings/enroll", body:
            EnrollRequest(challenge: invitation.challenge, certificates: evidence.certificateChain, proof: proof))
        try validateCandidate(candidate, invitation: invitation, evidence: evidence)
        var next = state
        next.pairingCandidate = candidate
        try persist(next)
        progress("pairingCandidatePrepared=true")
        return candidate
    }

    public func approvePairing(_ candidate: PairingCandidate) throws -> MutationResponse {
        guard !busy else { throw ClientError.operationInProgress }
        let enrolled = try ensureEnrollment()
        try validateCandidateForApproval(candidate, enrolled: enrolled)
        let change = DeviceMembershipChange(accountID: enrolled.accountID, deviceID: candidate.deviceID,
            publicKey: candidate.publicKey, operation: .addDevice)
        let authorization = try authorize(operation: .addDevice, payload: change.canonicalBytes(), identity: enrolled)
        let response: MutationResponse = try post("/v1/pairings/approve", body:
            MembershipRequest(change: change, authorization: authorization))
        guard response.accepted else { throw ClientError.invalidServerResponse }
        return response
    }

    /// Confirms server-side approval using the new device's own root. Candidate
    /// expiry does not invalidate already approved membership; the fresh enroll
    /// challenge is issued only to active members by the authority.
    public func completePairing() throws -> EnrollResponse {
        guard !busy else { throw ClientError.operationInProgress }
        if let enrolled = state.enrollment { return enrolled }
        guard state.pendingBootstrap == nil, let invitation = state.pendingPairing,
              let evidence = state.pendingPairingEvidence, let candidate = state.pairingCandidate else {
            throw ClientError.storedStateMismatch
        }
        try validateEvidence(evidence)
        try validateCandidate(candidate, invitation: invitation, evidence: evidence)
        let identity = EnrollResponse(accountID: candidate.accountID, deviceID: candidate.deviceID,
            publicKey: candidate.publicKey, serverPublicKey: configuration.serverPublicKey)
        let change = DeviceMembershipChange(accountID: candidate.accountID, deviceID: candidate.deviceID,
            publicKey: candidate.publicKey, operation: .enroll)
        let authorization = try authorize(operation: .enroll, payload: change.canonicalBytes(), identity: identity)
        let response: EnrollResponse = try post("/v1/pairings/confirm", body:
            MembershipRequest(change: change, authorization: authorization))
        guard response.serverPublicKey == configuration.serverPublicKey else { throw ClientError.serverIdentityMismatch }
        guard response.accountID == candidate.accountID, response.deviceID == candidate.deviceID,
              response.publicKey == candidate.publicKey else { throw ClientError.enrollmentIdentityMismatch }
        var next = state
        next.enrollment = response
        next.pendingPairing = nil
        next.pendingPairingEvidence = nil
        next.pairingCandidate = nil
        try persist(next)
        progress("serverAttestedEnrollment=true")
        return response
    }

    public func revokeDevice(_ deviceID: String) throws -> MutationResponse {
        guard !busy else { throw ClientError.operationInProgress }
        let enrolled = try ensureEnrollment()
        guard deviceID != enrolled.deviceID else { throw ProtocolError.invalidField("deviceID") }
        let change = DeviceMembershipChange(accountID: enrolled.accountID, deviceID: deviceID,
            publicKey: nil, operation: .revokeDevice)
        let authorization = try authorize(operation: .revokeDevice, payload: change.canonicalBytes(), identity: enrolled)
        let response: MutationResponse = try post("/v1/devices/revoke", body:
            MembershipRequest(change: change, authorization: authorization))
        guard response.accepted else { throw ClientError.invalidServerResponse }
        return response
    }

    public func recover(lostDeviceID: String, replacementCandidate: PairingCandidate) throws -> MutationResponse {
        guard !busy else { throw ClientError.operationInProgress }
        let enrolled = try ensureEnrollment()
        try validateCandidateForApproval(replacementCandidate, enrolled: enrolled)
        guard lostDeviceID != enrolled.deviceID else { throw ProtocolError.invalidField("lostDeviceID") }
        let change = RecoveryChange(accountID: enrolled.accountID, lostDeviceID: lostDeviceID,
            replacementDeviceID: replacementCandidate.deviceID, publicKey: replacementCandidate.publicKey)
        let authorization = try authorize(operation: .recoverDevice, payload: change.canonicalBytes(), identity: enrolled)
        let response: MutationResponse = try post("/v1/recovery", body:
            RecoveryRequest(change: change, authorization: authorization))
        guard response.accepted else { throw ClientError.invalidServerResponse }
        return response
    }

    /// Issue or reuse this device's current credential without signing or
    /// submitting any workload. Private key state is persisted before return.
    public func ensureCurrentCredential() async throws -> EpochCredential {
        guard !busy else { throw ClientError.operationInProgress }
        busy = true
        defer { busy = false }
        return try await ensureCurrentCredentialInternal()
    }

    public func signWorkload(domain: String, payload: Data) async throws -> AuthenticatedWorkload {
        guard !busy else { throw ClientError.operationInProgress }
        busy = true
        defer { busy = false }
        return try await prepareWorkload(domain: domain, payload: payload)
    }

    public func submit(_ workload: AuthenticatedWorkload) throws -> VerifyWorkloadResponse {
        guard !busy else { throw ClientError.operationInProgress }
        return try submitInternal(workload)
    }

    /// Live development exercise. A replay is counted only when the authority
    /// returns the explicit workload-replay error, never for a transport failure.
    public func runDemonstration(payload: Data, verifyReplay: Bool = true) async throws -> ClientRunResult {
        guard !busy else { throw ClientError.operationInProgress }
        busy = true
        defer { busy = false }
        let signed = try await prepareWorkload(domain: "swiftkey.demo.echo.v1", payload: payload)
        let response = try submitInternal(signed)
        var replayRejected = false
        if verifyReplay {
            do {
                _ = try submitInternal(signed)
                throw ClientError.replayUnexpectedlyAccepted
            } catch ClientError.serverRejected(let code) where code == "replayedWorkload" {
                replayRejected = true
                progress("workloadReplayRejected=true")
            }
        }
        let enrolled = try ensureEnrollment()
        return ClientRunResult(accountID: enrolled.accountID, deviceID: enrolled.deviceID,
                               rootPublicKey: enrolled.publicKey,
                               epoch: signed.credential.delegation.epoch,
                               epochPublicKey: signed.credential.delegation.publicKey,
                               workloadAccepted: response.accepted, replayRejected: replayRejected)
    }

    private func ensureEnrollment() throws -> EnrollResponse {
        if let enrollment = state.enrollment { return enrollment }
        guard state.pendingPairing == nil else { throw ClientError.storedStateMismatch }
        guard !configuration.bootstrapToken.isEmpty else { throw ClientError.invalidConfiguration }
        if state.pendingBootstrap == nil {
            let response: BootstrapChallengeResponse = try post("/v1/bootstrap/challenge", body: EmptyBody(), bootstrap: true)
            try validateInvitation(response, purpose: "swiftkey-bootstrap-v1")
            var next = state
            next.pendingBootstrap = response
            try persist(next) // Persist before generating a challenge-bound hardware key.
        }
        guard let pending = state.pendingBootstrap else { throw ClientError.storedStateMismatch }
        if state.pendingEvidence == nil {
            try pending.challenge.validate(now: platform.now())
            let evidence = try platform.enroll(pending.attestationChallenge)
            var next = state
            next.pendingEvidence = evidence
            try persist(next)
        }
        guard let evidence = state.pendingEvidence else { throw ClientError.storedStateMismatch }
        try validateEvidence(evidence)
        let message = try pending.challenge.canonicalBytes()
        let proof = try platform.signRootMessage(message)
        guard ProtocolCrypto.verify(signature: proof, message: message, publicKey: evidence.publicKey) else {
            throw ClientError.enrollmentIdentityMismatch
        }
        let response: EnrollResponse = try post("/v1/bootstrap/enroll", body:
            EnrollRequest(challenge: pending.challenge, certificates: evidence.certificateChain, proof: proof), bootstrap: true)
        guard response.serverPublicKey == configuration.serverPublicKey else { throw ClientError.serverIdentityMismatch }
        guard response.accountID == pending.challenge.accountID, response.deviceID == pending.challenge.deviceID,
              response.publicKey == evidence.publicKey,
              configuration.expectedAccountID.map({ $0 == response.accountID }) ?? true else { throw ClientError.enrollmentIdentityMismatch }
        var next = state
        next.enrollment = response
        next.pendingBootstrap = nil
        next.pendingEvidence = nil
        try persist(next)
        progress("serverAttestedEnrollment=true")
        return response
    }

    private func epochManager() async throws -> EpochManager {
        if let manager { return manager }
        let enrolled = try ensureEnrollment()
        let created = EpochManager(accountID: enrolled.accountID, deviceID: enrolled.deviceID,
                                   rootPublicKey: enrolled.publicKey, serverPublicKey: configuration.serverPublicKey,
                                   audience: configuration.audience)
        if let snapshot = state.epochSnapshot { try await created.restore(snapshot, now: platform.now()) }
        manager = created
        return created
    }

    private func prepareWorkload(domain: String, payload: Data) async throws -> AuthenticatedWorkload {
        _ = try await ensureCurrentCredentialInternal()
        let manager = try await epochManager()
        return try await manager.signWorkload(domain: domain, audience: configuration.audience,
                                              payload: payload, nonce: ProtocolCrypto.randomNonce(), now: platform.now())
    }

    private func ensureCurrentCredentialInternal() async throws -> EpochCredential {
        let manager = try await epochManager()
        // If an epoch boundary is crossed while issuing, the next operation can
        // retry. Never silently accept a stale or future credential.
        if try await manager.currentCredential(now: platform.now()) == nil {
            let delegation = try await manager.prepareDelegation(now: platform.now())
            try await saveSnapshot(manager)
            let authorization = try authorize(operation: .issueEpoch, payload: delegation.canonicalBytes())
            let credential: EpochCredential = try post("/v1/epochs", body:
                IssueEpochRequest(delegation: delegation, authorization: authorization))
            try await manager.acceptCredential(credential, now: platform.now())
            try await saveSnapshot(manager)
            progress("epochCredentialVerified=true epoch=\(delegation.epoch)")
        } else {
            try await saveSnapshot(manager)
            progress("epochCredentialReused=true")
        }
        guard let credential = try await manager.currentCredential(now: platform.now()) else { throw ProtocolError.credentialRequired }
        return credential
    }

    private func authorize(operation: SwiftKeyCore.Operation, payload: Data) throws -> RootAuthorization {
        let enrolled = try ensureEnrollment()
        return try authorize(operation: operation, payload: payload, identity: enrolled)
    }

    private func authorize(operation: SwiftKeyCore.Operation, payload: Data,
                           identity enrolled: EnrollResponse) throws -> RootAuthorization {
        let request = ChallengeRequest(accountID: enrolled.accountID, deviceID: enrolled.deviceID,
                                       operation: operation, payloadHash: ProtocolCrypto.sha256(payload))
        let challenge: ChallengeEnvelope = try post("/v1/challenges", body: request)
        let now = platform.now()
        try challenge.validate(now: now)
        guard challenge.accountID == request.accountID, challenge.deviceID == request.deviceID,
              challenge.operation == request.operation, challenge.payloadHash == request.payloadHash,
              challenge.expiresAt - now <= 900 else { throw ClientError.invalidServerResponse }
        let signature = try platform.signRootMessage(challenge.canonicalBytes())
        let authorization = RootAuthorization(kind: .androidStrongBoxP256, challenge: challenge, signature: signature)
        try ProtocolValidation.verifyAuthorization(authorization, publicKey: enrolled.publicKey, now: platform.now())
        return authorization
    }

    private func validateInvitation(_ invitation: BootstrapChallengeResponse, purpose: String) throws {
        let now = platform.now()
        try invitation.challenge.validate(now: now)
        guard invitation.challenge.operation == .enroll,
              configuration.expectedAccountID.map({ $0 == invitation.challenge.accountID }) ?? true,
              invitation.challenge.expiresAt - now <= 900,
              invitation.challenge.payloadHash == ProtocolCrypto.sha256(Data(purpose.utf8)),
              invitation.attestationChallenge == ProtocolCrypto.sha256(try invitation.challenge.canonicalBytes()) else {
            throw ClientError.invalidServerResponse
        }
    }

    private func validateEvidence(_ evidence: AndroidEnrollmentEvidence) throws {
        guard evidence.platform == "androidStrongBox", !evidence.certificateChain.isEmpty else {
            throw ClientError.unsupportedHardware
        }
        try ProtocolCrypto.validatePublicKey(evidence.publicKey)
    }

    private func validateCandidate(_ candidate: PairingCandidate, invitation: BootstrapChallengeResponse,
                                   evidence: AndroidEnrollmentEvidence) throws {
        guard candidate.accountID == invitation.challenge.accountID,
              candidate.deviceID == invitation.challenge.deviceID,
              candidate.publicKey == evidence.publicKey,
              candidate.expiresAt == invitation.challenge.expiresAt else { throw ClientError.enrollmentIdentityMismatch }
    }

    private func validateCandidateForApproval(_ candidate: PairingCandidate, enrolled: EnrollResponse) throws {
        guard candidate.accountID == enrolled.accountID, candidate.deviceID != enrolled.deviceID,
              candidate.publicKey != enrolled.publicKey else { throw ClientError.enrollmentIdentityMismatch }
        guard platform.now() < candidate.expiresAt else { throw ProtocolError.challengeExpired }
        try ProtocolCrypto.validatePublicKey(candidate.publicKey)
    }

    private func submitInternal(_ signed: AuthenticatedWorkload) throws -> VerifyWorkloadResponse {
        let enrolled = try ensureEnrollment()
        try ProtocolValidation.verifyWorkload(signed, rootPublicKey: enrolled.publicKey,
            serverPublicKey: configuration.serverPublicKey, expectedDomain: signed.workload.message.domain,
            expectedAudience: configuration.audience, accountID: enrolled.accountID, deviceID: enrolled.deviceID,
            now: platform.now())
        let response: VerifyWorkloadResponse = try post("/v1/workloads", body:
            VerifyWorkloadRequest(credential: signed.credential, workload: signed.workload))
        guard response.accepted, response.payloadHash == ProtocolCrypto.sha256(signed.workload.message.payload) else {
            throw ClientError.invalidServerResponse
        }
        progress("serverWorkloadAccepted=true")
        return response
    }

    private func post<Request: Encodable, Response: Decodable>(_ path: String, body: Request,
                                                               bootstrap: Bool = false) throws -> Response {
        let base = configuration.serverURL.hasSuffix("/") ? String(configuration.serverURL.dropLast()) : configuration.serverURL
        let bytes = try platform.post(base + path, JSONEncoder().encode(body), bootstrap ? configuration.bootstrapToken : "")
        if let error = try? JSONDecoder().decode(AuthorityErrorResponse.self, from: bytes) { throw ClientError.serverRejected(error.code) }
        return try JSONDecoder().decode(Response.self, from: bytes)
    }

    private func persist(_ next: ClientState) throws {
        try platform.writeState(JSONEncoder().encode(next))
        state = next
    }
    private func saveSnapshot(_ manager: EpochManager) async throws {
        var next = state
        next.epochSnapshot = await manager.snapshot()
        try persist(next)
    }
    private struct EmptyBody: Encodable {}
}
