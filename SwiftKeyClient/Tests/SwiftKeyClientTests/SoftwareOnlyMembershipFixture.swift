import Foundation
import SwiftKeyCore
import SwiftKeyClient

/// Multiple software-only test devices and an in-process authority. The fake
/// certificates intentionally contain plaintext and are never valid DER.
/// This verifies client state/authorization semantics, not hardware attestation.
final class SoftwareOnlyMembershipFixture: @unchecked Sendable {
    enum Failure: Error, Equatable { case invalidRequest, persistence, transport, unsafeGeneration }
    enum WriteStage { case invitation, evidence, candidate, enrollment }

    final class Device: @unchecked Sendable {
        let name: String
        let key = SoftwareSigningKey()
        fileprivate var saved: Data?
        fileprivate var boundChallenge: Data?
        fileprivate var generationCalls = 0
        fileprivate var rootMessages: [Data] = []
        fileprivate var failWrite: WriteStage?
        fileprivate init(_ name: String) { self.name = name }
        fileprivate var fakeCertificate: Data { Data("TEST ONLY, NOT DER: \(name)".utf8) }
    }

    struct Member { let key: Data; var active = true; var sequence: UInt64 = 1 }
    struct State {
        var now: UInt64 = Epoch.duration * 100 + 100
        var members: [String: Member] = [:]
        var invitations: [String: BootstrapChallengeResponse] = [:]
        var candidates: [String: PairingCandidate] = [:]
        var challenges: [Data: ChallengeEnvelope] = [:]
        var memberships: [MembershipRequest] = []
        var recoveries: [RecoveryRequest] = []
        var requests: [String: Int] = [:]
        var wrongConfirmationPin = false
        var wrongConfirmationDevice = false
        var wrongCandidateKey = false
        var loseCandidateResponse = false
        var loseConfirmationResponse = false
        var rejectMutation = false
    }

    let server = SoftwareSigningKey()
    let accountID = "membership-test-account"
    let serverURL = "http://127.0.0.1:8766"
    private let wrongKey = SoftwareSigningKey()
    private let lock = NSRecursiveLock()
    private var state = State()
    private var devices: [Device] = []

    func inspect<T>(_ body: (State) throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body(state)
    }

