import Foundation

public enum Epoch {
    public static let duration: UInt64 = 14_400
    public static func number(at unixSeconds: UInt64) -> UInt64 { unixSeconds / duration }
    public static func bounds(for epoch: UInt64) throws -> (start: UInt64, end: UInt64) {
        let (start, multiplyOverflow) = epoch.multipliedReportingOverflow(by: duration)
        let (end, addOverflow) = start.addingReportingOverflow(duration)
        guard !multiplyOverflow && !addOverflow else { throw ProtocolError.epochOverflow }
        return (start, end)
    }
    public static func validate(_ epoch: UInt64, now: UInt64) throws {
        let bounds = try bounds(for: epoch)
        guard bounds.start <= now && now < bounds.end else { throw ProtocolError.epochNotCurrent }
    }
}

/// Cryptographic/structural checks only. Authorities must separately check
/// membership, consume challenges/nonces atomically, and enforce sequences.
public enum ProtocolValidation {
    public static func verifyAuthorization(_ authorization: RootAuthorization,
                                           publicKey: Data, now: UInt64? = nil) throws {
        guard authorization.kind == .androidStrongBoxP256 else { throw ProtocolError.unsupportedAuthorization }
        if let now { try authorization.challenge.validate(now: now) }
        guard ProtocolCrypto.verify(signature: authorization.signature,
                                    message: try authorization.challenge.canonicalBytes(), publicKey: publicKey)
        else { throw ProtocolError.invalidSignature }
    }

    public static func verifyCredential(_ credential: EpochCredential, rootPublicKey: Data,
                                        serverPublicKey: Data, accountID: String,
                                        deviceID: String, now: UInt64) throws {
        let delegation = credential.delegation
        let challenge = credential.authorization.challenge
        guard delegation.accountID == accountID, delegation.deviceID == deviceID,
              challenge.accountID == accountID, challenge.deviceID == deviceID,
              challenge.operation == .issueEpoch,
              challenge.payloadHash == ProtocolCrypto.sha256(try delegation.canonicalBytes())
        else { throw ProtocolError.bindingMismatch }
        try Epoch.validate(delegation.epoch, now: now)
        // Challenge expiry was checked on issuance. A consumed short-lived
        // challenge expiring later must not shorten the four-hour credential.
        try verifyAuthorization(credential.authorization, publicKey: rootPublicKey)
        guard ProtocolCrypto.verify(signature: credential.serverSignature,
                                    message: try credential.unsignedCanonicalBytes(), publicKey: serverPublicKey)
        else { throw ProtocolError.invalidSignature }
    }

    public static func verifyWorkload(_ authenticated: AuthenticatedWorkload,
                                      rootPublicKey: Data, serverPublicKey: Data,
                                      expectedDomain: String, expectedAudience: String,
                                      accountID: String, deviceID: String, now: UInt64) throws {
        try verifyCredential(authenticated.credential, rootPublicKey: rootPublicKey,
                             serverPublicKey: serverPublicKey, accountID: accountID, deviceID: deviceID, now: now)
        let message = authenticated.workload.message
        guard message.domain == expectedDomain, message.audience == expectedAudience,
              message.audience == authenticated.credential.delegation.audience,
              message.accountID == accountID, message.deviceID == deviceID,
              message.epoch == authenticated.credential.delegation.epoch
        else { throw ProtocolError.bindingMismatch }
        guard ProtocolCrypto.verify(signature: authenticated.workload.signature,
                                    message: try message.canonicalBytes(),
                                    publicKey: authenticated.credential.delegation.publicKey)
        else { throw ProtocolError.invalidSignature }
    }
}
