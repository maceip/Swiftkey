plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

// CI increments the installable APK version without committing a version bump.
// Local builds retain the existing development version.
val swiftkeyVersionCode = providers.gradleProperty("swiftkeyVersionCode")
    .map { value ->
        require(value.matches(Regex("[1-9][0-9]*"))) { "Invalid SwiftKey version code" }
        value.toInt().also { require(it <= 2_100_000_000) { "SwiftKey version code is too large" } }
    }.orElse(1)
val swiftkeyVersionName = providers.gradleProperty("swiftkeyVersionName").orElse("1.0")

android {
    namespace = "com.pureswift.swiftandroid"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.pureswift.swiftandroidui"
        minSdk = 24
        targetSdk = 35
        versionCode = swiftkeyVersionCode.get()
        versionName = swiftkeyVersionName.get()
        ndk {
            //noinspection ChromeOsAbiSupport
            abiFilters += listOf("arm64-v8a")
        }
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            // On: a release build is the only thing that exercises the keep
            // rules the bridge modules ship. The JNI surface is invisible to
            // R8 — a missing rule fails at runtime, not at build time.
            isMinifyEnabled = true
            // Signed with the debug key so the minified build is installable
            // and can actually be run; this demo ships no release keystore.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        // Cupertino calendar uses java.time on the existing minSdk24 profile.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    buildFeatures {
        compose = true
    }
    packaging {
        resources {
            excludes += listOf("/META-INF/{AL2.0,LGPL2.1}")
        }
        jniLibs {
            keepDebugSymbols += listOf(
                "*/arm64-v8a/*.so",
                "*/armeabi-v7a/*.so",
                "*/x86_64/*.so"
            )
        }
    }
/*
    // Custom Swift build task
    val buildSwift by tasks.registering(Exec::class) {
        group = "build"
        description = "Build Swift sources"
        workingDir("$projectDir")
        commandLine("bash", "build-swift.sh")
    }

    tasks.withType<JavaCompile> {
        dependsOn(buildSwift)
    }*/
}

dependencies {
    coreLibraryDesugaring(libs.android.desugar.jdk)
    implementation(project(":composeui"))
    implementation(project(":androidbridge"))
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.fragment)
    implementation(libs.google.material)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.foundation)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test.junit4)
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)
}
