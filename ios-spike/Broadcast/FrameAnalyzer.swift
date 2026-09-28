import Foundation
import CoreVideo

/// 區域內亮度的 32x32 縮圖，用來判斷畫面是否靜止、內容有沒有變、是不是全黑。
/// 直接讀像素平面，不建 CIImage、不複製整張畫面，把擴充的記憶體壓到最低。
struct Thumb {
    static let size = 32
    var luma: [UInt8]

    /// 0...1
    var mean: Double {
        Double(luma.reduce(0) { $0 + Int($1) }) / Double(luma.count) / 255.0
    }

    /// 平均絕對差，0...255
    func diff(_ other: Thumb) -> Double {
        var sum = 0
        for i in 0..<luma.count {
            sum += abs(Int(luma[i]) - Int(other.luma[i]))
        }
        return Double(sum) / Double(luma.count)
    }
}

enum FrameAnalyzer {
    /// 支援 BGRA 與 420 雙平面（ReplayKit 最常給的格式）。其他格式回傳 nil 並由呼叫端記錄。
    static func thumbnail(of pixelBuffer: CVPixelBuffer, zone: Zone) -> Thumb? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let zoneX = Int(Double(width) * zone.x)
        let zoneY = Int(Double(height) * zone.y)
        let zoneW = max(1, Int(Double(width) * zone.width))
        let zoneH = max(1, Int(Double(height) * zone.height))
        let n = Thumb.size
        var out = [UInt8](repeating: 0, count: n * n)

        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
            let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let p = base.assumingMemoryBound(to: UInt8.self)
            for j in 0..<n {
                let y = min(height - 1, zoneY + j * zoneH / n)
                for i in 0..<n {
                    let x = min(width - 1, zoneX + i * zoneW / n)
                    out[j * n + i] = p[y * stride + x]
                }
            }
        case kCVPixelFormatType_32BGRA:
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let p = base.assumingMemoryBound(to: UInt8.self)
            for j in 0..<n {
                let y = min(height - 1, zoneY + j * zoneH / n)
                for i in 0..<n {
                    let x = min(width - 1, zoneX + i * zoneW / n)
                    let o = y * stride + x * 4
                    let b = Int(p[o]), g = Int(p[o + 1]), r = Int(p[o + 2])
                    out[j * n + i] = UInt8((r * 77 + g * 150 + b * 29) >> 8)
                }
            }
        default:
            return nil
        }
        return Thumb(luma: out)
    }

    static func fourCC(_ type: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((type >> 24) & 0xFF), UInt8((type >> 16) & 0xFF),
            UInt8((type >> 8) & 0xFF), UInt8(type & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? String(type)
    }
}
