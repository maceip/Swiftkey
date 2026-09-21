import Foundation
import Testing
import SwiftKeyCore
@testable import SwiftKeyClient

@Test func pairingLinksRequireIndependentOriginPinAndFullCanonicalCapability() throws {
    let config = PairingClientConfiguration(serverURL: "https://authority.example", serverPublicKey: SoftwareSigningKey().publicKey, audience: PairingV2.audience)
    let id = "00112233-4455-4677-8899-aabbccddeeff", secret = Data(repeating: 255, count: 32)
    let link = try PairingInvitation.link(pairingID: id, capability: secret, configuration: config)
    let parsed = try PairingInvitation(link: link, configuration: config)
    #expect(parsed.pairingID == id && parsed.capability == secret)
    #expect(!String(describing: parsed).contains(link) && !String(reflecting: parsed).contains(link))
    for invalid in [link.replacingOccurrences(of: "authority.example", with: "attacker.example"),
        link.replacingOccurrences(of: "/pair#", with: "/pair?"), link + "=", link + ".extra",
        link.replacingOccurrences(of: id, with: id.uppercased()),
        link.replacingOccurrences(of: "#v2.", with: "#v1."),
        link.replacingOccurrences(of: "authority.example", with: "authority.example@attacker.example"),
        link.replacingOccurrences(of: "https:", with: "http:")] {
        #expect(throws: PairingClientError.invalidInvitation) { try PairingInvitation(link: invalid, configuration: config) }
    }
}

@Test func pairingConfigurationRejectsNetworkTrustBootstrapAndNoncanonicalOrigins() throws {
    let key = SoftwareSigningKey().publicKey
    for url in ["http://authority.example", "https://authority.example/", "https://authority.example/a", "https://user@authority.example", "https://authority.example?x=1", "https://authority.example#pin"] {
        #expect(throws: ClientError.invalidConfiguration) {
            try PairingClientConfiguration(serverURL: url, serverPublicKey: key, audience: PairingV2.audience).validate()
        }
    }
    try PairingClientConfiguration(serverURL: "http://127.0.0.1:18088", serverPublicKey: key, audience: PairingV2.audience).validate()
}
