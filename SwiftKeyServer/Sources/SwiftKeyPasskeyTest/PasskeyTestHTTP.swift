import Foundation
import Vapor
import WebAuthn

public enum SwiftKeyPasskeyTest {
    /// A dedicated local harness owns its middleware stack. Existing authorities
    /// should call configure instead, preserving their own transport policies.
    public static func configureStandalone(_ app: Application, configuration: PasskeyTestConfiguration) throws {
        app.middleware = .init()
        app.middleware.use(PasskeyUnhandledErrorMiddleware())
        app.logger.logLevel = max(.info, app.logger.logLevel)
        app.http.server.configuration.logger.logLevel = max(.info, app.http.server.configuration.logger.logLevel)
        app.http.server.configuration.requestDecompression = .disabled
        app.http.server.configuration.idleTimeout = .seconds(30)
        try configure(app, configuration: configuration)
    }
    /// The caller opts in explicitly. This target has no authority dependency.
    public static func configure(_ app: Application, configuration: PasskeyTestConfiguration) throws {
        let store = PasskeyTestStore(configuration: configuration)
        try configure(app, configuration: configuration, store: store)
    }

    static func configure(_ app: Application, configuration: PasskeyTestConfiguration, store: PasskeyTestStore) throws {
        app.middleware.use(PasskeyHTTPMiddleware(configuration: configuration))
        for (path, name, ext, type) in [
            ("/passkeys/test", "passkeys", "html", "text/html; charset=utf-8"),
            ("/passkeys/test/app.js", "passkeys", "js", "text/javascript; charset=utf-8"),
            ("/passkeys/test/style.css", "passkeys", "css", "text/css; charset=utf-8"),
            ("/passkeys/test/host-grotesk.woff2", "host-grotesk", "woff2", "font/woff2"),
            ("/passkeys/test/jetbrains-mono.woff2", "jetbrains-mono", "woff2", "font/woff2")
        ] {
            guard let url = Bundle.module.url(forResource: name, withExtension: ext) else { throw PasskeyTestError.configuration }
            let bytes = try Data(contentsOf: url)
            app.on(.GET, path.pathComponents, body: .stream) { _ in
                Response(status: .ok, headers: ["Content-Type": type], body: .init(data: bytes))
            }
        }
        app.on(.GET, "passkeys", "test", "bootstrap", body: .stream) { request async throws -> Response in
            let oldID = try passkeySessionCookie(request)
            try await store.acceptRequest(sessionID: oldID)
            let (session, bootstrap) = try await store.bootstrap(existing: oldID)
            let response = try passkeyJSON(bootstrap)
            response.headers.add(name: "Set-Cookie", value: "swiftkey_passkey_test=\(session.id); Path=/passkeys/test; Max-Age=1800; HttpOnly; SameSite=Strict" + (configuration.secureCookies ? "; Secure" : ""))
            return response
        }
        func endpoint<T: Decodable & Sendable, R: Encodable & Sendable>(_ suffix: String, _ type: T.Type,
            run: @escaping @Sendable (String, T) async throws -> R) {
            app.on(.POST, ("/passkeys/test/" + suffix).pathComponents, body: .stream) { request async throws -> Response in
                let sessionID = try passkeySessionCookie(request)
                try await store.acceptRequest(sessionID: sessionID)
                guard request.headers["X-SwiftKey-Test-CSRF"].count == 1,
                      request.headers.contentType == .json else { throw PasskeyTestError.invalidRequest }
                let authorized = try await store.authorize(sessionID, csrf: request.headers.first(name: "X-SwiftKey-Test-CSRF"))
                let data = try await passkeyBody(request)
                let value = try JSONDecoder().decode(T.self, from: data)
                return try passkeyJSON(await run(authorized, value))
            }
        }
        endpoint("registration/options", RegistrationInput.self) { session, input in
            try await store.beginRegistration(sessionID: session, username: input.username)
        }
        endpoint("registration/verify", RegistrationFinish.self) { session, input in
            try await store.finishRegistration(sessionID: session, ceremonyID: input.ceremonyID, credential: input.credential)
        }
        endpoint("authentication/options", EmptyInput.self) { session, _ in
            try await store.beginAuthentication(sessionID: session)
        }
        endpoint("authentication/verify", AuthenticationFinish.self) { session, input in
            try await store.finishAuthentication(sessionID: session, ceremonyID: input.ceremonyID, credential: input.credential)
        }
        endpoint("signout", EmptyInput.self) { session, _ in
            await store.signOut(sessionID: session); return SignedOut()
        }
    }
}
private struct PasskeyUnhandledErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do { return try await next.respond(to: request) }
        catch {
            let status = (error as? any AbortError)?.status ?? .internalServerError
            let response = try passkeyJSON(["code": status == .notFound ? "notFound" : "invalidRequest",
                "error": "Test resource unavailable."], status: status)
            response.headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
            response.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
            return response
        }
    }
}
private struct RegistrationInput: Decodable, Sendable { let username: String }
private struct EmptyInput: Decodable, Sendable {}
private struct SignedOut: Encodable, Sendable { let authenticated = false }
private struct RegistrationFinish: Decodable, Sendable { let ceremonyID: String; let credential: RegistrationCredential }
private struct AuthenticationFinish: Decodable, Sendable { let ceremonyID: String; let credential: AuthenticationCredential }

