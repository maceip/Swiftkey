//
//  DesktopDemo.swift
//  SwiftUIDesktopDemo
//
//  The desktop rig's Swift entry: a counter view evaluated by the core and
//  pushed through the bridge into the rig's Compose window.
//

import Foundation
import SwiftUICore
import SwiftKeyUI
import ComposeUI
import SwiftJava

@JavaClass("com.pureswift.swiftui.desktop.SwiftRuntime")
open class SwiftRuntime: JavaObject {
}

@JavaImplementation("com.pureswift.swiftui.desktop.SwiftRuntime")
extension SwiftRuntime {

    @JavaMethod
    func start(_ store: TreeStore?) {
        guard let store else { return }
        // marshal re-renders onto the main thread; async state (e.g. a List
        // refresh Task) writes off-thread and JNI object creation must run here
        let runtime = BridgeRuntime(root: ContentView(), store: store) { block in
            DispatchQueue.main.async { block() }
        }
        runtime.start()
    }

    /// Test preview of the exact mobile presentation. This fixture is never
    /// linked into the Android launch path and claims no hardware identity.
    @JavaMethod
    func startIdentityPreview(_ store: TreeStore?) {
        guard let store else { return }
        let bytes = [UInt8(4)] + Array(UInt8(0)...UInt8(63))
        let rows = stride(from: 0, to: bytes.count, by: 8).map { start in
            bytes[start..<min(start + 8, bytes.count)].map { String(format: "%02x", $0) }.joined(separator: " ")
        }.joined(separator: "\n")
        let runtime = BridgeRuntime(root: SwiftKeyIdentityView(publicKeyText: rows), store: store) { block in
            DispatchQueue.main.async { block() }
        }
        runtime.start()
    }
}
