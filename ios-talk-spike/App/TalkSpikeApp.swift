import SwiftUI

@main
struct TalkSpikeApp: App {
    @StateObject private var model = TalkModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
