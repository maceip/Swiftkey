import Foundation
import SwiftUICore
import SwiftKeyUI
import SwiftKeyApplication

// Development-only public fixtures. These do not represent attested devices.
struct JSONTree: Encodable {
    let type: String
    let id: String
    let props: [String: JSONValue]
    let modifiers: [JSONModifier]
    let children: [JSONTree]
    init(_ node: RenderNode) {
        type = node.type; id = node.id
        props = node.props.mapValues(JSONValue.init)
        modifiers = node.modifiers.map { JSONModifier(kind: $0.kind, args: $0.args.mapValues(JSONValue.init)) }
        children = node.children.map(JSONTree.init)
    }
}
struct JSONModifier: Encodable { let kind: String; let args: [String: JSONValue] }
enum JSONValue: Encodable {
    case string(String), number(Double), bool(Bool), array([JSONValue])
    init(_ value: PropValue) {
        switch value {
        case .string(let x): self = .string(x)
        case .int(let x): self = .string(String(x))
        case .double(let x): self = x.isFinite ? .number(x) : .string(String(x))
        case .bool(let x): self = .bool(x)
        case .array(let x): self = .array(x.map(JSONValue.init))
        }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let x): try c.encode(x)
        case .number(let x): try c.encode(x)
        case .bool(let x): try c.encode(x)
        case .array(let x): try c.encode(x)
        }
    }
}
struct Surface: Encodable {
    let id: String
    let title: String
    let tree: JSONTree
    let actions: [String: String]
}
func nodes(_ node: RenderNode) -> [RenderNode] { [node] + node.children.flatMap(nodes) }

