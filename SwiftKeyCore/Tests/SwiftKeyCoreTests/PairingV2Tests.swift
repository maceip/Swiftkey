import Foundation
import Testing
@testable import SwiftKeyCore

private typealias V2 = PairingV2
private let v2Origin = "https://swiftkey.example"

private struct IndependentV2Vector {
    let name: String, type: String, json: Data, hex: String, hash: String
}
private func v2Vectors() throws -> [IndependentV2Vector] {
    let url = try #require(Bundle.module.url(forResource: "pairing-v2-vectors", withExtension: "json", subdirectory: "Fixtures"))
    let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let vectors = try #require(object["vectors"] as? [[String: Any]])
    return try vectors.map { record in
        IndependentV2Vector(name: try #require(record["name"] as? String), type: try #require(record["type"] as? String),
                            json: try JSONSerialization.data(withJSONObject: #require(record["wire"])),
                            hex: try #require(record["canonicalHex"] as? String), hash: try #require(record["sha256"] as? String))
    }
}
private func v2Record<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    let vector = try #require(v2Vectors().first { $0.name == name })
    return try PairingV2JSON.decode(type, from: vector.json)
}
private func v2Key(_ scalar: UInt8 = 9) throws -> SoftwareSigningKey {
    try SoftwareSigningKey(rawRepresentation: Data(repeating: 0x33, count: 31) + Data([scalar]))
}
private func v2Proofs(_ range: ClosedRange<Int>) throws -> [V2.RootProof] {
    try range.map { try v2Record(V2.RootProof.self, "proof\($0)") }
}
private func v2Mutate<T: Codable>(_ value: T, _ edit: (inout [String: Any]) -> Void) throws -> T {
    var object = try #require(JSONSerialization.jsonObject(with: PairingV2JSON.encode(value)) as? [String: Any])
    edit(&object)
    return try PairingV2JSON.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
}
private func v2Hex(_ value: Data) -> String { value.map { String(format: "%02x", $0) }.joined() }
private func checkVector<T: PairingV2CanonicalRecord>(_ type: T.Type, _ vector: IndependentV2Vector) throws {
    let value = try PairingV2JSON.decode(type, from: vector.json)
    #expect(try v2Hex(value.canonicalBytes()) == vector.hex)
    #expect(try v2Hex(value.digest()) == vector.hash)
    #expect(try PairingV2JSON.decode(type, from: PairingV2JSON.encode(value)) == value)
}

@Test func v2IndependentPythonVectorsCoverEveryCanonicalRecord() throws {
    let vectors = try v2Vectors()
    #expect(vectors.count == 46)
    #expect(Set(vectors.map(\.type)).count == 27)
    for vector in vectors {
        switch vector.type {
        case "OwnerDescriptor": try checkVector(V2.OwnerDescriptor.self, vector)
        case "PreEnrollmentChallenge": try checkVector(V2.PreEnrollmentChallenge.self, vector)
        case "AttestationEvidence": try checkVector(V2.AttestationEvidence.self, vector)
        case "DeviceTrustReceipt": try checkVector(V2.DeviceTrustReceipt.self, vector)
        case "AccountRoster": try checkVector(V2.AccountRoster.self, vector)
        case "ExistingAccountContext": try checkVector(V2.ExistingAccountContext.self, vector)
        case "PairingContext": try checkVector(V2.PairingContext.self, vector)
        case "CreatePairingIntent": try checkVector(V2.CreatePairingIntent.self, vector)
        case "PairingInspection": try checkVector(V2.PairingInspection.self, vector)
        case "JoinPairingIntent": try checkVector(V2.JoinPairingIntent.self, vector)
        case "PairTranscript": try checkVector(V2.PairTranscript.self, vector)
        case "ProposeAccountIntent": try checkVector(V2.ProposeAccountIntent.self, vector)
        case "ReplaceGenesisIntent": try checkVector(V2.ReplaceGenesisIntent.self, vector)
        case "RenewLeaseIntent": try checkVector(V2.RenewLeaseIntent.self, vector)
        case "AccountGenesis": try checkVector(V2.AccountGenesis.self, vector)
        case "ProposeMembershipIntent": try checkVector(V2.ProposeMembershipIntent.self, vector)
        case "MembershipProposal": try checkVector(V2.MembershipProposal.self, vector)
        case "RootChallenge": try checkVector(V2.RootChallenge.self, vector)
        case "RootProof": try checkVector(V2.RootProof.self, vector)
        case "OwnerSessionIntent": try checkVector(V2.OwnerSessionIntent.self, vector)
        case "ResultLookupIntent": try checkVector(V2.ResultLookupIntent.self, vector)
        case "OperationState": try checkVector(V2.OperationState.self, vector)
        case "SignedState": try checkVector(V2.SignedState.self, vector)
        case "ControlIntent": try checkVector(V2.ControlIntent.self, vector)
        case "PairReceipt": try checkVector(V2.PairReceipt.self, vector)
        case "AccountReceipt": try checkVector(V2.AccountReceipt.self, vector)
        case "MembershipReceipt": try checkVector(V2.MembershipReceipt.self, vector)
        default: Issue.record("Uncovered vector type \(vector.type)")
        }
    }
}

@Test func v2StrictJSONRejectsDuplicateAndUnknownKeysIncludingEscapedNestedKeys() throws {
    let id = "00000000-0000-0000-0000-000000000001"
    let duplicate = "{\"requestID\":\"\(id)\",\"r\\u0065questID\":\"\(id)\",\"rootKind\":\"android-strongbox-p256\"}"
    #expect(throws: V2.Error.duplicateKey("requestID")) { try PairingV2JSON.decode(V2.PreparationRequest.self, from: Data(duplicate.utf8)) }
    let intent = try v2Record(V2.CreatePairingIntent.self, "CreatePairingIntent")
    #expect(throws: V2.Error.unknownField("adminOverride")) {
        try v2Mutate(intent) { object in
            var context = object["context"] as! [String: Any]; context["adminOverride"] = true; object["context"] = context
        }
    }
    for malformed in ["{", "[]", "{\"requestID\":null}", "{}{}", "[1,]", "{\"x\":true,}"] {
        #expect(throws: (any Error).self) { try PairingV2JSON.decode(V2.PreparationRequest.self, from: Data(malformed.utf8)) }
    }
    let nested = String(repeating: "[", count: 66) + "0" + String(repeating: "]", count: 66)
    #expect(throws: (any Error).self) { try PairingV2JSON.decode(V2.PreparationRequest.self, from: Data(nested.utf8)) }
}

