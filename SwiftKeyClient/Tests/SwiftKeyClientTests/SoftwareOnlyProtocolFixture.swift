import Foundation
import SwiftKeyCore
import SwiftKeyClient

/// Deliberately software-only, in-process test double. The certificate bytes
/// below are not DER and must never be sent to or accepted by a real authority.
/// This fixture tests protocol/persistence behavior, not Android attestation.
final class SoftwareOnlyProtocolFixture: @unchecked Sendable {
    enum Failure: Error, Equatable {
        case storageUnavailable, hardwareUnavailable, transportUnavailable
        case invalidRequest, hardwareInvokedWithoutSavedChallenge
    }

    enum ReplayBehavior { case reject, transportFailure, unrelatedRejection, accept }

    struct State {
        var now: UInt64 = Epoch.duration * 100 + 100
        var persisted: Data?
        var events: [String] = []
        var requests: [String: Int] = [:]
        var challenges: [UInt64: ChallengeEnvelope] = [:]
        var generatedWithChallenges: [Data] = []
        var rootMessages: [Data] = []
        var acceptedWorkloads: [AuthenticatedWorkload] = []
        var writes: [ClientState] = []
        var writeFailuresRemaining = 0
        var failNextCredentialWrite = false
        var failCompletedEnrollmentWrite = false
        var failHardware = false
        var enrollmentAccepted = false
        var enrollmentTransportFailuresRemaining = 0
        var badRootSignatureAt: Int?
        var wrongEnrollmentServerKey = false
        var wrongCredentialSigner = false
        var wrongWorkloadReceipt = false
        var replayBehavior = ReplayBehavior.reject
    }

    let root = SoftwareSigningKey()
    let server = SoftwareSigningKey()
    private let wrongKey = SoftwareSigningKey()
    private let lock = NSRecursiveLock()
    private var state = State()
    private static let fakeCertificates = [Data("TEST-ONLY SOFTWARE FIXTURE; NOT AN ATTESTATION CERTIFICATE".utf8)]

    let accountID = "test-account"
    let deviceID = "test-device"
    let audience = "test-audience"
    let serverURL = "http://127.0.0.1:8765"

    var configuration: ClientConfiguration {
        ClientConfiguration(serverURL: serverURL, bootstrapToken: "test-only-bootstrap-token",
            serverPublicKey: server.publicKey, audience: audience)
    }

    var platform: ClientPlatform {
        ClientPlatform(enroll: { try self.enroll($0) },
            signRootMessage: { try self.signRoot($0) },
            post: { try self.post($0, body: $1, token: $2) },
            readState: { self.inspect { $0.persisted } },
            writeState: { try self.write($0) },
            now: { self.inspect { $0.now } })
    }

    func client() throws -> ProtocolClient {
        try ProtocolClient(configuration: configuration, platform: platform)
    }

    func inspect<T>(_ body: (State) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(state)
    }

    func change<T>(_ body: (inout State) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }

    func storedState() throws -> ClientState {
        guard let persisted = inspect({ $0.persisted }) else { throw Failure.storageUnavailable }
        return try JSONDecoder().decode(ClientState.self, from: persisted)
    }

    private func write(_ data: Data) throws {
        try change { state in
            state.events.append("writeState")
            if state.writeFailuresRemaining > 0 {
                state.writeFailuresRemaining -= 1
                throw Failure.storageUnavailable
            }
            let next = try JSONDecoder().decode(ClientState.self, from: data)
            if state.failNextCredentialWrite, next.epochSnapshot?.credential != nil {
                state.failNextCredentialWrite = false
                throw Failure.storageUnavailable
            }
            if state.failCompletedEnrollmentWrite, next.enrollment != nil {
                state.failCompletedEnrollmentWrite = false
                throw Failure.storageUnavailable
            }
            state.writes.append(next)
            state.persisted = data
        }
    }

    private func enroll(_ challenge: Data) throws -> AndroidEnrollmentEvidence {
        try change { state in
            state.events.append("hardwareEnrollment")
            // This assertion lives inside the fake hardware call, so a later
            // successful write cannot hide an unsafe generation ordering.
            guard let persisted = state.persisted,
                  let pending = try JSONDecoder().decode(ClientState.self, from: persisted).pendingBootstrap,
                  pending.attestationChallenge == challenge else {
                throw Failure.hardwareInvokedWithoutSavedChallenge
            }
            if state.failHardware { throw Failure.hardwareUnavailable }
            state.generatedWithChallenges.append(challenge)
            return AndroidEnrollmentEvidence(publicKey: root.publicKey,
                certificateChain: Self.fakeCertificates, platform: "androidStrongBox")
        }
    }

    private func signRoot(_ message: Data) throws -> Data {
        try change { state in
            state.events.append("rootSign")
            state.rootMessages.append(message)
            let key = state.badRootSignatureAt == state.rootMessages.count ? wrongKey : root
            return try key.sign(message: message)
        }
    }

