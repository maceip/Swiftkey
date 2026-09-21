import Foundation
import SwiftKeyCore

/// Provisioned separately from invitations and network responses. This contains
/// the public authority pin, never an enrollment or administrative bearer.
public struct PairingClientConfiguration: Codable, Equatable, Sendable {
    public let serverURL: String
    public let serverPublicKey: Data
    public let audience: String
    public let workloadAudience: String
    public init(serverURL: String, serverPublicKey: Data, audience: String = PairingV2.audience, workloadAudience: String = "swiftkey.local") {
        self.serverURL = serverURL; self.serverPublicKey = serverPublicKey; self.audience = audience; self.workloadAudience = workloadAudience
    }
    private enum CodingKeys: String, CodingKey { case serverURL, serverPublicKey, audience, workloadAudience }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try c.decode(String.self, forKey: .serverURL)
        serverPublicKey = try c.decode(Data.self, forKey: .serverPublicKey)
        audience = try c.decodeIfPresent(String.self, forKey: .audience) ?? PairingV2.audience
        workloadAudience = try c.decodeIfPresent(String.self, forKey: .workloadAudience) ?? "swiftkey.local"
        try validate()
    }
    public func validate() throws {
        guard let u = URLComponents(string: serverURL), u.url != nil,
              u.scheme == "https" || (u.scheme == "http" && u.host == "127.0.0.1"),
              let host = u.host, !host.isEmpty, host == host.lowercased(),
              u.user == nil, u.password == nil, u.query == nil, u.fragment == nil, u.path.isEmpty,
              u.string == serverURL, audience == PairingV2.audience, !workloadAudience.isEmpty, workloadAudience.utf8.count <= 256,
              !workloadAudience.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw ClientError.invalidConfiguration }
        try ProtocolCrypto.validatePublicKey(serverPublicKey)
        do { try PairingV2.validateContext(authorityID: authorityID, origin: serverURL, audience: audience) }
        catch { throw ClientError.invalidConfiguration }
    }
    public var authorityID: Data { ProtocolCrypto.sha256(serverPublicKey) }
}

/// Transient only: never Codable or included in a public/UI snapshot.
public struct PairingInvitation: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let pairingID: String
    public let capability: Data
    public init(link: String, configuration: PairingClientConfiguration) throws {
        try configuration.validate()
        let prefix = configuration.serverURL + "/pair#v2."
        guard link.utf8.count <= 2048, link.hasPrefix(prefix) else { throw PairingClientError.invalidInvitation }
        let parts = link.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw PairingClientError.invalidInvitation }
        let id = String(parts[0]), secret = String(parts[1])
        guard UUID(uuidString: id)?.uuidString.lowercased() == id,
              secret.count == 43, secret.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
              let bytes = Data(base64Encoded: secret.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="),
              bytes.count == 32, Self.encode(bytes) == secret else { throw PairingClientError.invalidInvitation }
        pairingID = id; capability = bytes
    }
    public static func link(pairingID: String, capability: Data, configuration: PairingClientConfiguration) throws -> String {
        try configuration.validate()
        guard UUID(uuidString: pairingID)?.uuidString.lowercased() == pairingID, capability.count == 32 else {
            throw PairingClientError.invalidInvitation
        }
        return configuration.serverURL + "/pair#v2." + pairingID + "." + encode(capability)
    }
    private static func encode(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public var description: String { "<private pairing invitation>" }
    public var debugDescription: String { description }
}

public enum PairingClientError: String, Error, Sendable {
    case invalidInvitation, identityRequired, alreadyOwned, invalidState, staleReview
    case invitationMustBeScannedAgain, outcomeUnknown, expired, receiptMismatch, rollback
    case signingUnavailable, membershipRevoked
}
