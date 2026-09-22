import CryptoKit
import Foundation
import Security

/// A bounded software authenticator for the explicitly labeled iOS mock harness.
/// It is not a production authenticator, Secure Enclave implementation, or attested device.
/// UP/UV mean simulated approval in this mock; BE/BS and signCount are always zero.
public struct MockPasskeyEngine: Sendable {
    public static let allowedRelyingParties: Set<String> = ["swiftkey.mock", "localhost"]
    public static let maximumCredentials = 128
    public static let maximumConsumedRequests = 4096
    public static let approvalLifetime: TimeInterval = 60

    public private(set) var state: MockPasskeyState
    public var credentials: [MockPasskeyCredential] { state.credentials }
    private var approvals: [UUID: Approval] = [:]
    private var cancelledTokens: Set<UUID> = []

    private struct Approval: Sendable {
        let requestID: UUID
        let digest: Data
        let issuedAt: Date
        let expiresAt: Date
    }

    public init(mode: MockPasskeyMode = .mock, state: MockPasskeyState = .init()) throws {
        guard mode == .mock else { throw MockPasskeyError.productionUnavailable }
        try Self.validate(state)
        self.state = state
    }

    /// Call only when the mock UI explicitly approves simulated verification.
    /// The token binds every request field, not merely its displayed RP or request ID.
    public mutating func approve(_ operation: MockPasskeyOperation, now: Date = Date()) throws -> MockApprovalToken {
        try validate(operation)
        try requireUnused(operation.requestID)
        guard now.timeIntervalSince1970.isFinite else { throw MockPasskeyError.malformedRequest }
        approvals = approvals.filter { $0.value.expiresAt > now }
        guard approvals.count < 64 else { throw MockPasskeyError.capacity }
        guard !approvals.values.contains(where: { $0.requestID == operation.requestID }) else { throw MockPasskeyError.approvalPending }
        let id = UUID()
        approvals[id] = Approval(requestID: operation.requestID, digest: try digest(operation),
                                 issuedAt: now, expiresAt: now.addingTimeInterval(Self.approvalLifetime))
        return MockApprovalToken(id: id)
    }

    public mutating func cancel(_ token: MockApprovalToken, now: Date = Date()) throws {
        guard let approval = approvals.removeValue(forKey: token.id) else {
            throw cancelledTokens.contains(token.id) ? MockPasskeyError.cancelled : MockPasskeyError.invalidApproval
        }
        try requireUnused(approval.requestID)
        guard now.timeIntervalSince1970.isFinite else { throw MockPasskeyError.malformedRequest }
        cancelledTokens.insert(token.id)
        if cancelledTokens.count > 64 { cancelledTokens = [token.id] }
        state.consumedRequests.append(MockConsumedRequest(requestID: approval.requestID, operationDigest: approval.digest,
                                                         consumedAt: now, outcome: .cancelled))
    }

    public mutating func create(_ request: MockCreatePasskeyRequest, approval: MockApprovalToken,
                                now: Date = Date()) throws -> MockRegistrationResponse {
        try validate(.create(request))
        try consume(approval, operation: .create(request), now: now)
        if state.credentials.contains(where: { $0.rpID == request.rpID && request.excludedCredentialIDs.contains($0.id) }) {
            throw MockPasskeyError.credentialExcluded
        }
        let credential: MockPasskeyCredential
        if let existing = state.credentials.first(where: { $0.rpID == request.rpID && $0.userHandle == request.userHandle }) {
            credential = existing
        } else {
            guard state.credentials.count < Self.maximumCredentials else { throw MockPasskeyError.capacity }
            let key = P256.Signing.PrivateKey()
            var identifier = Data(repeating: 0, count: 32)
            let result = identifier.withUnsafeMutableBytes { buffer in
                SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
            }
            guard result == errSecSuccess, !state.credentials.contains(where: { $0.id == identifier }) else {
                throw MockPasskeyError.invalidState
            }
            credential = MockPasskeyCredential(id: identifier, rpID: request.rpID, userHandle: request.userHandle,
                userName: request.userName, displayName: request.displayName, publicKeyX963: key.publicKey.x963Representation,
                createdAt: now, mockPrivateKeyRawRepresentation: key.rawRepresentation)
            state.credentials.append(credential)
        }
        let key = credential.publicKeyX963
        let cose = MockCBOR.map([
            (.integer(1), .integer(2)), (.integer(3), .integer(-7)), (.integer(-1), .integer(1)),
            (.integer(-2), .bytes(key.subdata(in: 1..<33))), (.integer(-3), .bytes(key.subdata(in: 33..<65)))
        ]).encoded()
        let authenticatorData = authData(rpID: request.rpID, flags: 0x45) + Data(repeating: 0, count: 16) +
            Data([0, 32]) + credential.id + cose
        let attestation = MockCBOR.map([(.text("fmt"), .text("none")), (.text("attStmt"), .map([])),
                                       (.text("authData"), .bytes(authenticatorData))]).encoded()
        return MockRegistrationResponse(credential: credential, attestationObject: attestation,
                                        authenticatorData: authenticatorData, clientDataHash: request.clientDataHash)
    }

