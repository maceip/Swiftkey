import Foundation

public enum Operation: String, Codable, Sendable, CaseIterable {
    case enroll, issueEpoch, addDevice, revokeDevice, recoverDevice
}

public struct ChallengeEnvelope: Codable, Sendable, Equatable {
    public let accountID: String
    public let deviceID: String
    public let operation: Operation
    public let sequence: UInt64
    public let nonce: Data
    public let expiresAt: UInt64
    public let payloadHash: Data

    public init(accountID: String, deviceID: String, operation: Operation, sequence: UInt64,
                nonce: Data, expiresAt: UInt64, payloadHash: Data) {
        self.accountID = accountID; self.deviceID = deviceID; self.operation = operation
        self.sequence = sequence; self.nonce = nonce; self.expiresAt = expiresAt
        self.payloadHash = payloadHash
    }

    public func canonicalBytes() throws -> Data {
        try validateIdentifier(accountID, "accountID"); try validateIdentifier(deviceID, "deviceID")
        try validateNonce(nonce)
        guard payloadHash.count == 32 else { throw ProtocolError.invalidField("payloadHash") }
        guard expiresAt > 0 else { throw ProtocolError.invalidField("expiresAt") }
        var bytes = try CanonicalEncoder(domain: "challenge")
        try bytes.append(accountID); try bytes.append(deviceID); try bytes.append(operation.rawValue)
        bytes.append(sequence); try bytes.append(nonce); bytes.append(expiresAt)
        try bytes.append(payloadHash)
        return bytes.data
    }

    public func validate(now: UInt64) throws {
        _ = try canonicalBytes()
        guard now < expiresAt else { throw ProtocolError.challengeExpired }
    }
}

public struct EpochDelegation: Codable, Sendable, Equatable {
    public let accountID: String
    public let deviceID: String
    public let audience: String
    public let epoch: UInt64
    public let publicKey: Data
    public let previousPublicKeyHash: Data?

    public init(accountID: String, deviceID: String, epoch: UInt64, publicKey: Data,
                audience: String = "swiftkey.local", previousPublicKeyHash: Data? = nil) {
        self.accountID = accountID; self.deviceID = deviceID
        self.audience = audience; self.epoch = epoch; self.publicKey = publicKey
        self.previousPublicKeyHash = previousPublicKeyHash
    }

    public func canonicalBytes() throws -> Data {
        try validateIdentifier(accountID, "accountID"); try validateIdentifier(deviceID, "deviceID")
        try validateIdentifier(audience, "audience")
        try ProtocolCrypto.validatePublicKey(publicKey)
        guard previousPublicKeyHash == nil || previousPublicKeyHash?.count == 32
        else { throw ProtocolError.invalidField("previousPublicKeyHash") }
        _ = try Epoch.bounds(for: epoch)
        var bytes = try CanonicalEncoder(domain: "epoch-delegation")
        try bytes.append(accountID); try bytes.append(deviceID); try bytes.append(audience); bytes.append(epoch)
        try bytes.append(publicKey); try bytes.appendOptional(previousPublicKeyHash)
        return bytes.data
    }
}

public enum AuthorizationKind: String, Codable, Sendable {
    case androidStrongBoxP256
    case appleAppAttest
}

public struct RootAuthorization: Codable, Sendable, Equatable {
    public let kind: AuthorizationKind
    public let challenge: ChallengeEnvelope
    public let signature: Data

    public init(kind: AuthorizationKind, challenge: ChallengeEnvelope, signature: Data) {
        self.kind = kind; self.challenge = challenge; self.signature = signature
    }

    public func canonicalBytes() throws -> Data {
        var bytes = try CanonicalEncoder(domain: "root-authorization")
        try bytes.append(kind.rawValue); try bytes.append(challenge.canonicalBytes())
        try bytes.append(signature)
        return bytes.data
    }
}

public struct EpochCredential: Codable, Sendable, Equatable {
    public let delegation: EpochDelegation
    public let authorization: RootAuthorization
    public let serverSignature: Data

    public init(delegation: EpochDelegation, authorization: RootAuthorization, serverSignature: Data) {
        self.delegation = delegation; self.authorization = authorization
        self.serverSignature = serverSignature
    }

    /// Raw message signed by the authority with ECDSA + SHA-256 exactly once.
    public func unsignedCanonicalBytes() throws -> Data {
        var bytes = try CanonicalEncoder(domain: "epoch-credential")
        try bytes.append(delegation.canonicalBytes()); try bytes.append(authorization.canonicalBytes())
        return bytes.data
    }

