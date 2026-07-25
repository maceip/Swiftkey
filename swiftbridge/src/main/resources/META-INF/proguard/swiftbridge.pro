# Consumer R8/ProGuard rules for the jextract-generated JNI bindings.
# Packaged under META-INF/proguard so any app consuming this jar picks them
# up automatically.
#
# Nothing here may be renamed or removed. Swift reaches these by name at
# runtime and R8 cannot see the callers:
#   - the `@_cdecl` thunks are named after the class and method, e.g.
#     Java_com_pureswift_bridge_BridgeExport__00024bridgeInvokeVoid__J;
#   - `BridgeHostBox` looks `BridgeHost` methods up from native code, so the
#     interface and its implementors have no Java-visible caller;
#   - `SwiftTask.run` is invoked only from the Kotlin scheduler via that
#     same generated box.
-keep class com.pureswift.bridge.** { *; }
-keep interface com.pureswift.bridge.** { *; }

# SwiftKitCore's `@ThreadSafe`/`@Unsigned` annotations are declared with JFR
# meta-annotations (`jdk.jfr.Label`, `jdk.jfr.Description`), which exist on
# the JDK but not on Android. They are documentation only and nothing reads
# them at runtime, so let R8 proceed rather than fail the release build.
-dontwarn jdk.jfr.**
