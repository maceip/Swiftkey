import Foundation

/// Wire u64 values are canonical decimal strings; never JSON floating-point numbers.
@propertyWrapper public struct V2UInt64: Codable, Equatable, Sendable {
    public var wrappedValue: UInt64
    public init(wrappedValue: UInt64) { self.wrappedValue = wrappedValue }
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              (value == "0" || value.first != "0"), let number = UInt64(value) else {
            throw PairingV2.Error.invalidField("u64")
        }
        wrappedValue = number
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer(); try container.encode(String(wrappedValue))
    }
}

public enum PairingV2JSON {
    public static let maximumBodyBytes = 1_048_576
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= maximumBodyBytes else { throw PairingV2.Error.invalidField("bodySize") }
        return data
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= maximumBodyBytes else { throw PairingV2.Error.invalidField("bodySize") }
        var scanner = V2JSONScanner(bytes: Array(data)); try scanner.scan()
        return try JSONDecoder().decode(type, from: data)
    }
}

extension PairingV2 {
    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    static func rejectUnknownKeys(_ decoder: Decoder, allowed: [String]) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        if let unknown = container.allKeys.first(where: { !allowed.contains($0.stringValue) }) {
            throw Error.unknownField(unknown.stringValue)
        }
    }
    static func decodeData(_ value: String) throws -> Data {
        guard let result = Data(base64Encoded: value), result.base64EncodedString() == value else {
            throw Error.invalidField("base64")
        }
        return result
    }
    static func require(_ condition: @autoclosure () -> Bool, _ field: String) throws {
        guard condition() else { throw Error.invalidField(field) }
    }
    public static func validateID(_ value: String) throws {
        guard let id = UUID(uuidString: value), id.uuidString.lowercased() == value else { throw Error.invalidField("uuid") }
    }
    public static func validateHash(_ value: Data) throws { try require(value.count == 32, "hash") }
    public static func validateText(_ value: String) throws {
        try require(!value.isEmpty && value.utf8.count <= 256 && value.utf8.elementsEqual(value.precomposedStringWithCanonicalMapping.utf8)
                    && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), "text")
    }
    public static func validateLabel(_ value: String) throws {
        try validateText(value); try require(value.utf8.count <= 120, "label")
    }
    public static func validatePolicy(_ value: String) throws { try require(value == ownershipPolicy, "ownershipPolicy") }
    public static func validateTexts(_ values: [String]) throws {
        try require(values.count <= 256 && values == values.sorted() && Set(values).count == values.count, "sortedUniqueArray")
        for value in values { try validateText(value) }
    }
    public static func validateOwners(_ values: [OwnerDescriptor], minimum: Int = 0, maximum: Int = 256) throws {
        try require(values.count >= minimum && values.count <= maximum, "ownerCount")
        try validateTexts(values.map(\.deviceID))
        try require(Set(values.map(\.rootPublicKey)).count == values.count, "distinctOwnerRoots")
        for value in values { try value.validate() }
    }
    public static func validateLifetime(_ start: UInt64, _ end: UInt64, maximum: UInt64) throws {
        try require(end > start && end - start <= maximum, "lifetime")
    }
    public static func validateContext(authorityID: Data, origin: String, audience: String) throws {
        try validateHash(authorityID); try require(audience == Self.audience, "audience")
        guard let url = URLComponents(string: origin), let scheme = url.scheme, let host = url.host,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty, !host.isEmpty, host == host.lowercased(), !host.hasSuffix("."),
              origin.utf8.allSatisfy({ $0 >= 33 && $0 < 127 }),
              (scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host))),
              url.port != (scheme == "https" ? 443 : 80), url.port.map({ $0 > 0 && $0 <= 65535 }) ?? true else {
            throw Error.invalidField("origin")
        }
    }

    public struct Signed<Payload: PairingV2CanonicalRecord>: Codable, Sendable, Equatable {
        public let payload: Payload
        public let signature: Data
        public init(payload: Payload, signature: Data) { self.payload = payload; self.signature = signature }
        private enum CodingKeys: String, CodingKey { case payload, signature }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: ["payload", "signature"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            payload = try c.decode(Payload.self, forKey: .payload)
            signature = try PairingV2.decodeData(c.decode(String.self, forKey: .signature))
            try PairingV2.require(signature.count >= 8 && signature.count <= 80, "signature")
        }
        /// Cryptographic signature verification only. Callers additionally bind expected context and object.
        public func verify(authorityPublicKey: Data) throws {
            guard ProtocolCrypto.verify(signature: signature, message: try payload.canonicalBytes(), publicKey: authorityPublicKey) else {
                throw Error.invalidSignature
            }
        }
        public static func sign(_ payload: Payload, using key: SoftwareSigningKey) throws -> Self {
            Self(payload: payload, signature: try key.sign(message: payload.canonicalBytes()))
        }
    }
    public struct RootAuthorized<Payload: PairingV2CanonicalRecord>: Codable, Sendable, Equatable {
        public let payload: Payload
        public let proof: RootProof
        public init(payload: Payload, proof: RootProof) { self.payload = payload; self.proof = proof }
        private enum CodingKeys: String, CodingKey { case payload, proof }
        public init(from decoder: Decoder) throws {
            try PairingV2.rejectUnknownKeys(decoder, allowed: ["payload", "proof"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            payload = try c.decode(Payload.self, forKey: .payload); proof = try c.decode(RootProof.self, forKey: .proof)
        }
    }

    public static func verifyContext(authorityID: Data, origin: String, audience: String,
                                     authorityPublicKey: Data, expectedOrigin: String) throws {
        try validateContext(authorityID: authorityID, origin: origin, audience: audience)
        try ProtocolCrypto.validatePublicKey(authorityPublicKey)
        guard authorityID == ProtocolCrypto.sha256(authorityPublicKey), origin == expectedOrigin else { throw Error.bindingMismatch }
    }
    /// Does not decide server eligibility or replay state; those require durable authority records.
    public static func verifyRootProof<Payload: PairingV2CanonicalRecord>(_ proof: RootProof, payload: Payload,
                    owner: OwnerDescriptor, authorityPublicKey: Data, expectedOrigin: String,
                    purpose: RootPurpose, scopeID: String, now: UInt64? = nil) throws {
        try proof.validate(); try owner.validate()
        let c = proof.challenge
        try verifyContext(authorityID: c.authorityID, origin: c.origin, audience: c.audience,
                          authorityPublicKey: authorityPublicKey, expectedOrigin: expectedOrigin)
        guard proof.rootKind == owner.rootKind, c.deviceID == owner.deviceID, c.rootKeyEpoch == owner.rootKeyEpoch,
              c.purpose == purpose, c.scopeID == scopeID, c.payloadHash == (try payload.digest()) else { throw Error.bindingMismatch }
        if let now, now < c.issuedAt || now >= c.expiresAt { throw Error.expired }
        guard ProtocolCrypto.verify(signature: proof.proof, message: try c.canonicalBytes(), publicKey: owner.rootPublicKey) else {
            throw Error.invalidSignature
        }
    }
}

/// JSONDecoder silently discards duplicate object keys. Scan first, including escaped-equivalent keys.
private struct V2JSONScanner {
    let bytes: [UInt8]
    var offset = 0
    mutating func scan() throws { try value(depth: 0); space(); guard offset == bytes.count else { throw PairingV2.Error.invalidJSON } }
    mutating func space() { while offset < bytes.count && [9, 10, 13, 32].contains(bytes[offset]) { offset += 1 } }
    mutating func take(_ byte: UInt8) throws { space(); guard offset < bytes.count && bytes[offset] == byte else { throw PairingV2.Error.invalidJSON }; offset += 1 }
    mutating func string() throws -> String {
        space(); let start = offset; try take(34)
        while offset < bytes.count {
            let byte = bytes[offset]; offset += 1
            if byte == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<offset])) }
            if byte == 92 { guard offset < bytes.count else { throw PairingV2.Error.invalidJSON }; offset += 1 }
        }
        throw PairingV2.Error.invalidJSON
    }
    mutating func value(depth: Int) throws {
        guard depth <= 64 else { throw PairingV2.Error.invalidJSON }
        space(); guard offset < bytes.count else { throw PairingV2.Error.invalidJSON }
        switch bytes[offset] {
        case 123:
            offset += 1; space(); var keys = Set<String>()
            if offset < bytes.count && bytes[offset] == 125 { offset += 1; return }
            while true {
                let key = try string(); guard keys.insert(key).inserted else { throw PairingV2.Error.duplicateKey(key) }
                try take(58); try value(depth: depth + 1); space()
                guard offset < bytes.count else { throw PairingV2.Error.invalidJSON }
                if bytes[offset] == 125 { offset += 1; return }; try take(44)
            }
        case 91:
            offset += 1; space()
            if offset < bytes.count && bytes[offset] == 93 { offset += 1; return }
            while true {
                try value(depth: depth + 1); space(); guard offset < bytes.count else { throw PairingV2.Error.invalidJSON }
                if bytes[offset] == 93 { offset += 1; return }; try take(44)
            }
        case 34: _ = try string()
        default:
            let start = offset
            while offset < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[offset]) { offset += 1 }
            guard offset > start else { throw PairingV2.Error.invalidJSON }
            // The typed decoder subsequently checks the primitive's grammar and expected type.
        }
    }
}