    public func canonicalBytes() throws -> Data {
        var bytes = try CanonicalEncoder(domain: "signed-epoch-credential")
        try bytes.append(unsignedCanonicalBytes()); try bytes.append(serverSignature)
        return bytes.data
    }
}

public struct DeviceMembershipChange: Codable, Sendable, Equatable {
    public let accountID: String
    /// The candidate/new device for add/recover, or target device for revoke.
    public let deviceID: String
    public let publicKey: Data?
    public let operation: Operation

    public init(accountID: String, deviceID: String, publicKey: Data?, operation: Operation) {
        self.accountID = accountID; self.deviceID = deviceID
        self.publicKey = publicKey; self.operation = operation
    }

    public func canonicalBytes() throws -> Data {
        try validateIdentifier(accountID, "accountID"); try validateIdentifier(deviceID, "deviceID")
        switch operation {
        case .enroll, .addDevice, .recoverDevice:
            guard let publicKey else { throw ProtocolError.invalidPublicKey }
            try ProtocolCrypto.validatePublicKey(publicKey)
        case .revokeDevice:
            guard publicKey == nil else { throw ProtocolError.invalidField("publicKey") }
        case .issueEpoch: throw ProtocolError.invalidField("operation")
        }
        var bytes = try CanonicalEncoder(domain: "device-membership")
        try bytes.append(accountID); try bytes.append(deviceID)
        try bytes.append(operation.rawValue); try bytes.appendOptional(publicKey)
        return bytes.data
    }
}

public struct WorkloadMessage: Codable, Sendable, Equatable {
    public let domain: String
    public let audience: String
    public let accountID: String
    public let deviceID: String
    public let epoch: UInt64
    public let nonce: Data
    public let payload: Data

    public init(domain: String, audience: String, accountID: String, deviceID: String,
                epoch: UInt64, nonce: Data, payload: Data) {
        self.domain = domain; self.audience = audience; self.accountID = accountID
        self.deviceID = deviceID; self.epoch = epoch; self.nonce = nonce; self.payload = payload
    }

    public func canonicalBytes() throws -> Data {
        try validateIdentifier(domain, "domain"); try validateIdentifier(audience, "audience")
        try validateIdentifier(accountID, "accountID"); try validateIdentifier(deviceID, "deviceID")
        try validateNonce(nonce); _ = try Epoch.bounds(for: epoch)
        var bytes = try CanonicalEncoder(domain: "workload")
        try bytes.append(domain); try bytes.append(audience)
        try bytes.append(accountID); try bytes.append(deviceID); bytes.append(epoch)
        try bytes.append(nonce); try bytes.append(payload)
        return bytes.data
    }
}

/// A single authorization binds both the exact lost root to revoke and the
/// exact replacement key to enroll. Authorities must apply it atomically.
public struct RecoveryChange: Codable, Sendable, Equatable {
    public let accountID: String
    public let lostDeviceID: String
    public let replacementDeviceID: String
    public let publicKey: Data

    public init(accountID: String, lostDeviceID: String, replacementDeviceID: String, publicKey: Data) {
        self.accountID = accountID; self.lostDeviceID = lostDeviceID
        self.replacementDeviceID = replacementDeviceID; self.publicKey = publicKey
    }

    public func canonicalBytes() throws -> Data {
        try validateIdentifier(accountID, "accountID")
        try validateIdentifier(lostDeviceID, "lostDeviceID")
        try validateIdentifier(replacementDeviceID, "replacementDeviceID")
        guard lostDeviceID != replacementDeviceID else { throw ProtocolError.bindingMismatch }
        try ProtocolCrypto.validatePublicKey(publicKey)
        var bytes = try CanonicalEncoder(domain: "device-recovery")
        try bytes.append(accountID); try bytes.append(lostDeviceID)
        try bytes.append(replacementDeviceID); try bytes.append(publicKey)
        return bytes.data
    }
}

public struct SignedWorkload: Codable, Sendable, Equatable {
    public let message: WorkloadMessage
    public let signature: Data
    public init(message: WorkloadMessage, signature: Data) {
        self.message = message; self.signature = signature
    }
}

public struct AuthenticatedWorkload: Codable, Sendable, Equatable {
    public let credential: EpochCredential
    public let workload: SignedWorkload
    public init(credential: EpochCredential, workload: SignedWorkload) {
        self.credential = credential; self.workload = workload
    }
}