    func change(_ body: (inout State) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&state)
    }

    func makeDevice(_ name: String, enrolled: Bool = false) throws -> Device {
        lock.lock(); defer { lock.unlock() }
        let device = Device(name)
        devices.append(device)
        if enrolled {
            state.members[name] = Member(key: device.key.publicKey)
            var saved = ClientState(configuration: configuration())
            saved.enrollment = EnrollResponse(accountID: accountID, deviceID: name,
                publicKey: device.key.publicKey, serverPublicKey: server.publicKey)
            device.saved = try encode(saved)
        }
        return device
    }

    func configuration(bootstrapToken: String = "") -> ClientConfiguration {
        ClientConfiguration(serverURL: serverURL, bootstrapToken: bootstrapToken,
            serverPublicKey: server.publicKey, audience: "membership-test-audience")
    }

    func client(_ device: Device, bootstrapToken: String = "") throws -> ProtocolClient {
        let platform = ClientPlatform(
            enroll: { try self.enroll(device, challenge: $0) },
            signRootMessage: { message in
                self.lock.lock(); defer { self.lock.unlock() }
                device.rootMessages.append(message)
                return try device.key.sign(message: message)
            },
            post: { try self.post(sender: device, url: $0, body: $1, token: $2) },
            readState: {
                self.lock.lock(); defer { self.lock.unlock() }
                return device.saved
            },
            writeState: { try self.write(device, bytes: $0) },
            now: { self.inspect { $0.now } })
        return try ProtocolClient(configuration: configuration(bootstrapToken: bootstrapToken), platform: platform)
    }

    func saved(_ device: Device) throws -> ClientState? {
        lock.lock(); defer { lock.unlock() }
        return try device.saved.map { try JSONDecoder().decode(ClientState.self, from: $0) }
    }

    func generationCount(_ device: Device) -> Int {
        lock.lock(); defer { lock.unlock() }
        return device.generationCalls
    }

    func failWrite(_ device: Device, at stage: WriteStage) {
        lock.lock(); defer { lock.unlock() }
        device.failWrite = stage
    }

    private func write(_ device: Device, bytes: Data) throws {
        lock.lock(); defer { lock.unlock() }
        let next = try JSONDecoder().decode(ClientState.self, from: bytes)
        let stage: WriteStage = next.enrollment != nil ? .enrollment :
            next.pairingCandidate != nil ? .candidate : next.pendingPairingEvidence != nil ? .evidence : .invitation
        if device.failWrite == stage { device.failWrite = nil; throw Failure.persistence }
        device.saved = bytes
    }

    private func enroll(_ device: Device, challenge: Data) throws -> AndroidEnrollmentEvidence {
        lock.lock(); defer { lock.unlock() }
        guard let saved = try saved(device), saved.pendingPairing?.attestationChallenge == challenge,
              device.boundChallenge == nil || device.boundChallenge == challenge else { throw Failure.unsafeGeneration }
        device.boundChallenge = challenge
        device.generationCalls += 1
        return AndroidEnrollmentEvidence(publicKey: device.key.publicKey,
            certificateChain: [device.fakeCertificate], platform: "androidStrongBox")
    }

    private func post(sender: Device, url: String, body: Data, token: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard url.hasPrefix(serverURL + "/v1/"), token.isEmpty else { throw Failure.invalidRequest }
        let path = String(url.dropFirst(serverURL.count))
        state.requests[path, default: 0] += 1
        switch path {
        case "/v1/pairings/challenge":
            let request: PairingChallengeRequest = try decode(body)
            guard request.accountID == accountID else { throw Failure.invalidRequest }
            let id = "candidate-\(state.requests[path, default: 0])"
            let challenge = challenge(deviceID: id, operation: .enroll, sequence: 1,
                payload: ProtocolCrypto.sha256(Data("swiftkey-pairing-v1".utf8)), lifetime: 900)
            let invitation = BootstrapChallengeResponse(challenge: challenge,
                attestationChallenge: ProtocolCrypto.sha256(try challenge.canonicalBytes()))
            state.invitations[id] = invitation
            return try encode(invitation)

        case "/v1/pairings/enroll":
            let request: EnrollRequest = try decode(body)
            guard request.challenge == state.invitations[request.challenge.deviceID]?.challenge,
                  request.certificates == [sender.fakeCertificate],
                  ProtocolCrypto.verify(signature: request.proof,
                    message: try request.challenge.canonicalBytes(), publicKey: sender.key.publicKey)
            else { throw Failure.invalidRequest }
            try request.challenge.validate(now: state.now)
            let candidate = PairingCandidate(accountID: accountID, deviceID: request.challenge.deviceID,
                publicKey: state.wrongCandidateKey ? wrongKey.publicKey : sender.key.publicKey,
                expiresAt: request.challenge.expiresAt)
            state.candidates[candidate.deviceID] = candidate
            if state.loseCandidateResponse { state.loseCandidateResponse = false; throw Failure.transport }
            return try encode(candidate)

        case "/v1/challenges":
            let request: ChallengeRequest = try decode(body)
            guard request.accountID == accountID, let member = state.members[request.deviceID] else {
                return try reject("unknownDevice")
            }
            guard member.active else { return try reject("revokedDevice") }
            let challenge = challenge(deviceID: request.deviceID, operation: request.operation,
                sequence: member.sequence + 1, payload: request.payloadHash, lifetime: 300)
            state.challenges[challenge.nonce] = challenge
            return try encode(challenge)

        case "/v1/pairings/approve", "/v1/pairings/confirm", "/v1/devices/revoke":
            let request: MembershipRequest = try decode(body)
            let expected: SwiftKeyCore.Operation = path == "/v1/pairings/approve" ? .addDevice :
                path == "/v1/pairings/confirm" ? .enroll : .revokeDevice
            guard request.change.operation == expected else { throw Failure.invalidRequest }
            try verify(request.authorization, operation: expected, payload: request.change.canonicalBytes())
            state.memberships.append(request)
            if state.rejectMutation { return try encode(MutationResponse(accepted: false)) }
            switch expected {
            case .addDevice:
                guard let candidate = state.candidates[request.change.deviceID],
                      candidate.publicKey == request.change.publicKey,
                      candidate.expiresAt > state.now else { throw Failure.invalidRequest }
                state.members[candidate.deviceID] = Member(key: candidate.publicKey)
                state.candidates.removeValue(forKey: candidate.deviceID)
            case .enroll:
                guard request.authorization.challenge.deviceID == request.change.deviceID,
                      state.members[request.change.deviceID]?.key == request.change.publicKey else {
                    throw Failure.invalidRequest
                }
            case .revokeDevice:
                guard request.change.publicKey == nil, state.members[request.change.deviceID]?.active == true,
                      request.change.deviceID != request.authorization.challenge.deviceID else {
                    throw Failure.invalidRequest
                }
                state.members[request.change.deviceID]?.active = false
            default: throw Failure.invalidRequest
            }
            consume(request.authorization)
            if expected == .enroll {
                if state.loseConfirmationResponse { state.loseConfirmationResponse = false; throw Failure.transport }
                return try encode(EnrollResponse(accountID: accountID,
                    deviceID: state.wrongConfirmationDevice ? "unexpected-device" : request.change.deviceID,
                    publicKey: try requireKey(request.change.publicKey),
                    serverPublicKey: state.wrongConfirmationPin ? wrongKey.publicKey : server.publicKey))
            }
            return try encode(MutationResponse())

        case "/v1/recovery":
            let request: RecoveryRequest = try decode(body)
            try verify(request.authorization, operation: .recoverDevice, payload: request.change.canonicalBytes())
            guard request.change.lostDeviceID != request.authorization.challenge.deviceID,
                  state.members[request.change.lostDeviceID]?.active == true,
                  let replacement = state.candidates[request.change.replacementDeviceID],
                  replacement.publicKey == request.change.publicKey, replacement.expiresAt > state.now else {
                throw Failure.invalidRequest
            }
            state.recoveries.append(request)
            if state.rejectMutation { return try encode(MutationResponse(accepted: false)) }
            state.members[replacement.deviceID] = Member(key: replacement.publicKey)
            state.members[request.change.lostDeviceID]?.active = false
            state.candidates.removeValue(forKey: replacement.deviceID)
            consume(request.authorization)
            return try encode(MutationResponse())
        default: throw Failure.invalidRequest
        }
    }

    private func verify(_ authorization: RootAuthorization, operation: SwiftKeyCore.Operation, payload: Data) throws {
        let value = authorization.challenge
        guard value.accountID == accountID, value.operation == operation,
              value.payloadHash == ProtocolCrypto.sha256(payload), state.challenges[value.nonce] == value,
              let member = state.members[value.deviceID], member.active,
              value.sequence == member.sequence + 1 else { throw Failure.invalidRequest }
        try ProtocolValidation.verifyAuthorization(authorization, publicKey: member.key, now: state.now)
    }

    private func consume(_ authorization: RootAuthorization) {
        let value = authorization.challenge
        state.members[value.deviceID]?.sequence = value.sequence
        state.challenges = state.challenges.filter { $0.value.deviceID != value.deviceID }
    }

    private func challenge(deviceID: String, operation: SwiftKeyCore.Operation,
                           sequence: UInt64, payload: Data, lifetime: UInt64) -> ChallengeEnvelope {
        ChallengeEnvelope(accountID: accountID, deviceID: deviceID, operation: operation,
            sequence: sequence, nonce: ProtocolCrypto.randomNonce(), expiresAt: state.now + lifetime, payloadHash: payload)
    }

    private func requireKey(_ key: Data?) throws -> Data {
        guard let key else { throw Failure.invalidRequest }; return key
    }
    private func reject(_ code: String) throws -> Data { try encode(AuthorityErrorResponse(code: code, error: "Test rejection")) }
    private func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
    private func decode<T: Decodable>(_ data: Data) throws -> T { try JSONDecoder().decode(T.self, from: data) }
}
