import Crypto
import Foundation

/// Explicitly typed prehashed input. Passing Data to sign(message:) always
/// hashes it, including Data that happens to contain a digest.
public struct PrehashedSHA256: Digest, Sendable {
    public static let byteCount = 32
    private let bytes: Data
    public init(_ bytes: Data) throws {
        guard bytes.count == Self.byteCount else { throw ProtocolError.invalidField("sha256Digest") }
        self.bytes = bytes
    }
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
}

/// A software key for short-lived delegated credentials or the authority.
/// This is never a hardware-key fallback and must not be used for enrollment.
public struct SoftwareSigningKey: Sendable {
    private let key: P256.Signing.PrivateKey
    public init() { key = P256.Signing.PrivateKey() }
    public init(rawRepresentation: Data) throws {
        key = try P256.Signing.PrivateKey(rawRepresentation: rawRepresentation)
    }
    public var publicKey: Data { key.publicKey.x963Representation }
    public var rawRepresentation: Data { key.rawRepresentation }
    public func sign(message: Data) throws -> Data {
        try key.signature(for: message).derRepresentation
    }
    public func sign(sha256Digest: PrehashedSHA256) throws -> Data {
        try key.signature(for: sha256Digest).derRepresentation
    }
}

public enum ProtocolCrypto {
    public static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    public static func validatePublicKey(_ publicKey: Data) throws {
        guard publicKey.count == 65, publicKey.first == 4,
              (try? P256.Signing.PublicKey(x963Representation: publicKey)) != nil
        else { throw ProtocolError.invalidPublicKey }
    }

    public static func verify(signature: Data, message: Data, publicKey: Data) -> Bool {
        guard let pair = signatureAndKey(signature, publicKey) else { return false }
        return pair.1.isValidSignature(pair.0, for: message)
    }

    public static func verify(signature: Data, sha256Digest: PrehashedSHA256, publicKey: Data) -> Bool {
        guard let pair = signatureAndKey(signature, publicKey) else { return false }
        return pair.1.isValidSignature(pair.0, for: sha256Digest)
    }

    public static func randomNonce() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    private static func signatureAndKey(_ signature: Data, _ publicKey: Data)
        -> (P256.Signing.ECDSASignature, P256.Signing.PublicKey)? {
        guard (try? validatePublicKey(publicKey)) != nil,
              let key = try? P256.Signing.PublicKey(x963Representation: publicKey),
              let signatureValue = try? P256.Signing.ECDSASignature(derRepresentation: signature),
              signatureValue.derRepresentation == signature else { return nil }
        return (signatureValue, key)
    }
}
