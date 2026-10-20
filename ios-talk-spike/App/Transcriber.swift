import Foundation
import AVFoundation
import Speech

/// 一個辨識器對一段音訊的產出。
struct TranscriptCandidate {
    var locale: String
    var text: String
    /// 每個字詞信心值的平均，拿不到時為 nil。
    var meanConfidence: Double?
    var asrMs: Double
    var setupMs: Double
}

/// SpeechAnalyzer（iOS 26）的薄包裝：對「一段已經切好的音訊」做一次性辨識。
///
/// 為什麼不做串流：這個驗證要量「對方講完到我聽到」的延遲，而且要同時用兩個語言的辨識器比對，
/// 一段一段做最單純。每段重建 analyzer 的成本會記錄在 setupMs，太高再改成長駐串流加 finalize(through:)。
final class Transcriber {
    static let shared = Transcriber()

    private(set) var analyzerFormat: AVAudioFormat?

    /// 確認語言模型在裝置上，沒有就下載；並預熱一次讓後面每段的 setup 變快。
    func prepare(locale: Locale) async throws -> String {
        guard let matched = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            let supported = await SpeechTranscriber.supportedLocales.map(\.identifier).joined(separator: ",")
            Metrics.shared.log("asr.unsupported", [:], ["locale": locale.identifier, "supported": supported])
            throw TranscriberError.unsupportedLocale(locale.identifier)
        }
        let transcriber = SpeechTranscriber(locale: matched, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.transcriptionConfidence])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            Metrics.shared.log("asr.asset.download.start", [:], ["locale": matched.identifier])
            try await request.downloadAndInstall()
            Metrics.shared.log("asr.asset.download.done", [:], ["locale": matched.identifier])
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if analyzerFormat == nil {
            analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        }
        let t0 = Date().timeIntervalSince1970
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        await analyzer.cancelAndFinishNow()
        let ms = (Date().timeIntervalSince1970 - t0) * 1000
        Metrics.shared.log("asr.warm", ["ms": ms], ["locale": matched.identifier])
        return matched.identifier
    }

    func transcribe(_ segment: AudioSegment, locale: Locale) async throws -> TranscriptCandidate {
        let tSetup = Date().timeIntervalSince1970
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.transcriptionConfidence])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        let setupMs = (Date().timeIntervalSince1970 - tSetup) * 1000

        // 先開始收結果，再餵音訊，不然結果序列可能漏掉前面的。
        let collector = Task<(String, Double?), Error> {
            var pieces: [String] = []
            var confSum = 0.0
            var confCount = 0
            for try await result in transcriber.results where result.isFinal {
                pieces.append(String(result.text.characters))
                for run in result.text.runs {
                    if let c = run.transcriptionConfidence {
                        confSum += Double(c)
                        confCount += 1
                    }
                }
            }
            let text = pieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return (text, confCount > 0 ? confSum / Double(confCount) : nil)
        }

        let t0 = Date().timeIntervalSince1970
        let (stream, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        for buffer in segment.buffers {
            builder.yield(AnalyzerInput(buffer: buffer))
        }
        builder.finish()
        let lastSample = try await analyzer.analyzeSequence(stream)
        if let lastSample {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let (text, confidence) = try await collector.value
        let asrMs = (Date().timeIntervalSince1970 - t0) * 1000
        Metrics.shared.log("asr.done", ["ms": asrMs, "setupMs": setupMs, "chars": Double(text.count), "conf": confidence ?? -1],
                           ["locale": locale.identifier])
        return TranscriptCandidate(locale: locale.identifier, text: text, meanConfidence: confidence, asrMs: asrMs, setupMs: setupMs)
    }

    enum TranscriberError: Error {
        case unsupportedLocale(String)
    }
}
