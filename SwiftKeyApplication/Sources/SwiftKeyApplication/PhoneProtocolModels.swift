import Foundation

/// Presentation projections for the v2 protocol, not cryptographic
/// evidence. Only an adapter that verifies canonical transcripts, signatures,
/// pinned authority, deadlines and current trust may supply live projections.
public enum PhoneProtocolPhase: String, Codable, CaseIterable, Sendable {
    case introduction, preparingIdentity, invitation, importingInvitation, inspectInvitation
    case comparePeers, waitingForPairConsent, paired, reviewGenesis, waitingForGenesisConsent
    case committed, signIn, owners, chooseOwnerChange, reviewMembership, waitingForMembershipConsent
    case reviewRevocation, reviewPolicy, reviewBrowserLogin, renewingTrust, trustUnavailable, revoked, cancelled, rejected, invalidated, expired, outcomeUnknown
}

public enum PhoneProtocolAvailability: String, Codable, Sendable {
    case notImplemented, browserReadOnly, nativeReady
}
public enum PhoneOwnershipPolicy: String, Codable, Sendable {
    case survivor = "two-owner-survivor-v1"
    public var warning: String {
        "Any current owner can add another owner or replace a lost owner with the new phone’s consent. A compromised owner can take over the account. At least two owners must remain. If all owners are lost, there is no administrative recovery."
    }
}

/// Every approval and cancellation identifies exactly what was displayed.
/// Adapters must revalidate this binding against durable state before signing.
public struct PhoneProtocolBinding: Codable, Equatable, Sendable {
    public var objectID: String
    public var revision: UInt64
    public var digest: String
    public var expiresAt: UInt64
    public init(objectID: String, revision: UInt64, digest: String, expiresAt: UInt64) {
        self.objectID = objectID; self.revision = revision; self.digest = digest; self.expiresAt = expiresAt
    }
}

public struct PhoneIdentity: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var fingerprint: String
    public var rootKind: String
    public var rootKeyEpoch: UInt64
    public var trust: String
    public var isCurrent: Bool
    public var revoked: Bool
    public init(id: String, label: String, fingerprint: String, rootKind: String = "Android StrongBox P-256",
                trust: String = "Not checked", rootKeyEpoch: UInt64 = 1, isCurrent: Bool = false, revoked: Bool = false) {
        self.id = id; self.label = label; self.fingerprint = fingerprint; self.rootKind = rootKind
        self.rootKeyEpoch = rootKeyEpoch; self.trust = trust; self.isCurrent = isCurrent; self.revoked = revoked
    }
}

public enum PhoneMembershipKind: String, Codable, Sendable { case add, replace, revoke }
public struct PhoneMembershipChange: Codable, Equatable, Sendable {
    public var kind: PhoneMembershipKind
    public var targetOwnerID: String?
    public var candidate: PhoneIdentity?
    public var resultingOwners: [PhoneIdentity]
    public init(kind: PhoneMembershipKind, targetOwnerID: String? = nil, candidate: PhoneIdentity? = nil,
                resultingOwners: [PhoneIdentity] = []) {
        self.kind = kind; self.targetOwnerID = targetOwnerID; self.candidate = candidate; self.resultingOwners = resultingOwners
    }
}

public struct PhoneConsentProgress: Codable, Equatable, Sendable {
    public var localAccepted: Bool
    public var peerAccepted: Bool
    public init(localAccepted: Bool = false, peerAccepted: Bool = false) {
        self.localAccepted = localAccepted; self.peerAccepted = peerAccepted
    }
}

/// A verified public receipt projection; `verified` is an adapter assertion,
/// never a substitute for verification of the underlying signed receipt.
public struct PhoneCommitReceipt: Codable, Equatable, Sendable {
    public var operationID: String
    public var accountID: String
    public var proposalDigest: String
    public var ledgerSequence: UInt64
    public var ledgerHash: String
    public var verified: Bool
    public init(operationID: String, accountID: String, proposalDigest: String, ledgerSequence: UInt64,
                ledgerHash: String, verified: Bool = false) {
        self.operationID = operationID; self.accountID = accountID; self.proposalDigest = proposalDigest
        self.ledgerSequence = ledgerSequence; self.ledgerHash = ledgerHash; self.verified = verified
    }
}

