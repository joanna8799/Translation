import Foundation

/// 匯率來源是 open.er-api.com 的免費端點（每天更新一次、不用金鑰、含 TWD）。
/// 出發前連一次網抓下來存起來，旅途中離線用快取。
final class CurrencyConverter: ObservableObject {
    @Published var status = "尚未抓匯率"
    private(set) var ratesPerUSD: [String: Double] = [:]
    private(set) var fetchedAt: Date?

    private let cacheKey = "talkspike.rates"
    private let cacheDateKey = "talkspike.rates.date"

    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let rates = try? JSONDecoder().decode([String: Double].self, from: data) {
            ratesPerUSD = rates
            fetchedAt = UserDefaults.standard.object(forKey: cacheDateKey) as? Date
            status = "快取匯率 \(fetchedAt.map { Self.dateFormatter.string(from: $0) } ?? "")"
        }
    }

    func refresh() async {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Payload: Decodable { let rates: [String: Double] }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            ratesPerUSD = payload.rates
            fetchedAt = Date()
            UserDefaults.standard.set(try JSONEncoder().encode(payload.rates), forKey: cacheKey)
            UserDefaults.standard.set(fetchedAt, forKey: cacheDateKey)
            await MainActor.run { status = "匯率已更新 \(Self.dateFormatter.string(from: Date()))，TWD/USD \(String(format: "%.2f", payload.rates["TWD"] ?? 0))" }
            Metrics.shared.log("fx.refresh.ok", ["count": Double(payload.rates.count)])
        } catch {
            await MainActor.run { status = "抓匯率失敗，用快取：\(error.localizedDescription)" }
            Metrics.shared.log("fx.refresh.error", [:], ["error": String(describing: error)])
        }
    }

    func toTWD(amount: Double, from code: String) -> Double? {
        guard let twd = ratesPerUSD["TWD"], let from = ratesPerUSD[code], from > 0 else { return nil }
        return amount / from * twd
    }

    /// 在一句話裡找金額，回傳「≈ NT$…」註記。沒寫幣別的數字用對方語言的預設幣別，並加問號。
    func annotate(_ text: String, defaultCurrency: String) -> String {
        var notes: [String] = []
        for hit in Self.findAmounts(in: text, defaultCurrency: defaultCurrency) {
            guard let twd = toTWD(amount: hit.amount, from: hit.code) else { continue }
            let amt = Self.numberFormatter.string(from: NSNumber(value: hit.amount)) ?? "\(hit.amount)"
            let twdText = Self.numberFormatter.string(from: NSNumber(value: twd.rounded())) ?? "\(twd)"
            notes.append("\(amt) \(hit.code)\(hit.assumed ? "?" : "") ≈ NT$\(twdText)")
        }
        return notes.joined(separator: "、")
    }

    struct AmountHit { var amount: Double; var code: String; var assumed: Bool }

    static let tokenToCode: [(String, String)] = [
        ("円", "JPY"), ("圓", "JPY"), ("yen", "JPY"), ("¥", "JPY"), ("￥", "JPY"),
        ("원", "KRW"), ("won", "KRW"), ("₩", "KRW"),
        ("บาท", "THB"), ("baht", "THB"), ("฿", "THB"), ("泰銖", "THB"),
        ("€", "EUR"), ("euro", "EUR"), ("euros", "EUR"), ("ユーロ", "EUR"), ("歐元", "EUR"),
        ("$", "USD"), ("dollar", "USD"), ("dollars", "USD"), ("ドル", "USD"), ("美元", "USD"), ("美金", "USD"),
        ("£", "GBP"), ("pound", "GBP"), ("pounds", "GBP"),
        ("đồng", "VND"), ("dong", "VND"), ("₫", "VND"),
        ("rupiah", "IDR"), ("rp", "IDR"),
        ("元", "CNY"), ("人民币", "CNY"), ("人民幣", "CNY"),
    ]

    static func findAmounts(in text: String, defaultCurrency: String) -> [AmountHit] {
        var hits: [AmountHit] = []
        let numberPattern = #"(\d{1,3}(?:[,，]\d{3})+|\d+)(?:[.．]\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: numberPattern) else { return hits }
        let ns = text as NSString
        let lower = text.lowercased()
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let numberText = ns.substring(with: match.range).replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "").replacingOccurrences(of: "．", with: ".")
            guard let amount = Double(numberText), amount >= 1 else { continue }
            // 看數字前後各 6 個字元有沒有幣別記號。
            let before = max(0, match.range.location - 6)
            let after = min(ns.length, match.range.location + match.range.length + 6)
            let context = (lower as NSString).substring(with: NSRange(location: before, length: after - before))
            var code: String?
            for (token, c) in tokenToCode where context.contains(token.lowercased()) {
                code = c
                break
            }
            if let code {
                hits.append(AmountHit(amount: amount, code: code, assumed: false))
            } else if amount >= 10 {
                hits.append(AmountHit(amount: amount, code: defaultCurrency, assumed: true))
            }
        }
        return hits
    }

    static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f
    }()
}
