import Foundation
import Crypto
import WebAuthn

struct PasskeyBootstrap: Encodable, Sendable {
    let csrf: String
    let relyingPartyID: String
    let origin: String
    let username: String?
}
struct PasskeyRegistrationStart: Encodable, Sendable {
    let ceremonyID: String
    let publicKey: RequiredRegistrationOptions
}
struct RequiredRegistrationOptions: Encodable, Sendable {
    let base: PublicKeyCredentialCreationOptions
    func encode(to encoder: any Encoder) throws {
        try base.encode(to: encoder)
        enum Keys: String, CodingKey { case authenticatorSelection }
        struct Selection: Encodable {
            let residentKey = "required"
            let requireResidentKey = true
            let userVerification = "required"
        }
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(Selection(), forKey: .authenticatorSelection)
    }
}
struct PasskeyAuthenticationStart: Encodable, Sendable {
    let ceremonyID: String
    let publicKey: PublicKeyCredentialRequestOptions
}
struct PasskeyResult: Encodable, Sendable {
    let registered: Bool
    let authenticated: Bool
    let username: String
    let credentialID: String
    let signCount: UInt32
    let backupEligible: Bool
    let backedUp: Bool
}

/// Test-only ephemeral state. No reference to an Authority, database, root key,
/// account or workload credential exists in this target.
actor PasskeyTestStore {
    struct Session: Sendable {
        let id: String
        let csrf: String
        let expires: TimeInterval
        var username: String?
    }
    private struct Ceremony {
        enum Kind { case registration, authentication }
        let kind: Kind
        let sessionID: String
        let challenge: [UInt8]
        let expires: TimeInterval
        let userHandle: [UInt8]
        let username: String
    }
    private struct StoredCredential {
        let id: String
        let userHandle: [UInt8]
        let username: String
        let publicKey: [UInt8]
        let backupEligible: Bool
        var signCount: UInt32
    }
    let configuration: PasskeyTestConfiguration
    private let manager: WebAuthnManager
    private let now: @Sendable () -> TimeInterval
    private var sessions: [String: Session] = [:]
    private var ceremonies: [String: Ceremony] = [:]
    private var credentials: [String: StoredCredential] = [:]
    private var budgetStart: TimeInterval = 0
    private var budgetCount = 0
    private var sessionRequests: [String: Int] = [:]
    private let algorithms = [PublicKeyCredentialParameters(alg: .algES256)]

    init(configuration: PasskeyTestConfiguration, now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.configuration = configuration; self.now = now
        manager = WebAuthnManager(configuration: .init(relyingPartyID: configuration.relyingPartyID,
            relyingPartyName: "SwiftKey Passkey Test", relyingPartyOrigin: configuration.origin))
    }
    private func randomBytes() -> [UInt8] { SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) } }
    private func token() -> String { PasskeyValidation.base64URL(randomBytes()) }
    private func prune() {
        let time = now()
        sessions = sessions.filter { $0.value.expires > time }
        ceremonies = ceremonies.filter { $0.value.expires > time && sessions[$0.value.sessionID] != nil }
    }
    func acceptRequest(sessionID: String?) throws {
        let time = now()
        if time < budgetStart || time - budgetStart >= 60 {
            budgetStart = time; budgetCount = 0; sessionRequests = [:]
        }
        guard budgetCount < 120 else { throw PasskeyTestError.rateLimited }
        budgetCount += 1
        if let sessionID {
            guard sessionRequests[sessionID, default: 0] < 40 else { throw PasskeyTestError.rateLimited }
            // Only known sessions can allocate a per-session budget entry.
            if sessions[sessionID] != nil { sessionRequests[sessionID, default: 0] += 1 }
        }
    }
    func bootstrap(existing: String?) throws -> (Session, PasskeyBootstrap) {
        prune()
        let session: Session
        if let existing, let value = sessions[existing] { session = value }
        else {
            guard sessions.count < 100 else { throw PasskeyTestError.capacity }
            session = Session(id: token(), csrf: token(), expires: now() + 1800)
            sessions[session.id] = session
        }
        return (session, PasskeyBootstrap(csrf: session.csrf, relyingPartyID: configuration.relyingPartyID,
            origin: configuration.origin, username: session.username))
    }
    func authorize(_ id: String?, csrf: String?) throws -> String {
        guard let id, let csrf, let session = sessions[id], session.expires > now(),
              csrf == session.csrf else { throw PasskeyTestError.session }
        return id
    }
    private func requireSession(_ id: String) throws {
        guard let session = sessions[id], session.expires > now() else { throw PasskeyTestError.session }
    }
    private func begin(_ ceremony: Ceremony) throws -> String {
        prune()
        guard ceremonies.count < 200 else { throw PasskeyTestError.capacity }
        // A tab/session owns at most one pending ceremony. New options explicitly
        // supersede its previous options rather than allowing a replay window.
        ceremonies = ceremonies.filter { $0.value.sessionID != ceremony.sessionID }
        let id = token(); ceremonies[id] = ceremony; return id
    }
    private func consume(_ id: String, sessionID: String, kind: Ceremony.Kind) throws -> Ceremony {
        try requireSession(sessionID)
        guard let ceremony = ceremonies[id], ceremony.sessionID == sessionID, ceremony.kind == kind else {
            throw PasskeyTestError.ceremony
        }
        ceremonies[id] = nil // consume even an invalid verification attempt
        guard ceremony.expires > now() else { throw PasskeyTestError.expired }
        return ceremony
    }
    func beginRegistration(sessionID: String, username: String) throws -> PasskeyRegistrationStart {
        try requireSession(sessionID)
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 80,
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              credentials.count < 200 else { throw PasskeyTestError.invalidRequest }
        let userHandle = randomBytes()
        let options = manager.beginRegistration(user: .init(id: userHandle, name: name, displayName: name),
            timeout: .seconds(120), publicKeyCredentialParameters: algorithms)
        let id = try begin(Ceremony(kind: .registration, sessionID: sessionID, challenge: options.challenge,
            expires: now() + 120, userHandle: userHandle, username: name))
        return .init(ceremonyID: id, publicKey: .init(base: options))
    }
    func finishRegistration(sessionID: String, ceremonyID: String, credential: RegistrationCredential) async throws -> PasskeyResult {
        let ceremony = try consume(ceremonyID, sessionID: sessionID, kind: .registration)
        let id = try PasskeyValidation.registration(credential)
        guard credentials[id] == nil else { throw PasskeyTestError.credential }
        let registered = try await manager.finishRegistration(challenge: ceremony.challenge,
            credentialCreationData: credential, requireUserVerification: true, supportedPublicKeyAlgorithms: algorithms,
            confirmCredentialIDNotRegisteredYet: { _ in true })
        // The actor can re-enter while the upstream async method verifies; enforce
        // uniqueness/capacity again at the actual insert, without another await.
        try requireSession(sessionID)
        guard credentials[id] == nil, credentials.count < 200 else { throw PasskeyTestError.credential }
        credentials[id] = StoredCredential(id: id, userHandle: ceremony.userHandle, username: ceremony.username,
            publicKey: registered.publicKey, backupEligible: registered.backupEligible, signCount: registered.signCount)
        return .init(registered: true, authenticated: false, username: ceremony.username, credentialID: id,
            signCount: registered.signCount, backupEligible: registered.backupEligible, backedUp: registered.isBackedUp)
    }
    func beginAuthentication(sessionID: String) throws -> PasskeyAuthenticationStart {
        try requireSession(sessionID)
        let options = manager.beginAuthentication(timeout: .seconds(120), userVerification: .required)
        let id = try begin(Ceremony(kind: .authentication, sessionID: sessionID, challenge: options.challenge,
            expires: now() + 120, userHandle: [], username: ""))
        return .init(ceremonyID: id, publicKey: options)
    }
    func finishAuthentication(sessionID: String, ceremonyID: String, credential: AuthenticationCredential) throws -> PasskeyResult {
        let ceremony = try consume(ceremonyID, sessionID: sessionID, kind: .authentication)
        let id = try PasskeyValidation.credentialID(credential.id, raw: credential.rawID)
        guard var stored = credentials[id], credential.response.userHandle == stored.userHandle else {
            throw PasskeyTestError.credential
        }
        try PasskeyValidation.clientData(credential.response.clientDataJSON)
        let flags = try PasskeyValidation.flags(credential.response.authenticatorData, registration: false)
        guard flags.eligible == stored.backupEligible else { throw PasskeyTestError.verification }
        let result = try manager.finishAuthentication(credential: credential, expectedChallenge: ceremony.challenge,
            credentialPublicKey: stored.publicKey, credentialCurrentSignCount: stored.signCount, requireUserVerification: true)
        stored.signCount = result.newSignCount
        credentials[id] = stored
        sessions[sessionID]?.username = stored.username
        return .init(registered: false, authenticated: true, username: stored.username, credentialID: id,
            signCount: result.newSignCount, backupEligible: stored.backupEligible, backedUp: flags.backedUp)
    }
    func signOut(sessionID: String) { sessions[sessionID]?.username = nil }
}
