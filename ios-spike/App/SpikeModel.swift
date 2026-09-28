import Foundation
import SwiftUI
import Combine

/// 五個驗證項目的彙整結果。
struct Summary {
    var extMaxFootprintMB = 0.0
    var extMemorySkips = 0
    var ocrCount = 0
    var ocrMsMedian = 0.0
    var ipcMsMedian = 0.0
    var translateMsMedian = 0.0
    var e2eMsMedian = 0.0
    var backgroundTranslateOK = 0
    var backgroundTranslateFail = 0
    var maxBackgroundSeconds = 0.0
    var blackouts = 0
    var visionLanguages = ""
    var pipRenderSize = ""
    var pipFailures = 0

    static func build(from events: [MetricEvent]) -> Summary {
        var s = Summary()
        var ocrMs: [Double] = []
        var ipcMs: [Double] = []
        var translateMs: [Double] = []
        var e2eMs: [Double] = []
        var runStart: TimeInterval?
        var runLast: TimeInterval?

        func median(_ xs: [Double]) -> Double {
            guard !xs.isEmpty else { return 0 }
            let sorted = xs.sorted()
            return sorted[sorted.count / 2]
        }

        for e in events {
            switch e.event {
            case "broadcast.started":
                s.visionLanguages = e.s?["visionLanguages"] ?? s.visionLanguages
            case "ext.ocr":
                s.ocrCount += 1
                if let v = e.v?["ocrMs"] { ocrMs.append(v) }
                if let v = e.v?["footprintMB"] { s.extMaxFootprintMB = max(s.extMaxFootprintMB, v) }
                if e.v?["blackout"] == 1 { s.blackouts += 1 }
            case "ext.skip.memory":
                s.extMemorySkips += 1
                if let v = e.v?["footprintMB"] { s.extMaxFootprintMB = max(s.extMaxFootprintMB, v) }
            case "broadcast.finished":
                if let v = e.v?["maxFootprintMB"] { s.extMaxFootprintMB = max(s.extMaxFootprintMB, v) }
            case "app.received":
                if let v = e.v?["ipcMs"] { ipcMs.append(v) }
            case "app.rendered":
                if let v = e.v?["translateMs"] { translateMs.append(v) }
                if let v = e.v?["e2eMs"] { e2eMs.append(v) }
                if e.s?["phase"] == "background" { s.backgroundTranslateOK += 1 }
            case "app.translate.failed":
                if e.s?["phase"] == "background" { s.backgroundTranslateFail += 1 }
            case "pip.renderSize":
                if let w = e.v?["w"], let h = e.v?["h"] { s.pipRenderSize = "\(Int(w))×\(Int(h))" }
            case "pip.failed":
                s.pipFailures += 1
            case "app.heartbeat":
                let inBackgroundWithPiP = e.s?["phase"] == "background" && e.v?["pip"] == 1
                if inBackgroundWithPiP {
                    if runStart == nil { runStart = e.t }
                    runLast = e.t
                    if let start = runStart, let last = runLast {
                        s.maxBackgroundSeconds = max(s.maxBackgroundSeconds, last - start)
                    }
                } else {
                    runStart = nil
                    runLast = nil
                }
            default:
                break
            }
        }
        s.ocrMsMedian = median(ocrMs)
        s.ipcMsMedian = median(ipcMs)
        s.translateMsMedian = median(translateMs)
        s.e2eMsMedian = median(e2eMs)
        return s
    }
}

@MainActor
final class SpikeModel: ObservableObject {
    @Published var zone = Zone.load() {
        didSet { zone.save() }
    }
    @Published var lastFrame: OCRFrame?
    @Published var lastTranslation = ""
    @Published var scenePhaseName = "active"
    @Published var summary = Summary()
    @Published var recent: [MetricEvent] = []
    @Published var extMaxFootprintMB = 0.0
    @Published var extFramesSeen = 0
    @Published var extOCRCount = 0
    @Published var extLastError = ""
    @Published var appFootprintMB = 0.0

    let pip = PiPController()
    let bridge = TranslationBridge.shared

    private var observer: DarwinObserver?
    private var heartbeat: Timer?
    private var lastTextHash = 0
    private var backgroundSince: TimeInterval?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // pip 是巢狀的 ObservableObject，它的變化要轉發出去畫面才會刷新。
        pip.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        observer = DarwinObserver(name: AppGroup.ocrNotification) { [weak self] in
            Task { @MainActor in self?.handleOCR() }
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        Metrics.app.log("app.launch")
        refreshSummary()
    }

