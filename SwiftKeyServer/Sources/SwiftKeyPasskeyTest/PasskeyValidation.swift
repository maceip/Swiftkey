import Foundation
import SwiftCBOR
import WebAuthn

/// These checks supply bindings not exposed/enforced by the pinned RP library.
/// Cryptographic WebAuthn verification remains in WebAuthnManager.
enum PasskeyValidation {
    static func base64URL(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func credentialID(_ id: URLEncodedBase64, raw: [UInt8]) throws -> String {
        guard (1...1023).contains(raw.count), id.asString() == base64URL(raw) else {
            throw PasskeyTestError.credential
        }
        return base64URL(raw)
    }

    static func clientData(_ bytes: [UInt8]) throws {
        struct Context: Decodable { let crossOrigin: Bool?; let topOrigin: String? }
        guard bytes.count <= 16_384 else { throw PasskeyTestError.invalidRequest }
        let context = try JSONDecoder().decode(Context.self, from: Data(bytes))
        guard context.crossOrigin != true, context.topOrigin == nil else { throw PasskeyTestError.verification }
    }

    static func flags(_ data: [UInt8], registration: Bool) throws -> (eligible: Bool, backedUp: Bool) {
        guard data.count >= 37 else { throw PasskeyTestError.verification }
        let flags = data[32]
        let eligible = flags & 0x08 != 0, backedUp = flags & 0x10 != 0
        guard flags & 0x05 == 0x05, !backedUp || eligible,
              (flags & 0x40 != 0) == registration,
              flags & 0x80 == 0 else { throw PasskeyTestError.verification }
        // This bounded harness requests no authenticator extensions.
        if !registration, data.count != 37 { throw PasskeyTestError.verification }
        return (eligible, backedUp)
    }

    static func registration(_ credential: RegistrationCredential) throws -> String {
        let id = try credentialID(credential.id, raw: credential.rawID)
        try clientData(credential.attestationResponse.clientDataJSON)
        let bytes = credential.attestationResponse.attestationObject
        guard bytes.count <= 65_536 else { throw PasskeyTestError.invalidRequest }
        let stream = BoundedCBORInput(bytes)
        let decoder = CBORDecoder(stream: stream, options: CBOROptions(maximumDepth: 8))
        guard let object = try decoder.decodeItem(), stream.remaining == 0,
              case let .map(map) = object, map.count == 3,
              object["fmt"] == .utf8String("none"), object["attStmt"] == .map([:]),
              case let .byteString(authData)? = object["authData"] else { throw PasskeyTestError.verification }
        _ = try flags(authData, registration: true)
        guard authData.count >= 55 else { throw PasskeyTestError.verification }
        let count = Int(authData[53]) * 256 + Int(authData[54])
        guard count > 0, count <= 1023, authData.count > 55 + count,
              Array(authData[55..<(55 + count)]) == credential.rawID else { throw PasskeyTestError.credential }
        return id
    }
}

private final class BoundedCBORInput: CBORInputStream {
    private var bytes: ArraySlice<UInt8>
    var remaining: Int { bytes.count }
    init(_ bytes: [UInt8]) { self.bytes = bytes[...] }
    func popByte() throws(CBORError) -> UInt8 {
        guard let first = bytes.first else { throw .unfinishedSequence }
        bytes = bytes.dropFirst(); return first
    }
    func popBytes(_ count: Int) throws(CBORError) -> ArraySlice<UInt8> {
        guard count >= 0, count <= bytes.count else { throw .unfinishedSequence }
        let result = bytes.prefix(count); bytes = bytes.dropFirst(count); return result
    }
}
