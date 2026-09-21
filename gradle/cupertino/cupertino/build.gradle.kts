// Local Android/desktop build of the vendored Compose Cupertino source.
// Upstream build and publication files are retained but are never applied here.
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.compose.multiplatform)
    alias(libs.plugins.kotlin.serialization)
}

group = "io.github.alexzhirkevich"
version = "0.2.0-alpha05-swiftkey"
val upstreamSource = rootProject.file("vendor/compose-cupertino/cupertino/src")

kotlin {
    androidTarget {
        compilations.all {
            compileTaskProvider.configure {
                compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
            }
        }
    }
    jvm("desktop") {
        compilations.all {
            compileTaskProvider.configure {
                compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
            }
        }
    }
    sourceSets {
        val nonIosMain by creating { dependsOn(commonMain.get()) }
        val jvmMain by creating { dependsOn(commonMain.get()) }
        val skikoMain by creating { dependsOn(commonMain.get()) }
        androidMain.get().dependsOn(nonIosMain)
        androidMain.get().dependsOn(jvmMain)
        val desktopMain by getting {
            dependsOn(nonIosMain)
            dependsOn(jvmMain)
            dependsOn(skikoMain)
        }
        all {
            kotlin.srcDir(upstreamSource.resolve("$name/kotlin"))
            resources.srcDir(upstreamSource.resolve("$name/resources"))
        }
        val desktopTest by getting {
            dependencies {
                implementation(kotlin("test"))
                implementation(compose.desktop.currentOs)
                implementation(compose.desktop.uiTestJUnit4)
            }
        }
        commonMain.dependencies {
            api(project(":cupertino-core"))
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.uiUtil)
            implementation(libs.kotlinx.datetime)
            implementation(libs.kotlinx.atomicfu)
            implementation(libs.kotlinx.serialization.json)
        }
    }
}

android {
    namespace = "io.github.alexzhirkevich.cupertino"
    compileSdk = 35
    defaultConfig { minSdk = 24 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}
