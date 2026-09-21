import Foundation

/// Administrative views contain public identities and credentials only. They
/// never encode the authority snapshot, enrollment-token hashes, or private keys.
public struct CreateAccountRequest: Codable, Sendable, Equatable {
    public let label: String
    public init(label: String) { self.label = label }
}

public struct AccountSummary: Codable, Sendable, Equatable {
    public let accountID: String
    public let label: String
    public let createdAt: UInt64
    public let status: String
    public let deviceCount: Int
    public let activeDeviceCount: Int
    public let imported: Bool
    /// The authority computes this; clients must not infer it from counts.
    public let canReissueInvitation: Bool

    public init(accountID: String, label: String, createdAt: UInt64, status: String, deviceCount: Int, activeDeviceCount: Int, imported: Bool, canReissueInvitation: Bool = false) {
        self.accountID = accountID
        self.label = label
        self.createdAt = createdAt
        self.status = status
        self.deviceCount = deviceCount
        self.activeDeviceCount = activeDeviceCount
        self.imported = imported
        self.canReissueInvitation = canReissueInvitation
    }
}

public struct AccountListResponse: Codable, Sendable, Equatable {
    public let accounts: [AccountSummary]

    public init(accounts: [AccountSummary]) {
        self.accounts = accounts
    }
}

public struct CreateAccountResponse: Codable, Sendable, Equatable {
    public let account: AccountSummary
    /// Returned only when an invitation is created or reissued, never in reads.
    public let enrollmentToken: String
    public let expiresAt: UInt64

    public init(account: AccountSummary, enrollmentToken: String, expiresAt: UInt64) {
        self.account = account
        self.enrollmentToken = enrollmentToken
        self.expiresAt = expiresAt
    }
}

public struct DeviceSummary: Codable, Sendable, Equatable {
    public let accountID: String
    public let deviceID: String
    public let publicKey: Data
    public let sequence: UInt64
    public let status: String
    public let enrolledAt: UInt64?
    public let revokedAt: UInt64?
    public let lastEpoch: UInt64?

    public init(accountID: String, deviceID: String, publicKey: Data, sequence: UInt64, status: String, enrolledAt: UInt64?, revokedAt: UInt64?, lastEpoch: UInt64?) {
        self.accountID = accountID
        self.deviceID = deviceID
        self.publicKey = publicKey
        self.sequence = sequence
        self.status = status
        self.enrolledAt = enrolledAt
        self.revokedAt = revokedAt
        self.lastEpoch = lastEpoch
    }
}

public struct DeviceListResponse: Codable, Sendable, Equatable {
    public let devices: [DeviceSummary]

    public init(devices: [DeviceSummary]) {
        self.devices = devices
    }
}

public struct EpochSummary: Codable, Sendable, Equatable {
    public let accountID: String
    public let deviceID: String
    public let epoch: UInt64
    public let publicKey: Data
    public let previousPublicKeyHash: Data?
    public let validFrom: UInt64
    public let validUntil: UInt64
    public let issuedAt: UInt64?
    public let status: String
    public let credential: EpochCredential

    public init(accountID: String, deviceID: String, epoch: UInt64, publicKey: Data, previousPublicKeyHash: Data?, validFrom: UInt64, validUntil: UInt64, issuedAt: UInt64?, status: String, credential: EpochCredential) {
        self.accountID = accountID
        self.deviceID = deviceID
        self.epoch = epoch
        self.publicKey = publicKey
        self.previousPublicKeyHash = previousPublicKeyHash
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.issuedAt = issuedAt
        self.status = status
        self.credential = credential
    }
}

public struct EpochListResponse: Codable, Sendable, Equatable {
    public let epochs: [EpochSummary]

    public init(epochs: [EpochSummary]) {
        self.epochs = epochs
    }
}

/// Keep a head outside the server to detect a later rollback or truncated log.
/// A signature authenticates this checkpoint; it is not an external witness.
public struct SignedLedgerHead: Codable, Sendable, Equatable {
    public let sequence: UInt64
    public let hash: Data
    public let signature: Data

    public func signingBytes() throws -> Data {
        var encoder = try CanonicalEncoder(domain: "swiftkey.ledger-head.v1")
        encoder.append(sequence)
        try encoder.append(hash)
        return encoder.data
    }

    public init(sequence: UInt64, hash: Data, signature: Data) {
        self.sequence = sequence
        self.hash = hash
        self.signature = signature
    }
}

public struct LedgerPage: Codable, Sendable, Equatable {
    public let events: [LedgerEvent]
    public let nextAfter: UInt64
    public let hasMore: Bool
    public let head: SignedLedgerHead

    public init(events: [LedgerEvent], nextAfter: UInt64, hasMore: Bool, head: SignedLedgerHead) {
        self.events = events
        self.nextAfter = nextAfter
        self.hasMore = hasMore
        self.head = head
    }
}

public struct AuthorityStatus: Codable, Sendable, Equatable {
    public let serverPublicKey: Data
    public let unixTime: UInt64
    public let epoch: UInt64
    public let epochStart: UInt64
    public let epochEnd: UInt64
    public let accountCount: Int
    public let activeDeviceCount: Int
    public let revokedDeviceCount: Int
    public let credentialCount: Int
    public let ledgerHead: SignedLedgerHead
    public let storage: String
    public let schemaVersion: Int
    /// Nil is an older legacy authority. False is the durable pairing-first cutover.
    public let legacyProvisioningAllowed: Bool?

    public init(serverPublicKey: Data, unixTime: UInt64, epoch: UInt64, epochStart: UInt64, epochEnd: UInt64, accountCount: Int, activeDeviceCount: Int, revokedDeviceCount: Int, credentialCount: Int, ledgerHead: SignedLedgerHead, storage: String, schemaVersion: Int, legacyProvisioningAllowed: Bool? = nil) {
        self.serverPublicKey = serverPublicKey
        self.unixTime = unixTime
        self.epoch = epoch
        self.epochStart = epochStart
        self.epochEnd = epochEnd
        self.accountCount = accountCount
        self.activeDeviceCount = activeDeviceCount
        self.revokedDeviceCount = revokedDeviceCount
        self.credentialCount = credentialCount
        self.ledgerHead = ledgerHead
        self.storage = storage
        self.schemaVersion = schemaVersion
        self.legacyProvisioningAllowed = legacyProvisioningAllowed
    }
}
