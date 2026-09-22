import CryptoKit
import Foundation

public enum MockPasskeyMode: Sendable { case mock, production }

public enum MockPasskeyError: String, Error, Sendable, Equatable, LocalizedError {
    case productionUnavailable, relyingPartyNotAllowed, malformedRequest, unsupportedAlgorithm
    case credentialExcluded, noMatchingCredential, ambiguousCredential, invalidState, capacity
    case approvalPending, invalidApproval, approvalExpired, approvalMismatch, cancelled, replayed
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .productionUnavailable: "Production passkeys are unavailable in this mock build."
        case .relyingPartyNotAllowed: "Mock passkeys only support swiftkey.mock and localhost."
        case .malformedRequest: "The mock passkey request is invalid."
        case .unsupportedAlgorithm: "The mock supports ES256 only."
        case .credentialExcluded: "A matching mock passkey is excluded by this request."
        case .noMatchingCredential: "No mock passkey matches this request."
        case .ambiguousCredential: "Choose a mock passkey for this request."
        case .invalidState: "The mock passkey data is invalid."
        case .capacity: "The bounded mock store is full."
        case .approvalPending: "This mock request is already awaiting approval."
        case .invalidApproval: "A fresh explicit mock approval is required."
        case .approvalExpired: "The mock approval expired. Start a new request."
        case .approvalMismatch: "The request changed after mock approval."
        case .cancelled: "Mock approval was cancelled."
        case .replayed: "This mock request has already been used."
        case .verificationFailed: "The mock passkey proof did not verify."
        }
    }
}

public struct MockCreatePasskeyRequest: Codable, Sendable, Equatable {
    public let requestID: UUID
    public let rpID: String
    public let userHandle: Data
    public let userName: String
    public let displayName: String
    public let clientDataHash: Data
    public let algorithms: [Int]
    public let excludedCredentialIDs: [Data]

    public init(requestID: UUID = UUID(), rpID: String, userHandle: Data, userName: String,
                displayName: String, clientDataHash: Data, algorithms: [Int] = [-7],
                excludedCredentialIDs: [Data] = []) {
        self.requestID = requestID; self.rpID = rpID; self.userHandle = userHandle
        self.userName = userName; self.displayName = displayName; self.clientDataHash = clientDataHash
        self.algorithms = algorithms; self.excludedCredentialIDs = excludedCredentialIDs
    }
}

public struct MockSignPasskeyRequest: Codable, Sendable, Equatable {
    public let requestID: UUID
    public let rpID: String
    public let clientDataHash: Data
    public let credentialID: Data?
    public let allowedCredentialIDs: [Data]
    public let userHandle: Data?

    public init(requestID: UUID = UUID(), rpID: String, clientDataHash: Data, credentialID: Data? = nil,
                allowedCredentialIDs: [Data] = [], userHandle: Data? = nil) {
        self.requestID = requestID; self.rpID = rpID; self.clientDataHash = clientDataHash
        self.credentialID = credentialID; self.allowedCredentialIDs = allowedCredentialIDs; self.userHandle = userHandle
    }
}

public enum MockPasskeyOperation: Codable, Sendable, Equatable {
    case create(MockCreatePasskeyRequest)
    case sign(MockSignPasskeyRequest)

    public var requestID: UUID {
        switch self { case .create(let request): request.requestID; case .sign(let request): request.requestID }
    }
}

/// Opaque, process-local, single-use evidence of the host's explicit simulated approval.
/// This does not represent LocalAuthentication, biometrics, or Secure Enclave authorization.
public struct MockApprovalToken: Sendable, Hashable {
    internal let id: UUID
    internal init(id: UUID) { self.id = id }
}

/// MOCK ONLY: Codable includes a software private key for an isolated app-group test store.
/// Never use this persistence model for real website credentials or log its encoded contents.
public struct MockPasskeyCredential: Codable, Sendable, Equatable, Identifiable, CustomStringConvertible {
    public let id: Data
    public let rpID: String
    public let userHandle: Data
    public let userName: String
    public let displayName: String
    public let publicKeyX963: Data
    public let createdAt: Date
    internal let mockPrivateKeyRawRepresentation: Data