public enum PhoneProtocolFailure: String, Error, Codable, Sendable {
    case unavailable, busy, expired, staleBinding, invalidAction, invalidProjection, outcomeUnknown, trustUnavailable
    public var message: String {
        switch self {
        case .unavailable: "This host cannot perform this operation. Open a compatible native phone with the v2 service connected."
        case .busy: "Wait for the current operation to finish."
        case .expired: "This review has expired. Check the original operation before starting again."
        case .staleBinding: "The reviewed object changed. Refresh and review every detail again."
        case .invalidAction: "This action is not available at this step."
        case .invalidProjection: "The service response could not be verified. Check the original operation."
        case .outcomeUnknown: "The result is unknown. Check the original operation; do not repeat the approval or start a replacement."
        case .trustUnavailable: "Required hardware trust could not be established. Check the original operation before attempting another approval."
        }
    }
}

/// Safe public UI state. Never put QR secrets, links, root keys, authentication
/// tokens, attestation chains or raw server errors in this Codable snapshot.
public struct PhoneProtocolSnapshot: Codable, Equatable, Sendable {
    public var phase: PhoneProtocolPhase
    public var availability: PhoneProtocolAvailability
    public var busy: Bool
    public var binding: PhoneProtocolBinding?
    public var authorityID: String
    public var origin: String
    public var audience: String
    public var accountID: String?
    public var accountLabel: String
    public var membershipRevision: UInt64
    public var authorizingOwnerID: String?
    public var localIdentity: PhoneIdentity?
    public var peer: PhoneIdentity?
    public var owners: [PhoneIdentity]
    public var policy: PhoneOwnershipPolicy
    public var progress: PhoneConsentProgress
    public var change: PhoneMembershipChange?
    public var receipt: PhoneCommitReceipt?
    public var failure: PhoneProtocolFailure?
    public var lastRequestID: String?
    public var browserRequest: PhoneBrowserRequest?
    public var credentialStatus: String?
    public init(phase: PhoneProtocolPhase = .introduction, availability: PhoneProtocolAvailability = .notImplemented,
                busy: Bool = false, binding: PhoneProtocolBinding? = nil, authorityID: String = "", origin: String = "",
                audience: String = "", accountID: String? = nil, accountLabel: String = "", membershipRevision: UInt64 = 0,
                authorizingOwnerID: String? = nil,
                localIdentity: PhoneIdentity? = nil, peer: PhoneIdentity? = nil, owners: [PhoneIdentity] = [],
                policy: PhoneOwnershipPolicy = .survivor, progress: PhoneConsentProgress = .init(),
                change: PhoneMembershipChange? = nil, receipt: PhoneCommitReceipt? = nil, failure: PhoneProtocolFailure? = nil,
                lastRequestID: String? = nil, browserRequest: PhoneBrowserRequest? = nil, credentialStatus: String? = nil) {
        self.phase = phase; self.availability = availability; self.busy = busy; self.binding = binding
        self.authorityID = authorityID; self.origin = origin; self.audience = audience; self.accountID = accountID
        self.accountLabel = accountLabel; self.membershipRevision = membershipRevision; self.authorizingOwnerID = authorizingOwnerID; self.localIdentity = localIdentity
        self.peer = peer; self.owners = owners; self.policy = policy; self.progress = progress
        self.change = change; self.receipt = receipt; self.failure = failure
        self.lastRequestID = lastRequestID; self.browserRequest = browserRequest; self.credentialStatus = credentialStatus
    }
}

/// Intentionally not Codable; hosts obtain this only through a secure camera or
/// manual-entry effect. Do not log, persist, echo, or include it in a view tree.
public struct PhoneInvitationInput: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let secretLink: String
    public init(secretLink: String) { self.secretLink = secretLink }
    public var description: String { "<transient pairing invitation>" }
    public var debugDescription: String { description }
}

public enum PhoneProtocolAction: Sendable, Equatable {
    case refresh, recover(requestID: String), prepareIdentity, renewIdentity, createPairing, inspectInvitation(PhoneInvitationInput)
    case join(PhoneProtocolBinding), confirmPeers(PhoneProtocolBinding), rejectPeers(PhoneProtocolBinding)
    case proposeAccount(PhoneProtocolBinding, label: String, policy: PhoneOwnershipPolicy)
    case approveGenesis(PhoneProtocolBinding)
    case rotateUnjoinedSecret(PhoneProtocolBinding)
    case replaceGenesis(PhoneProtocolBinding, label: String, policy: PhoneOwnershipPolicy)
    case signIn(accountID: String, membershipRevision: UInt64)
    case beginOwnerChange(PhoneMembershipKind, accountID: String, membershipRevision: UInt64, targetOwnerID: String?)
    case proposeMembership(PhoneProtocolBinding)
    case approveMembership(PhoneProtocolBinding), approveRevocation(PhoneProtocolBinding)
    case rejectProposal(PhoneProtocolBinding)
    case cancel(PhoneProtocolBinding), resume(PhoneProtocolBinding), restart

