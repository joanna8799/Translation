import SwiftUI
import AVFoundation

@main
struct LiveSpikeApp: App {
    @StateObject private var model = SpikeModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Self.configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onChange(of: scenePhase) { _, phase in
                    model.setScenePhase(phase)
                }
        }
    }

    /// PiP 要求 playback 類別的音訊工作階段。mixWithOthers 讓底下的閱讀 app 聲音不被打斷。
    private static func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            Metrics.app.log("audio.session.error", [:], ["error": String(describing: error)])
        }
    }
}
