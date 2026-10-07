import Foundation
import Network

/// 匯率來源是 open.er-api.com 的免費端點（每天更新一次、不用金鑰、含 TWD）。
/// 自動更新的時機：開 app、回到前景且快取超過 maxAge、網路從斷線恢復。離線時用快取。
final class CurrencyConverter: ObservableObject {
    @Published var status = "尚未抓匯率"
    @Published private(set) var fetchedAt: Date?
    private(set) var ratesPerUSD: [String: Double] = [:]

    /// 超過這個時間就視為過期，回前景或網路恢復時重抓。免費來源一天更新一次，6 小時夠了。
    var maxAge: TimeInterval = 6 * 3600

    private let cacheKey = "talkspike.rates"
    private let cacheDateKey = "talkspike.rates.date"
    private let monitor = NWPathMonitor()
    private var wasOnline = true
    private var refreshing = false

    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let rates = try? JSONDecoder().decode([String: Double].self, from: data) {
            ratesPerUSD = rates
            fetchedAt = UserDefaults.standard.object(forKey: cacheDateKey) as? Date
            status = summaryText(prefix: "快取匯率")
        }
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let online = path.status == .satisfied
            let cameBack = online && !self.wasOnline
            self.wasOnline = online
            if cameBack { Task { await self.refreshIfStale() } }
        }
        monitor.start(queue: DispatchQueue(label: "talkspike.currency.network"))
    }

    var isStale: Bool {
        guard let fetchedAt else { return true }
        return Date().timeIntervalSince(fetchedAt) > maxAge
    }

    /// 過期才抓，給回前景與網路恢復用。
    func refreshIfStale() async {
        guard isStale else { return }
        await refresh()
    }

    /// 給使用者看的一行：匯率值、幾小時前更新、來源。
    func summaryText(prefix: String) -> String {
        let twd = ratesPerUSD["TWD"].map { String(format: "TWD/USD %.2f", $0) } ?? "無資料"
        let age: String
        if let fetchedAt {
            let hours = Int(Date().timeIntervalSince(fetchedAt) / 3600)
            age = hours < 1 ? "剛更新" : "\(hours) 小時前更新"
        } else {
            age = "未更新"
        }
        return "\(prefix) \(twd)，\(age)，每 6 小時自動重抓"
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Payload: Decodable { let rates: [String: Double] }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            ratesPerUSD = payload.rates
            fetchedAt = Date()
            UserDefaults.standard.set(try JSONEncoder().encode(payload.rates), forKey: cacheKey)
            UserDefaults.standard.set(fetchedAt, forKey: cacheDateKey)
            await MainActor.run { status = summaryText(prefix: "匯率") }
            Metrics.shared.log("fx.refresh.ok", ["count": Double(payload.rates.count)])
        } catch {
            await MainActor.run { status = summaryText(prefix: "離線，用快取匯率") }
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
