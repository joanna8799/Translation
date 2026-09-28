import Foundation

/// 主 app 與廣播擴充共用的設定。
/// 改 bundle prefix 時，這裡的兩個字串要跟 project.yml 一起改。
enum AppGroup {
    static let id = "group.com.example.livespike"
    static let broadcastExtensionBundleID = "com.example.livespike.Broadcast"

    /// 擴充每次 OCR 完成後覆寫的檔案，主 app 收到 Darwin 通知後讀取。
    static let latestOCRFile = "latest_ocr.json"
    static let ocrNotification = "com.example.livespike.ocr.updated"

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else {
            fatalError("App Group \(id) 不存在：檢查 project.yml 的 application-groups 與開發者帳號的 App Group 設定")
        }
        return url
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }

    enum Keys {
        static let zone = "zone"
        static let extMaxFootprintMB = "ext.maxFootprintMB"
        static let extFramesSeen = "ext.framesSeen"
        static let extOCRCount = "ext.ocrCount"
        static let extLastError = "ext.lastError"
        static let extVisionLanguages = "ext.visionLanguages"
    }
}