private func passkeyJSON<T: Encodable>(_ value: T, status: HTTPResponseStatus = .ok) throws -> Response {
    Response(status: status, headers: ["Content-Type": "application/json; charset=utf-8"],
        body: .init(data: try JSONEncoder().encode(value)))
}
private func passkeySessionCookie(_ request: Request) throws -> String? {
    let values = request.headers["Cookie"].flatMap { $0.split(separator: ";") }
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.split(separator: "=", maxSplits: 1).first == "swiftkey_passkey_test" }
    guard values.count <= 1 else { throw PasskeyTestError.session }
    guard let value = values.first else { return nil }
    let pair = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    guard pair.count == 2, pair[1].utf8.count == 43,
          pair[1].utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw PasskeyTestError.session }
    return String(pair[1])
}
private func passkeyBody(_ request: Request) async throws -> Data {
    let limit = 131_072
    if let buffer = request.body.data, buffer.readableBytes > limit { throw Abort(.payloadTooLarge) }
    let buffer = try await request.eventLoop.flatSubmit { request.body.collect(max: limit + 1) }.get()
    guard let buffer, buffer.readableBytes <= limit else { throw Abort(.payloadTooLarge) }
    return Data(buffer.readableBytesView)
}
private struct PasskeyHTTPMiddleware: AsyncMiddleware {
    let configuration: PasskeyTestConfiguration
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard request.url.path == "/passkeys/test" || request.url.path.hasPrefix("/passkeys/test/") else {
            return try await next.respond(to: request)
        }
        let response: Response
        do {
            guard request.headers["Host"].count == 1,
                  request.headers.first(name: "Host")?.lowercased() == configuration.authority else { throw PasskeyTestError.invalidRequest }
            if request.method != .GET && request.method != .HEAD {
                guard request.headers["Origin"].count == 1,
                      request.headers.first(name: "Origin") == configuration.origin else { throw PasskeyTestError.verification }
            }
            response = try await next.respond(to: request)
        } catch {
            let status: HTTPResponseStatus
            let code: String
            switch error {
            case PasskeyTestError.session: status = .unauthorized; code = "sessionRequired"
            case PasskeyTestError.ceremony: status = .conflict; code = "ceremonyUnavailable"
            case PasskeyTestError.expired: status = .gone; code = "ceremonyExpired"
            case PasskeyTestError.capacity, PasskeyTestError.rateLimited: status = .tooManyRequests; code = "testCapacity"
            case let abort as any AbortError: status = abort.status; code = "invalidRequest"
            default: status = .badRequest; code = "verificationFailed"
            }
            // Do not echo WebAuthn bytes, key material, cookies or exception text.
            response = try passkeyJSON(["code": code, "error": "Passkey test request was not accepted."], status: status)
        }
        response.headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
        response.headers.replaceOrAdd(name: "Content-Security-Policy", value: "default-src 'none'; script-src 'self'; style-src 'self'; font-src 'self'; connect-src 'self'; img-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'")
        response.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        response.headers.replaceOrAdd(name: "Referrer-Policy", value: "no-referrer")
        response.headers.replaceOrAdd(name: "X-Frame-Options", value: "DENY")
        return response
    }
}
