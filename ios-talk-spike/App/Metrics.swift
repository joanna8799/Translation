import Foundation

/// 一行一個 JSON 的量測紀錄，寫在 app 的 Documents 目錄，可用檔案 app 取出。
struct MetricEvent: Codable {
    var t: TimeInterval
    var event: String
    var v: [String: Double]?
    var s: [String: String]?
}

final class Metrics {
    static let shared = Metrics()

    static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("talkspike_metrics.jsonl")
    }

    private let queue = DispatchQueue(label: "talkspike.metrics")
    private var handle: FileHandle?

    private init() {}

    func log(_ event: String, _ values: [String: Double] = [:], _ strings: [String: String] = [:]) {
        let entry = MetricEvent(
            t: Date().timeIntervalSince1970,
            event: event,
            v: values.isEmpty ? nil : values,
            s: strings.isEmpty ? nil : strings
        )
        queue.async { [self] in
            guard var data = try? JSONEncoder().encode(entry) else { return }
            data.append(0x0A)
            if handle == nil {
                let url = Self.fileURL
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                handle = try? FileHandle(forWritingTo: url)
                _ = try? handle?.seekToEnd()
            }
            try? handle?.write(contentsOf: data)
        }
    }

    static func readAll() -> [MetricEvent] {
        let decoder = JSONDecoder()
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        var events: [MetricEvent] = []
        for line in text.split(separator: "\n") {
            if let data = line.data(using: .utf8), let event = try? decoder.decode(MetricEvent.self, from: data) {
                events.append(event)
            }
        }
        return events.sorted { $0.t < $1.t }
    }

    static func reset() {
        try? FileManager.default.removeItem(at: fileURL)
        shared.queue.async { shared.handle = nil }
    }
}
