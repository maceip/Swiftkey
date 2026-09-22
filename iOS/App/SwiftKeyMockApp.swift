import SwiftUI

@main
struct SwiftKeyMockApp: App {
    @StateObject private var model = MockAppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            MockHomeView(model: model)
                .tint(MockDesign.accent)
                .task { await model.load() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refreshFromStore() }
                }
        }
    }
}
