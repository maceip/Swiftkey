import Foundation
import SwiftKeyCore

/// Configuration is provisioned independently of the network response.
public struct ClientConfiguration: Codable, Sendable {
    public let serverURL: String
    public let bootstrapToken: String
    public let serverPublicKey: Data
    public let audience: String
    public let expectedAccountID: String?

    public init(serverURL: String, bootstrapToken: String, serverPublicKey: Data, audience: String, expectedAccountID: String? = nil) {
        self.serverURL = serverURL
        self.bootstrapToken = bootstrapToken
        self.serverPublicKey = serverPublicKey
        self.audience = audience
        self.expectedAccountID = expectedAccountID
    }
}

public struct AndroidEnrollmentEvidence: Codable, Sendable {
    public let publicKey: Data
    public let certificateChain: [Data]
    public let platform: String

    public init(publicKey: Data, certificateChain: [Data], platform: String) {
        self.publicKey = publicKey
        self.certificateChain = certificateChain
        self.platform = platform
    }
}

/// Platform operations remain outside the shared protocol. Signing receives a
/// raw canonical message: Android SHA256withECDSA hashes it exactly once.
public struct ClientPlatform: Sendable {
    public let enroll: @Sendable (Data) throws -> AndroidEnrollmentEvidence
    public let signRootMessage: @Sendable (Data) throws -> Data
    public let post: @Sendable (_ url: String, _ body: Data, _ bearerToken: String) throws -> Data
    public let readState: @Sendable () throws -> Data?
    public let writeState: @Sendable (Data) throws -> Void
    public let now: @Sendable () -> UInt64

    public init(
        enroll: @escaping @Sendable (Data) throws -> AndroidEnrollmentEvidence,
        signRootMessage: @escaping @Sendable (Data) throws -> Data,
        post: @escaping @Sendable (String, Data, String) throws -> Data,
        readState: @escaping @Sendable () throws -> Data?,
        writeState: @escaping @Sendable (Data) throws -> Void,
        now: @escaping @Sendable () -> UInt64 = { UInt64(max(0, Date().timeIntervalSince1970)) }
    ) {
        self.enroll = enroll
        self.signRootMessage = signRootMessage
        self.post = post
        self.readState = readState
        self.writeState = writeState
        self.now = now
    }
}

public enum ClientError: Error, Equatable, Sendable {
    case invalidConfiguration
    case serverIdentityMismatch
    case invalidServerResponse
    case enrollmentIdentityMismatch
    case storedStateMismatch
    case unsupportedHardware
    case serverRejected(String)
    case replayUnexpectedlyAccepted
    case operationInProgress
}