@Test func v2DecimalU64AndBase64AreCanonicalAndLossless() throws {
    let owner = try v2Record(V2.OwnerDescriptor.self, "owner1")
    let large = try v2Mutate(owner) { $0["rootKeyEpoch"] = String(UInt64.max) }
    #expect(large.rootKeyEpoch == UInt64.max)
    #expect(try PairingV2JSON.decode(V2.OwnerDescriptor.self, from: PairingV2JSON.encode(large)).rootKeyEpoch == UInt64.max)
    for bad: Any in [1, "01", "1.0", "+1", "-1", " 1", "18446744073709551616"] {
        #expect(throws: (any Error).self) { try v2Mutate(owner) { $0["rootKeyEpoch"] = bad } }
    }
    #expect(throws: (any Error).self) { try v2Mutate(owner) { $0["attestationReceiptHash"] = owner.attestationReceiptHash.base64EncodedString().dropLast().description } }
    #expect(throws: (any Error).self) { try v2Mutate(owner) { $0["attestationReceiptHash"] = " " + owner.attestationReceiptHash.base64EncodedString() } }
    #expect(throws: (any Error).self) { try v2Mutate(owner) { $0["rootPublicKey"] = Data(repeating: 0, count: 65).base64EncodedString() } }
}

@Test func v2RejectsUnsupportedProfilesAmbiguousIDsAndContexts() throws {
    let owner = try v2Record(V2.OwnerDescriptor.self, "owner1")
    #expect(throws: V2.Error.unsupportedRootKind) { try v2Mutate(owner) { $0["rootKind"] = "apple-app-attest" } }
    #expect(throws: (any Error).self) { try v2Mutate(owner) { $0["rootKind"] = "software-p256" } }
    #expect(throws: (any Error).self) { try v2Mutate(owner) { $0["deviceID"] = "device-1" } }
    #expect(throws: (any Error).self) { try v2Mutate(owner) { $0["role"] = "admin" } }
    let genesis = try v2Record(V2.AccountGenesis.self, "AccountGenesis")
    #expect(throws: (any Error).self) { try v2Mutate(genesis) { $0["label"] = "Cafe\u{301}" } }
    #expect(throws: (any Error).self) { try v2Mutate(genesis) { $0["ownershipPolicyID"] = "admin-recovery" } }
    for origin in ["http://swiftkey.example", "https://swiftkey.example/", "https://user@swiftkey.example", "https://swiftkey.example?q=1", "https://SWIFTKEY.example", "https://swiftkey.example:443"] {
        #expect(throws: (any Error).self) { try v2Mutate(genesis) { $0["origin"] = origin } }
    }
    #expect(throws: (any Error).self) { try v2Mutate(genesis) { $0["audience"] = "some-other-service" } }
    let loopback = try v2Mutate(genesis) { $0["origin"] = "http://127.0.0.1:8080" }
    #expect(loopback.origin == "http://127.0.0.1:8080")
}

