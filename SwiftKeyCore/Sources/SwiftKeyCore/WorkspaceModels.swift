import Foundation

/// Public account/credential/ledger read parameters; no session credentials.
public struct WorkspaceQuery: Codable, Sendable, Equatable {
    public let accountID: String?
    public let after: UInt64
    public let limit: Int
    public init(accountID: String? = nil, after: UInt64 = 0, limit: Int = 25) {
        self.accountID = accountID; self.after = after; self.limit = limit
    }
}

/// One authority read. Its metadata describes the server, never a client secret.
public struct WorkspaceOverview: Codable, Sendable, Equatable {
    public let status: AuthorityStatus
    public let accounts: [AccountSummary]
    public let selectedAccountID: String?
    public let devices: [DeviceSummary]
    public let epochs: [EpochSummary]
    public let ledger: LedgerPage
    public let serverURL: String
    public let audience: String
    public let workloadDomain: String
    public init(status: AuthorityStatus, accounts: [AccountSummary], selectedAccountID: String?, devices: [DeviceSummary], epochs: [EpochSummary], ledger: LedgerPage, serverURL: String, audience: String, workloadDomain: String) {
        self.status = status; self.accounts = accounts; self.selectedAccountID = selectedAccountID
        self.devices = devices; self.epochs = epochs; self.ledger = ledger
        self.serverURL = serverURL; self.audience = audience; self.workloadDomain = workloadDomain
    }
}

public struct VerifyCredentialRequest: Codable, Sendable, Equatable {
    public let credential: EpochCredential
    public init(credential: EpochCredential) { self.credential = credential }
}

/// A non-consuming online authorization receipt. Servers return this only after
/// current membership, attestation policy and credential checks succeed. It is
/// a point-in-time result, not authority for accepting a later signed workload.
public struct CredentialVerificationResponse: Codable, Sendable, Equatable {
    public let accountID: String
    public let deviceID: String
    public let epoch: UInt64
    public let checkedAt: UInt64
    public let validUntil: UInt64
    public let credentialHash: Data
    public init(accountID: String, deviceID: String, epoch: UInt64, checkedAt: UInt64, validUntil: UInt64, credentialHash: Data) {
        self.accountID = accountID; self.deviceID = deviceID; self.epoch = epoch
        self.checkedAt = checkedAt; self.validUntil = validUntil; self.credentialHash = credentialHash
    }
}

/// Secret handoff configuration, compatible with the device client's JSON.
/// Unlike WorkspaceOverview, this must never be placed in a ledger or snapshot.
public struct EnrollmentConfiguration: Codable, Sendable, Equatable {
    public let serverURL: String
    public let bootstrapToken: String
    public let serverPublicKey: Data
    public let audience: String
    public let expectedAccountID: String?
    public init(serverURL: String, bootstrapToken: String, serverPublicKey: Data, audience: String, expectedAccountID: String? = nil) {
        self.serverURL = serverURL; self.bootstrapToken = bootstrapToken
        self.serverPublicKey = serverPublicKey; self.audience = audience
        self.expectedAccountID = expectedAccountID
    }
}

public struct EnrollmentBundle: Codable, Sendable, Equatable {
    public let version: Int
    public let accountID: String
    public let label: String
    public let expiresAt: UInt64
    public let configuration: EnrollmentConfiguration
    public init(version: Int = 1, accountID: String, label: String, expiresAt: UInt64, configuration: EnrollmentConfiguration) {
        self.version = version; self.accountID = accountID; self.label = label
        self.expiresAt = expiresAt; self.configuration = configuration
    }
}
