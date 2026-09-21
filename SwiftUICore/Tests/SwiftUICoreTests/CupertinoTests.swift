import Foundation
import Testing
@testable import SwiftUICore

private func cupertinoNodes(_ node: RenderNode) -> [RenderNode] {
    [node] + node.children.flatMap(cupertinoNodes)
}
private func cupertinoAction(_ node: RenderNode, _ key: String) throws -> Int64 {
    guard case .int(let id)? = node.props[key] else { throw CupertinoTestFailure.missingAction(key) }
    return Int64(id)
}
private enum CupertinoTestFailure: Error { case missingAction(String) }

@Suite("Cupertino bridge contracts")
struct CupertinoTests {
    @Test("All pinned symbols and unsupported UIKit capabilities are explicit")
    func symbolRegistry() {
        let names = CupertinoSymbol.allCases.map(\.rawValue)
        #expect(names.count == 879)
        #expect(Set(names).count == names.count)
        #expect(names.filter { $0.hasPrefix("CupertinoIcons.") }.count == 833)
        #expect(names.filter { $0.hasPrefix("AdaptiveIcons.") }.count == 46)
        for surface in CupertinoUIKitSurface.allCases {
            guard case .unsupported(let reason) = surface.capability else { Issue.record("UIKit surface incorrectly shared"); continue }
            #expect(!reason.isEmpty)
        }
    }

    @Test("Host effects stay idle until commanded and honor the Swift enabled gate")
    func hostEffects() throws {
        let idle = ViewHost(CupertinoHapticFeedback { Text("Idle") }).evaluate()
        #expect(idle.props["commandID"] == nil && idle.props["type"] == nil)
        var performed = 0
        let host = ViewHost(CupertinoHapticFeedback(type: .longPress, commandID: "gesture-7", enabled: false,
            onPerformed: { performed += 1 }) { Text("Feedback") })
        let node = host.evaluate()
        #expect(node.props["commandID"] == .string("gesture-7"))
        host.callbacks.invokeVoid(try cupertinoAction(node, "onPerformed"))
        #expect(performed == 0)
        #expect("Account settings".cupertinoSectionTitle(style: .grouped) == "ACCOUNT SETTINGS")
        #expect("Account settings".cupertinoSectionTitle(style: .sidebar) == "Account settings")
    }

    @Test("Optional actions keep keyed IDs and refresh their captures", arguments: [false, true])
    func keyedCallbacks(cupertino: Bool) throws {
        final class Probe { var includesOptional = false; var generation = 1; var received = 0 }
        struct Screen: View {
            let probe: Probe
            let cupertino: Bool
            var body: some View {
                let generation = probe.generation
                var actions: [String: ComposableAction] = ["onZ": .void { probe.received = generation }]
                if probe.includesOptional { actions["onA"] = .void { probe.received = -generation } }
                return AnyView(cupertino ? AnyView(CupertinoComponent("CupertinoButton", actions: actions)) : AnyView(ComposableView("Custom", actions: actions)))
            }
        }
        let probe = Probe()
        let host = ViewHost(Screen(probe: probe, cupertino: cupertino))
        let id = try cupertinoAction(host.evaluate(), "onZ")
        host.callbacks.invokeVoid(id)
        #expect(probe.received == 1)
        probe.includesOptional = true; probe.generation = 2
        let added = host.evaluate()
        #expect(try cupertinoAction(added, "onZ") == id)
        #expect(try cupertinoAction(added, "onA") != id)
        host.callbacks.invokeVoid(id)
        #expect(probe.received == 2)
        probe.includesOptional = false; probe.generation = 3
        let removed = host.evaluate()
        #expect(removed.props["onA"] == nil)
        #expect(try cupertinoAction(removed, "onZ") == id)
        host.callbacks.invokeVoid(id)
        #expect(probe.received == 3)
    }

