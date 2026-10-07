import SwiftUI

// MARK: - 設定

struct SettingsSheet: View {
    @EnvironmentObject private var model: TalkModel
    @Environment(\.dismiss) private var dismiss

    private var busy: Bool { model.state != .idle }

    var body: some View {
        NavigationStack {
            Form {
                Section("語言") {
                    Picker("對方語言", selection: Binding(get: { model.foreign }, set: { model.setForeign($0) })) {
                        ForEach(LanguageProfile.foreignChoices) { p in Text(p.displayName).tag(p) }
                    }
                    .disabled(busy)
                    Text("換語言會自動下載該語言的語音模型與翻譯語言包。北歐語言要 iOS 27 的翻譯才支援，芬蘭文目前 Apple 沒有，按準備後看狀態。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("輸出") {
                    Picker("模式", selection: $model.outputMode) {
                        ForEach(TalkModel.OutputMode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    Text(model.outputMode == .earbuds
                         ? "對方的話翻成中文播進你的耳機；你的話翻成外語顯示在螢幕，按「播給對方」才用喇叭唸。"
                         : "兩個方向都從手機喇叭出聲，手機放兩人中間。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("我講完自動用喇叭唸給對方", isOn: $model.autoSpeakToThem)
                    Toggle("麥克風指向背面（對準對方）", isOn: $model.micFacingBack)
                        .disabled(busy)
                }

                Section("語言模型與匯率") {
                    Button(model.ready ? "重新準備" : "準備（下載語言模型、抓匯率）") {
                        Task { await model.prepare() }
                    }
                    .disabled(busy)
                    LabeledContent("語音模型") { Text(model.assetStatus).multilineTextAlignment(.trailing) }
                    LabeledContent("翻譯 外→中", value: model.toChinese.status)
                    LabeledContent("翻譯 中→外", value: model.toForeign.status)
                    LabeledContent("匯率") { Text(model.currency.status).multilineTextAlignment(.trailing) }
                }
                .font(.subheadline)

                Section("目前音訊路徑") {
                    Text(model.routeDescription).font(.caption)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}

// MARK: - 驗證

struct VerifyView: View {
    @EnvironmentObject private var model: TalkModel

    var body: some View {
        NavigationStack {
            List {
                checklistSection
                Section("紀錄") {
                    Button("重新整理摘要") { model.refreshSummary() }
                    Button("清除量測紀錄", role: .destructive) { model.resetMetrics() }
                    Text("紀錄檔在「檔案」app > 我的 iPhone > TalkSpike > talkspike_metrics.jsonl")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("驗證項目")
            .onAppear { model.refreshSummary() }
        }
    }

    private var checklistSection: some View {
        Section {
            let s = model.summary
            row("1 音訊路徑：內建麥克風收音、耳機 A2DP 播放、沒掉到 HFP",
                "\(s.routeSamples) 次路徑紀錄，內建麥克風 \(s.routeBuiltInMicOK)，外接輸出 \(s.routeExternalOut)，HFP \(s.routeHFP)",
                pass: s.routeSamples > 0 && s.routeHFP == 0 && s.routeBuiltInMicOK == s.routeSamples && s.routeExternalOut > 0)
            row("2 語種判斷準確率",
                "標記 \(s.judgedTotal) 句，判對 \(s.judgedCorrect)" + (s.judgedTotal > 0 ? String(format: "（%.0f%%）", Double(s.judgedCorrect) / Double(s.judgedTotal) * 100) : ""),
                pass: s.judgedTotal >= 40 && Double(s.judgedCorrect) / Double(max(s.judgedTotal, 1)) >= 0.9)
            row("3 端到端延遲（講完到出聲）",
                "中位數 \(Int(s.e2eMsMedian)) ms；辨識 \(Int(s.asrMsMedian)) ms（setup \(Int(s.asrSetupMsMedian))）、翻譯 \(Int(s.translateMsMedian)) ms，共 \(s.turns) 回合",
                pass: s.turns >= 20 && s.e2eMsMedian > 0 && s.e2eMsMedian < 1500)
            row("4 耳機與擴音切換",
                "\(s.overrideAttempts) 次，成功 \(s.overrideOK)，中位數 \(Int(s.overrideMsMedian)) ms",
                pass: s.overrideAttempts >= 10 && s.overrideOK == s.overrideAttempts && s.overrideMsMedian < 300)
            row("5 連續運作與耗電",
                String(format: "最長 %.0f 秒，每 30 分鐘掉電 %.1f%%", s.longestSessionSec, s.batteryDropPer30Min),
                pass: s.longestSessionSec >= 1800 && s.batteryDropPer30Min < 20)
        } header: {
            Text("五個驗證項目")
        } footer: {
            Text("在「對話」分頁每一句按 👍 或 👎 標記語種判斷，標滿 40 句項目 2 才算數。")
        }
    }

    private func row(_ title: String, _ detail: String, pass: Bool) -> some View {
        HStack(alignment: .top) {
            Image(systemName: pass ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(pass ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
