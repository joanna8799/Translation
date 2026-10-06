import Foundation

/// 同一段音訊同時給中文辨識器和外語辨識器，決定是誰在講。
///
/// 主要訊號是辨識信心值。中文模型聽到日文會吐出一串漢字但信心很低，反過來也一樣。
/// 信心值拿不到時退回文字啟發式（字數、文字系統），這在中日之間不可靠，所以驗證項目 2 要實際量準確率。
struct LanguageDecision {
    var side: Turn.Side
    var chosen: TranscriptCandidate
    var scoreChinese: Double
    var scoreForeign: Double
    var method: String

    var note: String {
        String(format: "%@ 中%.2f 外%.2f", method, scoreChinese, scoreForeign)
    }
}

enum LanguageDecider {
    static func decide(chinese: TranscriptCandidate, foreign: TranscriptCandidate, foreignProfile: LanguageProfile, segmentMs: Double) -> LanguageDecision? {
        let zhEmpty = chinese.text.isEmpty
        let fxEmpty = foreign.text.isEmpty
        if zhEmpty && fxEmpty { return nil }
        if zhEmpty { return LanguageDecision(side: .them, chosen: foreign, scoreChinese: 0, scoreForeign: 1, method: "only") }
        if fxEmpty { return LanguageDecision(side: .me, chosen: chinese, scoreChinese: 1, scoreForeign: 0, method: "only") }

        if let cz = chinese.meanConfidence, let cf = foreign.meanConfidence {
            // 信心值為主，字數密度為輔：錯語言的模型通常只吐得出短短幾個字。
            let dz = density(chinese.text, ms: segmentMs, script: .han)
            let df = density(foreign.text, ms: segmentMs, script: foreignProfile.script)
            let sz = 0.75 * cz + 0.25 * dz
            let sf = 0.75 * cf + 0.25 * df
            return sz >= sf
                ? LanguageDecision(side: .me, chosen: chinese, scoreChinese: sz, scoreForeign: sf, method: "conf")
                : LanguageDecision(side: .them, chosen: foreign, scoreChinese: sz, scoreForeign: sf, method: "conf")
        }

        // 沒有信心值：文字系統符合度加字數密度。
        let sz = 0.5 * scriptMatch(chinese.text, .han) + 0.5 * density(chinese.text, ms: segmentMs, script: .han)
        let sf = 0.5 * scriptMatch(foreign.text, foreignProfile.script) + 0.5 * density(foreign.text, ms: segmentMs, script: foreignProfile.script)
        return sz >= sf
            ? LanguageDecision(side: .me, chosen: chinese, scoreChinese: sz, scoreForeign: sf, method: "heur")
            : LanguageDecision(side: .them, chosen: foreign, scoreChinese: sz, scoreForeign: sf, method: "heur")
    }

    /// 每秒字數相對該文字系統正常語速的比例，上限 1。
    static func density(_ text: String, ms: Double, script: LanguageProfile.Script) -> Double {
        guard ms > 0 else { return 0 }
        let perSecond = Double(text.count) / (ms / 1000)
        let normal: Double
        switch script {
        case .han, .japanese: normal = 4.0     // 中日每秒約 3 到 5 字
        case .hangul, .thai: normal = 4.0
        case .latin: normal = 12.0             // 拉丁字母含空白每秒約 10 到 15 字元
        }
        return min(perSecond / normal, 1)
    }

    /// 文字裡屬於預期文字系統的字元比例。
    static func scriptMatch(_ text: String, _ script: LanguageProfile.Script) -> Double {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return 0 }
        let matched = letters.filter { belongs($0, script) }.count
        return Double(matched) / Double(letters.count)
    }

    private static func belongs(_ s: Unicode.Scalar, _ script: LanguageProfile.Script) -> Bool {
        let v = s.value
        let han = (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
        let kana = (0x3040...0x30FF).contains(v)
        let hangul = (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v)
        let thai = (0x0E00...0x0E7F).contains(v)
        let latin = v < 0x0250 || (0x1E00...0x1EFF).contains(v)
        switch script {
        case .han: return han
        case .japanese: return han || kana
        case .hangul: return hangul
        case .thai: return thai
        case .latin: return latin
        }
    }
}
