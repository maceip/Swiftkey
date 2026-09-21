// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SwiftKeyClient",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "SwiftKeyClient", targets: ["SwiftKeyClient"])],
    dependencies: [.package(path: "../SwiftKeyCore")],
    targets: [
        .target(name: "SwiftKeyClient", dependencies: ["SwiftKeyCore"]),
        .testTarget(name: "SwiftKeyClientTests", dependencies: ["SwiftKeyClient"]),
    ]
)