    func setScenePhase(_ phase: ScenePhase) {
        let name: String
        switch phase {
        case .active: name = "active"
        case .inactive: name = "inactive"
        case .background: name = "background"
        @unknown default: name = "unknown"
        }
        scenePhaseName = name
        if name == "background" {
            backgroundSince = Date().timeIntervalSince1970
        } else {
            backgroundSince = nil
        }
        Metrics.app.log("app.scenePhase", ["pip": pip.isActive ? 1 : 0], ["phase": name])
    }

    private func tick() {
        appFootprintMB = MemoryFootprint.currentMB()
        extMaxFootprintMB = AppGroup.defaults.double(forKey: AppGroup.Keys.extMaxFootprintMB)
        extFramesSeen = AppGroup.defaults.integer(forKey: AppGroup.Keys.extFramesSeen)
        extOCRCount = AppGroup.defaults.integer(forKey: AppGroup.Keys.extOCRCount)
        extLastError = AppGroup.defaults.string(forKey: AppGroup.Keys.extLastError) ?? ""
        var values: [String: Double] = ["pip": pip.isActive ? 1 : 0, "footprintMB": appFootprintMB]
        if let since = backgroundSince {
            values["backgroundSeconds"] = Date().timeIntervalSince1970 - since
        }
        Metrics.app.log("app.heartbeat", values, ["phase": scenePhaseName])
    }

    /// 擴充寫完 latest_ocr.json 並送出 Darwin 通知後進來。
    private func handleOCR() {
        let url = AppGroup.containerURL.appendingPathComponent(AppGroup.latestOCRFile)
        guard let data = try? Data(contentsOf: url),
              let frame = try? JSONDecoder().decode(OCRFrame.self, from: data) else {
            Metrics.app.log("app.received.unreadable")
            return
        }
        let now = Date().timeIntervalSince1970
        Metrics.app.log(
            "app.received",
            [
                "ipcMs": (now - frame.ocrDoneAt) * 1000,
                "sinceCaptureMs": (now - frame.capturedAt) * 1000,
                "lines": Double(frame.lines.count),
            ],
            ["phase": scenePhaseName]
        )
        lastFrame = frame

        if frame.blackout {
            Metrics.app.log("app.blackout", [:], ["phase": scenePhaseName])
            pip.render(lines: ["畫面全黑"], note: "目標 app 可能偵測到錄影而遮掉內容")
            return
        }

        let text = frame.joinedText
        guard !text.isEmpty else {
            pip.render(lines: ["（區域內沒有文字）"], note: "OCR \(Int(frame.ocrMs)) ms")
            return
        }
        let hash = text.hashValue
        guard hash != lastTextHash else {
            Metrics.app.log("app.dedupe")
            return
        }
        lastTextHash = hash
        pip.render(lines: frame.lines.map(\.text), note: "OCR \(Int(frame.ocrMs)) ms，翻譯中…")

        let phase = scenePhaseName
        Task { [weak self] in
            guard let self else { return }
            let t0 = Date().timeIntervalSince1970
            do {
                let output = try await bridge.translate(text)
                let t1 = Date().timeIntervalSince1970
                let e2e = (t1 - frame.capturedAt) * 1000
                lastTranslation = output
                pip.render(lines: output.components(separatedBy: "\n"), note: "端到端 \(Int(e2e)) ms")
                Metrics.app.log(
                    "app.rendered",
                    ["e2eMs": e2e, "translateMs": (t1 - t0) * 1000],
                    ["phase": phase]
                )
            } catch {
                lastTranslation = "翻譯失敗：\(error)"
                pip.render(lines: frame.lines.map(\.text), note: "翻譯失敗：\(error)")
                Metrics.app.log("app.translate.failed", [:], ["error": String(describing: error), "phase": phase])
            }
        }
    }

    func testTranslate() {
        Task {
            let sample = "今日はいい天気ですね。\n明日も晴れるといいな。"
            do {
                let out = try await bridge.translate(sample)
                lastTranslation = out
                pip.render(lines: out.components(separatedBy: "\n"), note: "測試翻譯")
                Metrics.app.log("app.testTranslate.ok", [:], ["phase": scenePhaseName])
            } catch {
                lastTranslation = "翻譯失敗：\(error)"
                Metrics.app.log("app.testTranslate.failed", [:], ["error": String(describing: error), "phase": scenePhaseName])
            }
        }
    }

    func refreshSummary() {
        let events = Metrics.readAll()
        summary = Summary.build(from: events)
        recent = Array(events.suffix(40).reversed())
    }

    func resetMetrics() {
        Metrics.reset()
        AppGroup.defaults.removeObject(forKey: AppGroup.Keys.extMaxFootprintMB)
        AppGroup.defaults.removeObject(forKey: AppGroup.Keys.extLastError)
        lastTextHash = 0
        refreshSummary()
    }
}
