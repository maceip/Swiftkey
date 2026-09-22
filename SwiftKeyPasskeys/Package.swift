// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftKeyPasskeys",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "SwiftKeyPasskeys", targets: ["SwiftKeyPasskeys"])],
    targets: [
        .target(name: "SwiftKeyPasskeys"),
        .testTarget(name: "SwiftKeyPasskeysTests", dependencies: ["SwiftKeyPasskeys"])
    ]
)
