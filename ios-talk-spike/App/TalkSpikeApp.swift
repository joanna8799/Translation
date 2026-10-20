import SwiftUI

@main
struct TalkSpikeApp: App {
    @StateObject private var model = TalkModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.currency.refreshIfStale() }
                    }
                }
        }
    }
}
