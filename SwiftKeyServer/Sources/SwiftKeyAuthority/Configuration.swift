import Foundation
import SwiftKeyCore

public struct ServerConfiguration: Codable, Sendable {
    public var host: String
    public var port: Int
    public var stateDirectory: String
    public var androidPackage: String
    public var androidSigningCertificateSHA256: String
    public var androidMinimumVersion: UInt64
    public var workloadAudience: String
    public var workloadDomain: String
    public var pairingV2: PairingV2Configuration?
    public init(host: String = "127.0.0.1", port: Int = 18088, stateDirectory: String, androidPackage: String, androidSigningCertificateSHA256: String, androidMinimumVersion: UInt64 = 1, workloadAudience: String = "swiftkey.local", workloadDomain: String = "swiftkey.demo.echo.v1", pairingV2: PairingV2Configuration? = nil) {
        self.host = host; self.port = port; self.stateDirectory = stateDirectory; self.androidPackage = androidPackage
        self.androidSigningCertificateSHA256 = androidSigningCertificateSHA256; self.androidMinimumVersion = androidMinimumVersion; self.workloadAudience = workloadAudience
        self.workloadDomain = workloadDomain
        self.pairingV2 = pairingV2
    }
    func policyFingerprint() throws -> Data {
        struct Policy: Encodable { let version: Int; let package: String; let signer: Data; let minimumVersion: UInt64; let audience: String; let domain: String }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return ProtocolCrypto.sha256(try encoder.encode(Policy(version: 1, package: androidPackage, signer: decodeHex(androidSigningCertificateSHA256), minimumVersion: androidMinimumVersion, audience: workloadAudience, domain: workloadDomain)))
    }
}

/// Explicit opt-in. A missing block keeps existing installations on v1. Once
/// v2 data exists its origin/audience are pinned in the same durable snapshot.
public struct PairingV2Configuration: Codable, Sendable {
    public var origin: String
    public var enabled: Bool
    public init(origin: String, enabled: Bool = true) { self.origin = origin; self.enabled = enabled }
}

public enum AuthorityError: Error, CustomStringConvertible, Sendable {
    case rejected(String)
    case protocolFailure(code: String, message: String)
    public var description: String { switch self { case .rejected(let message), .protocolFailure(_, let message): return message } }
    public var code: String { switch self { case .rejected: return "rejected"; case .protocolFailure(let code, _): return code } }
}

func require(_ condition: @autoclosure () throws -> Bool, _ message: String, code: String = "rejected") throws {
    guard try condition() else { throw AuthorityError.protocolFailure(code: code, message: message) }
}

func randomBytes(_ count: Int) -> Data { Data((0..<count).map { _ in UInt8.random(in: 0...255) }) }
func hex(_ data: some Collection<UInt8>) -> String { data.map { String(format: "%02x", $0) }.joined() }
func decodeHex(_ string: String) throws -> Data {
    try require(string.count == 64 && string.allSatisfy { $0.isHexDigit && $0.isASCII }, "Expected a SHA256 hexadecimal fingerprint")
    let bytes = Array(string.utf8)
    return Data(stride(from: 0, to: bytes.count, by: 2).map { UInt8(String(decoding: bytes[$0..<$0 + 2], as: UTF8.self), radix: 16)! })
}

public struct VerifiedAndroidIdentity: Codable, Sendable {
    public let publicKey: Data
    public let certificateSHA256: Data
    public let packageName: String
    public let packageVersion: UInt64
    public let certificateChain: [Data]
    public let attestationChallenge: Data
    public init(publicKey: Data, certificateSHA256: Data, packageName: String, packageVersion: UInt64, certificateChain: [Data] = [], attestationChallenge: Data = Data()) {
        self.publicKey = publicKey; self.certificateSHA256 = certificateSHA256; self.packageName = packageName; self.packageVersion = packageVersion; self.certificateChain = certificateChain
        self.attestationChallenge = attestationChallenge
    }
}

public protocol EnrollmentVerifier: Sendable {
    func verify(certificates: [Data], challenge: Data, now: UInt64) async throws -> VerifiedAndroidIdentity
    func revalidate(_ identity: VerifiedAndroidIdentity, now: UInt64) async throws
}