    public var description: String { "MockPasskeyCredential(mock software key; private material redacted)" }
}

public struct MockConsumedRequest: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable { case completed, cancelled }
    public let requestID: UUID
    public let operationDigest: Data
    public let consumedAt: Date
    public let outcome: Outcome
}

/// Contains MOCK private keys. Persist atomically under the host's app-group lock.
/// Used request IDs are retained; hitting the journal bound fails instead of weakening replay checks.
public struct MockPasskeyState: Codable, Sendable, Equatable, CustomStringConvertible {
    public let formatVersion: Int
    public internal(set) var credentials: [MockPasskeyCredential]
    public internal(set) var consumedRequests: [MockConsumedRequest]

    public init() { formatVersion = 1; credentials = []; consumedRequests = [] }
    public var description: String { "MockPasskeyState(credentials: \(credentials.count), consumed requests: \(consumedRequests.count); private material redacted)" }
}

public struct MockRegistrationResponse: Sendable {
    public let credential: MockPasskeyCredential
    public let attestationObject: Data
    public let authenticatorData: Data
    public let clientDataHash: Data
    public var publicKeyX963: Data { credential.publicKeyX963 }

    /// The OS owns clientDataJSON. Empty data emits the hash-only placeholder;
    /// supplied browser bytes must hash to the exact approved clientDataHash.
    public func webAuthnJSON(clientDataJSON: Data = Data()) throws -> Data {
        try validateClientDataJSON(clientDataJSON, hash: clientDataHash)
        let key = try P256.Signing.PublicKey(x963Representation: publicKeyX963)
        return try JSONSerialization.data(withJSONObject: [
            "id": credential.id.base64URLEncodedString(), "rawId": credential.id.base64URLEncodedString(),
            "type": "public-key", "clientExtensionResults": [String: String](),
            "response": ["clientDataJSON": clientDataJSON.base64URLEncodedString(),
                         "attestationObject": attestationObject.base64URLEncodedString(),
                         "authenticatorData": authenticatorData.base64URLEncodedString(),
                         "publicKeyAlgorithm": -7, "publicKey": key.derRepresentation.base64URLEncodedString(),
                         "transports": ["internal"]]
        ], options: [.sortedKeys])
    }
}

public struct MockAssertionResponse: Sendable {
    public let credentialID: Data
    public let userHandle: Data
    public let rpID: String
    public let authenticatorData: Data
    public let signatureDER: Data
    public let clientDataHash: Data

    public func verify(publicKeyX963: Data) throws {
        guard authenticatorData.count == 37, clientDataHash.count == 32,
              authenticatorData.prefix(32) == Data(SHA256.hash(data: Data(rpID.utf8))),
              authenticatorData[32] == 0x05, authenticatorData.suffix(4) == Data(repeating: 0, count: 4) else {
            throw MockPasskeyError.verificationFailed
        }
        do {
            let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyX963)
            let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureDER)
            guard publicKey.isValidSignature(signature, for: authenticatorData + clientDataHash) else {
                throw MockPasskeyError.verificationFailed
            }
        } catch { throw MockPasskeyError.verificationFailed }
    }

    public func webAuthnJSON(clientDataJSON: Data = Data()) throws -> Data {
        try validateClientDataJSON(clientDataJSON, hash: clientDataHash)
        return try JSONSerialization.data(withJSONObject: [
            "id": credentialID.base64URLEncodedString(), "rawId": credentialID.base64URLEncodedString(),
            "type": "public-key", "clientExtensionResults": [String: String](),
            "response": ["clientDataJSON": clientDataJSON.base64URLEncodedString(),
                         "authenticatorData": authenticatorData.base64URLEncodedString(),
                         "signature": signatureDER.base64URLEncodedString(), "userHandle": userHandle.base64URLEncodedString()]
        ], options: [.sortedKeys])
    }
}

extension Data {
    public func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private func validateClientDataJSON(_ bytes: Data, hash: Data) throws {
    guard bytes.isEmpty || (bytes.count <= 65_536 && Data(SHA256.hash(data: bytes)) == hash) else {
        throw MockPasskeyError.approvalMismatch
    }
}
