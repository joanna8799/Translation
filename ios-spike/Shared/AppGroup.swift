import Foundation

/// 主 app 與廣播擴充共用的設定。
///
/// App Group 的實際 ID 在執行期決定：
/// - Xcode 用付費或免費帳號直接裝：就是 project.yml 裡的 `group.com.example.livespike`。
/// - 用 AltStore 以免費 Apple ID 側載：AltServer 會把 App Group 改名（後面加 Team ID），
///   並把改過的清單寫進每個 bundle（主 app 與擴充各自）的 Info.plist 的 `ALTAppGroups`。
///   所以先讀 `ALTAppGroups`，沒有才用預設值。
enum AppGroup {
    static let defaultID = "group.com.example.livespike"

    static let id: String = {
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String],
           let first = groups.first, !first.isEmpty {
            return first
        }
        return defaultID
    }()

    /// 廣播擴充的 bundle ID 也在執行期從 PlugIns 目錄找，側載工具改 bundle ID 也不會壞。
    static let broadcastExtensionBundleID: String = {
        if let dir = Bundle.main.builtInPlugInsURL,
           let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in items where url.pathExtension == "appex" {
                if let b = Bundle(url: url), let bid = b.bundleIdentifier { return bid }
            }
        }
        return "com.example.livespike.Broadcast"
    }()

    /// 擴充每次 OCR 完成後覆寫的檔案，主 app 收到 Darwin 通知後讀取。
    static let latestOCRFile = "latest_ocr.json"
    static let ocrNotification = "com.example.livespike.ocr.updated"

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else {
            fatalError("App Group \(id) 不存在：Xcode 安裝請檢查 project.yml 的 application-groups 與帳號的 App Group；AltStore 安裝請確認 .ipa 是 CI 用 ad-hoc 簽過 entitlements 的版本")
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
