import Foundation

public enum ProtocolError: Error, Sendable, Equatable {
    case invalidField(String)
    case fieldTooLarge
    case invalidPublicKey
    case invalidSignature
    case unsupportedAuthorization
    case challengeExpired
    case epochNotCurrent
    case epochOverflow
    case bindingMismatch
    case credentialRequired
}

/// v1 binary format: ASCII "SwiftKey", u16 BE version, length-prefixed domain,
/// then schema-ordered fields. Strings are NFC UTF-8; lengths are u32 BE.
public struct CanonicalEncoder: Sendable {
    public private(set) var data: Data
    public static let maximumFieldBytes = 1_048_576

    public init(domain: String) throws {
        data = Data("SwiftKey".utf8)
        data.append(contentsOf: [0, 1])
        try append(domain)
    }

    public mutating func append(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    public mutating func append(_ value: String) throws {
        try append(Data(value.precomposedStringWithCanonicalMapping.utf8))
    }

    public mutating func append(_ value: Data) throws {
        guard value.count <= Self.maximumFieldBytes else { throw ProtocolError.fieldTooLarge }
        let count = UInt32(value.count)
        for shift in stride(from: 24, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: count >> UInt32(shift)))
        }
        data.append(value)
    }

    public mutating func appendOptional(_ value: Data?) throws {
        data.append(value == nil ? 0 : 1)
        if let value { try append(value) }
    }
}

func validateIdentifier(_ value: String, _ name: String) throws {
    guard !value.isEmpty, value.utf8.count <= 256,
          !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { throw ProtocolError.invalidField(name) }
}

func validateNonce(_ nonce: Data) throws {
    guard nonce.count == 32 else { throw ProtocolError.invalidField("nonce") }
}
