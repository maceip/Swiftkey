import Foundation

/// Explicit, opt-in configuration for an ephemeral interoperability harness.
public struct PasskeyTestConfiguration: Sendable {
    public let relyingPartyID: String
    public let origin: String
    public let authority: String
    public let secureCookies: Bool
    public let localPort: Int

    public init(relyingPartyID: String, origin: String) throws {
        guard let url = URLComponents(string: origin), let scheme = url.scheme,
              ["http", "https"].contains(scheme), let host = url.host,
              host == host.lowercased(), host == relyingPartyID,
              !host.isEmpty, host.utf8.count <= 253,
              host.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }),
              !host.hasPrefix("."), !host.hasSuffix("."), !host.contains(".."),
              url.user == nil, url.password == nil, url.path.isEmpty,
              url.query == nil, url.fragment == nil,
              scheme == "https" || host == "localhost",
              url.port == nil || (1024...65535).contains(url.port!),
              origin == "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "") else {
            throw PasskeyTestError.configuration
        }
        self.relyingPartyID = relyingPartyID
        self.origin = origin
        self.authority = host + (url.port.map { ":\($0)" } ?? "")
        self.secureCookies = scheme == "https"
        self.localPort = url.port ?? (scheme == "https" ? 443 : 80)
    }

    /// No routes are installed unless explicitly enabled. Partial or invalid
    /// configuration fails startup instead of silently picking an RP identity.
    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self? {
        let enabled = environment["SWIFTKEY_PASSKEY_TEST_ENABLED"]
        guard enabled == "1" else {
            guard enabled == nil || enabled == "0" else { throw PasskeyTestError.configuration }
            guard environment["SWIFTKEY_PASSKEY_RP_ID"] == nil,
                  environment["SWIFTKEY_PASSKEY_ORIGIN"] == nil else { throw PasskeyTestError.configuration }
            return nil
        }
        guard let id = environment["SWIFTKEY_PASSKEY_RP_ID"],
              let origin = environment["SWIFTKEY_PASSKEY_ORIGIN"] else { throw PasskeyTestError.configuration }
        return try Self(relyingPartyID: id, origin: origin)
    }
}

enum PasskeyTestError: Error {
    case configuration, invalidRequest, session, ceremony, expired, credential, verification, capacity, rateLimited
}