@Test func v2IndependentPythonRootSignaturesAndCompleteGenesisChainVerify() throws {
    let authority = try v2Key(), pair = try v2Record(V2.PairReceipt.self, "PairReceipt")
    let genesisReceipt = try v2Record(V2.AccountReceipt.self, "AccountReceipt"), proofs = try v2Proofs(1...4)
    let signedPair = try V2.Signed.sign(pair, using: authority), signedAccount = try V2.Signed.sign(genesisReceipt, using: authority)
    try V2.verifyAccountReceipt(signedAccount, pairReceipt: signedPair, proofs: proofs, authorityPublicKey: authority.publicKey, expectedOrigin: v2Origin)
    #expect(throws: (any Error).self) { try V2.verifyAccountReceipt(signedAccount, pairReceipt: signedPair, proofs: Array(proofs.dropLast()), authorityPublicKey: authority.publicKey, expectedOrigin: v2Origin) }
    #expect(throws: (any Error).self) { try V2.verifyAccountReceipt(signedAccount, pairReceipt: signedPair, proofs: proofs + [proofs[0]], authorityPublicKey: authority.publicKey, expectedOrigin: v2Origin) }
    #expect(throws: (any Error).self) { try V2.verifyPairReceipt(signedPair, proofs: proofs, authorityPublicKey: v2Key(8).publicKey, expectedOrigin: v2Origin) }
    #expect(throws: (any Error).self) { try V2.verifyPairReceipt(signedPair, proofs: proofs, authorityPublicKey: authority.publicKey, expectedOrigin: "https://attacker.example") }
    // Receipt verification is historical: a consumed root challenge's present expiry does not invalidate accepted consent.
    try V2.verifyPairReceipt(signedPair, proofs: proofs, authorityPublicKey: authority.publicKey, expectedOrigin: v2Origin)
    #expect(throws: V2.Error.expired) {
        try V2.verifyRootProof(proofs[0], payload: pair.transcript, owner: pair.transcript.owners[0], authorityPublicKey: authority.publicKey,
                              expectedOrigin: v2Origin, purpose: .confirmPair, scopeID: pair.transcript.pairingID, now: 1200)
    }
}

@Test func v2MembershipReceiptBindsTargetEpochFullDeltaAndBothRoots() throws {
    let authority = try v2Key(), pair = try v2Record(V2.PairReceipt.self, "membershipPairReceipt")
    let receipt = try v2Record(V2.MembershipReceipt.self, "MembershipReceipt"), proofs = try v2Proofs(5...8)
    let signedPair = try V2.Signed.sign(pair, using: authority), signedReceipt = try V2.Signed.sign(receipt, using: authority)
    try V2.verifyMembershipReceipt(signedReceipt, pairReceipt: signedPair, proofs: proofs, authorityPublicKey: authority.publicKey, expectedOrigin: v2Origin)
    #expect(throws: (any Error).self) { try V2.verifyMembershipReceipt(signedReceipt, pairReceipt: signedPair, proofs: Array(proofs.dropLast()), authorityPublicKey: authority.publicKey, expectedOrigin: v2Origin) }
    let proposal = receipt.proposal
    #expect(throws: (any Error).self) { try v2Mutate(proposal) { $0["nextMembershipRevision"] = "3" } }
    #expect(throws: (any Error).self) {
        try v2Mutate(proposal) { object in
            var context = object["context"] as! [String: Any], account = context["existingAccount"] as! [String: Any]
            var lost = account["lostOwner"] as! [String: Any]; lost["rootKeyEpoch"] = "3"
            account["lostOwner"] = lost; context["existingAccount"] = account; object["context"] = context
        }
    }
    #expect(throws: (any Error).self) { try v2Mutate(proposal) { object in object["resultingOwners"] = (object["resultingOwners"] as! [[String: Any]]).reversed().map { $0 } } }
    #expect(throws: (any Error).self) { try v2Mutate(proposal) { $0["candidate"] = $0["authorizingOwner"] } }
}

