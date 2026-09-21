// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SwiftKeyCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "SwiftKeyCore", targets: ["SwiftKeyCore"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2")
    ],
    targets: [
        .target(name: "SwiftKeyCore", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .testTarget(name: "SwiftKeyCoreTests", dependencies: ["SwiftKeyCore"], resources: [.copy("Fixtures")])
    ]
)
