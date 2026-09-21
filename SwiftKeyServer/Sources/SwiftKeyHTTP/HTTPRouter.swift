import Foundation
import Vapor
import SwiftKeyAuthority
import SwiftKeyCore

public struct ConsoleAssets: Sendable {
    let indexHTML: Data
    let script: Data
    let stylesheet: Data
    let fonts: [String: Data]

    public init(indexHTML: Data, script: Data, stylesheet: Data, fonts: [String: Data] = [:]) {
        self.indexHTML = indexHTML; self.script = script; self.stylesheet = stylesheet
        self.fonts = fonts
    }
}

private struct Empty: Codable, Sendable {}
private struct ServerTime: Codable, Sendable {
    let unixTime: UInt64
    let epoch: UInt64
    let epochStart: UInt64
    let epochEnd: UInt64
}

private func json<T: Encodable>(_ value: T, status: HTTPResponseStatus = .ok) throws -> Response {
    let data = try JSONEncoder().encode(value)
    return Response(status: status, headers: HTTPHeaders([("Content-Type", "application/json; charset=utf-8")]),
        body: .init(data: data))
}

private func errorResponse(_ error: any Error) -> Response {
    let code: String
    let message: String
    let status: HTTPResponseStatus
    if let failure = error as? AuthorityError {
        code = failure.code; message = failure.description
        switch code {
        case "replayedWorkload": status = .conflict
        case "staleView", "sessionBusy", "v2Required": status = .conflict
        case "staleState", "staleMembership", "staleChallenge", "requestConflict", "identityReserved", "alreadyAccepted", "rootAlreadyBound": status = .conflict
        case "rateLimited": status = .tooManyRequests
        case "v2Unavailable", "trustUnavailable", "unavailable", "internalError": status = .serviceUnavailable
        case "expired": status = .gone
        case "invalidRequest": status = .badRequest
        case "notFound": status = .notFound
        default: status = .forbidden
        }
    } else if let failure = error as? any AbortError {
        status = failure.status
        code = status == .notFound ? "notFound" : "invalidRequest"
        message = status == .notFound ? "Resource not found" : "Invalid HTTP request"
    } else if error is DecodingError || error is ProtocolError || error is PairingV2.Error {
        code = "invalidRequest"; message = "Invalid protocol request"; status = .badRequest
    } else {
        code = "internalError"; message = "Authority operation failed"; status = .internalServerError
        // No request/response bodies, bearer values, or persistence internals.
        FileHandle.standardError.write(Data("Authority failure: \(type(of: error))\n".utf8))
    }
    return (try? json(AuthorityErrorResponse(code: code, error: message), status: status))
        ?? Response(status: .internalServerError)
}

private func bearer(_ header: String?) throws -> String {
    guard let header, header.hasPrefix("Bearer "), (8...4103).contains(header.utf8.count) else {
        throw AuthorityError.protocolFailure(code: "unauthorized", message: "Bearer authorization is required")
    }
    return String(header.dropFirst(7))
}

private func authorizationHeader(_ request: Request) throws -> String? {
    let values = request.headers["Authorization"]
    guard values.count <= 1 else {
        throw AuthorityError.protocolFailure(code: "unauthorized", message: "Ambiguous bearer authorization")
    }
    return values.first
}

/// All routes defer collection so authentication and transport budgets run first.
private func route(_ method: HTTPMethod, _ path: String, on router: any RoutesBuilder,
                   use handler: @escaping @Sendable (Request) async throws -> Response) {
    router.on(method, path.pathComponents, body: .stream, use: handler)
}

private func collectBody(_ request: Request, limit: Int) async throws -> Data {
    // Vapor's collector checks >= max while the protocol accepts exactly limit
    // bytes. Pre-collected request bodies bypass that collector's bound entirely.
    if let buffered = request.body.data, buffered.readableBytes > limit {
        throw Abort(.payloadTooLarge)
    }
    let buffer = try await request.eventLoop.flatSubmit {
        request.body.collect(max: limit + 1)
    }.get()
    guard let buffer else { return Data() }
    guard buffer.readableBytes <= limit else { throw Abort(.payloadTooLarge) }
    return Data(buffer.readableBytesView)
}

private struct SecurityHeaders: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response: Response
        do { response = try await next.respond(to: request) }
        catch { response = errorResponse(error) }
        response.headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
        response.headers.replaceOrAdd(name: "Content-Security-Policy", value: "default-src 'none'; script-src 'self'; style-src 'self'; font-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'; form-action 'none'")
        response.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        response.headers.replaceOrAdd(name: "Cross-Origin-Resource-Policy", value: "same-origin")
        response.headers.replaceOrAdd(name: "Referrer-Policy", value: "no-referrer")
        response.headers.replaceOrAdd(name: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()")
        response.headers.replaceOrAdd(name: "X-Frame-Options", value: "DENY")
        return response
    }
}

