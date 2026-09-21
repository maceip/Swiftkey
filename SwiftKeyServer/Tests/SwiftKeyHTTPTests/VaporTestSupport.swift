import Foundation
import Vapor
import VaporTesting
import SwiftKeyAuthority
@testable import SwiftKeyHTTP

/// Each test owns its configured Vapor app, and shutdown runs when configuration,
/// request dispatch, or an assertion helper throws. All authority state is temporary.
func withHTTPApplication(authority: Authority, adminToken: String, bootstrapToken: String,
                         console: ConsoleAssets, _ run: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    app.logger.logLevel = .critical
    do {
        try SwiftKeyHTTP.configure(app, authority: authority, adminToken: adminToken,
            bootstrapToken: bootstrapToken, console: console)
        try await run(app)
    } catch {
        try? await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}

extension Application {
    /// A thin convenience over VaporTesting, preserving explicit wire bytes and
    /// duplicate headers instead of implicitly encoding through Content.
    func execute(uri: String, method: HTTPMethod, headers: HTTPHeaders = [:], body: ByteBuffer? = nil) async throws -> TestingHTTPResponse {
        try await testing().sendRequest(method, uri, headers: headers, body: body)
    }
}

func paddedHTTPBody(_ json: String, count: Int) -> ByteBuffer {
    precondition(json.utf8.count <= count)
    return ByteBuffer(string: json + String(repeating: " ", count: count - json.utf8.count))
}
