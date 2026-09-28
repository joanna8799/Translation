import Foundation

/// 一行一個 JSON 的量測紀錄。主 app 與擴充各寫自己的檔案，避免兩個程序同時寫一個檔。
struct MetricEvent: Codable {
    var t: TimeInterval
    var src: String
    var event: String
    var v: [String: Double]?
    var s: [String: String]?
}

final class Metrics {
    static let ext = Metrics(source: "ext")
    static let app = Metrics(source: "app")

    static var fileURLs: [URL] {
        ["ext", "app"].map { AppGroup.containerURL.appendingPathComponent("metrics_\($0).jsonl") }
    }

    private let source: String
    private let queue = DispatchQueue(label: "livespike.metrics")
    private var handle: FileHandle?

    private init(source: String) {
        self.source = source
    }

    private var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent("metrics_\(source).jsonl")
    }

    func log(_ event: String, _ values: [String: Double] = [:], _ strings: [String: String] = [:]) {
        let entry = MetricEvent(
            t: Date().timeIntervalSince1970,
            src: source,
            event: event,
            v: values.isEmpty ? nil : values,
            s: strings.isEmpty ? nil : strings
        )
        queue.async { [self] in
            guard var data = try? JSONEncoder().encode(entry) else { return }
            data.append(0x0A)
            if handle == nil {
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    FileManager.default.createFile(atPath: fileURL.path, contents: nil)
                }
                handle = try? FileHandle(forWritingTo: fileURL)
                _ = try? handle?.seekToEnd()
            }
            try? handle?.write(contentsOf: data)
        }
    }

    /// 讀兩個檔案並依時間排序。
    static func readAll() -> [MetricEvent] {
        let decoder = JSONDecoder()
        var events: [MetricEvent] = []
        for url in fileURLs {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                if let data = line.data(using: .utf8), let event = try? decoder.decode(MetricEvent.self, from: data) {
                    events.append(event)
                }
            }
        }
        return events.sorted { $0.t < $1.t }
    }

    static func reset() {
        for url in fileURLs {
            try? FileManager.default.removeItem(at: url)
        }
        ext.queue.async { ext.handle = nil }
        app.queue.async { app.handle = nil }
    }
}