private struct AdminAuthorization: AsyncMiddleware {
    let tokenHash: Data

    init(adminToken: String, bootstrapToken: String) throws {
        guard adminToken.utf8.count >= 32, adminToken.utf8.count <= 4096,
              adminToken.utf8.allSatisfy({ 0x21...0x7e ~= $0 }), adminToken != bootstrapToken else {
            throw AuthorityError.protocolFailure(code: "invalidRequest", message: "Admin token must be a separate secret of at least 32 bytes")
        }
        tokenHash = ProtocolCrypto.sha256(Data(adminToken.utf8))
    }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let components = request.url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2, components[0] == "v1", components[1] == "admin" else {
            return try await next.respond(to: request)
        }
        // Authenticate before looking up accounts or interpreting query/body data.
        guard request.headers["Authorization"].count == 1,
              let token = try? bearer(request.headers.first(name: "Authorization")) else { throw unauthorized() }
        let candidate = ProtocolCrypto.sha256(Data(token.utf8))
        var difference: UInt8 = 0
        for (left, right) in zip(candidate, tokenHash) { difference |= left ^ right }
        guard difference == 0 else { throw unauthorized() }
        return try await next.respond(to: request)
    }

    private func unauthorized() -> AuthorityError {
        .protocolFailure(code: "unauthorized", message: "Admin bearer authorization is required")
    }
}

private struct LedgerQuery {
    let after: UInt64
    let limit: Int
    let accountID: String?

    init(_ query: String?) throws {
        var values: [String: String] = [:]
        if let query, !query.isEmpty {
            guard query.utf8.count <= 1024 else { throw Self.invalid() }
            for part in query.split(separator: "&", omittingEmptySubsequences: false) {
                let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pair.count == 2, let key = String(pair[0]).removingPercentEncoding,
                      let value = String(pair[1]).removingPercentEncoding,
                      ["after", "limit", "accountID"].contains(key), values[key] == nil else { throw Self.invalid() }
                values[key] = value
            }
        }
        let cursor = values["after"] ?? "0"
        let count = values["limit"] ?? "100"
        guard !cursor.isEmpty, cursor.utf8.allSatisfy({ 0x30...0x39 ~= $0 }), let after = UInt64(cursor),
              !count.isEmpty, count.utf8.allSatisfy({ 0x30...0x39 ~= $0 }), let limit = Int(count),
              (1...200).contains(limit) else { throw Self.invalid() }
        if let id = values["accountID"] { try validateAccountID(id) }
        self.after = after; self.limit = limit; self.accountID = values["accountID"]
    }

    private static func invalid() -> AuthorityError {
        .protocolFailure(code: "invalidRequest", message: "Invalid ledger pagination")
    }
}

private func validateAccountID(_ value: String) throws {
    guard !value.isEmpty, value.utf8.count <= 256,
          value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
          !value.contains("/") else {
        throw AuthorityError.protocolFailure(code: "invalidRequest", message: "Invalid account identifier")
    }
}

private func endpoint<T: Decodable & Sendable, R: Encodable & Sendable>(
    _ path: String, router: any RoutesBuilder,
    body: @escaping @Sendable (T, String?) async throws -> R
) {
    route(.POST, path, on: router) { request in
        let authorization = try authorizationHeader(request)
        let bytes = try await collectBody(request, limit: 2_000_000)
        let value = try JSONDecoder().decode(T.self, from: bytes)
        return try json(await body(value, authorization))
    }
}