    public mutating func sign(_ request: MockSignPasskeyRequest, approval: MockApprovalToken,
                              now: Date = Date()) throws -> MockAssertionResponse {
        try validate(.sign(request))
        try consume(approval, operation: .sign(request), now: now)
        let candidates = matchingCredentials(for: request)
        guard !candidates.isEmpty else { throw MockPasskeyError.noMatchingCredential }
        guard candidates.count == 1 else { throw MockPasskeyError.ambiguousCredential }
        let credential = candidates[0]
        let authenticatorData = authData(rpID: request.rpID, flags: 0x05)
        let key = try P256.Signing.PrivateKey(rawRepresentation: credential.mockPrivateKeyRawRepresentation)
        let signature = try key.signature(for: authenticatorData + request.clientDataHash).derRepresentation
        let response = MockAssertionResponse(credentialID: credential.id, userHandle: credential.userHandle,
            rpID: request.rpID, authenticatorData: authenticatorData, signatureDER: signature, clientDataHash: request.clientDataHash)
        try response.verify(publicKeyX963: credential.publicKeyX963)
        return response
    }

    public func matchingCredentials(for request: MockSignPasskeyRequest) -> [MockPasskeyCredential] {
        state.credentials.filter { credential in
            credential.rpID == request.rpID && (request.credentialID == nil || credential.id == request.credentialID) &&
            (request.userHandle == nil || credential.userHandle == request.userHandle) &&
            (request.allowedCredentialIDs.isEmpty || request.allowedCredentialIDs.contains(credential.id))
        }
    }

    public mutating func deleteCredential(id: Data) throws {
        guard let index = state.credentials.firstIndex(where: { $0.id == id }) else { throw MockPasskeyError.noMatchingCredential }
        state.credentials.remove(at: index)
        // Retain consumed request IDs so deletion cannot reopen accepted ceremonies.
    }

    private mutating func consume(_ token: MockApprovalToken, operation: MockPasskeyOperation, now: Date) throws {
        guard let approval = approvals.removeValue(forKey: token.id) else {
            if cancelledTokens.contains(token.id) { throw MockPasskeyError.cancelled }
            try requireUnused(operation.requestID)
            throw MockPasskeyError.invalidApproval
        }
        guard approval.requestID == operation.requestID, approval.digest == (try digest(operation)) else {
            throw MockPasskeyError.approvalMismatch
        }
        guard now.timeIntervalSince1970.isFinite, now >= approval.issuedAt, now < approval.expiresAt else {
            throw MockPasskeyError.approvalExpired
        }
        try requireUnused(operation.requestID)
        state.consumedRequests.append(MockConsumedRequest(requestID: operation.requestID, operationDigest: approval.digest,
                                                         consumedAt: now, outcome: .completed))
    }

    private func requireUnused(_ requestID: UUID) throws {
        if let previous = state.consumedRequests.first(where: { $0.requestID == requestID }) {
            throw previous.outcome == .cancelled ? MockPasskeyError.cancelled : MockPasskeyError.replayed
        }
        guard state.consumedRequests.count < Self.maximumConsumedRequests else { throw MockPasskeyError.capacity }
    }
    private func digest(_ operation: MockPasskeyOperation) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return Data(SHA256.hash(data: try encoder.encode(operation)))
    }
    private func authData(rpID: String, flags: UInt8) -> Data {
        Data(SHA256.hash(data: Data(rpID.utf8))) + Data([flags, 0, 0, 0, 0])
    }
    private func validate(_ operation: MockPasskeyOperation) throws {
        switch operation {
        case .create(let request):
            try Self.validateRP(request.rpID)
            guard request.clientDataHash.count == 32, (1...64).contains(request.userHandle.count),
                  Self.validName(request.userName), Self.validName(request.displayName),
                  !request.algorithms.isEmpty, request.algorithms.count <= 32,
                  Self.validDescriptors(request.excludedCredentialIDs) else { throw MockPasskeyError.malformedRequest }
            guard request.algorithms.contains(-7) else { throw MockPasskeyError.unsupportedAlgorithm }
        case .sign(let request):
            try Self.validateRP(request.rpID)
            guard request.clientDataHash.count == 32, request.credentialID.map({ (1...1024).contains($0.count) }) ?? true,
                  request.userHandle.map({ (1...64).contains($0.count) }) ?? true,
                  Self.validDescriptors(request.allowedCredentialIDs) else { throw MockPasskeyError.malformedRequest }
        }
    }
    private static func validateRP(_ rpID: String) throws {
        guard allowedRelyingParties.contains(rpID) else { throw MockPasskeyError.relyingPartyNotAllowed }
    }
    private static func validName(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    private static func validDescriptors(_ values: [Data]) -> Bool {
        values.count <= 128 && values.allSatisfy { (1...1024).contains($0.count) }
    }
    private static func validate(_ state: MockPasskeyState) throws {
        guard state.formatVersion == 1, state.credentials.count <= maximumCredentials,
              state.consumedRequests.count <= maximumConsumedRequests,
              Set(state.credentials.map(\.id)).count == state.credentials.count,
              Set(state.consumedRequests.map(\.requestID)).count == state.consumedRequests.count else { throw MockPasskeyError.invalidState }
        var users: Set<String> = []
        for credential in state.credentials {
            guard allowedRelyingParties.contains(credential.rpID), credential.id.count == 32,
                  (1...64).contains(credential.userHandle.count), validName(credential.userName), validName(credential.displayName),
                  credential.createdAt.timeIntervalSince1970.isFinite,
                  users.insert(credential.rpID + ":" + credential.userHandle.base64URLEncodedString()).inserted else { throw MockPasskeyError.invalidState }
            guard let key = try? P256.Signing.PrivateKey(rawRepresentation: credential.mockPrivateKeyRawRepresentation),
                  key.publicKey.x963Representation == credential.publicKeyX963 else { throw MockPasskeyError.invalidState }
        }
        guard state.consumedRequests.allSatisfy({ $0.operationDigest.count == 32 && $0.consumedAt.timeIntervalSince1970.isFinite }) else {
            throw MockPasskeyError.invalidState
        }
    }
}
