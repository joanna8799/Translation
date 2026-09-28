import Foundation
import SwiftUI
import Translation

/// Apple Translation framework 只能透過 SwiftUI 的 translationTask 取得 session，
/// 這裡用一個看不見的 View 把 session 的閉包養著，其他地方透過 bridge 丟工作進去。
/// 驗證重點：app 在背景（PiP 中）時，這條路還能不能翻。
final class TranslationBridge: ObservableObject {
    static let shared = TranslationBridge()

    enum BridgeError: Error {
        case noSession
        case timeout
    }

    final class Job {
        let id: UUID
        let text: String
        let continuation: CheckedContinuation<String, Error>
        init(id: UUID, text: String, continuation: CheckedContinuation<String, Error>) {
            self.id = id
            self.text = text
            self.continuation = continuation
        }
    }

    @Published var status = "尚未建立 session"
    @Published var availability = "未查詢"
    @Published var sourceLanguage = "ja"
    @Published var targetLanguage = "zh-Hant"

    private let lock = NSLock()
    private var inflight: [UUID: Job] = [:]
    private var continuation: AsyncStream<Job>.Continuation?

    /// translationTask 每次重建 session 都會拿一條新的 stream。舊的結束。
    func makeStream() -> AsyncStream<Job> {
        continuation?.finish()
        return AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    /// 由 session 的消費端呼叫：取走工作，回傳 nil 表示已被取消。
    func claim(_ job: Job) -> Job? {
        lock.withLock { inflight.removeValue(forKey: job.id) }
    }

    func translate(_ text: String, timeout: TimeInterval = 15) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.enqueue(text) }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw BridgeError.timeout
            }
            guard let result = try await group.next() else { throw BridgeError.noSession }
            group.cancelAll()
            return result
        }
    }

    /// inflight 只有一把鑰匙（id）。claim 與 onCancel 誰先拿到誰負責 resume，另一方拿到 nil 就什麼都不做，
    /// 這樣 continuation 不會被 resume 兩次。
    private func enqueue(_ text: String) async throws -> String {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                guard let stream = self.continuation else {
                    continuation.resume(throwing: BridgeError.noSession)
                    return
                }
                let job = Job(id: id, text: text, continuation: continuation)
                self.lock.withLock { self.inflight[id] = job }
                stream.yield(job)
            }
        } onCancel: {
            let job = self.lock.withLock { self.inflight.removeValue(forKey: id) }
            job?.continuation.resume(throwing: CancellationError())
        }
    }
}

/// 放在畫面上的隱形 View，負責養 TranslationSession。
struct TranslationHost: View {
    @ObservedObject private var bridge = TranslationBridge.shared
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(configuration) { session in
                await run(session)
            }
            .onAppear { reconfigure() }
            .onChange(of: bridge.sourceLanguage) { _, _ in reconfigure() }
            .onChange(of: bridge.targetLanguage) { _, _ in reconfigure() }
            .task { await checkAvailability() }
    }

    private func reconfigure() {
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: bridge.sourceLanguage),
            target: Locale.Language(identifier: bridge.targetLanguage)
        )
    }

    private func checkAvailability() async {
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: bridge.sourceLanguage),
            to: Locale.Language(identifier: bridge.targetLanguage)
        )
        let text: String
        switch status {
        case .installed: text = "語言包已安裝"
        case .supported: text = "支援但未下載，按「準備翻譯」會跳下載"
        case .unsupported: text = "不支援這組語言"
        @unknown default: text = "未知狀態"
        }
        await MainActor.run { bridge.availability = text }
        Metrics.app.log("translate.availability", [:], ["status": text])
    }

    private func run(_ session: TranslationSession) async {
        await MainActor.run { bridge.status = "session 建立，準備語言包…" }
        do {
            try await session.prepareTranslation()
            await MainActor.run { bridge.status = "語言包就緒" }
            Metrics.app.log("translate.prepared")
        } catch {
            await MainActor.run { bridge.status = "prepare 失敗：\(error)" }
            Metrics.app.log("translate.prepare.error", [:], ["error": String(describing: error)])
        }

        let stream = bridge.makeStream()
        for await queued in stream {
            guard let job = bridge.claim(queued) else { continue }
            let t0 = Date().timeIntervalSince1970
            do {
                let response = try await session.translate(job.text)
                let ms = (Date().timeIntervalSince1970 - t0) * 1000
                Metrics.app.log("translate.ok", ["ms": ms, "chars": Double(job.text.count)])
                job.continuation.resume(returning: response.targetText)
            } catch {
                Metrics.app.log("translate.error", [:], ["error": String(describing: error)])
                job.continuation.resume(throwing: error)
            }
        }
        await MainActor.run { bridge.status = "session 結束" }
        Metrics.app.log("translate.session.ended")
    }
}
