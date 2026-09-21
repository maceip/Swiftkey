import Foundation
import Testing
import SwiftASN1
import X509

private func keyUsageExtension(boolean: [UInt8], oid: UInt8 = 15) -> [UInt8] {
    let body: [UInt8] = [6, 3, 0x55, 0x1d, oid] + boolean + [4, 4, 3, 2, 7, 0x80]
    return [0x30, UInt8(body.count)] + body
}

@Test(arguments: [UInt8(1), UInt8(255)])
func keyUsageCriticalTrueCompatibility(_ value: UInt8) throws {
    let ext = try Certificate.Extension(derEncoded: keyUsageExtension(boolean: [1, 1, value]))
    #expect(ext.critical)
}

@Test(arguments: [[UInt8(1), 1, 0], [1, 1, 2], [1, 2, 0, 1], [2, 1, 1]])
func malformedOrDefaultCriticalEncodingIsRejected(_ bytes: [UInt8]) {
    #expect(throws: (any Error).self) { try Certificate.Extension(derEncoded: keyUsageExtension(boolean: bytes)) }
}

@Test func compatibilityDoesNotApplyToOtherExtensions() {
    #expect(throws: (any Error).self) { try Certificate.Extension(derEncoded: keyUsageExtension(boolean: [1, 1, 1], oid: 19)) }
}

@Test func originalSignedTBSBytesArePreserved() throws {
    let leafData = try Data(contentsOf: #require(Bundle.module.url(forResource: "android-leaf", withExtension: "der", subdirectory: "Fixtures")))
    let issuerData = try Data(contentsOf: #require(Bundle.module.url(forResource: "android-issuer", withExtension: "der", subdirectory: "Fixtures")))
    let leaf = try Certificate(derEncoded: Array(leafData))
    let issuer = try Certificate(derEncoded: Array(issuerData))
    #expect(issuer.publicKey.isValidSignature(leaf.signature, for: leaf))
    let node = try DER.parse(Array(leafData))
    guard case .constructed(let children) = node.content else { Issue.record("Fixture is not a certificate"); return }
    #expect(leaf.tbsCertificateBytes == Array(children)[0].encodedBytes)
    // Changing only critical TRUE to canonical 0xff must invalidate the real
    // signature. The compatibility parser never performs this rewrite.
    var rewritten = leafData
    let flag = try #require(rewritten.range(of: Data([6, 3, 0x55, 0x1d, 15, 1, 1, 1])))
    rewritten[flag.upperBound - 1] = 255
    let changed = try Certificate(derEncoded: Array(rewritten))
    #expect(!issuer.publicKey.isValidSignature(changed.signature, for: changed))
}