@Test func v2LeaseRenewalPreservesMembershipIdentityButNotRootEpoch() throws {
    let proposal = try v2Record(V2.MembershipProposal.self, "MembershipProposal")
    let renewed = try v2Mutate(proposal.authorizingOwner) { $0["attestationReceiptHash"] = Data(repeating: 7, count: 32).base64EncodedString() }
    #expect(renewed.hasSameRoot(as: proposal.authorizingOwner))
    let intent = V2.CreatePairingIntent(authorityID: proposal.authorityID, origin: proposal.origin, audience: proposal.audience,
                                        requestID: "00000000-0000-0000-0000-000000000040", initiator: renewed, context: proposal.context)
    try intent.validate()
    let epochChanged = try v2Mutate(renewed) { $0["rootKeyEpoch"] = "9" }
    #expect(!epochChanged.hasSameRoot(as: proposal.authorizingOwner))
    #expect(throws: (any Error).self) {
        try V2.CreatePairingIntent(authorityID: proposal.authorityID, origin: proposal.origin, audience: proposal.audience,
                                  requestID: intent.requestID, initiator: epochChanged, context: proposal.context).validate()
    }
}

@Test func v2SignedProjectionRejectsNestedOriginMixingAndTamperedState() throws {
    let authority = try v2Key(), state = try v2Record(V2.OperationState.self, "OperationState")
    let header = try v2Record(V2.SignedState.self, "SignedState"), account = try v2Record(V2.AccountReceipt.self, "AccountReceipt")
    let response = V2.OperationResponse(state: state, signedState: try .sign(header, using: authority), accountReceipt: try .sign(account, using: authority))
    try response.verify(authorityPublicKey: authority.publicKey, expectedOrigin: v2Origin, now: 1150)
    #expect(throws: V2.Error.expired) { try response.verify(authorityPublicKey: authority.publicKey, expectedOrigin: v2Origin, now: 1200) }
    let alteredState = try v2Mutate(state) { $0["revision"] = "6" }
    #expect(throws: (any Error).self) { try V2.OperationResponse(state: alteredState, signedState: response.signedState, accountReceipt: response.accountReceipt).verify(authorityPublicKey: authority.publicKey, expectedOrigin: v2Origin) }
    let foreignInspection = try v2Mutate(v2Record(V2.PairingInspection.self, "PairingInspection")) { $0["origin"] = "https://other.example" }
    #expect(throws: (any Error).self) {
        try V2.OperationResponse(state: state, signedState: response.signedState, inspection: .sign(foreignInspection, using: authority), accountReceipt: response.accountReceipt)
            .verify(authorityPublicKey: authority.publicKey, expectedOrigin: v2Origin)
    }
}

@Test func v2DetachedSignaturesRoundTripAcrossECDSAIntegerWidths() throws {
    let header = try v2Record(V2.SignedState.self, "SignedState")
    for authority in [try v2Key(), SoftwareSigningKey()] {
        for _ in 0..<2048 {
            let signed = try V2.Signed.sign(header, using: authority)
            #expect(ProtocolCrypto.verify(signature: signed.signature, message: try header.canonicalBytes(), publicKey: authority.publicKey))
        }
    }
}

@Test func v2WireOperationBindsPayloadPurposeAndScopeWithoutSecretInPublicProjection() throws {
    let proof = try v2Record(V2.RootProof.self, "proof1"), transcript = try v2Record(V2.PairTranscript.self, "PairTranscript")
    let request = V2.OperationRequest(payload: .confirmPair(transcript), proof: proof)
    #expect(request.payload.scopeID == transcript.pairingID)
    #expect(try PairingV2JSON.decode(V2.OperationRequest.self, from: PairingV2JSON.encode(request)) == request)
    let other = try v2Record(V2.PairTranscript.self, "membershipTranscript")
    #expect(throws: (any Error).self) { try V2.OperationRequest(payload: .confirmPair(other), proof: proof).validate() }
    let state = try v2Record(V2.OperationState.self, "OperationState"), header = try v2Record(V2.SignedState.self, "SignedState")
    let response = V2.OperationResponse(state: state, signedState: try .sign(header, using: v2Key()))
    let secret = Data(repeating: 0xff, count: 32)
    let execution = V2.ExecutionResponse(operation: response, secret: secret, sessionToken: "test-token", sessionExpiresAt: UInt64.max)
    let encoded = try PairingV2JSON.encode(execution)
    #expect(try PairingV2JSON.decode(V2.ExecutionResponse.self, from: encoded) == execution)
    #expect(!String(decoding: try PairingV2JSON.encode(response), as: UTF8.self).contains(secret.base64EncodedString()))
    #expect(throws: (any Error).self) { try v2Mutate(execution) { $0["sessionExpiresAt"] = 3 } }
}
