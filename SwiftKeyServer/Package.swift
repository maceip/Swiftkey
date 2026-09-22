// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwiftKeyServer",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "swiftkey-server", targets: ["SwiftKeyServer"]), .executable(name: "swiftkey-passkey-test-server", targets: ["SwiftKeyPasskeyTestServer"]), .executable(name: "swiftkey-operator", targets: ["SwiftKeyOperator"]), .library(name: "SwiftKeyAuthority", targets: ["SwiftKeyAuthority"])],
    dependencies: [
        .package(path: "../SwiftKeyCore"),
        .package(path: "../SwiftKeyClient"),
        .package(path: "../SwiftKeyApplication"),
        .package(path: "../SwiftKeyUI"),
        .package(path: "../AndroidSwiftUI/SwiftUICore"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.2"),
        .package(url: "https://github.com/brokenhandsio/swift-webauthn.git", exact: "1.0.0-beta.1"),
        .package(url: "https://github.com/unrelentingtech/SwiftCBOR.git", from: "0.4.7"),
        .package(path: "Vendor/SwiftKeyCertificates"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2")
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .executableTarget(name: "SwiftKeyOperator", dependencies: [.product(name: "SwiftKeyCore", package: "SwiftKeyCore")]),
        .target(name: "SwiftKeyAuthority", dependencies: ["CSQLite", .product(name: "SwiftKeyCore", package: "SwiftKeyCore"), .product(name: "X509", package: "SwiftKeyCertificates", moduleAliases: ["X509": "SwiftKeyX509"]), .product(name: "SwiftASN1", package: "swift-asn1"), .product(name: "Crypto", package: "swift-crypto")]),
        .target(name: "SwiftKeyHTTP", dependencies: ["SwiftKeyAuthority", .product(name: "SwiftKeyCore", package: "SwiftKeyCore"), .product(name: "SwiftKeyApplication", package: "SwiftKeyApplication"), .product(name: "SwiftKeyUI", package: "SwiftKeyUI"), .product(name: "SwiftUICore", package: "SwiftUICore"), .product(name: "Vapor", package: "vapor")]),
        .target(name: "SwiftKeyPasskeyTest", dependencies: [.product(name: "Vapor", package: "vapor"), .product(name: "WebAuthn", package: "swift-webauthn"), .product(name: "SwiftCBOR", package: "SwiftCBOR"), .product(name: "Crypto", package: "swift-crypto")], resources: [.process("Resources")]),
        .executableTarget(name: "SwiftKeyPasskeyTestServer", dependencies: ["SwiftKeyPasskeyTest", .product(name: "Vapor", package: "vapor")]),
        .executableTarget(name: "SwiftKeyServer", dependencies: ["SwiftKeyAuthority", "SwiftKeyHTTP", "SwiftKeyPasskeyTest", .product(name: "SwiftKeyCore", package: "SwiftKeyCore"), .product(name: "Vapor", package: "vapor")], resources: [.process("Resources")]),
        .testTarget(name: "SwiftKeyPasskeyTestTests", dependencies: ["SwiftKeyPasskeyTest", .product(name: "VaporTesting", package: "vapor"), .product(name: "Crypto", package: "swift-crypto"), .product(name: "SwiftCBOR", package: "SwiftCBOR")], resources: [.copy("Fixtures")]),
        .testTarget(name: "SwiftKeyHTTPTests", dependencies: ["SwiftKeyHTTP", "SwiftKeyAuthority", .product(name: "SwiftKeyCore", package: "SwiftKeyCore"), .product(name: "VaporTesting", package: "vapor")]),
        .testTarget(name: "SwiftKeyAuthorityTests", dependencies: ["SwiftKeyAuthority", .product(name: "SwiftKeyCore", package: "SwiftKeyCore"), .product(name: "SwiftKeyClient", package: "SwiftKeyClient"), .product(name: "SwiftKeyApplication", package: "SwiftKeyApplication"), .product(name: "X509", package: "SwiftKeyCertificates", moduleAliases: ["X509": "SwiftKeyX509"]), .product(name: "SwiftASN1", package: "swift-asn1")], resources: [.copy("Fixtures")])
    ]
)
