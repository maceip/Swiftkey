/// In-memory scheduling for a native host's background read and explicit actions.
/// The host serializes access (the Android session is an actor). A queued action
/// retains its original review binding; the store validates it after the read.
public struct PhoneProtocolActionSchedule: Sendable {
    public enum Decision: Sendable, Equatable { case start, deferred, busy }
    public enum Intent: Sendable, Equatable {
        case action(PhoneProtocolAction)
        case presentInvitation(PhoneProtocolBinding)
    }
    public private(set) var isPerforming = false
    private var quietRead = false
    private var deferredIntent: Intent?

    public init() {}

    public mutating func begin(_ action: PhoneProtocolAction, quiet: Bool = false) -> Decision {
        begin(.action(action), quiet: quiet, isRefresh: action == .refresh)
    }

    public mutating func beginInvitation(_ binding: PhoneProtocolBinding) -> Decision {
        begin(.presentInvitation(binding), quiet: false, isRefresh: false)
    }

    private mutating func begin(_ intent: Intent, quiet: Bool, isRefresh: Bool) -> Decision {
        if isPerforming {
            guard quietRead, !quiet, deferredIntent == nil else { return .busy }
            deferredIntent = intent
            return .deferred
        }
        isPerforming = true
        quietRead = quiet && isRefresh
        return .start
    }

    public mutating func finish() -> Intent? {
        let next = deferredIntent
        deferredIntent = nil; quietRead = false; isPerforming = false
        return next
    }

    /// Background reads keep the same enabled/layout state. Once the user asks
    /// for an action, visible busy state prevents another tap from being queued.
    public func presentation(_ snapshot: PhoneProtocolSnapshot) -> PhoneProtocolSnapshot {
        var result = snapshot
        if quietRead && deferredIntent == nil { result.busy = false }
        return result
    }

    /// Rechecked before and after retrieving a private invitation. The service
    /// independently verifies its deadline and refuses an active operation.
    public static func canPresentInvitation(_ binding: PhoneProtocolBinding,
                                            in snapshot: PhoneProtocolSnapshot) -> Bool {
        !snapshot.busy && snapshot.phase == .invitation && snapshot.binding == binding
    }
}
