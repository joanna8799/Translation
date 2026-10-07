import Foundation
import SwiftUI
import Combine
import UIKit

/// 五個驗證項目的彙整。
struct Summary {
    var routeSamples = 0
    var routeHFP = 0
    var routeBuiltInMicOK = 0
    var routeExternalOut = 0
    var judgedTotal = 0
    var judgedCorrect = 0
    var e2eMsMedian = 0.0
    var asrMsMedian = 0.0
    var asrSetupMsMedian = 0.0
    var translateMsMedian = 0.0
    var turns = 0
    var overrideAttempts = 0
    var overrideOK = 0
    var overrideMsMedian = 0.0
    var batteryDropPer30Min = 0.0
    var longestSessionSec = 0.0

    static func build(from events: [MetricEvent]) -> Summary {
        var s = Summary()
        var e2e: [Double] = []
        var asr: [Double] = []
        var setup: [Double] = []
        var tr: [Double] = []
        var ov: [Double] = []
        var sessionStart: (t: TimeInterval, battery: Double)?

        func median(_ xs: [Double]) -> Double {
            guard !xs.isEmpty else { return 0 }
            let sorted = xs.sorted()
            return sorted[sorted.count / 2]
        }

        for e in events {
            switch e.event {
            case "audio.route":
                s.routeSamples += 1
                let route = e.s?["route"] ?? ""
                if route.contains("BluetoothHFP") { s.routeHFP += 1 }
                if route.hasPrefix("in: MicrophoneBuiltIn") { s.routeBuiltInMicOK += 1 }
                if route.contains("BluetoothA2DP") || route.contains("Headphones") { s.routeExternalOut += 1 }
            case "lang.judge":
                s.judgedTotal += 1
                if e.v?["correct"] == 1 { s.judgedCorrect += 1 }
            case "turn.done":
                s.turns += 1
                if let v = e.v?["e2eMs"], v > 0 { e2e.append(v) }
                if let v = e.v?["asrMs"] { asr.append(v) }
                if let v = e.v?["setupMs"] { setup.append(v) }
                if let v = e.v?["translateMs"] { tr.append(v) }
            case "route.override":
                s.overrideAttempts += 1
                if e.v?["ok"] == 1 { s.overrideOK += 1 }
                if let v = e.v?["ms"] { ov.append(v) }
            case "session.start":
                sessionStart = (e.t, e.v?["battery"] ?? -1)
            case "session.stop", "session.heartbeat":
                if let start = sessionStart {
                    let sec = e.t - start.t
                    s.longestSessionSec = max(s.longestSessionSec, sec)
                    if let b = e.v?["battery"], start.battery >= 0, b >= 0, sec > 60 {
                        let drop = (start.battery - b) * 100
                        s.batteryDropPer30Min = max(s.batteryDropPer30Min, drop / sec * 1800)
                    }
                    if e.event == "session.stop" { sessionStart = nil }
                }
            default:
                break
            }
        }
        s.e2eMsMedian = median(e2e)
        s.asrMsMedian = median(asr)
        s.asrSetupMsMedian = median(setup)
        s.translateMsMedian = median(tr)
        s.overrideMsMedian = median(ov)
        return s
    }
}

@MainActor
final class TalkModel: ObservableObject {
    enum State: String { case idle = "待機", preparing = "準備中", listening = "聆聽中", processing = "處理中", speaking = "播放中" }
    enum OutputMode: String, CaseIterable, Identifiable {
        case earbuds = "耳機模式"
        case speaker = "擴音模式"
        var id: String { rawValue }
    }

    @Published var state: State = .idle
    @Published var foreign: LanguageProfile = LanguageProfile.foreignChoices[0]
    @Published var outputMode: OutputMode = .earbuds
    @Published var micFacingBack = true
    @Published var autoSpeakToThem = false
    @Published var turns: [Turn] = []
    @Published var routeDescription = "尚未設定音訊"
    @Published var assetStatus = "尚未準備語言模型"
    @Published var levelDb = -120.0
    @Published var summary = Summary()
    @Published var lastError = ""
    @Published var ready = false

    let toChinese: TranslationBridge
    let toForeign: TranslationBridge
    let currency = CurrencyConverter()