    @Test("Optional named slots do not move surviving slot identities")
    func namedSlotIdentity() throws {
        func tree(extra: Bool) -> RenderNode {
            var slots: [CupertinoSlot] = []
            if extra { slots.append(CupertinoSlot("leadingIcon") { Text("Icon") }) }
            slots.append(CupertinoSlot("content") { Text("Body") })
            return ViewHost(CupertinoComponent("CupertinoButton", slots: slots)).evaluate()
        }
        let before = try #require(tree(extra: false).children.first)
        let after = try #require(tree(extra: true).children.last)
        #expect(before == after)
        #expect(before.type == "CupertinoSlot")
        #expect(before.props["name"] == .string("content"))
    }

    @Test("Typed range callbacks reject malformed and out-of-range state")
    func rangeEvents() throws {
        var value = CupertinoRangeValue(start: 0.2, end: 0.8)
        let binding = Binding(get: { value }, set: { value = $0 })
        let host = ViewHost(CupertinoRangeSlider(value: binding))
        let id = try cupertinoAction(host.evaluate(), "onValueChange")
        for invalid in ["{}", "{\"start\":0.8,\"end\":0.2}", "{\"start\":-1,\"end\":0.5}", "{\"start\":0,\"end\":2}", "{\"start\":\"NaN\",\"end\":1}"] {
            host.callbacks.invokeString(id, invalid)
            #expect(value == .init(start: 0.2, end: 0.8))
        }
        host.callbacks.invokeString(id, "{\"start\":0.1,\"end\":0.6}")
        #expect(value == .init(start: 0.1, end: 0.6))
        let disabled = ViewHost(CupertinoRangeSlider(value: binding, enabled: false))
        disabled.callbacks.invokeString(try cupertinoAction(disabled.evaluate(), "onValueChange"), "{\"start\":0,\"end\":1}")
        #expect(value == .init(start: 0.1, end: 0.6))
    }

    @Test("Editing callbacks retain UTF-16 selection and reject invalid composition")
    func editingEvents() throws {
        var value = CupertinoEditingValue(text: "A😀B")
        #expect(value.selectionStart == 4)
        let binding = Binding(get: { value }, set: { value = $0 })
        let host = ViewHost(CupertinoTextField(value: binding))
        let id = try cupertinoAction(host.evaluate(), "onValueChange")
        host.callbacks.invokeString(id, "{\"text\":\"A😀B\",\"selectionStart\":1,\"selectionEnd\":3,\"compositionStart\":1,\"compositionEnd\":3}")
        #expect(value.selectionEnd == 3 && value.compositionEnd == 3)
        let accepted = value
        for invalid in ["{\"text\":\"x\",\"selectionStart\":0,\"selectionEnd\":4}", "{\"text\":\"x\",\"selectionStart\":0,\"selectionEnd\":1,\"compositionStart\":0}"] {
            host.callbacks.invokeString(id, invalid)
            #expect(value == accepted)
        }
        let readOnly = ViewHost(CupertinoTextField(value: binding, options: .init(readOnly: true)))
        readOnly.callbacks.invokeString(try cupertinoAction(readOnly.evaluate(), "onValueChange"), "{\"text\":\"x\",\"selectionStart\":0,\"selectionEnd\":1}")
        #expect(value == accepted)
    }

    @Test("Dates cross the bridge as Int64 JSON and respect the configured years")
    func pickerEvents() throws {
        var date = CupertinoDateSelection(selectedDateMillis: 1_763_683_200_000)
        let host = ViewHost(CupertinoDatePicker(selection: Binding(get: { date }, set: { date = $0 }), yearRange: 2020...2030))
        let node = host.evaluate()
        #expect(node.props["selectedDateMillis"] == .int(1_763_683_200_000))
        let id = try cupertinoAction(node, "onSelectionChange")
        host.callbacks.invokeString(id, "{\"selectedDateMillis\":1795219200000}")
        #expect(date.selectedDateMillis == 1_795_219_200_000)
        host.callbacks.invokeString(id, "{\"selectedDateMillis\":0}")
        #expect(date.selectedDateMillis == 1_795_219_200_000)
        var time = CupertinoTimeSelection(hour: 23, minute: 59)
        let timeHost = ViewHost(CupertinoTimePicker(selection: Binding(get: { time }, set: { time = $0 })))
        let timeID = try cupertinoAction(timeHost.evaluate(), "onSelectionChange")
        timeHost.callbacks.invokeString(timeID, "{\"hour\":24,\"minute\":0}")
        #expect(time.hour == 23)
        timeHost.callbacks.invokeString(timeID, "{\"hour\":0,\"minute\":0}")
        #expect(time == .init(hour: 0, minute: 0))
    }

