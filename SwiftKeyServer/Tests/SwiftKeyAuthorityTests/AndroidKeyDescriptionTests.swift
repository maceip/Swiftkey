import Foundation
import Testing
@testable import SwiftKeyAuthority

// Minimal DER construction solely for schema tests. Production parsing uses
// SwiftASN1 and real X.509 verification, never these fixture bytes.
private enum FixtureDER {
    static func node(_ tag: [UInt8], _ body: Data) -> Data {
        let count = body.count
        let length: [UInt8] = count < 128 ? [UInt8(count)] : (count < 256 ? [0x81, UInt8(count)] : [0x82, UInt8(count >> 8), UInt8(count & 255)])
        return Data(tag + length) + body
    }
    static func sequence(_ values: [Data]) -> Data { node([0x30], values.reduce(Data(), +)) }
    static func set(_ values: [Data]) -> Data { node([0x31], values.reduce(Data(), +)) }
    static func octets(_ data: Data) -> Data { node([4], data) }
    static func integer(_ value: UInt16, enumeration: Bool = false) -> Data {
        var bytes = value > 255 ? [UInt8(value >> 8), UInt8(value & 255)] : [UInt8(value)]
        if bytes[0] >= 128 { bytes.insert(0, at: 0) }
        return node([enumeration ? 10 : 2], Data(bytes))
    }
    static func tagged(_ number: UInt16, _ data: Data) -> Data {
        var bytes: [UInt8] = number < 31 ? [0xa0 | UInt8(number)] : [0xbf]
        if number >= 31 { if number >= 128 { bytes.append(UInt8(number >> 7) | 0x80) }; bytes.append(UInt8(number & 127)) }
        return node(bytes, data)
    }
    static let challenge = Data(repeating: 7, count: 32)
    static let config = ServerConfiguration(stateDirectory: "/unused", androidPackage: "test.fixture", androidSigningCertificateSHA256: String(repeating: "ab", count: 32))
    static func description(fault: String = "") -> Data {
        let package = sequence([octets(Data((fault == "package" ? "wrong.package" : "test.fixture").utf8)), integer(1)])
        let app = sequence([set([package]), set([octets(Data(repeating: fault == "signer" ? 0xac : 0xab, count: 32))])])
        let lockedByte: UInt8 = fault == "unlocked" ? 0 : (fault == "berTrue" ? 1 : (fault == "nonstandardTrue" ? 2 : 0xff))
        let boolBytes = fault == "boolLength" ? Data([1, 1]) : Data([lockedByte])
        let root = sequence([octets(Data(repeating: 1, count: 32)), node([fault == "boolTag" ? 4 : 1], boolBytes), integer(fault == "boot" ? 2 : 0, enumeration: true), octets(Data(repeating: 2, count: 32))])
        var hardware = [tagged(1, set([integer(fault == "purpose" ? 3 : 2)])), tagged(2, integer(3)), tagged(3, integer(256)), tagged(5, set([integer(fault == "digest" ? 2 : 4)])), tagged(10, integer(fault == "curve" ? 2 : 1)), tagged(702, integer(fault == "origin" ? 2 : 0)), tagged(704, root)]
        if fault == "duplicate" { hardware.append(tagged(702, integer(0))) }
        if fault == "missingHardware" { hardware.removeFirst() }
        return sequence([integer(400), integer(fault == "attestationLevel" ? 1 : 2, enumeration: true), integer(400), integer(fault == "keyLevel" ? 1 : 2, enumeration: true), octets(fault == "challenge" ? Data(repeating: 8, count: 32) : challenge), octets(Data()), sequence([tagged(709, octets(app))]), sequence(hardware)])
    }
}

@Test func validStrongBoxDescriptionMatchesExactPolicy() throws {
    let identity = try AndroidKeyDescription.parse(FixtureDER.description(), expectedChallenge: FixtureDER.challenge, configuration: FixtureDER.config)
    #expect(identity.package == "test.fixture")
    #expect(identity.version == 1)
}

@Test(arguments: ["package", "signer", "unlocked", "boot", "purpose", "digest", "curve", "origin", "duplicate", "missingHardware", "attestationLevel", "keyLevel", "challenge", "nonstandardTrue", "boolLength", "boolTag", "berTrue"])
func invalidAttestationPolicyIsRejected(_ fault: String) throws {
    #expect(throws: (any Error).self) { try AndroidKeyDescription.parse(FixtureDER.description(fault: fault), expectedChallenge: FixtureDER.challenge, configuration: FixtureDER.config) }
}

@Test func malformedDERIsRejected() {
    #expect(throws: (any Error).self) { try AndroidKeyDescription.parse(FixtureDER.description() + Data([0]), expectedChallenge: FixtureDER.challenge, configuration: FixtureDER.config) }
}
