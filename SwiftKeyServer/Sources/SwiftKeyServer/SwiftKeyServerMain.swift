import Foundation
import Vapor
import SwiftKeyAuthority
import SwiftKeyCore
import SwiftKeyHTTP
import SwiftKeyPasskeyTest
import Darwin

@main struct SwiftKeyServerMain {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let passkeyTest = try PasskeyTestConfiguration.fromEnvironment()
        if arguments.contains("--help") {
            print("swiftkey-server --config config/device.json --bootstrap-token-file /private/bootstrap-token --admin-token-file /private/admin-token")
            print("Verify captured evidence without serving: --config config/device.json --verify-attestation-file evidence.json")
            return
        }
        func option(_ name: String) -> String? { guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }; return arguments[index + 1] }
        let configPath = option("--config") ?? "config/device.json"
        let configuration = try JSONDecoder().decode(ServerConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
        if let evidencePath = option("--verify-attestation-file") {
            struct Evidence: Decodable { let challenge: Data; let certificates: [Data] }
            let evidence = try JSONDecoder().decode(Evidence.self, from: Data(contentsOf: URL(fileURLWithPath: evidencePath)))
            let verifier = AndroidAttestationVerifier(configuration: configuration)
            do {
                let identity = try await verifier.verify(certificates: evidence.certificates, challenge: evidence.challenge, now: UInt64(Date().timeIntervalSince1970))
                print("Verified StrongBox attestation: package=\(identity.packageName), version=\(identity.packageVersion), publicKey=\(identity.publicKey.base64EncodedString())")
            } catch {
                FileHandle.standardError.write(Data("Attestation verification failed: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
            return
        }
        guard let tokenPath = option("--bootstrap-token-file") else { throw AuthorityError.rejected("--bootstrap-token-file is required") }
        guard let adminTokenPath = option("--admin-token-file") else { throw AuthorityError.rejected("--admin-token-file is required") }
        let token = try PrivateTokenFile.read(tokenPath)
        let adminToken = try PrivateTokenFile.read(adminTokenPath)
        guard adminToken != token else { throw AuthorityError.rejected("Admin and bootstrap tokens must be different") }
        guard configuration.host == "127.0.0.1", (1024...65535).contains(configuration.port) else { throw AuthorityError.rejected("This local authority binds IPv4 loopback only, using an unprivileged port") }
        let verifier = AndroidAttestationVerifier(configuration: configuration)
        try await verifier.prepare()
        let authority = try Authority(configuration: configuration, bootstrapToken: token, verifier: verifier)
        func resource(_ name: String, extension ext: String) throws -> Data {
            guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
                throw AuthorityError.rejected("Console resources are missing")
            }
            return try Data(contentsOf: url)
        }
        let console = try ConsoleAssets(indexHTML: resource("index", extension: "html"),
            script: resource("app", extension: "js"), stylesheet: resource("style", extension: "css"),
            fonts: ["host-grotesk.woff2": resource("host-grotesk", extension: "woff2"),
                    "jetbrains-mono.woff2": resource("jetbrains-mono", extension: "woff2")])
        // SwiftKey owns command-line parsing and the validated bind address.
        // Do not pass its private-file options or unvalidated Vapor serve flags
        // to Vapor's command parser.
        let environment = Environment(name: "production", arguments: [CommandLine.arguments[0]])
        let app = try await Application.make(environment)
        do {
            app.http.server.configuration.hostname = configuration.host
            app.http.server.configuration.port = configuration.port
            try SwiftKeyHTTP.configure(app, authority: authority, adminToken: adminToken,
                bootstrapToken: token, console: console)
            if let passkeyTest {
                try SwiftKeyPasskeyTest.configure(app, configuration: passkeyTest)
                print("Ephemeral passkey test: \(passkeyTest.origin)/passkeys/test")
            }
            print("SwiftKey authority (Vapor): http://\(configuration.host):\(configuration.port)")
            print("Public key pin file: \(URL(fileURLWithPath: configuration.stateDirectory).appendingPathComponent("server-public-key.txt").path)")
            try await app.execute()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
