// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SwiftKeyApplication",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "SwiftKeyApplication", targets: ["SwiftKeyApplication"])],
    dependencies: [.package(path: "../SwiftKeyCore"), .package(path: "../SwiftKeyClient")],
    targets: [
        .target(name: "SwiftKeyApplication", dependencies: ["SwiftKeyCore", "SwiftKeyClient"]),
        .testTarget(name: "SwiftKeyApplicationTests", dependencies: ["SwiftKeyApplication", "SwiftKeyCore"])
    ]
)
