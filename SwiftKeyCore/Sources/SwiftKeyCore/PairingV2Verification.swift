import Foundation

extension PairingV2.OwnerDescriptor {
    /// Membership identity is stable across trust-lease renewal; signed snapshots keep their captured receipt hash.
    public func hasSameRoot(as other: PairingV2.OwnerDescriptor) -> Bool {
        deviceID == other.deviceID && rootKind == other.rootKind && rootKeyEpoch == other.rootKeyEpoch
            && rootPublicKey == other.rootPublicKey && role == other.role
    }
}

extension PairingV2.DeviceTrustReceipt {
    public func ownerDescriptor() throws -> PairingV2.OwnerDescriptor {
        try validate()
        return .init(deviceID: deviceID, rootKind: rootKind, rootKeyEpoch: rootKeyEpoch,
                     rootPublicKey: rootPublicKey, attestationReceiptHash: try digest())
    }
}

extension PairingV2 {
    public static func verifyTrustReceipt(_ receipt: Signed<DeviceTrustReceipt>,
                    authorityPublicKey: Data, expectedOrigin: String,
                    challenge: PreEnrollmentChallenge? = nil, evidence: AttestationEvidence? = nil,
                    expectedRootPublicKey: Data? = nil, now: UInt64? = nil) throws {
        try receipt.verify(authorityPublicKey: authorityPublicKey)
        let value = receipt.payload
        try verifyContext(authorityID: value.authorityID, origin: value.origin, audience: value.audience,
                          authorityPublicKey: authorityPublicKey, expectedOrigin: expectedOrigin)
        if let challenge {
            guard value.deviceID == challenge.deviceID, value.rootKind == challenge.rootKind,
                  value.trustPolicyID == challenge.trustPolicyID,
                  value.originalChallengeHash == (try challenge.digest()),
                  value.authorityID == challenge.authorityID, value.origin == challenge.origin,
                  value.audience == challenge.audience else { throw Error.bindingMismatch }
        }
        if let evidence, value.evidenceHash != (try evidence.digest()) || value.rootKind != evidence.rootKind { throw Error.bindingMismatch }
        if let expectedRootPublicKey, value.rootPublicKey != expectedRootPublicKey { throw Error.bindingMismatch }
        if let now, now < value.verifiedAt || now >= value.leaseExpiresAt { throw Error.expired }
    }

    private static func acceptedProof(_ digest: Data, in proofs: [RootProof]) throws -> RootProof {
        let matches = try proofs.filter { try $0.digest() == digest }
        guard matches.count == 1, let result = matches.first else { throw Error.bindingMismatch }
        return result
    }

    /// Verifies both complete root approvals; authority signature alone does not supply owner consent.
    public static func verifyPairReceipt(_ receipt: Signed<PairReceipt>, proofs: [RootProof],
                                         authorityPublicKey: Data, expectedOrigin: String) throws {
        try receipt.verify(authorityPublicKey: authorityPublicKey)
        let transcript = receipt.payload.transcript
        try verifyContext(authorityID: transcript.authorityID, origin: transcript.origin, audience: transcript.audience,
                          authorityPublicKey: authorityPublicKey, expectedOrigin: expectedOrigin)
        for (owner, digest) in zip(transcript.owners, [receipt.payload.aConsentDigest, receipt.payload.bConsentDigest]) {
            let proof = try acceptedProof(digest, in: proofs)
            try verifyRootProof(proof, payload: transcript, owner: owner, authorityPublicKey: authorityPublicKey,
                                expectedOrigin: expectedOrigin, purpose: .confirmPair, scopeID: transcript.pairingID)
            guard proof.challenge.issuedAt >= transcript.issuedAt, proof.challenge.expiresAt <= transcript.expiresAt,
                  proof.challenge.issuedAt <= receipt.payload.confirmedAt else { throw Error.bindingMismatch }
        }
    }

