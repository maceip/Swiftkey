// swift-tools-version: 6.1
import PackageDescription

// Development-only surface fixtures, never linked into the app or authority.
let package = Package(
    name: "PhoneProtocolPreview",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../SwiftKeyUI"),
        .package(path: "../../SwiftKeyApplication"),
        .package(path: "../../AndroidSwiftUI/SwiftUICore")
    ],
    targets: [.executableTarget(name: "PhoneProtocolPreview", dependencies: [
        .product(name: "SwiftKeyUI", package: "SwiftKeyUI"),
        .product(name: "SwiftKeyApplication", package: "SwiftKeyApplication"),
        .product(name: "SwiftUICore", package: "SwiftUICore")
    ])]
)
