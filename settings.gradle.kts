pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "AndroidSwiftUI"

// Reusable libraries live at the repo root.
include(":composeui")     // Compose Multiplatform interpreter
include(":androidbridge") // reusable Android JNI host glue
include(":swiftbridge")   // jextract-JNI generated bindings + SwiftKitCore runtime

// The demo apps consume the libraries; their sources stay under Demo/.
include(":demo-app")
project(":demo-app").projectDir = file("Demo/app")
include(":demo-desktop")
project(":demo-desktop").projectDir = file("Demo/desktop")

// Retain the complete upstream tree and its original build files. Local build
// files compile all six libraries without upstream release/signing configuration;
// bounded source fixes are recorded in SWIFTKEY-PATCHES.json.
for (module in listOf("cupertino-core", "cupertino", "cupertino-native",
    "cupertino-adaptive", "cupertino-decompose", "cupertino-icons-extended")) {
    include(":" + module)
    project(":" + module).projectDir = file("gradle/cupertino/" + module)
}