    public static func verifyAccountReceipt(_ receipt: Signed<AccountReceipt>, pairReceipt: Signed<PairReceipt>,
                    proofs: [RootProof], authorityPublicKey: Data, expectedOrigin: String) throws {
        try receipt.verify(authorityPublicKey: authorityPublicKey)
        try verifyPairReceipt(pairReceipt, proofs: proofs, authorityPublicKey: authorityPublicKey, expectedOrigin: expectedOrigin)
        let value = receipt.payload, genesis = value.genesis, pair = pairReceipt.payload
        try verifyContext(authorityID: genesis.authorityID, origin: genesis.origin, audience: genesis.audience,
                          authorityPublicKey: authorityPublicKey, expectedOrigin: expectedOrigin)
        guard pair.transcript.context.purpose == .createAccount,
              genesis.owners == pair.transcript.owners, genesis.pairingID == pair.transcript.pairingID,
              genesis.pairTranscriptHash == (try pair.transcript.digest()), value.pairReceiptHash == (try pair.digest()),
              genesis.issuedAt >= pair.confirmedAt, genesis.expiresAt <= pair.expiresAt else { throw Error.bindingMismatch }
        for (owner, digest) in zip(genesis.owners, [value.aApprovalDigest, value.bApprovalDigest]) {
            let proof = try acceptedProof(digest, in: proofs)
            try verifyRootProof(proof, payload: genesis, owner: owner, authorityPublicKey: authorityPublicKey,
                                expectedOrigin: expectedOrigin, purpose: .approveGenesis, scopeID: genesis.proposalID)
            guard proof.challenge.issuedAt >= genesis.issuedAt, proof.challenge.expiresAt <= genesis.expiresAt,
                  proof.challenge.issuedAt <= value.createdAt else { throw Error.bindingMismatch }
        }
    }

    public static func verifyMembershipReceipt(_ receipt: Signed<MembershipReceipt>, pairReceipt: Signed<PairReceipt>,
                    proofs: [RootProof], authorityPublicKey: Data, expectedOrigin: String) throws {
        try receipt.verify(authorityPublicKey: authorityPublicKey)
        try verifyPairReceipt(pairReceipt, proofs: proofs, authorityPublicKey: authorityPublicKey, expectedOrigin: expectedOrigin)
        let value = receipt.payload, proposal = value.proposal, pair = pairReceipt.payload
        try verifyContext(authorityID: proposal.authorityID, origin: proposal.origin, audience: proposal.audience,
                          authorityPublicKey: authorityPublicKey, expectedOrigin: expectedOrigin)
        guard proposal.context == pair.transcript.context,
              pair.transcript.owners.contains(where: { $0.hasSameRoot(as: proposal.authorizingOwner) }),
              pair.transcript.owners.contains(proposal.candidate),
              proposal.pairingID == pair.transcript.pairingID, proposal.pairTranscriptHash == (try pair.transcript.digest()),
              proposal.pairReceiptHash == (try pair.digest()), proposal.issuedAt >= pair.confirmedAt,
              proposal.expiresAt <= pair.expiresAt else { throw Error.bindingMismatch }
        for (owner, digest) in zip([proposal.authorizingOwner, proposal.candidate], [value.authorizerApprovalDigest, value.candidateApprovalDigest]) {
            let proof = try acceptedProof(digest, in: proofs)
            try verifyRootProof(proof, payload: proposal, owner: owner, authorityPublicKey: authorityPublicKey,
                                expectedOrigin: expectedOrigin, purpose: .approveMembership, scopeID: proposal.proposalID)
            guard proof.challenge.issuedAt >= proposal.issuedAt, proof.challenge.expiresAt <= proposal.expiresAt,
                  proof.challenge.issuedAt <= value.committedAt else { throw Error.bindingMismatch }
        }
    }
}

