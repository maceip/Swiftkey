import Foundation
import SwiftASN1
@_spi(FixedExpiryValidationTime) import X509
import Crypto
import SwiftKeyCore

/// The executable only constructs this verifier. Test fixtures inject their own
/// EnrollmentVerifier directly into isolated Authority instances; no HTTP mode
/// or production configuration accepts software attestation.
public actor AndroidAttestationVerifier: EnrollmentVerifier {
    private struct Trust: Sendable {
        let roots: [Certificate]
        let revokedSerials: Set<String>
        let fetchedAt: UInt64
    }
    private let configuration: ServerConfiguration
    private var trust: Trust?
    public init(configuration: ServerConfiguration) { self.configuration = configuration }

    public func prepare() async throws { _ = try await trustedMaterial(now: UInt64(Date().timeIntervalSince1970)) }

    public func revalidate(_ identity: VerifiedAndroidIdentity, now: UInt64) async throws {
        let current = try await verify(certificates: identity.certificateChain, challenge: identity.attestationChallenge, now: now)
        try require(current.publicKey == identity.publicKey && current.certificateSHA256 == identity.certificateSHA256, "Registered attestation identity changed", code: "attestationRejected")
    }

    private func trustedMaterial(now: UInt64) async throws -> Trust {
        if let trust, now >= trust.fetchedAt && now - trust.fetchedAt < 3600 { return trust }
        async let rootsData = Self.fetch("https://android.googleapis.com/attestation/root")
        async let statusData = Self.fetch("https://android.googleapis.com/attestation/status")
        let pemRoots = try JSONDecoder().decode([String].self, from: await rootsData)
        try require(pemRoots.count >= 2 && pemRoots.count <= 16, "Google trust-root response was unexpected")
        let roots = try pemRoots.map { try Certificate(pemEncoded: $0) }
        struct Status: Decodable { let entries: [String: Entry] }
        struct Entry: Decodable { let status: String }
        let status = try JSONDecoder().decode(Status.self, from: await statusData)
        try require(!status.entries.isEmpty, "Google revocation response was empty")
        let material = Trust(roots: roots, revokedSerials: Set(status.entries.keys.map(Self.normalizeSerial)), fetchedAt: now)
        trust = material
        return material
    }

    private static func fetch(_ endpoint: String) async throws -> Data {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        try require((response as? HTTPURLResponse)?.statusCode == 200 && response.url?.scheme == "https" && response.url?.host == "android.googleapis.com" && data.count <= 10_485_760, "Cannot refresh official Google attestation trust material")
        return data
    }

    private static func normalizeSerial(_ serial: String) -> String {
        let stripped = serial.lowercased().drop(while: { $0 == "0" })
        return stripped.isEmpty ? "0" : String(stripped)
    }

    public func verify(certificates encoded: [Data], challenge: Data, now: UInt64) async throws -> VerifiedAndroidIdentity {
        do {
            try require((2...8).contains(encoded.count) && encoded.allSatisfy { !$0.isEmpty && $0.count <= 32_768 }, "Invalid attestation certificate-chain bounds")
            let material = try await trustedMaterial(now: now)
            let certificates = try encoded.map { try Certificate(derEncoded: Array($0)) }
            var verifier = Verifier(rootCertificates: CertificateStore(material.roots)) {
                RFC5280Policy(fixedExpiryValidationTime: Date(timeIntervalSince1970: TimeInterval(now)))
            }
            let result = await verifier.validate(leaf: certificates[0], intermediates: CertificateStore(certificates.dropFirst()))
            guard case .validCertificate(let chain) = result else { throw AuthorityError.rejected("Attestation does not form a valid chain to a current Google root") }
            for certificate in chain {
                try require(!material.revokedSerials.contains(Self.normalizeSerial(hex(certificate.serialNumber.bytes))), "Attestation certificate is revoked or suspended")
            }
            let oid: ASN1ObjectIdentifier = [1, 3, 6, 1, 4, 1, 11129, 2, 1, 17]
            // Scan the validated path from its trust anchor toward the leaf.
            // An attacker may append a child containing a fabricated extension.
            guard let attested = chain.reversed().first(where: { $0.extensions[oid: oid] != nil }), let attestation = attested.extensions[oid: oid] else {
                throw AuthorityError.rejected("Android key attestation extension is missing")
            }
            let rootFirst = Array(chain.reversed())
            let provisioningOID: ASN1ObjectIdentifier = [1, 3, 6, 1, 4, 1, 11129, 2, 1, 30]
            if let provisioningIndex = rootFirst.firstIndex(where: { $0.extensions[oid: provisioningOID] != nil }) {
                try require(rootFirst.firstIndex(of: attested) == provisioningIndex + 1, "Key attestation must immediately follow provisioning information")
            }
            try require(attested == certificates[0], "The trusted attestation extension does not bind the submitted leaf key")
            guard let key = P256.Signing.PublicKey(attested.publicKey) else { throw AuthorityError.rejected("Attested key is not P-256") }
            let identity = try AndroidKeyDescription.parse(Data(attestation.value), expectedChallenge: challenge, configuration: configuration)
            return VerifiedAndroidIdentity(publicKey: key.x963Representation, certificateSHA256: ProtocolCrypto.sha256(encoded[0]), packageName: identity.package, packageVersion: identity.version, certificateChain: encoded, attestationChallenge: challenge)
        } catch let error as AuthorityError {
            throw AuthorityError.protocolFailure(code: "attestationRejected", message: error.description)
        } catch {
            throw AuthorityError.protocolFailure(code: "attestationRejected", message: "Malformed Android attestation or unavailable trust material: \(error)")
        }
    }
}

