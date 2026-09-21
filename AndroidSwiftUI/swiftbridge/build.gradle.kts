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
    // VERSION_11 doesn't parse: generated wrapper types (e.g. `SwiftTask`)
    // implement `JNISwiftInstance`, whose `equals()` jextract generates using
    // pattern-matching `instanceof`, a Java 16+ syntax feature.
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
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
    // `BridgeExport`'s config has `enableJavaCallbacks: true` (needed for
    // `BridgeHost`), which makes the JExtractSwiftPlugin shell out to
    // swift-java's own Gradle to build SwiftKitCore. SwiftPM sandboxes build
    // plugins (no network) by default, which blocks that download — the
    // outer Gradle process here isn't sandboxed, so without this flag the
    // inner `swift build` fails where a bare Gradle invocation wouldn't.
    // An absolute compiler path avoids a reused Gradle daemon resolving Swift
    // through a different PATH/toolchain manager than the invoking shell.
    commandLine(
        providers.environmentVariable("SWIFTKEY_SWIFT").orElse("swift").get(),
        "build", "--target", "BridgeExport", "--disable-sandbox"
    )
    outputs.dir(jextractGenerated)
}

sourceSets {
    main {
        java {
            srcDir(swiftKitCoreSrc)
            srcDir(jextract)
        }
        // SwiftKitCore ships its own `-keep org.swift.swiftkit.**` rules under
        // META-INF/proguard. We compile it from source rather than consuming its
        // jar, so without this its rules never reach a minifying consumer.
        resources {
            srcDir(rootDir.resolve(".build/checkouts/swift-java/SwiftKitCore/src/main/resources"))
        }
    }
}