    @Test("Sheet commands carry IDs and state consent restricts callback transitions")
    func sheetState() throws {
        var value = CupertinoSheetValue.hidden
        let host = ViewHost(CupertinoBottomSheetScaffold(value: Binding(get: { value }, set: { value = $0 }),
            allowedValues: [.hidden, .expanded], command: .init(id: 7, value: .show), slots: [CupertinoSlot("content") { Text("Body") }]))
        let node = host.evaluate()
        #expect(node.props["command"] == .string("show"))
        #expect(node.props["commandID"] == .int(7))
        let id = try cupertinoAction(node, "onStateChange")
        host.callbacks.invokeString(id, "{\"value\":\"PartiallyExpanded\"}")
        #expect(value == .hidden)
        host.callbacks.invokeString(id, "{\"value\":\"Expanded\"}")
        #expect(value == .expanded)
    }

    @Test("Alert builder order and individual callback identities are preserved")
    func orderedActions() throws {
        var selected: String? = nil
        let host = ViewHost(CupertinoAlertDialog(visible: .constant(true), title: "Choose") {
            CupertinoAlertAction("One", kind: .default) { selected = "one" }
            CupertinoAlertAction("Two", kind: .destructive) { selected = "two" }
            CupertinoAlertAction("Three", kind: .cancel) { selected = "three" }
        })
        let entries = cupertinoNodes(host.evaluate()).filter { node in
            if case .string(let name)? = node.props["name"] { return name.hasPrefix("AlertDialogActionsScope.") }; return false
        }
        #expect(entries.map { $0.props["name"] } == [.string("AlertDialogActionsScope.default"), .string("AlertDialogActionsScope.destructive"), .string("AlertDialogActionsScope.cancel")])
        for (index, expected) in ["one", "two", "three"].enumerated() {
            host.callbacks.invokeVoid(try cupertinoAction(entries[index], "onClick"))
            #expect(selected == expected)
        }
    }

    @Test("Lazy section items resolve only requested rows using stable keys")
    func lazyItems() throws {
        final class Probe { var built = 0 }
        struct Row: View {
            let value: Int; let probe: Probe
            var body: some View { probe.built += 1; return Text("Row \(value)") }
        }
        let probe = Probe()
        let host = ViewHost(CupertinoLazyItems(0..<10_000, id: { $0 }) { Row(value: $0, probe: probe) })
        let tree = host.evaluate()
        #expect(tree.props["name"] == .string("LazySectionScope.items"))
        #expect(tree.count == 10_000)
        #expect(tree.children.isEmpty && probe.built == 0)
        let provider = try cupertinoAction(tree, "itemProvider")
        let row = try #require(host.callbacks.item(provider, 42))
        #expect(row.props["text"] == .string("Row 42"))
        #expect(probe.built == 1)
        #expect(host.callbacks.item(provider, -1)?.type == "EmptyView")
        #expect(host.callbacks.item(provider, 10_000)?.type == "EmptyView")
        #expect(probe.built == 1)
    }