extension PairingV2.OperationResponse {
    /// Verifies the authority's projection. Final owner consent still requires the receipt helpers above.
    public func verify(authorityPublicKey: Data, expectedOrigin: String, now: UInt64? = nil) throws {
        try validate(); try state.validate(); try signedState.verify(authorityPublicKey: authorityPublicKey)
        let header = signedState.payload
        try PairingV2.verifyContext(authorityID: header.authorityID, origin: header.origin, audience: header.audience,
                                    authorityPublicKey: authorityPublicKey, expectedOrigin: expectedOrigin)
        guard header.scopeKind == state.scopeKind, header.scopeID == state.scopeID,
              header.revision == state.revision, header.payloadHash == (try state.digest()) else { throw PairingV2.Error.bindingMismatch }
        if let now, now < header.issuedAt || now >= header.expiresAt { throw PairingV2.Error.expired }
        try inspection?.verify(authorityPublicKey: authorityPublicKey)
        try transcript?.verify(authorityPublicKey: authorityPublicKey)
        try pairReceipt?.verify(authorityPublicKey: authorityPublicKey)
        try genesis?.verify(authorityPublicKey: authorityPublicKey)
        try membershipProposal?.verify(authorityPublicKey: authorityPublicKey)
        try accountReceipt?.verify(authorityPublicKey: authorityPublicKey)
        try membershipReceipt?.verify(authorityPublicKey: authorityPublicKey)
        try trustReceipt?.verify(authorityPublicKey: authorityPublicKey)
        try roster?.verify(authorityPublicKey: authorityPublicKey)
        func context(_ authorityID: Data, _ origin: String, _ audience: String) throws {
            guard authorityID == header.authorityID, origin == header.origin, audience == header.audience else { throw PairingV2.Error.bindingMismatch }
        }
        if let p = inspection?.payload { try context(p.authorityID, p.origin, p.audience) }
        if let p = transcript?.payload { try context(p.authorityID, p.origin, p.audience) }
        if let p = pairReceipt?.payload.transcript { try context(p.authorityID, p.origin, p.audience) }
        if let p = genesis?.payload { try context(p.authorityID, p.origin, p.audience) }
        if let p = membershipProposal?.payload { try context(p.authorityID, p.origin, p.audience) }
        if let p = accountReceipt?.payload.genesis { try context(p.authorityID, p.origin, p.audience) }
        if let p = membershipReceipt?.payload.proposal { try context(p.authorityID, p.origin, p.audience) }
        if let p = trustReceipt?.payload { try context(p.authorityID, p.origin, p.audience) }
        if let p = roster?.payload { try context(p.authorityID, p.origin, p.audience) }
        if let transcript, let pairReceipt, transcript.payload != pairReceipt.payload.transcript { throw PairingV2.Error.bindingMismatch }
        if let genesis, let accountReceipt, genesis.payload != accountReceipt.payload.genesis { throw PairingV2.Error.bindingMismatch }
        if let membershipProposal, let membershipReceipt, membershipProposal.payload != membershipReceipt.payload.proposal { throw PairingV2.Error.bindingMismatch }
        if accountReceipt != nil && membershipReceipt != nil { throw PairingV2.Error.bindingMismatch }
        var objects: [Data] = []
        if let inspection { objects.append(try inspection.payload.digest()) }
        if let transcript { objects.append(try transcript.payload.digest()) }
        if let pairReceipt { objects.append(try pairReceipt.payload.digest()); objects.append(try pairReceipt.payload.transcript.digest()) }
        if let genesis { objects.append(try genesis.payload.digest()) }
        if let membershipProposal { objects.append(try membershipProposal.payload.digest()) }
        if let accountReceipt { objects.append(try accountReceipt.payload.digest()); objects.append(try accountReceipt.payload.genesis.digest()) }
        if let membershipReceipt { objects.append(try membershipReceipt.payload.digest()); objects.append(try membershipReceipt.payload.proposal.digest()) }
        if let trustReceipt { objects.append(try trustReceipt.payload.digest()) }
        if let roster { objects.append(try roster.payload.digest()) }
        if !objects.isEmpty, !objects.contains(state.objectHash) { throw PairingV2.Error.bindingMismatch }
        if let receiptHash = state.receiptHash {
            let receiptHashes = try [pairReceipt?.payload.digest(), accountReceipt?.payload.digest(), membershipReceipt?.payload.digest(), trustReceipt?.payload.digest()].compactMap { $0 }
            guard receiptHashes.contains(receiptHash) else { throw PairingV2.Error.bindingMismatch }
        }
    }
}
