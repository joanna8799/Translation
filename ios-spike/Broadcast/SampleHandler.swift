import ReplayKit
import Vision
import CoreMedia
import CoreVideo
import ImageIO

/// 廣播擴充：只做三件事，抓區域縮圖判斷靜止、跑 Vision OCR、把文字丟給主 app。
/// 記憶體上限 50 MB，所以不建 CIImage、不複製畫面、不載任何模型、不做翻譯與排版。
final class SampleHandler: RPBroadcastSampleHandler {

    // 參數，驗證時可以調
    private let checkInterval: TimeInterval = 0.33   // 每秒最多檢查 3 次
    private let stillThreshold = 1.5                 // 兩次檢查差異小於此視為靜止
    private let changeThreshold = 4.0                // 與上次 OCR 的畫面差異大於此才重跑
    private let footprintCeilingMB = 40.0            // 超過就跳過這幀，離 50 MB 留餘裕
    private let blackoutLuma = 0.05

    private let metrics = Metrics.ext
    private var zone = Zone.load()
    private var seq = 0
    private var framesSeen = 0
    private var ocrCount = 0
    private var lastCheckedAt: TimeInterval = 0
    private var prevThumb: Thumb?
    private var lastOCRThumb: Thumb?
    private var maxFootprint = 0.0

    private lazy var request: VNRecognizeTextRequest = {
        let r = VNRecognizeTextRequest()
        r.recognitionLevel = .accurate
        r.usesLanguageCorrection = false   // 漫畫專有名詞多，先關掉
        r.recognitionLanguages = ["ja", "ko", "zh-Hant", "zh-Hans", "en"]
        return r
    }()

    // MARK: - 生命週期

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        zone = Zone.load()
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        AppGroup.defaults.set(supported.joined(separator: ","), forKey: AppGroup.Keys.extVisionLanguages)
        AppGroup.defaults.set(0, forKey: AppGroup.Keys.extFramesSeen)
        AppGroup.defaults.set(0, forKey: AppGroup.Keys.extOCRCount)
        AppGroup.defaults.removeObject(forKey: AppGroup.Keys.extLastError)
        metrics.log(
            "broadcast.started",
            ["footprintMB": MemoryFootprint.currentMB()],
            ["zone": "\(zone)", "visionLanguages": supported.joined(separator: ",")]
        )
    }

    override func broadcastPaused() {
        metrics.log("broadcast.paused")
    }

    override func broadcastResumed() {
        metrics.log("broadcast.resumed")
        prevThumb = nil
    }

    override func broadcastFinished() {
        metrics.log(
            "broadcast.finished",
            ["framesSeen": Double(framesSeen), "ocrCount": Double(ocrCount), "maxFootprintMB": maxFootprint]
        )
    }

    // MARK: - 每一幀

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        framesSeen += 1
        let now = Date().timeIntervalSince1970
        guard now - lastCheckedAt >= checkInterval else { return }
        lastCheckedAt = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        autoreleasepool {
            analyze(pixelBuffer, sampleBuffer: sampleBuffer, capturedAt: now)
        }
    }

    private func analyze(_ pixelBuffer: CVPixelBuffer, sampleBuffer: CMSampleBuffer, capturedAt: TimeInterval) {
        let footprint = MemoryFootprint.currentMB()
        maxFootprint = max(maxFootprint, footprint)
        AppGroup.defaults.set(maxFootprint, forKey: AppGroup.Keys.extMaxFootprintMB)
        AppGroup.defaults.set(framesSeen, forKey: AppGroup.Keys.extFramesSeen)

        if footprint > footprintCeilingMB {
            metrics.log("ext.skip.memory", ["footprintMB": footprint])
            return
        }

        let format = FrameAnalyzer.fourCC(CVPixelBufferGetPixelFormatType(pixelBuffer))
        guard let thumb = FrameAnalyzer.thumbnail(of: pixelBuffer, zone: zone) else {
            metrics.log("ext.skip.format", [:], ["pixelFormat": format])
            return
        }
        defer { prevThumb = thumb }
        guard let prev = prevThumb else { return }

        let motion = thumb.diff(prev)
        guard motion < stillThreshold else { return }                      // 還在捲動
        if let last = lastOCRThumb, thumb.diff(last) < changeThreshold { return } // 內容沒變

        let orientation = orientationOf(sampleBuffer)
        request.regionOfInterest = zone.visionROI
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])

        let t0 = Date().timeIntervalSince1970
        var lines: [TextLine] = []
        do {
            try handler.perform([request])
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let box = observation.boundingBox
                lines.append(TextLine(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    box: [box.minX, box.minY, box.width, box.height]
                ))
            }
        } catch {
            let message = String(describing: error)
            AppGroup.defaults.set(message, forKey: AppGroup.Keys.extLastError)
            metrics.log("ext.ocr.error", [:], ["error": message])
            return
        }
        let t1 = Date().timeIntervalSince1970

        lastOCRThumb = thumb
        seq += 1
        ocrCount += 1
        AppGroup.defaults.set(ocrCount, forKey: AppGroup.Keys.extOCRCount)

        let frame = OCRFrame(
            seq: seq,
            capturedAt: capturedAt,
            ocrDoneAt: t1,
            ocrMs: (t1 - t0) * 1000,
            footprintMB: MemoryFootprint.currentMB(),
            orientation: orientation.rawValue,
            pixelFormat: format,
            frameWidth: CVPixelBufferGetWidth(pixelBuffer),
            frameHeight: CVPixelBufferGetHeight(pixelBuffer),
            meanLuma: thumb.mean,
            blackout: thumb.mean < blackoutLuma && lines.isEmpty,
            lines: lines
        )
        write(frame)
        metrics.log(
            "ext.ocr",
            [
                "ocrMs": frame.ocrMs,
                "lines": Double(lines.count),
                "footprintMB": frame.footprintMB,
                "meanLuma": thumb.mean,
                "blackout": frame.blackout ? 1 : 0,
                "motion": motion,
                "orientation": Double(orientation.rawValue),
            ],
            ["pixelFormat": format]
        )
        DarwinNotifier.post(AppGroup.ocrNotification)
    }

    // MARK: - 工具

    private func orientationOf(_ sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        if let number = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
           let orientation = CGImagePropertyOrientation(rawValue: number.uint32Value) {
            return orientation
        }
        return .up
    }

    private func write(_ frame: OCRFrame) {
        let url = AppGroup.containerURL.appendingPathComponent(AppGroup.latestOCRFile)
        if let data = try? JSONEncoder().encode(frame) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