    public var binding: PhoneProtocolBinding? {
        switch self {
        case .join(let b), .confirmPeers(let b), .rejectPeers(let b), .proposeAccount(let b, _, _),
             .approveGenesis(let b), .rotateUnjoinedSecret(let b), .replaceGenesis(let b, _, _), .proposeMembership(let b), .approveMembership(let b), .approveRevocation(let b),
             .cancel(let b), .rejectProposal(let b), .resume(let b): b
        default: nil
        }
    }
    public var isReadOnly: Bool {
        switch self { case .refresh, .resume, .recover: true; default: false }
    }
}

/// Pure shared guard for both native callbacks and stale browser callback IDs.
/// The verified service independently enforces all protocol authorization.
public extension PhoneProtocolSnapshot {
    func rejection(for action: PhoneProtocolAction, now: UInt64) -> PhoneProtocolFailure? {
        if busy { return .busy }
        if availability == .notImplemented { return .unavailable }
        if availability == .browserReadOnly && action != .refresh { return .unavailable }
        if let requested = action.binding, requested != binding { return .staleBinding }
        if action.isReadOnly {
            if case .resume = action, binding == nil { return .invalidAction }
            if case .recover(let id) = action, id != lastRequestID { return .staleBinding }
            return nil
        }
        if phase == .outcomeUnknown { return .outcomeUnknown }
        if (phase == .trustUnavailable && action != .renewIdentity) || phase == .revoked { return .trustUnavailable }
        if action.binding != nil, let binding, now >= binding.expiresAt { return .expired }
        if let b = action.binding, b.objectID.isEmpty || b.digest.isEmpty || b.revision == 0 || authorityID.isEmpty || origin.isEmpty || audience.isEmpty { return .invalidProjection }
        switch action {
        case .prepareIdentity: return [.introduction, .inspectInvitation].contains(phase) && localIdentity == nil ? nil : .invalidAction
        case .renewIdentity:
            return [.trustUnavailable, .renewingTrust].contains(phase) && localIdentity != nil && localIdentity?.revoked == false ? nil : .invalidAction
        case .createPairing: return phase == .invitation && localIdentity != nil && binding == nil ? nil : .invalidAction
        case .inspectInvitation(let input):
            return [.introduction, .importingInvitation, .invitation].contains(phase) && !input.secretLink.isEmpty ? nil : .invalidAction
        case .join: return phase == .inspectInvitation && validPair ? nil : .invalidAction
        case .confirmPeers, .rejectPeers:
            return phase == .comparePeers && validPair && !progress.localAccepted ? nil : .invalidAction
        case .rotateUnjoinedSecret:
            return phase == .invitation && peer == nil ? nil : .invalidAction
        case .replaceGenesis(_, let label, _):
            return [.reviewGenesis, .waitingForGenesisConsent].contains(phase) && validLabel(label) ? nil : .invalidAction
        case .proposeAccount(_, let label, _):
            return phase == .paired && change == nil && validLabel(label) ? nil : .invalidAction
        case .approveGenesis:
            return phase == .reviewGenesis && validPair && !progress.localAccepted && owners.count == 2
                && owners.allSatisfy({ !$0.revoked }) && owners.contains(where: { $0.sameRoot(as: localIdentity!) })
                && owners.contains(where: { $0.sameRoot(as: peer!) }) ? nil : .invalidAction
        case .signIn(let account, let revision):
            return [.committed, .signIn, .owners].contains(phase) && hasVerifiedReceipt
                && currentLocalOwner != nil && account == accountID && revision == membershipRevision ? nil : .invalidAction
        case .beginOwnerChange(let kind, let account, let revision, let target):
            if kind == .revoke { return .unavailable } // Its wire profile is not specified yet.
            guard [.owners, .chooseOwnerChange].contains(phase), account == accountID, revision == membershipRevision else { return .staleBinding }
            guard let localOwner = currentLocalOwner else { return .invalidAction }
            if kind == .add { return target == nil ? nil : .invalidAction }
            guard let target, target != localOwner.id, owners.contains(where: { $0.id == target && !$0.revoked }) else { return .invalidAction }
            if kind == .revoke && owners.filter({ !$0.revoked }).count <= 2 { return .invalidAction }
            return nil
        case .proposeMembership: return phase == .paired && change != nil ? nil : .invalidAction
        case .approveMembership:
            return phase == .reviewMembership && validMembershipChange && !progress.localAccepted && change?.kind != .revoke ? nil : .invalidAction
        case .approveRevocation:
            return .unavailable // Standalone revocation remains gated until its wire profile exists.
        case .rejectProposal:
            return [.reviewGenesis, .waitingForGenesisConsent, .reviewMembership, .waitingForMembershipConsent].contains(phase) ? nil : .invalidAction
        case .cancel:
            return [.invitation, .inspectInvitation, .comparePeers, .waitingForPairConsent, .paired, .reviewGenesis,
                    .waitingForGenesisConsent, .reviewMembership, .waitingForMembershipConsent, .reviewRevocation].contains(phase) ? nil : .invalidAction
        case .restart: return [.cancelled, .rejected, .invalidated, .expired].contains(phase) ? nil : .invalidAction
        case .refresh, .resume, .recover: return nil
        }
    }
    var hasVerifiedReceipt: Bool {
        guard let receipt, let binding else { return false }
        return receipt.verified && receipt.accountID == accountID && receipt.proposalDigest == binding.digest
            && receipt.operationID == binding.objectID && receipt.ledgerSequence > 0 && !receipt.ledgerHash.isEmpty
    }
    private func validLabel(_ label: String) -> Bool {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        return !normalized.isEmpty && normalized.utf8.count <= 120
            && !normalized.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
    private var validPair: Bool {
        guard let localIdentity, let peer else { return false }
        return !localIdentity.revoked && !peer.revoked && localIdentity.id != peer.id
            && !localIdentity.fingerprint.isEmpty && !peer.fingerprint.isEmpty
            && localIdentity.fingerprint.lowercased() != peer.fingerprint.lowercased()
    }
    private var currentLocalOwner: PhoneIdentity? {
        guard let localIdentity, !localIdentity.revoked else { return nil }
        return owners.first(where: { !$0.revoked && $0.sameRoot(as: localIdentity) })
    }
    private var validMembershipChange: Bool {
        guard let change, accountID != nil, membershipRevision > 0 else { return false }
        let current = owners.filter { !$0.revoked }, result = change.resultingOwners.filter { !$0.revoked }
        guard result.count >= 2, Set(result.map(\.id)).count == result.count else { return false }
        guard let authorizingOwnerID, current.contains(where: { $0.id == authorizingOwnerID }),
              change.targetOwnerID != authorizingOwnerID,
              Set(result.map { $0.fingerprint.lowercased() }).count == result.count,
              result.allSatisfy({ !$0.fingerprint.isEmpty }) else { return false }
        for owner in current where owner.id != change.targetOwnerID {
            guard result.contains(where: { $0.sameRoot(as: owner) }) else { return false }
        }
        if let candidate = change.candidate {
            guard !candidate.revoked, result.contains(where: { $0.sameRoot(as: candidate) }),
                  validPair, let localIdentity, let peer,
                  let authorizer = current.first(where: { $0.id == authorizingOwnerID }),
                  (localIdentity.sameRoot(as: authorizer) && peer.sameRoot(as: candidate))
                    || (localIdentity.sameRoot(as: candidate) && peer.sameRoot(as: authorizer)) else { return false }
        }
        let previousIDs = Set(current.map(\.id)), resultIDs = Set(result.map(\.id))
        switch change.kind {
        case .add:
            guard let candidate = change.candidate, !previousIDs.contains(candidate.id), change.targetOwnerID == nil else { return false }
            return resultIDs == previousIDs.union([candidate.id])
        case .replace, .revoke:
            guard let target = change.targetOwnerID, current.contains(where: { $0.id == target && !$0.isCurrent }) else { return false }
            if change.kind == .revoke { return change.candidate == nil && resultIDs == previousIDs.subtracting([target]) }
            guard let candidate = change.candidate, !previousIDs.contains(candidate.id) else { return false }
            return resultIDs == previousIDs.subtracting([target]).union([candidate.id])
        }
    }
}

/// Public review data only; the browser-login wire profile is still gated.
public struct PhoneBrowserRequest: Codable, Equatable, Sendable {
    public var origin: String
    public var scopes: [String]
    public var expiresAt: UInt64
    public init(origin: String, scopes: [String], expiresAt: UInt64) {
        self.origin = origin; self.scopes = scopes; self.expiresAt = expiresAt
    }
}

private extension PhoneIdentity {
    func sameRoot(as other: PhoneIdentity) -> Bool {
        id == other.id && fingerprint.lowercased() == other.fingerprint.lowercased()
            && rootKind == other.rootKind && rootKeyEpoch == other.rootKeyEpoch && revoked == other.revoked
    }
}
