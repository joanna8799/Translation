import Foundation
import CoreGraphics

/// 使用者框選的擷取區域，0...1 標準化，左上角為原點（UIKit 座標）。
struct Zone: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let `default` = Zone(x: 0.05, y: 0.12, width: 0.90, height: 0.55)

    /// Vision 的 regionOfInterest 用左下角為原點。
    var visionROI: CGRect {
        CGRect(x: x, y: 1 - y - height, width: width, height: height)
    }

    static func load() -> Zone {
        guard let data = AppGroup.defaults.data(forKey: AppGroup.Keys.zone),
              let zone = try? JSONDecoder().decode(Zone.self, from: data) else {
            return .default
        }
        return zone
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: AppGroup.Keys.zone)
        }
    }
}

struct TextLine: Codable {
    var text: String
    var confidence: Float
    /// Vision 標準化座標 [x, y, w, h]，左下角為原點，相對整個畫面。
    var box: [Double]
}

/// 擴充每次 OCR 的產出，也是 IPC 的訊息格式。
struct OCRFrame: Codable {
    var seq: Int
    var capturedAt: TimeInterval
    var ocrDoneAt: TimeInterval
    var ocrMs: Double
    var footprintMB: Double
    var orientation: UInt32
    var pixelFormat: String
    var frameWidth: Int
    var frameHeight: Int
    var meanLuma: Double
    /// 區域幾乎全黑且沒有文字：目標 app 可能偵測到錄影而把內容遮掉。
    var blackout: Bool
    var lines: [TextLine]

    var joinedText: String { lines.map(\.text).joined(separator: "\n") }
}