/// Schema-specific interpretation on top of SwiftASN1's strict DER parser.
/// Cryptographic operations and X.509 path validation remain in maintained
/// Swift Crypto / Swift Certificates implementations.
enum AndroidKeyDescription {
    static func children(_ node: ASN1Node, identifier: ASN1Identifier) throws -> [ASN1Node] {
        try require(node.identifier == identifier, "Unexpected Android attestation ASN.1 field")
        guard case .constructed(let values) = node.content else { throw AuthorityError.rejected("Expected constructed ASN.1 value") }
        return Array(values)
    }
    static func integer(_ node: ASN1Node) throws -> UInt64 { try UInt64(derEncoded: node) }
    static func enumeration(_ node: ASN1Node) throws -> UInt64 { try UInt64(derEncoded: node, withIdentifier: .enumerated) }
    static func octets(_ node: ASN1Node) throws -> Data { Data(try ASN1OctetString(derEncoded: node).bytes) }
    static func authorizations(_ node: ASN1Node) throws -> [UInt: ASN1Node] {
        var result: [UInt: ASN1Node] = [:]
        for field in try children(node, identifier: .sequence) {
            try require(field.identifier.tagClass == .contextSpecific && result[field.identifier.tagNumber] == nil, "Duplicate or untagged Android authorization")
            guard case .constructed(let wrapped) = field.content else { throw AuthorityError.rejected("Android authorization must use explicit tagging") }
            let values = Array(wrapped)
            try require(values.count == 1, "Android authorization has multiple values")
            result[field.identifier.tagNumber] = values[0]
        }
        return result
    }
    static func field(_ fields: [UInt: ASN1Node], _ tag: UInt) throws -> ASN1Node {
        guard let value = fields[tag] else { throw AuthorityError.rejected("Missing required Android authorization tag\(tag)") }
        return value
    }
    static func integerSet(_ node: ASN1Node) throws -> Set<UInt64> { Set(try children(node, identifier: .set).map(integer)) }

    static func parse(_ encoded: Data, expectedChallenge: Data, configuration: ServerConfiguration) throws -> (package: String, version: UInt64) {
        let fields = try children(DER.parse(Array(encoded)), identifier: .sequence)
        try require(fields.count == 8, "Invalid KeyDescription field count")
        let attestationVersion = try integer(fields[0])
        let keyMintVersion = try integer(fields[2])
        try require(attestationVersion >= 3 && keyMintVersion >= 4, "Unsupported pre-StrongBox key attestation version")
        try require(try enumeration(fields[1]) == 2 && enumeration(fields[3]) == 2, "Both attestation and key security levels must be StrongBox")
        try require(try octets(fields[4]) == expectedChallenge, "Attestation challenge does not match issued enrollment")
        _ = try octets(fields[5])
        let software = try authorizations(fields[6]); let hardware = try authorizations(fields[7])
        // Critical key properties must be hardware-enforced, never copied from
        // softwareEnforced to create an apparent StrongBox policy.
        try require(try integerSet(field(hardware, 1)).contains(2), "StrongBox key is not authorized for signing")
        try require(try integer(field(hardware, 2)) == 3, "StrongBox key algorithm is not EC")
        try require(try integer(field(hardware, 3)) == 256, "StrongBox key size is not256")
        try require(try integerSet(field(hardware, 5)).contains(4), "StrongBox key does not authorize SHA256")
        try require(try integer(field(hardware, 10)) == 1, "StrongBox EC curve is not P-256")
        try require(try integer(field(hardware, 702)) == 0, "StrongBox key origin is not generated")
        let root = try children(field(hardware, 704), identifier: .sequence)
        try require(root.count == 4, "Invalid verified-boot RootOfTrust")
        try require(try !octets(root[0]).isEmpty && Bool(derEncoded: root[1]) && enumeration(root[2]) == 0 && !octets(root[3]).isEmpty, "Device must have locked, verified boot")
        try require(hardware[709] == nil, "Unexpected hardware placement of application identity")
        let application = try children(DER.parse(Array(octets(field(software, 709)))), identifier: .sequence)
        try require(application.count == 2, "Invalid application identity")
        let packages = try children(application[0], identifier: .set)
        try require(packages.count == 1, "Shared-UID application keys are not accepted")
        let package = try children(packages[0], identifier: .sequence)
        try require(package.count == 2, "Invalid attested package information")
        let nameBytes = try octets(package[0]); let version = try integer(package[1])
        try require(String(data: nameBytes, encoding: .utf8) == configuration.androidPackage && version >= configuration.androidMinimumVersion, "Android package or app version does not match policy")
        let digests = try children(application[1], identifier: .set).map(octets)
        try require(digests.count == 1 && digests[0] == decodeHex(configuration.androidSigningCertificateSHA256), "Android application signing certificate does not match policy")
        return (configuration.androidPackage, version)
    }
}
