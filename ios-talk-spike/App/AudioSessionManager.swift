import Foundation
import AVFoundation

/// 音訊路徑是這個驗證專案最重要的一塊：
/// - 輸出走藍牙 A2DP（或有線耳機），音質正常。
/// - 輸入固定用 iPhone 內建麥克風收對方的聲音。耳機上的麥克風在你嘴邊，收不到對方。
/// - 絕對不要加 .allowBluetooth（HFP）：一加系統就會改用耳機麥克風，整條音訊掉到電話音質（8 到 16 kHz）。
/// - 沒接耳機時 playAndRecord 預設從聽筒出聲，要改到擴音。
/// - 「播給對方」時暫時把輸出切到擴音，播完切回耳機。
final class AudioSessionManager {
    enum Output { case preferred, speaker }

    private let session = AVAudioSession.sharedInstance()
    private var observer: NSObjectProtocol?
    var onRouteChange: ((String) -> Void)?

    func configure(micFacingBack: Bool) throws {
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP])
        try selectBuiltInMic(facingBack: micFacingBack)
        try session.setActive(true)
        try ensureSensibleOutput()
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).map(String.init) ?? "?"
            try? self.ensureSensibleOutput()
            let desc = self.routeDescription()
            Metrics.shared.log("audio.route", [:], ["route": desc, "reason": reason])
            self.onRouteChange?(desc)
        }
        Metrics.shared.log("audio.route", [:], ["route": routeDescription(), "reason": "configure"])
    }

    func deactivate() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// 內建麥克風，可選背面資料來源加心形指向，對準站在手機背面方向的對方。
    func selectBuiltInMic(facingBack: Bool) throws {
        guard let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            Metrics.shared.log("audio.mic.missing")
            return
        }
        try session.setPreferredInput(mic)
        guard facingBack, let sources = mic.dataSources else { return }
        if let back = sources.first(where: { $0.orientation == .back }) {
            if back.supportedPolarPatterns?.contains(.cardioid) == true {
                try? back.setPreferredPolarPattern(.cardioid)
            }
            try mic.setPreferredDataSource(back)
            Metrics.shared.log("audio.mic.back", [:], ["pattern": back.selectedPolarPattern?.rawValue ?? "none"])
        }
    }

    /// 沒有外接輸出時，playAndRecord 會走聽筒，改成擴音；有耳機時不碰。
    func ensureSensibleOutput() throws {
        let outputs = session.currentRoute.outputs.map(\.portType)
        if outputs.contains(.builtInReceiver) {
            try session.overrideOutputAudioPort(.speaker)
        }
    }

    /// 回傳切換花的毫秒數，並記錄切換後的實際路徑。
    @discardableResult
    func setOutput(_ output: Output) throws -> Double {
        let t0 = Date().timeIntervalSince1970
        switch output {
        case .speaker:
            try session.overrideOutputAudioPort(.speaker)
        case .preferred:
            try session.overrideOutputAudioPort(.none)
            try ensureSensibleOutput()
        }
        let ms = (Date().timeIntervalSince1970 - t0) * 1000
        let desc = routeDescription()
        let wantSpeaker = output == .speaker
        let ok = wantSpeaker == session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
        Metrics.shared.log("route.override", ["ms": ms, "ok": ok ? 1 : 0], ["to": wantSpeaker ? "speaker" : "preferred", "route": desc])
        return ms
    }

    var hasExternalOutput: Bool {
        session.currentRoute.outputs.contains {
            [.bluetoothA2DP, .headphones, .bluetoothLE, .airPlay, .usbAudio].contains($0.portType)
        }
    }

    var usesHFP: Bool {
        session.currentRoute.outputs.contains { $0.portType == .bluetoothHFP }
            || session.currentRoute.inputs.contains { $0.portType == .bluetoothHFP }
    }

    func routeDescription() -> String {
        let ins = session.currentRoute.inputs.map { "\($0.portType.rawValue)\($0.selectedDataSource.map { "/" + $0.dataSourceName } ?? "")" }
        let outs = session.currentRoute.outputs.map { $0.portType.rawValue }
        return "in: \(ins.joined(separator: ",")) → out: \(outs.joined(separator: ","))"
    }

    static func requestMicPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
