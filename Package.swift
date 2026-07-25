// swift-tools-version: 6.1
import PackageDescription

import class Foundation.FileManager
import class Foundation.ProcessInfo

let package = Package(
    name: "AndroidSwiftUI",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // The umbrella app code imports: the SwiftUI API and Compose bridge,
        // re-exported, plus the Android host (android.view bridging).
        .library(
            name: "AndroidSwiftUI",
            targets: ["AndroidSwiftUI"]
        ),
        // The platform-neutral JNI bridge to the Compose interpreter, on its own.
        .library(
            name: "ComposeUI",
            targets: ["ComposeUI"]
        ),
        // Desktop test-rig dylib: the bridge plus a demo root view, loaded by
        // the Compose Desktop rig on the host JVM.
        .library(
            name: "SwiftUIDesktopDemo",
            type: .dynamic,
            targets: ["SwiftUIDesktopDemo"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/PureSwift/Android.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-java.git",
            branch: "main"
        ),
        // A Swift global actor backed by the Android main looper, so `@MainActor`
        // / `DispatchQueue.main` work on Android without hand-draining a RunLoop.
        // Same identity (`swift-android-native`) as the PureSwift/Android
        // dependency; pinned to the fork/branch that package uses so the Android
        // build's single-revision requirement is satisfied. The `CoreFoundation`
        // trait drains the dispatch main queue through `CFRunLoopRunInMode`, which
        // is what makes `DispatchQueue.main` reliable as the render scheduler.
        .package(
            url: "https://github.com/MillerTechnologyPeru/swift-android-native.git",
            branch: "feature/pureswift",
            traits: ["CoreFoundation"]
        ),
        .package(path: "SwiftUICore")
    ],
    targets: [
        // The Android umbrella: re-exports SwiftUICore + ComposeUI and adds the
        // android.view bridging (SwiftUIActivity, SwiftUIApplication, host view).
        .target(
            name: "AndroidSwiftUI",
            dependencies: [
                "ComposeUI",
                "BridgeExport",
                .product(
                    name: "SwiftUICore",
                    package: "SwiftUICore"
                ),
                .product(
                    name: "AndroidKit",
                    package: "Android"
                ),
                .product(
                    name: "AndroidLooper",
                    package: "swift-android-native",
                    condition: .when(platforms: [.android])
                )
            ],
            swiftSettings: [
              .swiftLanguageMode(.v5)
            ]
        ),
        // JNI bridge between the evaluation core and the Compose interpreter.
        // Platform-neutral: no android.* imports, so it builds for the desktop
        // JVM (macOS dylib) and cross-compiles for Android identically.
        .target(
            name: "ComposeUI",
            dependencies: [
                .product(name: "SwiftUICore", package: "SwiftUICore"),
                .product(name: "SwiftJava", package: "swift-java")
            ],
            swiftSettings: [
              .swiftLanguageMode(.v5)
            ]
        ),
        // The jextract-JNI export surface. Isolated thin target: only its tiny
        // public API is exported (a large surface like ComposeUI's would choke
        // jextract on result builders/generics). Carries the JExtractSwiftPlugin.
        .target(
            name: "BridgeExport",
            dependencies: [
                "ComposeUI",
                .product(name: "SwiftJava", package: "swift-java")
            ],
            exclude: [
                "swift-java.config"
            ],
            swiftSettings: [
              .swiftLanguageMode(.v5)
            ],
            plugins: [
                .plugin(name: "JExtractSwiftPlugin", package: "swift-java")
            ]
        ),
        .target(
            name: "SwiftUIDesktopDemo",
            dependencies: [
                "ComposeUI",
                "BridgeExport",
                .product(name: "SwiftUICore", package: "SwiftUICore")
            ],
            // `Playgrounds` symlinks the Android demo's shared sources; the rig
            // reuses them verbatim on desktop. Excluded: the app entry point (it
            // needs the Android host or Apple's App/Scene) and the two Android-
            // only screens — Map (schematic) and Video (Media3) — which have no
            // desktop rendering; their catalog entries are gated on `DESKTOP_RIG`.
            // The Custom Views screen (the composable registry) IS included: the
            // registry is a cross-platform extension point, and the desktop rig
            // registers pure-Compose factories for it (see DemoComposables.kt).
            exclude: [
                "Playgrounds/App.swift",
                "Playgrounds/MapPlaygrounds.swift",
                "Playgrounds/VideoPlaygrounds.swift",
            ],
            swiftSettings: [
              .swiftLanguageMode(.v5),
              // Marks the desktop test rig so the shared catalog can exclude the
              // Android-only screens whose playground files this target excludes.
              .define("DESKTOP_RIG")
            ]
        )
    ]
)
