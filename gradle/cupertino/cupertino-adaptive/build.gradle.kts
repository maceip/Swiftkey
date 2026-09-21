// Local Android/desktop build of the vendored Compose Cupertino source.
// Upstream build and publication files are retained but are never applied here.
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.compose.multiplatform)
}

group = "io.github.alexzhirkevich"
version = "0.2.0-alpha05-swiftkey"
val upstreamSource = rootProject.file("vendor/compose-cupertino/cupertino-adaptive/src")

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
        commonMain.dependencies {
            api(project(":cupertino"))
            api(project(":cupertino-native"))
            api(compose.material3)
            implementation(project(":cupertino-core"))
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.uiUtil)
        }
    }
}

android {
    namespace = "io.github.alexzhirkevich.cupertinoadaptive"
    compileSdk = 35
    defaultConfig { minSdk = 24 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}