    private func post(_ url: String, body: Data, token: String) throws -> Data {
        guard url.hasPrefix(serverURL + "/v1/") else { throw Failure.invalidRequest }
        let path = String(url.dropFirst(serverURL.count))
        let expectedToken = path.hasPrefix("/v1/bootstrap/") ? configuration.bootstrapToken : ""
        guard token == expectedToken else { throw Failure.invalidRequest }
        return try change { state in
            state.requests[path, default: 0] += 1
            state.events.append(path)
            switch path {
            case "/v1/bootstrap/challenge":
                let challenge = makeChallenge(operation: .enroll, sequence: 0,
                    payloadHash: ProtocolCrypto.sha256(Data("swiftkey-bootstrap-v1".utf8)), now: state.now)
                state.challenges[0] = challenge
                return try encode(BootstrapChallengeResponse(challenge: challenge,
                    attestationChallenge: ProtocolCrypto.sha256(try challenge.canonicalBytes())))

            case "/v1/bootstrap/enroll":
                let request = try JSONDecoder().decode(EnrollRequest.self, from: body)
                guard request.challenge == state.challenges[0], request.certificates == Self.fakeCertificates,
                      ProtocolCrypto.verify(signature: request.proof,
                        message: try request.challenge.canonicalBytes(), publicKey: root.publicKey) else {
                    throw Failure.invalidRequest
                }
                // An authority may return the original completed enrollment
                // after a lost response; a first enrollment still expires.
                if !state.enrollmentAccepted { try request.challenge.validate(now: state.now) }
                state.enrollmentAccepted = true
                if state.enrollmentTransportFailuresRemaining > 0 {
                    state.enrollmentTransportFailuresRemaining -= 1
                    throw Failure.transportUnavailable
                }
                return try encode(EnrollResponse(accountID: accountID, deviceID: deviceID,
                    publicKey: root.publicKey,
                    serverPublicKey: state.wrongEnrollmentServerKey ? wrongKey.publicKey : server.publicKey))

            case "/v1/challenges":
                let request = try JSONDecoder().decode(ChallengeRequest.self, from: body)
                guard request.accountID == accountID, request.deviceID == deviceID,
                      request.operation == .issueEpoch else { throw Failure.invalidRequest }
                let sequence = UInt64(state.requests[path, default: 0])
                let challenge = makeChallenge(operation: request.operation, sequence: sequence,
                    payloadHash: request.payloadHash, now: state.now)
                state.challenges[sequence] = challenge
                return try encode(challenge)

            case "/v1/epochs":
                let request = try JSONDecoder().decode(IssueEpochRequest.self, from: body)
                guard state.challenges[request.authorization.challenge.sequence] == request.authorization.challenge,
                      request.authorization.challenge.payloadHash == ProtocolCrypto.sha256(try request.delegation.canonicalBytes())
                else { throw Failure.invalidRequest }
                try ProtocolValidation.verifyAuthorization(request.authorization, publicKey: root.publicKey, now: state.now)
                let unsigned = EpochCredential(delegation: request.delegation,
                    authorization: request.authorization, serverSignature: Data())
                let key = state.wrongCredentialSigner ? wrongKey : server
                let credential = EpochCredential(delegation: request.delegation,
                    authorization: request.authorization,
                    serverSignature: try key.sign(message: unsigned.unsignedCanonicalBytes()))
                return try encode(credential)

            case "/v1/workloads":
                let request = try JSONDecoder().decode(VerifyWorkloadRequest.self, from: body)
                let authenticated = AuthenticatedWorkload(credential: request.credential, workload: request.workload)
                try ProtocolValidation.verifyWorkload(authenticated, rootPublicKey: root.publicKey,
                    serverPublicKey: server.publicKey, expectedDomain: "swiftkey.demo.echo.v1",
                    expectedAudience: audience, accountID: accountID, deviceID: deviceID, now: state.now)
                if state.acceptedWorkloads.contains(where: { $0.workload.message.nonce == request.workload.message.nonce }) {
                    switch state.replayBehavior {
                    case .reject:
                        return try encode(AuthorityErrorResponse(code: "replayedWorkload", error: "Already consumed"))
                    case .transportFailure: throw Failure.transportUnavailable
                    case .unrelatedRejection:
                        return try encode(AuthorityErrorResponse(code: "revokedDevice", error: "Device revoked"))
                    case .accept: break
                    }
                }
                state.acceptedWorkloads.append(authenticated)
                return try encode(VerifyWorkloadResponse(accepted: true,
                    payloadHash: ProtocolCrypto.sha256(state.wrongWorkloadReceipt ? Data() : request.workload.message.payload)))

            default: throw Failure.invalidRequest
            }
        }
    }

    private func makeChallenge(operation: SwiftKeyCore.Operation, sequence: UInt64,
                               payloadHash: Data, now: UInt64) -> ChallengeEnvelope {
        ChallengeEnvelope(accountID: accountID, deviceID: deviceID, operation: operation,
            sequence: sequence, nonce: ProtocolCrypto.randomNonce(), expiresAt: now + 300,
            payloadHash: payloadHash)
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
}
