import Foundation
import SwiftUI
import Translation

/// Apple Translation framework 只能透過 SwiftUI 的 translationTask 取得 session，
/// 用一個看不見的 View 把 session 養著，其他地方透過 bridge 丟工作進去。
/// 這裡會有兩個 bridge：外語到中文、中文到外語。
final class TranslationBridge: ObservableObject {
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

    let name: String
    @Published var status = "尚未建立 session"
    @Published var sourceLanguage: String
    @Published var targetLanguage: String

    private let lock = NSLock()
    private var inflight: [UUID: Job] = [:]
    private var continuation: AsyncStream<Job>.Continuation?

    init(name: String, source: String, target: String) {
        self.name = name
        self.sourceLanguage = source
        self.targetLanguage = target
    }

    func makeStream() -> AsyncStream<Job> {
        continuation?.finish()
        return AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func claim(_ job: Job) -> Job? {
        lock.withLock { inflight.removeValue(forKey: job.id) }
    }

    func translate(_ text: String, timeout: TimeInterval = 10) async throws -> String {
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

struct TranslationHost: View {
    @ObservedObject var bridge: TranslationBridge
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
    }

    private func reconfigure() {
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: bridge.sourceLanguage),
            target: Locale.Language(identifier: bridge.targetLanguage)
        )
    }

    private func run(_ session: TranslationSession) async {
        await MainActor.run { bridge.status = "準備語言包…" }
        do {
            try await session.prepareTranslation()
            await MainActor.run { bridge.status = "就緒" }
            Metrics.shared.log("translate.prepared", [:], ["bridge": bridge.name])
        } catch {
            await MainActor.run { bridge.status = "prepare 失敗：\(error)" }
            Metrics.shared.log("translate.prepare.error", [:], ["bridge": bridge.name, "error": String(describing: error)])
        }

        let stream = bridge.makeStream()
        for await queued in stream {
            guard let job = bridge.claim(queued) else { continue }
            let t0 = Date().timeIntervalSince1970
            do {
                let response = try await session.translate(job.text)
                let ms = (Date().timeIntervalSince1970 - t0) * 1000
                Metrics.shared.log("translate.ok", ["ms": ms, "chars": Double(job.text.count)], ["bridge": bridge.name])
                job.continuation.resume(returning: response.targetText)
            } catch {
                Metrics.shared.log("translate.error", [:], ["bridge": bridge.name, "error": String(describing: error)])
                job.continuation.resume(throwing: error)
            }
        }
        await MainActor.run { bridge.status = "session 結束" }
    }
}