/// The executable binds only loopback. Treat every request as one transport
/// source, never trust forwarded-IP headers. This conservative source budget
/// also caps all unauthenticated work when a local reverse proxy is present.
private actor V2RequestBudget {
    private var start: UInt64 = 0
    private var total = 0
    private var expensive = 0
    func accept(expensive isExpensive: Bool) throws {
        let now = UInt64(Date().timeIntervalSince1970)
        if now < start || now - start >= 60 { start = now; total = 0; expensive = 0 }
        try requireHTTP(total < 240 && (!isExpensive || expensive < 16))
        total += 1; if isExpensive { expensive += 1 }
    }
    private func requireHTTP(_ allowed: Bool) throws {
        if !allowed { throw AuthorityError.protocolFailure(code: "rateLimited", message: "V2 transport request budget exhausted") }
    }
}
private struct V2RosterRequest: Decodable, Sendable {
    let accountID: String
    init(from decoder: Decoder) throws {
        struct Key: CodingKey { let stringValue: String; var intValue: Int? { nil }; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil } }
        let c = try decoder.container(keyedBy: Key.self)
        guard c.allKeys.count == 1, c.allKeys.first?.stringValue == "accountID" else { throw PairingV2.Error.invalidJSON }
        accountID = try c.decode(String.self, forKey: Key(stringValue: "accountID")!)
        try PairingV2.validateID(accountID)
    }
}
private func v2Endpoint<T: Decodable & Sendable, R: Encodable & Sendable>(
    _ path: String, router: any RoutesBuilder, budget: V2RequestBudget,
    body: @escaping @Sendable (T, String?) async throws -> R
) {
    route(.POST, path, on: router) { request in
        try await budget.accept(expensive: path.hasSuffix("/attest") || path.hasSuffix("/prepare"))
        let authorization = try authorizationHeader(request)
        let bytes = try await collectBody(request, limit: 750_000)
        let value = try PairingV2JSON.decode(T.self, from: bytes)
        return try json(await body(value, authorization))
    }
}

