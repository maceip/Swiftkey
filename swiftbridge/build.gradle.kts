// Reusable library exposing the jextract-JNI generated Java bindings for the
// Swift `BridgeExport` module, so any JVM/Android host can call the Swift
// bridge through a generated, typed API instead of hand-matched `external`
// declarations.
//
// The generated bindings and swift-java's `SwiftKitCore` runtime are both plain
// Java; we compile them here directly (our Gradle toolchain) rather than
// consuming swift-java's own Gradle build, which pins a Gradle version this
// project doesn't vendor. The generation itself is driven by SwiftPM's
// JExtractSwiftPlugin during `swift build`; the `jextract` task below runs it.
plugins {
    `java-library`
}

java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}

// The pinned swift-java checkout SwiftPM resolved into `.build/checkouts`.
val swiftKitCoreSrc = rootDir.resolve(".build/checkouts/swift-java/SwiftKitCore/src/main/java")
// Where JExtractSwiftPlugin writes the generated Java for the BridgeExport target.
val jextractGenerated = rootDir.resolve(
    ".build/plugins/outputs/androidswiftui/BridgeExport/destination/JExtractSwiftPlugin/src/generated/java"
)

// Regenerate the bindings by building the Swift target. Host-side generation is
// platform-independent (the same Java serves the desktop JVM and the Android
// cross-compiled `.so`), so this runs once against the host toolchain.
val jextract by tasks.registering(Exec::class) {
    workingDir = rootDir
    // The plugin invokes `javac`, so it needs a JDK; reuse the one running Gradle.
    environment("JAVA_HOME", System.getProperty("java.home"))
    commandLine("swift", "build", "--target", "BridgeExport")
    outputs.dir(jextractGenerated)
}

sourceSets {
    main {
        java {
            srcDir(swiftKitCoreSrc)
            srcDir(jextract)
        }
    }
}
