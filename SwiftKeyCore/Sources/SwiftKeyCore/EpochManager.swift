import Foundation

/// Contains a SOFTWARE epoch private key. Store in app-private atomic storage;
/// never send this Codable type to the authority or log it. Root keys are not
/// exportable and do not appear here. Pins bind restoration to the same trust.
public struct EpochManagerSnapshot: Codable, Sendable, Equatable {
    public let delegation: EpochDelegation
    public let privateKey: Data
    public let credential: EpochCredential?
    public let rootPublicKeyHash: Data
    public let serverPublicKeyHash: Data
    public let previousPublicKeyHash: Data?

    public init(delegation: EpochDelegation, privateKey: Data, credential: EpochCredential?,
                rootPublicKeyHash: Data, serverPublicKeyHash: Data, previousPublicKeyHash: Data?) {
        self.delegation = delegation; self.privateKey = privateKey; self.credential = credential
        self.rootPublicKeyHash = rootPublicKeyHash; self.serverPublicKeyHash = serverPublicKeyHash
        self.previousPublicKeyHash = previousPublicKeyHash
    }
}

/// In-memory software epoch keys. Network and hardware calls stay in the client
/// between prepareDelegation and acceptCredential; stale responses fail closed.
public actor EpochManager {
    public let accountID: String
    public let deviceID: String
    public let audience: String
    private let rootPublicKey: Data
    private let serverPublicKey: Data
    private var key: SoftwareSigningKey?
    private var delegation: EpochDelegation?
    private var credential: EpochCredential?
    private var previousPublicKeyHash: Data?

    public init(accountID: String, deviceID: String, rootPublicKey: Data, serverPublicKey: Data,
                audience: String = "swiftkey.local") {
        self.accountID = accountID; self.deviceID = deviceID
        self.rootPublicKey = rootPublicKey; self.serverPublicKey = serverPublicKey
        self.audience = audience
    }

    public func prepareDelegation(now: UInt64) throws -> EpochDelegation {
        try validateIdentifier(accountID, "accountID"); try validateIdentifier(deviceID, "deviceID")
        try validateIdentifier(audience, "audience")
        let currentEpoch = Epoch.number(at: now)
        try Epoch.validate(currentEpoch, now: now)
        if let delegation, delegation.epoch == currentEpoch { return delegation }
        if let delegation, delegation.epoch > currentEpoch { throw ProtocolError.epochNotCurrent }
        let nextKey = SoftwareSigningKey()
        previousPublicKeyHash = delegation.map { ProtocolCrypto.sha256($0.publicKey) }
        let nextDelegation = EpochDelegation(accountID: accountID, deviceID: deviceID,
                                             epoch: currentEpoch, publicKey: nextKey.publicKey,
                                             audience: audience, previousPublicKeyHash: previousPublicKeyHash)
        key = nextKey; delegation = nextDelegation; credential = nil
        return nextDelegation
    }

    public func acceptCredential(_ credential: EpochCredential, now: UInt64) throws {
        guard let delegation, credential.delegation == delegation else { throw ProtocolError.bindingMismatch }
        try ProtocolValidation.verifyCredential(credential, rootPublicKey: rootPublicKey,
                                                serverPublicKey: serverPublicKey, accountID: accountID,
                                                deviceID: deviceID, now: now)
        self.credential = credential
    }

    public func currentCredential(now: UInt64) throws -> EpochCredential? {
        _ = try prepareDelegation(now: now)
        return credential
    }

    public func snapshot() -> EpochManagerSnapshot? {
        guard let key, let delegation else { return nil }
        return EpochManagerSnapshot(delegation: delegation, privateKey: key.rawRepresentation,
                                    credential: credential, rootPublicKeyHash: ProtocolCrypto.sha256(rootPublicKey),
                                    serverPublicKeyHash: ProtocolCrypto.sha256(serverPublicKey),
                                    previousPublicKeyHash: previousPublicKeyHash)
    }

    public func restore(_ snapshot: EpochManagerSnapshot, now: UInt64) throws {
        try Epoch.validate(Epoch.number(at: now), now: now)
        guard snapshot.delegation.accountID == accountID, snapshot.delegation.deviceID == deviceID,
              snapshot.delegation.audience == audience,
              snapshot.rootPublicKeyHash == ProtocolCrypto.sha256(rootPublicKey),
              snapshot.serverPublicKeyHash == ProtocolCrypto.sha256(serverPublicKey),
              snapshot.previousPublicKeyHash == snapshot.delegation.previousPublicKeyHash
        else { throw ProtocolError.bindingMismatch }
        let bounds = try Epoch.bounds(for: snapshot.delegation.epoch)
        guard snapshot.delegation.epoch <= Epoch.number(at: now) else { throw ProtocolError.epochNotCurrent }
        _ = try snapshot.delegation.canonicalBytes()
        let restored = try SoftwareSigningKey(rawRepresentation: snapshot.privateKey)
        guard restored.publicKey == snapshot.delegation.publicKey else { throw ProtocolError.bindingMismatch }
        if let credential = snapshot.credential {
            guard credential.delegation == snapshot.delegation else { throw ProtocolError.bindingMismatch }
            try ProtocolValidation.verifyCredential(credential, rootPublicKey: rootPublicKey,
                                                    serverPublicKey: serverPublicKey, accountID: accountID,
                                                    deviceID: deviceID, now: min(now, bounds.end - 1))
        }
        key = restored; delegation = snapshot.delegation; credential = snapshot.credential
        previousPublicKeyHash = snapshot.previousPublicKeyHash
        // Restoring an expired snapshot rotates immediately without ever
        // exposing its old credential as valid, retaining the key-hash chain.
        _ = try prepareDelegation(now: now)
    }

    public func signWorkload(domain: String, audience: String, payload: Data,
                             nonce: Data, now: UInt64) throws -> AuthenticatedWorkload {
        let delegation = try prepareDelegation(now: now)
        guard audience == self.audience else { throw ProtocolError.bindingMismatch }
        guard let key, let credential else { throw ProtocolError.credentialRequired }
        let message = WorkloadMessage(domain: domain, audience: audience, accountID: accountID,
                                      deviceID: deviceID, epoch: delegation.epoch, nonce: nonce, payload: payload)
        let signature = try key.sign(message: message.canonicalBytes())
        return AuthenticatedWorkload(credential: credential, workload: SignedWorkload(message: message, signature: signature))
    }
}
