# Swift binds these by name — `@JavaClass("com.pureswift.swiftandroid.…")` —
# and calls their methods over JNI, so R8 sees no caller for either the
# classes or their members. The package is bridge glue only; keeping it
# whole costs nothing an app would otherwise shrink.
-keep class com.pureswift.swiftandroid.** { *; }