public enum SwiftKeyHTTP {
    public static func configure(_ app: Application, authority: Authority, adminToken: String,
                                 bootstrapToken: String, console: ConsoleAssets) throws {
        let authorization = try AdminAuthorization(adminToken: adminToken, bootstrapToken: bootstrapToken)
        let workspaceSessions = BrowserWorkspaceSessions(authority: authority)
        let v2Budget = V2RequestBudget()
        // Keep byte limits on the received protocol representation and prevent
        // lower-level trace/debug logs from exposing headers or body chunks.
        app.http.server.configuration.requestDecompression = .disabled
        // Bound idle sockets even before Vapor has enough bytes to dispatch a
        // request. This is an inactivity limit, not a total upload deadline.
        app.http.server.configuration.idleTimeout = .seconds(30)
        app.logger.logLevel = max(.info, app.logger.logLevel)
        app.http.server.configuration.logger.logLevel = max(.info, app.http.server.configuration.logger.logLevel)
        // Own the middleware stack: Vapor defaults log request URIs and render a
        // different error envelope. Never log bearer/capability-bearing input.
        app.middleware = .init()
        app.middleware.use(SecurityHeaders())
        // App-wide middleware also protects unknown admin paths and methods.
        app.middleware.use(authorization)
        route(.GET, "/", on: app) { _ in asset(console.indexHTML, type: "text/html; charset=utf-8") }
        route(.GET, "/app.js", on: app) { _ in asset(console.script, type: "text/javascript; charset=utf-8") }
        route(.GET, "/style.css", on: app) { _ in asset(console.stylesheet, type: "text/css; charset=utf-8") }
        // Only these bundled assets can be served; never map a URL to a file path
        // or register arbitrary names supplied by the asset dictionary.
        for name in ["host-grotesk.woff2", "jetbrains-mono.woff2"] {
            if let font = console.fonts[name] {
                route(.GET, "/fonts/" + name, on: app) { _ in asset(font, type: "font/woff2") }
            }
        }
        route(.GET, "/health", on: app) { _ in
            let status = try await authority.status()
            return try json(["status": "ok", "storage": status.storage])
        }
        route(.GET, "/v1/time", on: app) { _ in
            let now = UInt64(Date().timeIntervalSince1970); let epoch = now / Epoch.duration
            return try json(ServerTime(unixTime: now, epoch: epoch,
                epochStart: epoch * Epoch.duration, epochEnd: (epoch + 1) * Epoch.duration))
        }
        endpoint("/v1/bootstrap/challenge", router: app) { (_: Empty, authorization) in try await authority.bootstrapChallenge(token: bearer(authorization)) }
        endpoint("/v1/bootstrap/enroll", router: app) { (request: EnrollRequest, authorization) in try await authority.bootstrapEnroll(request, token: bearer(authorization)) }
        endpoint("/v1/challenges", router: app) { (request: ChallengeRequest, _) in try await authority.challenge(request) }
        endpoint("/v1/epochs", router: app) { (request: IssueEpochRequest, _) in try await authority.issueEpoch(request) }
        endpoint("/v1/workloads", router: app) { (request: VerifyWorkloadRequest, _) in try await authority.verifyWorkload(request) }
        endpoint("/v1/credentials/verify", router: app) { (request: VerifyCredentialRequest, _) in try await authority.verifyCredential(request) }
        endpoint("/v1/pairings/challenge", router: app) { (request: PairingChallengeRequest, _) in try await authority.pairingChallenge(request) }
        endpoint("/v1/pairings/enroll", router: app) { (request: EnrollRequest, _) in try await authority.pairingEnroll(request) }
        endpoint("/v1/pairings/approve", router: app) { (request: MembershipRequest, _) in try await authority.approvePairing(request) }
        endpoint("/v1/pairings/confirm", router: app) { (request: MembershipRequest, _) in try await authority.confirmPairing(request) }
        endpoint("/v1/devices/revoke", router: app) { (request: MembershipRequest, _) in try await authority.revoke(request) }
        endpoint("/v1/recovery", router: app) { (request: RecoveryRequest, _) in try await authority.recover(request) }
        v2Endpoint("/v2/identities/prepare", router: app, budget: v2Budget) { (request: PairingV2.PreparationRequest, _) in try await authority.prepareIdentityV2(request) }
        v2Endpoint("/v2/identities/attest", router: app, budget: v2Budget) { (request: PairingV2.AttestationRequest, _) in try await authority.attestIdentityV2(request) }
        v2Endpoint("/v2/challenges", router: app, budget: v2Budget) { (request: PairingV2.RootChallengeRequest, _) in try await authority.rootChallengeV2(request) }
        v2Endpoint("/v2/pairings/inspect", router: app, budget: v2Budget) { (request: PairingV2.InspectionRequest, _) in try await authority.inspectPairingV2(request) }
        v2Endpoint("/v2/operations", router: app, budget: v2Budget) { (request: PairingV2.OperationRequest, _) in try await authority.executeV2(request) }
        v2Endpoint("/v2/accounts/roster", router: app, budget: v2Budget) { (request: V2RosterRequest, authorization) in try await authority.accountRosterV2(accountID: request.accountID, bearer: bearer(authorization)) }

        let admin = app.grouped("v1", "admin")
        route(.POST, "/workspace", on: admin) { request in
            let bytes = try await collectBody(request, limit: 16_384)
            let query = try JSONDecoder().decode(WorkspaceQuery.self, from: bytes)
            return try json(await authority.workspace(query))
        }
        route(.POST, "/ui/sessions", on: admin) { _ in
            try json(await workspaceSessions.create(), status: .created)
        }
        route(.POST, "/ui/sessions/:id/events", on: admin) { request in
            let bytes = try await collectBody(request, limit: 131_072)
            let events = try JSONDecoder().decode(BrowserEventRequest.self, from: bytes)
            return try json(await workspaceSessions.dispatch(id: request.parameters.require("id"), request: events))
        }
        route(.DELETE, "/ui/sessions/:id", on: admin) { request in
            await workspaceSessions.disconnect(id: try request.parameters.require("id"))
            return Response(status: .noContent)
        }
        route(.GET, "/accounts", on: admin) { _ in try json(await authority.listAccounts()) }
        route(.POST, "/accounts", on: admin) { request in
            let bytes = try await collectBody(request, limit: 16_384)
            let value = try JSONDecoder().decode(CreateAccountRequest.self, from: bytes)
            return try json(await authority.createAccount(value), status: .created)
        }
        route(.GET, "/accounts/:id", on: admin) { request in
            let id = try request.parameters.require("id"); try validateAccountID(id)
            return try json(await authority.account(id: id))
        }
        route(.POST, "/accounts/:id/enrollment-invitation", on: admin) { request in
            let id = try request.parameters.require("id"); try validateAccountID(id)
            return try json(await authority.reissueEnrollmentInvitation(accountID: id))
        }
        route(.GET, "/accounts/:id/devices", on: admin) { request in
            let id = try request.parameters.require("id"); try validateAccountID(id)
            return try json(await authority.devices(accountID: id))
        }
        route(.GET, "/accounts/:id/epochs", on: admin) { request in
            let id = try request.parameters.require("id"); try validateAccountID(id)
            return try json(await authority.epochs(accountID: id))
        }
        route(.GET, "/ledger", on: admin) { request in
            let query = try LedgerQuery(request.url.query)
            return try json(await authority.ledger(after: query.after, limit: query.limit, accountID: query.accountID))
        }
        route(.GET, "/status", on: admin) { _ in try json(await authority.status()) }
    }

    private static func asset(_ bytes: Data, type: String) -> Response {
        Response(status: .ok, headers: HTTPHeaders([("Content-Type", type)]), body: .init(data: bytes))
    }
}
