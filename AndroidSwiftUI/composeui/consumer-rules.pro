# The types Swift binds by name (`@JavaClass("com.pureswift.swiftui.…")`)
# and drives over JNI: the tree store it pushes into, the node objects it
# constructs slot by slot, the host view, and the one remaining hand-matched
# callback. R8 sees no Java caller for their members.
#
# Deliberately not a whole-package keep: the interpreter itself (Render.kt,
# the composable registry) is only ever called from Kotlin and should stay
# shrinkable.
-keep class com.pureswift.swiftui.TreeStore { *; }
-keep class com.pureswift.swiftui.ViewNode { *; }
-keep class com.pureswift.swiftui.SwiftUIHostView { *; }
-keep class com.pureswift.swiftui.SwiftCallbackSink { *; }