    private let audio = AudioSessionManager()
    private let capture = AudioCapture()
    private let transcriber = Transcriber.shared
    private let speaker = Speaker()
    private var loopTask: Task<Void, Never>?
    private var heartbeat: Timer?
    private var levelTimer: Timer?

    init() {
        let first = LanguageProfile.foreignChoices[0]
        toChinese = TranslationBridge(name: "toChinese", source: first.translationLanguage, target: LanguageProfile.chinese.translationLanguage)
        toForeign = TranslationBridge(name: "toForeign", source: LanguageProfile.chinese.translationLanguage, target: first.translationLanguage)
        UIDevice.current.isBatteryMonitoringEnabled = true
        audio.onRouteChange = { [weak self] desc in
            Task { @MainActor in self?.routeDescription = desc }
        }
    }

    func setForeign(_ profile: LanguageProfile) {
        foreign = profile
        toChinese.sourceLanguage = profile.translationLanguage
        toForeign.targetLanguage = profile.translationLanguage
        ready = false
        assetStatus = "語言已切換，請重新準備"
    }

    // MARK: - 準備

    func prepare() async {
        state = .preparing
        lastError = ""
        guard await AudioSessionManager.requestMicPermission() else {
            lastError = "沒有麥克風權限"
            state = .idle
            return
        }
        do {
            assetStatus = "下載／預熱中文模型…"
            let zh = try await transcriber.prepare(locale: LanguageProfile.chinese.locale)
            assetStatus = "下載／預熱 \(foreign.displayName) 模型…"
            let fx = try await transcriber.prepare(locale: foreign.locale)
            assetStatus = "語音模型就緒：\(zh)、\(fx)。翻譯：\(toChinese.status) / \(toForeign.status)"
            ready = true
        } catch {
            lastError = "語音模型準備失敗：\(error)"
            assetStatus = "失敗"
        }
        await currency.refresh()
        state = .idle
    }

    // MARK: - 開始／停止

