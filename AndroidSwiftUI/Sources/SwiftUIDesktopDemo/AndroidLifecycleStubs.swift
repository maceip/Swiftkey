//
//  AndroidLifecycleStubs.swift
//  SwiftUIDesktopDemo
//
//  `BridgeExport` declares the four Android lifecycle entry points as fixed
//  symbols, since it sits below `AndroidSwiftUI` and can't call into it (see
//  the note at their declaration). Every product that links `BridgeExport`
//  therefore has to define them, and the desktop rig links it for the event
//  dispatch. There is no Android lifecycle on a desktop JVM — the rig's
//  Compose window drives everything from `SwiftRuntime.start` — so these are
//  deliberately empty. The linker, not a runtime JNI lookup, is what proves
//  they exist.
//

@_cdecl("swiftui_applicationCreated")
func swiftui_applicationCreated() {}

@_cdecl("swiftui_applicationTerminated")
func swiftui_applicationTerminated() {}

@_cdecl("swiftui_activityCreated")
func swiftui_activityCreated() {}

@_cdecl("swiftui_activityResult")
func swiftui_activityResult(_ requestCode: Int32, _ resultCode: Int32) {}
