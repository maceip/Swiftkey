import Foundation
import Vapor
import SwiftKeyPasskeyTest

@main struct PasskeyTestServerMain {
    static func main() async throws {
        guard let configuration = try PasskeyTestConfiguration.fromEnvironment() else {
            throw Abort(.badRequest, reason: "Set SWIFTKEY_PASSKEY_TEST_ENABLED=1, SWIFTKEY_PASSKEY_RP_ID and SWIFTKEY_PASSKEY_ORIGIN explicitly")
        }
        // This standalone executable neither reads nor initializes authority state.
        // HTTPS deployments require a separate local reverse proxy; this helper
        // intentionally serves only the documented localhost development origin.
        guard configuration.origin.hasPrefix("http://localhost:"), configuration.localPort >= 1024 else {
            throw Abort(.badRequest, reason: "Standalone harness requires http://localhost:<unprivileged-port>")
        }
        let app = try await Application.make(Environment(name: "production", arguments: [CommandLine.arguments[0]]))
        do {
            app.http.server.configuration.hostname = "127.0.0.1"
            app.http.server.configuration.port = configuration.localPort
            try SwiftKeyPasskeyTest.configureStandalone(app, configuration: configuration)
            print("Ephemeral passkey test: \(configuration.origin)/passkeys/test")
            print("No SwiftKey authority state is opened. Credentials disappear when this process stops.")
            try await app.execute()
        } catch {
            try? await app.asyncShutdown(); throw error
        }
        try await app.asyncShutdown()
    }
}
