import Foundation
import AVFoundation

/// AVSpeechSynthesizer 的 async 包裝。用系統內建語音，有下載到「進階」或「增強」品質就優先用。
final class Speaker: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isSpeaking = false
    /// 第一個字出聲的時間，給端到端延遲用。
    private(set) var lastStartedAt: TimeInterval?
    var onStart: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ text: String, language: String, rate: Float = AVSpeechUtteranceDefaultSpeechRate) async {
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: language)
        utterance.rate = rate
        isSpeaking = true
        lastStartedAt = nil
        // 沒有對應語音或系統沒回呼時不能讓整條管線卡住：超時就強制結束。
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(text.count) * 0.4 + 5))
            guard let self, !Task.isCancelled else { return }
            Metrics.shared.log("tts.timeout", ["chars": Double(text.count)])
            self.synthesizer.stopSpeaking(at: .immediate)
            await MainActor.run { self.finish() }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
            synthesizer.speak(utterance)
        }
        watchdog.cancel()
        isSpeaking = false
    }

    /// 只能 resume 一次：delegate 與 watchdog 誰先到誰負責。
    private func finish() {
        continuation?.resume()
        continuation = nil
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased() == language.lowercased() }
        let ranked = candidates.sorted { a, b in rank(a.quality) > rank(b.quality) }
        return ranked.first ?? AVSpeechSynthesisVoice(language: language)
    }

    private static func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
        switch q {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        lastStartedAt = Date().timeIntervalSince1970
        onStart?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish()
    }
}
