import Foundation

/// NativePhoneProtocolService connects the verified hardware-backed v2 client.
/// Implementors own durable operation IDs, independently verify every authority
/// projection, and enforce exact request/binding/policy authorization.
/// A browser renderer must never implement this by signing on its user's behalf.
public protocol PhoneProtocolService: Sendable {
    func perform(_ action: PhoneProtocolAction, requestID: String) async throws -> PhoneProtocolSnapshot
}

/// Shared serialized action boundary. It performs presentation validation only;
/// it cannot establish hardware trust or verify a protocol receipt by itself.
public actor PhoneProtocolStore {
    private let service: (any PhoneProtocolService)?
    private let clock: @Sendable () -> UInt64
    private var value = PhoneProtocolSnapshot()
    private var generation: UInt64 = 0
    private var active: UUID?
    public init(service: (any PhoneProtocolService)? = nil,
                clock: @escaping @Sendable () -> UInt64 = { UInt64(max(0, Date().timeIntervalSince1970)) }) {
        self.service = service; self.clock = clock
    }
    public func snapshot() -> PhoneProtocolSnapshot { value }
    public func clearSession() { generation &+= 1; active = nil; value = .init() }

    @discardableResult public func send(_ action: PhoneProtocolAction) async -> PhoneProtocolSnapshot {
        guard let service else { var result = value; result.failure = .unavailable; return result }
        // Initial read is the only way to obtain a verified live projection.
        if !(action == .refresh && value.availability == .notImplemented && !value.busy),
           let failure = value.rejection(for: action, now: clock()) {
            var result = value; result.failure = failure; return result
        }
        let run = UUID(), session = generation, before = value
        let requestID: String
        if case .recover(let original) = action { requestID = original }
        else { requestID = UUID().uuidString.lowercased() }
        active = run; value.busy = true; value.failure = nil
        if !action.isReadOnly { value.lastRequestID = requestID }
        defer { if active == run { active = nil; value.busy = false } }
        do {
            let response = try await service.perform(action, requestID: requestID)
            guard generation == session else { return value }
            try validate(response, previous: before)
            value = response; value.busy = false
            if value.phase == .outcomeUnknown, value.lastRequestID == nil {
                value.lastRequestID = action.isReadOnly ? before.lastRequestID : requestID
            }
        } catch {
            guard generation == session else { return value }
            value = before; value.busy = false
            if action.isReadOnly {
                value.failure = (error as? PhoneProtocolFailure) ?? .unavailable
            } else {
                // Transport errors are not proof of rejection. Preserve the
                // original request identity and offer only result recovery.
                value.phase = .outcomeUnknown; value.failure = .outcomeUnknown
                value.lastRequestID = requestID
            }
        }
        return value
    }
    private func validate(_ projection: PhoneProtocolSnapshot, previous: PhoneProtocolSnapshot) throws {
        if let accountID = previous.accountID, accountID == projection.accountID,
           projection.membershipRevision < previous.membershipRevision { throw PhoneProtocolFailure.invalidProjection }
        if let old = previous.binding, let new = projection.binding, old.objectID == new.objectID {
            guard new.revision >= old.revision,
                  new.revision != old.revision || (new == old && projection.authorityID == previous.authorityID
                    && projection.origin == previous.origin && projection.audience == previous.audience) else {
                throw PhoneProtocolFailure.invalidProjection
            }
        }
        if let b = projection.binding {
            guard !b.objectID.isEmpty, !b.digest.isEmpty, b.revision > 0, b.expiresAt > 0 else {
                throw PhoneProtocolFailure.invalidProjection
            }
        }
        guard Set(projection.owners.map(\.id)).count == projection.owners.count else {
            throw PhoneProtocolFailure.invalidProjection
        }
        if projection.phase == .committed {
            guard projection.hasVerifiedReceipt,
                  projection.owners.filter({ !$0.revoked }).count >= 2 else {
                throw PhoneProtocolFailure.invalidProjection
            }
        }
    }
}
