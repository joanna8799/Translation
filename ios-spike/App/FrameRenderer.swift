import CoreVideo
import CoreMedia
import UIKit

/// 把幾行文字畫成一張 BGRA 影格，包成 CMSampleBuffer 給 PiP 用。
/// PiP 只能播影片，所以字幕必須是影片影格。
final class FrameRenderer {
    let width: Int
    let height: Int
    private var pool: CVPixelBufferPool?
    private var formatDescription: CMVideoFormatDescription?

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
    }

    func makeSampleBuffer(lines: [String], note: String) -> CMSampleBuffer? {
        guard let pool else { return nil }
        var pixelBufferOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut)
        guard let pixelBuffer = pixelBufferOut else { return nil }

        draw(into: pixelBuffer, lines: lines, note: note)

        if formatDescription == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDescription
            )
        }
        guard let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBufferOut: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBufferOut
        )
        guard let sampleBuffer = sampleBufferOut else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return sampleBuffer
    }

    private func draw(into pixelBuffer: CVPixelBuffer, lines: [String], note: String) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        let w = CGFloat(width)
        let h = CGFloat(height)
        context.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // 洋紅色細框：之後讓擴充在擷取畫面裡認出 PiP 視窗並遮掉，避免自我擷取迴圈。
        context.setStrokeColor(UIColor.magenta.cgColor)
        context.setLineWidth(8)
        context.stroke(CGRect(x: 4, y: 4, width: w - 8, height: h - 8))

        // CGContext 原點在左下，翻轉後才能用 UIKit 的字串繪圖。
        context.translateBy(x: 0, y: h)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 30, weight: .medium),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
        ]
        let noteAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18),
            .foregroundColor: UIColor(white: 0.7, alpha: 1),
        ]
        (lines.joined(separator: "\n") as NSString).draw(
            in: CGRect(x: 24, y: 20, width: w - 48, height: h - 74),
            withAttributes: bodyAttributes
        )
        (note as NSString).draw(
            in: CGRect(x: 24, y: h - 46, width: w - 48, height: 30),
            withAttributes: noteAttributes
        )
    }
}
