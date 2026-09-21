// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

import class Foundation.FileManager
import class Foundation.ProcessInfo

// Note: the JAVA_HOME environment variable must be set to point to where
// Java is installed, e.g.,
//   Library/Java/JavaVirtualMachines/openjdk-21.jdk/Contents/Home.
func findJavaHome() -> String {
  if let home = ProcessInfo.processInfo.environment["JAVA_HOME"] {
    return home
  }

  // This is a workaround for envs (some IDEs) which have trouble with
  // picking up env variables during the build process
  let path = "\(FileManager.default.homeDirectoryForCurrentUser.path()).java_home"
  if let home = try? String(contentsOfFile: path, encoding: .utf8) {
    if let lastChar = home.last, lastChar.isNewline {
      return String(home.dropLast())
    }

    return home
  }

  fatalError("Please set the JAVA_HOME environment variable to point to where Java is installed.")
}
let javaHome = findJavaHome()

let javaIncludePath = "\(javaHome)/include"
#if os(Linux)
  let javaPlatformIncludePath = "\(javaIncludePath)/linux"
#elseif os(macOS)
  let javaPlatformIncludePath = "\(javaIncludePath)/darwin"
#elseif os(Windows)
  let javaPlatformIncludePath = "\(javaIncludePath)/win32"
#endif

let package = Package(
    name: "SwiftAndroidApp",
    platforms: [
      .macOS(.v13),
      .iOS(.v13),
      .tvOS(.v13),
      .watchOS(.v6),
      .macCatalyst(.v13),
    ],
    products: [
        .library(
            name: "SwiftAndroidApp",
            type: .dynamic,
            targets: ["SwiftAndroidApp"]
        ),
    ],
    dependencies: [
        .package(
            path: "../../"
        ),
        .package(path: "../../../SwiftKeyCore"),
        .package(path: "../../../SwiftKeyClient"),
        .package(path: "../../../SwiftKeyUI"),
        .package(path: "../../../SwiftKeyApplication")
    ],
    targets: [
        .target(
            name: "SwiftAndroidApp",
            dependencies: [
                .product(
                    name: "AndroidSwiftUI",
                    package: "AndroidSwiftUI"
                ),
                .product(name: "SwiftKeyCore", package: "SwiftKeyCore"),
                .product(name: "SwiftKeyClient", package: "SwiftKeyClient"),
                .product(name: "SwiftKeyUI", package: "SwiftKeyUI"),
                .product(name: "SwiftKeyApplication", package: "SwiftKeyApplication")
            ],
            // This is the installed SwiftKey product, including its debug APK.
            // The source directory is shared with developer playgrounds; only
            // product entry, identity, and pairing code belongs in this target.
            sources: [
                "App.swift",
                "HardwareKeyView.swift",
                "AndroidProtocolBridge.swift",
                "AndroidPhoneProtocolBridge.swift",
                "AndroidPhoneProtocolView.swift"
            ],
            swiftSettings: [
              .swiftLanguageMode(.v5),
              .unsafeFlags(["-I\(javaIncludePath)", "-I\(javaPlatformIncludePath)"])
            ]
        ),
    ]
)
