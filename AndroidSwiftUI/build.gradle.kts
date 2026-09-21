// Top-level build file where you can add configuration options common to all sub-projects/modules.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.multiplatform) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.compose.multiplatform) apply false
}

// Compile the complete vendored library surface independently of Swift/JNI and
// application adapters. No upstream publication/signing task is registered.
tasks.register("verifyCupertinoBuild") {
    group = "verification"
    description = "Compile all six vendored Cupertino libraries for Android and desktop"
    for (module in listOf("cupertino-core", "cupertino", "cupertino-native",
        "cupertino-adaptive", "cupertino-decompose", "cupertino-icons-extended")) {
        dependsOn(":$module:compileKotlinDesktop", ":$module:compileDebugKotlinAndroid")
    }
}