    @Test("Section dropdown triggers its binding and keeps menu entries in a real menu scope", arguments: [false, true])
    func sectionMenuScopes(lazy: Bool) throws {
        var expanded = false
        let binding = Binding(get: { expanded }, set: { expanded = $0 })
        let view = lazy ? AnyView(CupertinoLazyDropdownMenu(expanded: binding, slots: [])) : AnyView(CupertinoSectionDropdownMenu(expanded: binding, slots: []))
        let host = ViewHost(view)
        let node = host.evaluate()
        host.callbacks.invokeVoid(try cupertinoAction(node, "onClick"))
        #expect(expanded)
        host.callbacks.invokeVoid(try cupertinoAction(node, "onDismissRequest"))
        #expect(!expanded)
        let disabled = lazy ? AnyView(CupertinoLazyDropdownMenu(expanded: binding, enabled: false, slots: [])) : AnyView(CupertinoSectionDropdownMenu(expanded: binding, enabled: false, slots: []))
        let disabledHost = ViewHost(disabled)
        disabledHost.callbacks.invokeVoid(try cupertinoAction(disabledHost.evaluate(), "onClick"))
        #expect(!expanded)
        let catalog = ViewHost(CupertinoCatalogView(surface: lazy ? .lazySectionScope_dropdownMenu : .sectionScope_SectionDropdownMenu,
            showsPicker: false, initiallyPresented: true)).evaluate()
        let nodes = cupertinoNodes(catalog)
        #expect(!nodes.contains { $0.type == "ScrollView" })
        if lazy {
            let parent = try #require(nodes.first { $0.props["name"] == .string("LazySectionScope.dropdownMenu") })
            let content = try #require(parent.children.first { $0.props["name"] == .string("content") })
            #expect(cupertinoNodes(content).contains { $0.props["name"] == .string("CupertinoMenuScope.MenuAction") })
        } else {
            let parent = try #require(nodes.first { $0.props["name"] == .string("SectionScope.SectionDropdownMenu") })
            let menu = try #require(parent.children.first { $0.props["name"] == .string("menu") })
            #expect(menu.children.first?.props["name"] == .string("CupertinoDropdownMenu"))
        }
    }

