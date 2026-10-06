import Foundation
import AVFoundation

/// 一段完整的發言：從開口到停頓。
struct AudioSegment {
    var buffers: [AVAudioPCMBuffer]
    var durationMs: Double
    /// 偵測到講完的牆鐘時間，端到端延遲從這裡起算。
    var endedAt: TimeInterval
    var peakDb: Double
}

/// 簡單的能量式語音活動偵測，把連續音訊切成一回合一回合。
/// 不用 SpeechDetector 是因為我們要自己掌握「講完了」的時間點來量延遲，而且這個做法在任何格式都能跑。
final class TurnSegmenter {
    /// 相對噪音底的開口門檻（dB）。市場、車站可調高到 12 到 15。
    var startAboveFloorDb = 10.0
    var minSpeechMs = 300.0
    var endSilenceMs = 700.0
    var maxSegmentMs = 15_000.0
    var preRollMs = 300.0
    /// TTS 播放中設 true，避免把自己播出來的聲音當成對方在講。
    var muted = false {
        didSet { if muted { reset() } }
    }

    private var noiseFloorDb = -60.0
    private var speaking = false
    private var speechMs = 0.0
    private var silenceMs = 0.0
    private var current: [AVAudioPCMBuffer] = []
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollMsAccum = 0.0
    private var peakDb = -120.0
    private(set) var lastLevelDb = -120.0

    func reset() {
        speaking = false
        speechMs = 0
        silenceMs = 0
        current = []
        preRoll = []
        preRollMsAccum = 0
        peakDb = -120
    }

    /// 餵一個 buffer，講完一回合時回傳該回合。
    func push(_ buffer: AVAudioPCMBuffer) -> AudioSegment? {
        guard !muted else { return nil }
        let ms = Double(buffer.frameLength) / buffer.format.sampleRate * 1000
        let db = Self.rmsDb(buffer)
        lastLevelDb = db

        // 噪音底：安靜時慢慢往下追，吵時慢慢往上爬，不讓一句話把底拉高。
        if db < noiseFloorDb {
            noiseFloorDb += (db - noiseFloorDb) * 0.2
        } else {
            noiseFloorDb += (db - noiseFloorDb) * 0.005
        }
        let threshold = max(noiseFloorDb + startAboveFloorDb, -55)
        let loud = db > threshold

        if !speaking {
            preRoll.append(buffer)
            preRollMsAccum += ms
            while preRollMsAccum > preRollMs, preRoll.count > 1 {
                let dropped = preRoll.removeFirst()
                preRollMsAccum -= Double(dropped.frameLength) / dropped.format.sampleRate * 1000
            }
            if loud {
                speaking = true
                current = preRoll
                preRoll = []
                preRollMsAccum = 0
                speechMs = ms
                silenceMs = 0
                peakDb = db
            }
            return nil
        }

        current.append(buffer)
        peakDb = max(peakDb, db)
        if loud {
            speechMs += ms
            silenceMs = 0
        } else {
            silenceMs += ms
        }
        let totalMs = current.reduce(0.0) { $0 + Double($1.frameLength) / $1.format.sampleRate * 1000 }
        let ended = silenceMs >= endSilenceMs || totalMs >= maxSegmentMs
        guard ended else { return nil }

        let segment = AudioSegment(buffers: current, durationMs: totalMs, endedAt: Date().timeIntervalSince1970, peakDb: peakDb)
        let hadSpeech = speechMs >= minSpeechMs
        reset()
        return hadSpeech ? segment : nil
    }

    static func rmsDb(_ buffer: AVAudioPCMBuffer) -> Double {
        let n = Int(buffer.frameLength)
        guard n > 0 else { return -120 }
        var sum = 0.0
        if let f = buffer.floatChannelData {
            let p = f[0]
            for i in 0..<n { let x = Double(p[i]); sum += x * x }
        } else if let s = buffer.int16ChannelData {
            let p = s[0]
            for i in 0..<n { let x = Double(p[i]) / 32768; sum += x * x }
        } else {
            return -120
        }
        let rms = (sum / Double(n)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -120
    }
}

/// AVAudioEngine 麥克風 tap，轉成辨識器要的格式，餵給 segmenter。
final class AudioCapture {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    let segmenter = TurnSegmenter()
    private var continuation: AsyncStream<AudioSegment>.Continuation?
    private(set) var isRunning = false

    func segments() -> AsyncStream<AudioSegment> {
        continuation?.finish()
        return AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func start(targetFormat: AVAudioFormat) throws {
        let input = engine.inputNode
        let hw = input.outputFormat(forBus: 0)
        self.targetFormat = targetFormat
        converter = AVAudioConverter(from: hw, to: targetFormat)
        Metrics.shared.log("audio.format", ["hwRate": hw.sampleRate, "hwCh": Double(hw.channelCount), "targetRate": targetFormat.sampleRate],
                           ["target": targetFormat.description])
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: hw) { [weak self] buffer, _ in
            guard let self, let converted = self.convert(buffer) else { return }
            if let segment = self.segmenter.push(converted) {
                Metrics.shared.log("vad.segment", ["ms": segment.durationMs, "peakDb": segment.peakDb])
                self.continuation?.yield(segment)
            }
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        segmenter.reset()
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter, let target = targetFormat else { return nil }
        if buffer.format == target { return buffer }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error || error != nil {
            Metrics.shared.log("audio.convert.error", [:], ["error": String(describing: error)])
            return nil
        }
        return out.frameLength > 0 ? out : nil
    }
}