    func start() {
        guard ready, let format = transcriber.analyzerFormat else {
            lastError = "先按「準備」"
            return
        }
        lastError = ""
        do {
            try audio.configure(micFacingBack: micFacingBack)
            routeDescription = audio.routeDescription()
            try capture.start(targetFormat: format)
        } catch {
            lastError = "音訊啟動失敗：\(error)"
            return
        }
        state = .listening
        Metrics.shared.log("session.start", ["battery": Double(UIDevice.current.batteryLevel)], ["foreign": foreign.id, "mode": outputMode.rawValue])
        heartbeat = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Metrics.shared.log("session.heartbeat", ["battery": Double(UIDevice.current.batteryLevel)])
        }
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.levelDb = self.capture.segmenter.lastLevelDb }
        }
        let stream = capture.segments()
        loopTask = Task { [weak self] in
            for await segment in stream {
                guard let self else { return }
                await self.handle(segment)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        heartbeat?.invalidate()
        heartbeat = nil
        levelTimer?.invalidate()
        levelTimer = nil
        speaker.stop()
        capture.stop()
        Metrics.shared.log("session.stop", ["battery": Double(UIDevice.current.batteryLevel)])
        audio.deactivate()
        state = .idle
        refreshSummary()
    }

    // MARK: - 一回合

    private func handle(_ segment: AudioSegment) async {
        state = .processing
        defer { if state == .processing { state = .listening } }

        let tAsr = Date().timeIntervalSince1970
        async let zhTask = transcriber.transcribe(segment, locale: LanguageProfile.chinese.locale)
        async let fxTask = transcriber.transcribe(segment, locale: foreign.locale)
        let zh: TranscriptCandidate
        let fx: TranscriptCandidate
        do {
            (zh, fx) = try await (zhTask, fxTask)
        } catch is CancellationError {
            // 按「停止」時正在處理的那一句會被取消，這不是錯誤。
            return
        } catch {
            lastError = "辨識失敗：\(error)"
            Metrics.shared.log("turn.asr.error", [:], ["error": String(describing: error)])
            return
        }
        let asrMs = (Date().timeIntervalSince1970 - tAsr) * 1000
        guard let decision = LanguageDecider.decide(chinese: zh, foreign: fx, foreignProfile: foreign, segmentMs: segment.durationMs) else {
            Metrics.shared.log("turn.empty", ["ms": segment.durationMs])
            return
        }
        Metrics.shared.log("lang.decision", ["zhScore": decision.scoreChinese, "fxScore": decision.scoreForeign, "them": decision.side == .them ? 1 : 0],
                           ["method": decision.method, "zh": zh.text, "fx": fx.text])

        let tTr = Date().timeIntervalSince1970
        var translated = ""
        do {
            switch decision.side {
            case .them: translated = try await toChinese.translate(decision.chosen.text)
            case .me: translated = try await toForeign.translate(decision.chosen.text)
            }
        } catch is CancellationError {
            return
        } catch {
            lastError = "翻譯失敗：\(error)"
            Metrics.shared.log("turn.translate.error", [:], ["error": String(describing: error)])
        }
        let translateMs = (Date().timeIntervalSince1970 - tTr) * 1000

        let note = decision.side == .them
            ? currency.annotate(decision.chosen.text, defaultCurrency: foreign.defaultCurrency)
            : ""

        var turn = Turn(side: decision.side, original: decision.chosen.text, translated: translated, currencyNote: note,
                        asrMs: asrMs, translateMs: translateMs, e2eMs: 0, decisionNote: decision.note, judgedCorrect: nil)
        turns.insert(turn, at: 0)

        // 輸出。對方講的：翻成中文唸給我聽（耳機模式走耳機，擴音模式走擴音）。
        // 我講的：螢幕顯示外語；擴音模式或開了自動播放才唸給對方。
        var e2eMs = 0.0
        if !translated.isEmpty {
            let shouldSpeak: Bool
            let toSpeaker: Bool
            switch decision.side {
            case .them:
                shouldSpeak = true
                toSpeaker = outputMode == .speaker
            case .me:
                shouldSpeak = outputMode == .speaker || autoSpeakToThem
                toSpeaker = true
            }
            if shouldSpeak {
                let language = decision.side == .them ? LanguageProfile.chinese.ttsLanguage : foreign.ttsLanguage
                e2eMs = await speak(translated, language: language, toSpeaker: toSpeaker, since: segment.endedAt)
            }
        }
        turn.e2eMs = e2eMs
        if let i = turns.firstIndex(where: { $0.id == turn.id }) { turns[i] = turn }
        Metrics.shared.log("turn.done", ["asrMs": asrMs, "setupMs": max(zh.setupMs, fx.setupMs), "translateMs": translateMs, "e2eMs": e2eMs,
                                         "segmentMs": segment.durationMs],
                           ["side": decision.side.rawValue])
        refreshSummary()
    }

    /// 回傳「講完到第一個字出聲」的毫秒數。
    private func speak(_ text: String, language: String, toSpeaker: Bool, since endedAt: TimeInterval) async -> Double {
        state = .speaking
        capture.segmenter.muted = true
        var e2e = 0.0
        speaker.onStart = { e2e = (Date().timeIntervalSince1970 - endedAt) * 1000 }
        let needOverride = toSpeaker && audio.hasExternalOutput
        if needOverride { _ = try? audio.setOutput(.speaker) }
        await speaker.speak(text, language: language)
        if needOverride { _ = try? audio.setOutput(.preferred) }
        // 擴音播完後留一點時間，免得殘響被當成下一句。
        try? await Task.sleep(for: .milliseconds(toSpeaker ? 400 : 150))
        capture.segmenter.muted = false
        state = .listening
        return e2e
    }

    /// 「播給對方」按鈕：把最近一句我講的翻譯用擴音唸出來。
    func replayLastMineToThem() {
        guard let turn = turns.first(where: { $0.side == .me && !$0.translated.isEmpty }) else { return }
        Task { _ = await speak(turn.translated, language: foreign.ttsLanguage, toSpeaker: true, since: Date().timeIntervalSince1970) }
    }

    func judge(_ turn: Turn, correct: Bool) {
        guard let i = turns.firstIndex(where: { $0.id == turn.id }) else { return }
        turns[i].judgedCorrect = correct
        Metrics.shared.log("lang.judge", ["correct": correct ? 1 : 0], ["side": turn.side.rawValue, "note": turn.decisionNote])
        refreshSummary()
    }

    func refreshSummary() {
        summary = Summary.build(from: Metrics.readAll())
    }

    func resetMetrics() {
        Metrics.reset()
        turns = []
        refreshSummary()
    }
}
