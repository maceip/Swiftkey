// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SwiftKeyUI",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SwiftKeyUI", targets: ["SwiftKeyUI"])],
    dependencies: [
        .package(path: "../AndroidSwiftUI/SwiftUICore"),
        .package(path: "../SwiftKeyApplication"),
        .package(path: "../SwiftKeyCore")
    ],
    targets: [
        .target(name: "SwiftKeyUI", dependencies: [
            .product(name: "SwiftUICore", package: "SwiftUICore"),
            .product(name: "SwiftKeyApplication", package: "SwiftKeyApplication"),
            .product(name: "SwiftKeyCore", package: "SwiftKeyCore")
        ]),
        .testTarget(name: "SwiftKeyUITests", dependencies: ["SwiftKeyUI"])
    ]
)