    @Test("Catalog alerts stack long actions and sheets provide a bounded full content surface")
    func presentationExamples() throws {
        for surface in [CupertinoSurfaceName.cupertinoAlertDialog, .adaptiveAlertDialog, .cupertinoAlertDialogNative, .adaptiveAlertDialogNative, .alertDialogActionsScope_destructive] {
            let nodes = cupertinoNodes(ViewHost(CupertinoCatalogView(surface: surface, showsPicker: false, initiallyPresented: true)).evaluate())
            let dialog = try #require(nodes.first { node in
                guard case .string(let name)? = node.props["name"] else { return false }
                return name.contains("AlertDialog") && !name.contains("Scope")
            })
            #expect(dialog.props["buttonsOrientation"] == .string("Vertical"))
        }
        for surface in [CupertinoSurfaceName.cupertinoBottomSheetScaffold, .cupertinoBottomSheetContent, .cupertinoBottomSheetDefaults_DragHandle] {
            let nodes = cupertinoNodes(ViewHost(CupertinoCatalogView(surface: surface, showsPicker: false, initiallyPresented: true)).evaluate())
            let content = try #require(nodes.first { $0.props["name"] == .string("CupertinoBottomSheetContent") })
            #expect(content.modifiers.contains { $0.kind == "frame" && $0.args["fillHeight"] == .bool(true) })
            #expect(cupertinoNodes(content).contains { $0.props["text"] == .string("Sheet content") })
        }
    }

    @Test("Catalog alerts dismiss by leaving composition and can be presented again", arguments: CupertinoSurfaceName.allCases.filter { $0.rawValue.contains("AlertDialog") })
    func alertLifecycle(surface: CupertinoSurfaceName) throws {
        let host = ViewHost(CupertinoCatalogView(surface: surface, showsPicker: false))
        func dialog(_ tree: RenderNode) -> RenderNode? {
            cupertinoNodes(tree).first { node in
                guard case .string(let name)? = node.props["name"] else { return false }
                return name.contains("AlertDialog") && !name.contains("Scope")
            }
        }
        func present(_ tree: RenderNode) throws {
            let button = try #require(cupertinoNodes(tree).first { $0.props["name"] == .string("CupertinoButton") })
            host.callbacks.invokeVoid(try cupertinoAction(button, "onClick"))
        }
        let initial = host.evaluate()
        #expect(dialog(initial) == nil)
        try present(initial)
        let shown = try #require(dialog(host.evaluate()))
        host.callbacks.invokeVoid(try cupertinoAction(shown, "onDismissRequest"))
        let dismissed = host.evaluate()
        #expect(dialog(dismissed) == nil)
        try present(dismissed)
        let reopened = try #require(dialog(host.evaluate()))
        let action = try #require(cupertinoNodes(reopened).first { node in
            guard case .string(let name)? = node.props["name"] else { return false }
            return name.hasPrefix("AlertDialogActionsScope.") || name.hasPrefix("NativeAlertDialogActionsScope.")
        })
        host.callbacks.invokeVoid(try cupertinoAction(action, "onClick"))
        #expect(dialog(host.evaluate()) == nil)
    }

    @Test("Typed alert visibility bindings control composition", arguments: 0..<4)
    func typedAlertVisibility(kind: Int) throws {
        var visible = false
        let binding = Binding(get: { visible }, set: { visible = $0 })
        let slots = [CupertinoSlot("title") { Text("Title") }]
        let view: AnyView
        switch kind {
        case 0: view = AnyView(CupertinoAlertDialog(visible: binding, slots: slots))
        case 1: view = AnyView(AdaptiveAlertDialog(visible: binding, slots: slots))
        case 2: view = AnyView(CupertinoAlertDialogNative(visible: binding, slots: slots))
        default: view = AnyView(AdaptiveAlertDialogNative(visible: binding, slots: slots))
        }
        let host = ViewHost(view)
        #expect(cupertinoNodes(host.evaluate()).allSatisfy { $0.type != "Composable" })
        visible = true
        let alert = try #require(cupertinoNodes(host.evaluate()).first { $0.type == "Composable" })
        host.callbacks.invokeVoid(try cupertinoAction(alert, "onDismissRequest"))
        #expect(!visible)
        #expect(cupertinoNodes(host.evaluate()).allSatisfy { $0.type != "Composable" })
    }

    @Test("Default search cancel and clear controls dispatch their actual native callback types")
    func defaultControlCallbacks() throws {
        var text = "Search terms"
        let binding = Binding(get: { text }, set: { text = $0 })
        let host = ViewHost(CupertinoSearchTextFieldDefaults.CancelButton(value: binding))
        let node = host.evaluate()
        #expect(node.props["onClick"] == nil)
        host.callbacks.invokeString(try cupertinoAction(node, "onValueChange"), "")
        #expect(text.isEmpty)
        text = "Retained"
        let disabled = ViewHost(CupertinoSearchTextFieldDefaults.CancelButton(value: binding, enabled: false))
        disabled.callbacks.invokeString(try cupertinoAction(disabled.evaluate(), "onValueChange"), "")
        #expect(text == "Retained")
        var clicks = 0
        for visible in [false, true] {
            let clear = ViewHost(CupertinoSectionDefaults.TextFieldClearButton(visible: visible) { clicks += 1 })
            clear.callbacks.invokeVoid(try cupertinoAction(clear.evaluate(), "onClick"))
        }
        #expect(clicks == 1)
    }

    @Test("Passive defaults expose only consumed native props and retain required slots")
    func defaultDecorationContracts() throws {
        let passive: [AnyView] = [AnyView(CupertinoDropdownMenuDefaults.PickerLeadingIcon()),
            AnyView(CupertinoNavigationBarDefaults.Divider()), AnyView(CupertinoTopAppBarDefaults.Divider()),
            AnyView(CupertinoSectionDefaults.LabelChevron())]
        for view in passive {
            let node = ViewHost(view).evaluate()
            #expect(Set(node.props.keys) == ["name"])
        }
        let handle = ViewHost(CupertinoBottomSheetDefaults.DragHandle(width: 44, height: 6, shape: .rounded(3), color: .blue)).evaluate()
        #expect(handle.props["width"] == .double(44) && handle.props["height"] == .double(6))
        #expect(handle.props["shape"] == .double(3))
        #expect(handle.props["onClick"] == nil)
        let thumb = ViewHost(CupertinoSliderDefaults.Thumb(enabled: false, width: 32, height: 30)).evaluate()
        #expect(thumb.props["thumbWidth"] == .double(32) && thumb.props["thumbHeight"] == .double(30))
        #expect(thumb.props["color"] == nil && thumb.props["onClick"] == nil)
        let track = ViewHost(CupertinoSliderDefaults.Track()).evaluate()
        #expect(Set(track.props.keys) == ["name", "enabled"])
        let icon = ViewHost(CupertinoSearchTextFieldDefaults.LeadingIcon(symbol: .outlined_Person, rotateWithLayoutDirection: false)).evaluate()
        #expect(icon.props["imageVector"] == .string("CupertinoIcons.Outlined.Person"))
        #expect(icon.props["rotateWithLayoutDirection"] == .bool(false))
        let picker = ViewHost(CupertinoSectionDefaults.PickerButton(expanded: true, shape: .rounded(8), contentColor: .blue) { Text("Selected") }).evaluate()
        #expect(picker.props["expanded"] == .bool(true) && picker.props["onClick"] == nil)
        #expect(picker.children.first?.props["name"] == .string("title"))
        let decoration = ViewHost(CupertinoTextFieldDefaults.DecorationBox(valueIsEmpty: false, isError: true,
            contentAlignment: .top, colors: [.errorTextColor: .red], slots: [CupertinoSlot("innerTextField") { Text("Input") }])).evaluate()
        #expect(decoration.props["contentAlignment"] == .string("top") && decoration.props["isError"] == .bool(true))
        #expect(decoration.props["errorTextColor"] == .color(.red))
        #expect(decoration.props["onClick"] == nil)
    }

    @Test("Every catalog case respects presentation state in a valid named-slot tree", arguments: CupertinoSurfaceName.allCases)
    func catalog(surface: CupertinoSurfaceName) throws {
        for presented in [false, true] {
            let host = ViewHost(CupertinoCatalogView(surface: surface, showsPicker: false, initiallyPresented: presented))
            let tree = host.evaluate()
            let nodes = cupertinoNodes(tree)
            let expectedInTree = presented || !surface.rawValue.contains("AlertDialog")
            #expect(nodes.contains { $0.props["name"] == .string(surface.rawValue) } == expectedInTree)
            for node in nodes where node.type == "CupertinoSlot" {
                guard case .string(let name)? = node.props["name"] else { Issue.record("Unnamed slot"); continue }
                #expect(!name.isEmpty && !name.contains("/"))
            }
            if let directory = ProcessInfo.processInfo.environment["CUPERTINO_FIXTURE_DIR"] {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                let data = try JSONSerialization.data(withJSONObject: fixtureObject(tree), options: [.sortedKeys])
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(surface.rawValue + (presented ? "-open.json" : "-closed.json")))
            }
        }
    }
}

private func fixtureValue(_ value: PropValue) -> Any {
    switch value {
    case .string(let value): value
    case .double(let value): value
    case .bool(let value): value
    case .int(let value): value
    case .array(let value): value.map(fixtureValue)
    }
}
private func fixtureObject(_ node: RenderNode) -> [String: Any] {
    var object: [String: Any] = ["type": node.type, "id": node.id,
        "props": node.props.mapValues(fixtureValue), "children": node.children.map(fixtureObject),
        "modifiers": node.modifiers.map { ["kind": $0.kind, "args": $0.args.mapValues(fixtureValue)] as [String: Any] }]
    if let count = node.count { object["count"] = count }
    return object
}