@MainActor func makeSurfaces() -> [Surface] {
    let now: UInt64 = 1_800_000_000
    let a = PhoneIdentity(id: "00000000-0000-4000-8000-000000000001", label: "Your phone · fixture",
                          fingerprint: String(repeating: "a1b2", count: 16), trust: "Synthetic accepted trust", isCurrent: true)
    let b = PhoneIdentity(id: "00000000-0000-4000-8000-000000000002", label: "Second phone · fixture",
                          fingerprint: String(repeating: "c3d4", count: 16), trust: "Synthetic accepted trust")
    let c = PhoneIdentity(id: "00000000-0000-4000-8000-000000000003", label: "Replacement phone · fixture",
                          fingerprint: String(repeating: "e5f6", count: 16), trust: "Synthetic accepted trust")
    let binding = PhoneProtocolBinding(objectID: "00000000-0000-4000-8000-000000000010", revision: 3,
                                       digest: "a1b2c3d4e5f60718293a" + String(repeating: "b", count: 44), expiresAt: now + 93)
    let account = "00000000-0000-4000-8000-000000000020"
    var fixtures: [(String, String, PhoneProtocolSnapshot)] = []
    for (index, phase) in PhoneProtocolPhase.allCases.enumerated() {
        var s = PhoneProtocolSnapshot(phase: phase, availability: .nativeReady, binding: binding,
            authorityID: String(repeating: "0123456789abcdef", count: 4), origin: "https://authority.example", audience: "swiftkey-authority-v2",
            accountID: account, accountLabel: "Personal account · fixture", membershipRevision: 3,
            localIdentity: a, peer: b, owners: [a, b], lastRequestID: "00000000-0000-4000-8000-000000000030")
        switch phase {
        case .introduction: s.binding = nil; s.accountID = nil; s.localIdentity = nil; s.peer = nil; s.owners = []
        case .preparingIdentity: s.busy = true; s.accountID = nil; s.peer = nil; s.owners = []
        case .invitation:
            s.accountID = nil; s.peer = nil
        case .importingInvitation, .inspectInvitation, .comparePeers, .waitingForPairConsent, .paired:
            s.accountID = nil
        case .committed, .signIn, .owners, .chooseOwnerChange:
            s.receipt = PhoneCommitReceipt(operationID: binding.objectID, accountID: account,
                proposalDigest: binding.digest, ledgerSequence: 42, ledgerHash: String(repeating: "abcd", count: 16), verified: true)
        case .reviewMembership, .waitingForMembershipConsent:
            s.change = PhoneMembershipChange(kind: .replace, targetOwnerID: b.id, candidate: c, resultingOwners: [a, c]); s.peer = c
            s.authorizingOwnerID = a.id
        case .reviewRevocation:
            s.owners = [a, b, c]
            s.change = PhoneMembershipChange(kind: .revoke, targetOwnerID: b.id, resultingOwners: [a, c])
        case .reviewBrowserLogin:
            s.browserRequest = PhoneBrowserRequest(origin: "https://workspace.example", scopes: ["account:read", "credential:verify"], expiresAt: now + 120)
        case .trustUnavailable: s.failure = .trustUnavailable; s.localIdentity?.trust = "Lease expired · fixture"
        case .renewingTrust: s.busy = true
        case .revoked: s.localIdentity?.revoked = true
        case .expired: s.binding?.expiresAt = now - 1
        case .outcomeUnknown: s.failure = .outcomeUnknown
        default: break
        }
        if [.waitingForPairConsent, .waitingForGenesisConsent, .waitingForMembershipConsent].contains(phase) {
            s.progress = .init(localAccepted: true, peerAccepted: false)
        }
        let title = phase.rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        fixtures.append((phase.rawValue, String(format: "%02d", index + 1) + " / " + title.capitalized, s))
    }
    var unavailable = PhoneProtocolSnapshot()
    fixtures.append(("unavailable", "Service not implemented / safe default", unavailable))
    unavailable.phase = .reviewGenesis; unavailable.availability = .browserReadOnly
    unavailable.binding = binding; unavailable.owners = [a,b]; unavailable.accountID = account
    fixtures.append(("browser", "Browser / signing unavailable", unavailable))
    if var review = fixtures.first(where: { $0.0 == "reviewMembership" })?.2 {
        var existing = review
        for phase in [PhoneProtocolPhase.inspectInvitation, .comparePeers, .paired] {
            existing.phase = phase
            fixtures.append(("existing-" + phase.rawValue, "Replace phone / " + phase.rawValue, existing))
        }
        var candidateReview = review
        var candidate = c; candidate.isCurrent = true
        var authorizer = a; authorizer.isCurrent = false
        candidateReview.localIdentity = candidate; candidateReview.peer = authorizer
        candidateReview.owners = [authorizer, b]
        candidateReview.change = .init(kind: .replace, targetOwnerID: b.id, candidate: candidate, resultingOwners: [authorizer, candidate])
        fixtures.append(("candidateConsent", "Candidate / join existing account consent", candidateReview))
        review.change = PhoneMembershipChange(kind: .add, candidate: c, resultingOwners: [a,b,c])
        fixtures.append(("addOwner", "Add phone / full resulting roster", review))
        review.busy = true
        fixtures.append(("busy", "Approval in flight / controls disabled", review))
        review.busy = false; review.binding?.expiresAt = now
        fixtures.append(("expiredReview", "Review at exact deadline / controls disabled", review))
    }
    if var committed = fixtures.first(where: { $0.0 == "committed" })?.2 {
        committed.receipt?.verified = false
        fixtures.append(("unverifiedReceipt", "Receipt verification failed / no success", committed))
        committed.receipt?.verified = true
        committed.binding?.expiresAt = now - 1
        committed.phase = .signIn
        committed.change = .init(kind: .add, candidate: b, resultingOwners: [a,b])
        fixtures.append(("signInRetry", "Phone added / sign-in needs retry", committed))
    }
    if var imported = fixtures.first(where: { $0.0 == "inspectInvitation" })?.2 {
        imported.localIdentity = nil
        fixtures.append(("inspectBeforePreparation", "Scanned first / prepare final local root before joining", imported))
    }
    if var renew = fixtures.first(where: { $0.0 == "trustUnavailable" })?.2 {
        renew.binding = nil; renew.lastRequestID = nil
        renew.localIdentity?.trust = "Lease expired · retained StrongBox root"
        fixtures.append(("renewRetainedIdentity", "Expired lease / explicitly renew the retained hardware identity", renew))
        renew.localIdentity = nil; renew.peer = nil; renew.owners = []; renew.accountID = nil
        fixtures.append(("admissionUnavailable", "Identity admission failed / no renewal or silent root replacement", renew))
    }
    if var owner = fixtures.first(where: { $0.0 == "owners" })?.2 {
        owner.credentialStatus = "Epoch 3000000 verified · expires 1800000300"
        fixtures.append(("epochReady", "Owner signed in / current epoch credential verified", owner))
        owner.phase = .committed
        owner.credentialStatus = "No current epoch credential"
        fixtures.append(("epochMissing", "Account committed / epoch credential still unavailable", owner))
    }
    return fixtures.map { id, title, snapshot in
        var observed = "", actions: [String: String] = [:]
        let host = ViewHost(PhoneProtocolView(snapshot: snapshot, drafts: .constant(.init(accountLabel: "Personal account")), now: now,
            effects: [.camera, .manualImport, .invitationPresentation],
            onAction: { observed = String(describing: $0) }, onEffect: { observed = String(describing: $0) }))
        let tree = host.evaluate()
        for node in nodes(tree) {
            if case .int(let callback) = node.props["onTap"] {
                observed = "Blocked by shared state guard"
                host.callbacks.invokeVoid(Int64(callback)); actions[String(callback)] = observed
            }
        }
        return Surface(id: id, title: title, tree: JSONTree(tree), actions: actions)
    }
}

let destination = CommandLine.arguments.dropFirst().first ?? "/tmp/swiftkey-phone-surfaces.json"
let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(makeSurfaces()).write(to: URL(fileURLWithPath: destination), options: .atomic)
print("Exported shared Swift phone surfaces to \(destination)")
