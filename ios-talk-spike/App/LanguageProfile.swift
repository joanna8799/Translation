import Foundation

/// 對方語言的設定。一趟旅行通常只有一種外語，所以這裡是「中文加一種外語」的模型。
/// 要支援多語自動偵測，見 README 的 WhisperKit 備案。
struct LanguageProfile: Identifiable, Hashable {
    enum Script { case han, japanese, hangul, thai, latin }

    let id: String
    let displayName: String
    /// Speech framework（SpeechTranscriber）的 locale。
    let speechLocale: String
    /// Translation framework 的語言識別碼。
    let translationLanguage: String
    /// AVSpeechSynthesizer 的語言。
    let ttsLanguage: String
    /// 對方講到價格但沒說幣別時，預設用這個幣別換算。
    let defaultCurrency: String
    let script: Script

    static let chinese = LanguageProfile(
        id: "zh", displayName: "中文（台灣）", speechLocale: "zh-TW",
        translationLanguage: "zh-Hant", ttsLanguage: "zh-TW", defaultCurrency: "TWD", script: .han)

    static let foreignChoices: [LanguageProfile] = [
        LanguageProfile(id: "ja", displayName: "日文", speechLocale: "ja-JP", translationLanguage: "ja", ttsLanguage: "ja-JP", defaultCurrency: "JPY", script: .japanese),
        LanguageProfile(id: "ko", displayName: "韓文", speechLocale: "ko-KR", translationLanguage: "ko", ttsLanguage: "ko-KR", defaultCurrency: "KRW", script: .hangul),
        LanguageProfile(id: "en", displayName: "英文", speechLocale: "en-US", translationLanguage: "en", ttsLanguage: "en-US", defaultCurrency: "USD", script: .latin),
        LanguageProfile(id: "th", displayName: "泰文", speechLocale: "th-TH", translationLanguage: "th", ttsLanguage: "th-TH", defaultCurrency: "THB", script: .thai),
        LanguageProfile(id: "fr", displayName: "法文", speechLocale: "fr-FR", translationLanguage: "fr", ttsLanguage: "fr-FR", defaultCurrency: "EUR", script: .latin),
        LanguageProfile(id: "de", displayName: "德文", speechLocale: "de-DE", translationLanguage: "de", ttsLanguage: "de-DE", defaultCurrency: "EUR", script: .latin),
        LanguageProfile(id: "es", displayName: "西班牙文", speechLocale: "es-ES", translationLanguage: "es", ttsLanguage: "es-ES", defaultCurrency: "EUR", script: .latin),
        LanguageProfile(id: "it", displayName: "義大利文", speechLocale: "it-IT", translationLanguage: "it", ttsLanguage: "it-IT", defaultCurrency: "EUR", script: .latin),
        LanguageProfile(id: "vi", displayName: "越南文", speechLocale: "vi-VN", translationLanguage: "vi", ttsLanguage: "vi-VN", defaultCurrency: "VND", script: .latin),
        LanguageProfile(id: "id", displayName: "印尼文", speechLocale: "id-ID", translationLanguage: "id", ttsLanguage: "id-ID", defaultCurrency: "IDR", script: .latin),
    ]

    var locale: Locale { Locale(identifier: speechLocale) }
}

/// 一回合對話。
struct Turn: Identifiable {
    enum Side: String { case me, them }
    let id = UUID()
    var side: Side
    var original: String
    var translated: String
    var currencyNote: String
    var asrMs: Double
    var translateMs: Double
    var e2eMs: Double
    var decisionNote: String
    /// 測試者事後標記語種判斷對不對，nil 表示還沒標。
    var judgedCorrect: Bool?
}
