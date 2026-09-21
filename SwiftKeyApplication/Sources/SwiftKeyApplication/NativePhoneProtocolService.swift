import Foundation
import SwiftKeyCore
import SwiftKeyClient

/// The native adapter owns a verified client. Public view state contains no
/// authority bearer, invitation capability, private leaf, or raw server error.
public actor NativePhoneProtocolService: PhoneProtocolService {
    private let client: PairingClient
    private var active = false
    public init(client: PairingClient) { self.client = client }

    public func invitation(for binding: PhoneProtocolBinding) async throws -> String {
        let current = try project(await client.snapshot())
        guard !active, current.phase == .invitation, current.binding == binding,
              binding.expiresAt > (await client.snapshot()).now else { throw PhoneProtocolFailure.staleBinding }
        return try await client.invitationLink()
    }

    public func perform(_ action: PhoneProtocolAction, requestID: String) async throws -> PhoneProtocolSnapshot {
        guard !active else { throw PhoneProtocolFailure.busy }
        active = true; defer { active = false }
        let before = await client.snapshot()
        let review = try project(before)
        if let failure = review.rejection(for: action, now: before.now) {
            var rejected = review; rejected.failure = failure; return rejected
        }
        do {
            switch action {
            case .refresh, .resume: try await client.refresh()
            case .recover(let id): try await client.recover(requestID: id)
            case .prepareIdentity: try await client.prepareIdentity(requestID: requestID)
            case .renewIdentity: try await client.renewIdentity(requestID: requestID)
            case .createPairing: try await client.createPairing(requestID: requestID)
            case .inspectInvitation(let input): try await client.inspectInvitation(input.secretLink)
            case .join: try await client.join(requestID: requestID)
            case .confirmPeers: try await client.confirmPair(requestID: requestID)
            case .rejectPeers, .rejectProposal: try await client.control(.reject, requestID: requestID)
            case .proposeAccount(_, let label, let policy):
                guard policy == .survivor else { throw PhoneProtocolFailure.invalidAction }
                try await client.proposeAccount(label: label, requestID: requestID)
            case .replaceGenesis(_, let label, let policy):
                guard policy == .survivor else { throw PhoneProtocolFailure.invalidAction }
                try await client.replaceGenesis(label: label, requestID: requestID)
            case .approveGenesis: try await client.approveGenesis(requestID: requestID)
            case .rotateUnjoinedSecret: try await client.control(.rotateUnjoinedSecret, requestID: requestID)
            case .signIn:
                try await client.signIn(requestID: requestID)
                _ = try await client.ensureCurrentCredential()
            case .beginOwnerChange(let kind, _, _, let target):
                guard kind != .revoke else { throw PhoneProtocolFailure.unavailable }
                try await client.beginOwnerChange(replacing: kind == .replace ? target : nil, requestID: requestID)
            case .proposeMembership: try await client.proposeMembership(requestID: requestID)
            case .approveMembership: try await client.approveMembership(requestID: requestID)
            case .approveRevocation: throw PhoneProtocolFailure.unavailable
            case .cancel:
                if before.operation == nil { try await client.discardInspection() }
                else { try await client.control(.cancel, requestID: requestID) }
            case .restart: try await client.restart()
            }
            return try project(await client.snapshot())
        } catch {
            let latest = await client.snapshot()
            var result = try project(latest)
            if latest.pendingRequestID != nil {
                result.phase = .outcomeUnknown; result.failure = .outcomeUnknown
            } else if let failure = error as? PhoneProtocolFailure { result.failure = failure }
            else if let error = error as? PairingClientError {
                switch error {
                case .expired: result.failure = .expired
                case .membershipRevoked: result.phase = .revoked; result.failure = .trustUnavailable
                case .receiptMismatch, .rollback: result.failure = .invalidProjection
                case .staleReview: result.failure = .staleBinding
                case .outcomeUnknown: result.failure = .outcomeUnknown
                default: result.failure = .invalidAction
                }
            } else if case ClientError.serverRejected(let code) = error {
                if code == "revokedDevice" { result.phase = .revoked; result.failure = .trustUnavailable }
                else if code == "trustExpired" || code == "trustUnavailable" {
                    result.phase = .trustUnavailable; result.failure = .trustUnavailable
                } else { result.failure = .unavailable }
            } else { result.failure = .unavailable }
            return result
        }
    }

    func project(_ source: PairingClientSnapshot) throws -> PhoneProtocolSnapshot {
        let config = source.configuration, localID = source.identity?.payload.deviceID
        func phone(_ owner: PairingV2.OwnerDescriptor) -> PhoneIdentity {
            .init(id: owner.deviceID, label: owner.deviceID == localID ? "This phone" : "Other phone",
                fingerprint: hex(ProtocolCrypto.sha256(owner.rootPublicKey)), rootKind: "Android StrongBox P-256",
                trust: "Verified hardware identity", rootKeyEpoch: owner.rootKeyEpoch, isCurrent: owner.deviceID == localID)
        }
        var result = PhoneProtocolSnapshot(phase: source.identity == nil ? .introduction : .invitation,
            availability: .nativeReady, authorityID: hex(config.authorityID), origin: config.serverURL,
            audience: config.audience, localIdentity: try source.identity.map { phone(try $0.payload.ownerDescriptor()) },
            lastRequestID: source.pendingRequestID)
        if let own = source.identity?.payload, source.now >= own.leaseExpiresAt {
            result.localIdentity?.trust = "Hardware trust lease expired"
        }
        func setExisting(_ context: PairingV2.PairingContext, candidate: PairingV2.OwnerDescriptor? = nil,
                         authorizer: PairingV2.OwnerDescriptor? = nil, resultingOwners: [PairingV2.OwnerDescriptor] = []) {
            guard let account = context.existingAccount else { return }
            result.accountID = account.accountID; result.accountLabel = account.accountLabel
            result.membershipRevision = account.membershipRevision; result.owners = account.existingOwners.map(phone)
            result.authorizingOwnerID = authorizer?.deviceID
            result.change = .init(kind: context.purpose == .replaceOwner ? .replace : .add,
                targetOwnerID: account.lostOwner?.deviceID, candidate: candidate.map(phone), resultingOwners: resultingOwners.map(phone))
        }
        if let credential = source.credential, let bounds = try? Epoch.bounds(for: credential.delegation.epoch),
           bounds.start <= source.now, source.now < bounds.end {
            result.credentialStatus = "Epoch \(credential.delegation.epoch) verified · expires \(bounds.end)"
        } else { result.credentialStatus = "No current epoch credential" }
        if let operation = source.operation ?? source.committedOperation {
            let state = operation.state
            result.binding = .init(objectID: state.scopeID, revision: state.revision,
                digest: hex(state.objectHash), expiresAt: state.phaseExpiresAt)
            if let inspection = operation.inspection?.payload {
                result.phase = .invitation
                setExisting(inspection.context, authorizer: inspection.initiator)
            }
            if let transcript = operation.transcript?.payload {
                result.peer = transcript.owners.first { $0.deviceID != localID }.map(phone)
                result.owners = transcript.owners.map(phone)
                result.progress = .init(localAccepted: state.approvedSignerIDs.contains(localID ?? ""),
                    peerAccepted: state.approvedSignerIDs.contains(result.peer?.id ?? ""))
                result.phase = result.progress.localAccepted ? .waitingForPairConsent : .comparePeers
                let existingIDs = Set(transcript.context.existingAccount?.existingOwners.map(\.deviceID) ?? [])
                setExisting(transcript.context,
                    candidate: transcript.owners.first { !existingIDs.contains($0.deviceID) },
                    authorizer: transcript.owners.first { existingIDs.contains($0.deviceID) })
                if operation.pairReceipt != nil { result.phase = .paired; result.progress = .init(localAccepted: true, peerAccepted: true) }
            }
            if let genesis = operation.genesis?.payload {
                result.accountID = genesis.accountID; result.accountLabel = genesis.label
                result.owners = genesis.owners.map(phone); result.membershipRevision = genesis.initialMembershipRevision
                result.progress = .init(localAccepted: state.approvedSignerIDs.contains(localID ?? ""),
                    peerAccepted: state.approvedSignerIDs.contains(result.peer?.id ?? ""))
                result.phase = result.progress.localAccepted ? .waitingForGenesisConsent : .reviewGenesis
            }
            if let proposal = operation.membershipProposal?.payload {
                setExisting(proposal.context, candidate: proposal.candidate, authorizer: proposal.authorizingOwner,
                    resultingOwners: proposal.resultingOwners)
                result.progress = .init(localAccepted: state.approvedSignerIDs.contains(localID ?? ""),
                    peerAccepted: state.approvedSignerIDs.contains(result.peer?.id ?? ""))
                result.phase = result.progress.localAccepted ? .waitingForMembershipConsent : .reviewMembership
            }
            if let receipt = operation.accountReceipt?.payload {
                result.receipt = .init(operationID: receipt.genesis.proposalID, accountID: receipt.genesis.accountID,
                    proposalDigest: hex(try receipt.genesis.digest()), ledgerSequence: receipt.ledgerLastSequence,
                    ledgerHash: hex(receipt.ledgerHeadHash), verified: true)
                result.membershipRevision = receipt.membershipRevision; result.phase = .committed
            }
            if let receipt = operation.membershipReceipt?.payload, let account = receipt.proposal.context.existingAccount {
                result.receipt = .init(operationID: receipt.proposal.proposalID, accountID: account.accountID,
                    proposalDigest: hex(try receipt.proposal.digest()), ledgerSequence: receipt.ledgerLastSequence,
                    ledgerHash: hex(receipt.ledgerHeadHash), verified: true)
                result.owners = receipt.proposal.resultingOwners.map(phone)
                result.membershipRevision = receipt.membershipRevision; result.phase = .committed
            }
            switch state.status {
            case .cancelled: result.phase = .cancelled
            case .rejected: result.phase = .rejected
            case .expired: result.phase = .expired
            case .invalidated: result.phase = .invalidated
            default: break
            }
            if !state.status.isTerminal && source.now >= state.phaseExpiresAt { result.phase = .expired }
            if result.phase == .committed, source.signedIn { result.phase = .owners }
        } else if let inspection = source.inspection?.payload {
            result.phase = .inspectInvitation
            result.binding = .init(objectID: inspection.pairingID, revision: inspection.revision,
                digest: hex(try inspection.digest()), expiresAt: inspection.expiresAt)
            result.peer = phone(inspection.initiator)
            setExisting(inspection.context, authorizer: inspection.initiator)
            if source.now >= inspection.expiresAt { result.phase = .expired }
        }
        if let roster = source.roster?.payload, result.phase == .owners || result.phase == .committed {
            result.accountID = roster.accountID; result.accountLabel = roster.accountLabel
            result.membershipRevision = roster.membershipRevision; result.owners = roster.owners.map(phone)
            if !roster.owners.contains(where: { $0.deviceID == localID }) { result.phase = .revoked }
        }
        if let identity = source.identity?.payload, source.now >= identity.leaseExpiresAt,
           ![.cancelled, .rejected, .invalidated, .expired, .revoked].contains(result.phase) {
            result.phase = .trustUnavailable
        }
        if source.identity == nil, source.admissionFailure != nil {
            result.phase = .trustUnavailable; result.failure = .trustUnavailable
        }
        if source.pendingRequestID != nil { result.phase = .outcomeUnknown; result.failure = .outcomeUnknown }
        return result
    }
    private func hex(_ bytes: Data) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
}
