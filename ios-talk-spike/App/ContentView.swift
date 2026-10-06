import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: TalkModel

    var body: some View {
        NavigationStack {
            List {
                checklistSection
                setupSection
                controlsSection
                turnsSection
            }
            .navigationTitle("TalkSpike")
            .background(TranslationHost(bridge: model.toChinese))
            .background(TranslationHost(bridge: model.toForeign))
            .onAppear { model.refreshSummary() }
        }
    }

    // MARK: - 驗證項目

    private var checklistSection: some View {
        Section("驗證項目") {
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
            Button("重新整理摘要") { model.refreshSummary() }
            Button("清除量測紀錄", role: .destructive) { model.resetMetrics() }
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

    // MARK: - 設定

    private var setupSection: some View {
        Section("設定") {
            Picker("對方語言", selection: Binding(
                get: { model.foreign },
                set: { model.setForeign($0) }
            )) {
                ForEach(LanguageProfile.foreignChoices) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .disabled(model.state != .idle)
            Picker("輸出", selection: $model.outputMode) {
                ForEach(TalkModel.OutputMode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            Toggle("麥克風指向背面（對準對方）", isOn: $model.micFacingBack)
                .disabled(model.state != .idle)
            Toggle("我講完自動用擴音唸給對方", isOn: $model.autoSpeakToThem)
            Button(model.ready ? "重新準備語言模型與匯率" : "準備（下載語言模型、抓匯率）") {
                Task { await model.prepare() }
            }
            .disabled(model.state == .preparing || model.state == .listening)
            Text(model.assetStatus).font(.caption).foregroundStyle(.secondary)
            Text("翻譯 session：外→中 \(model.toChinese.status)；中→外 \(model.toForeign.status)").font(.caption).foregroundStyle(.secondary)
            Text(model.currency.status).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - 控制

    private var controlsSection: some View {
        Section("控制") {
            HStack {
                Text(model.state.rawValue).font(.headline)
                Spacer()
                if model.state == .idle {
                    Button("開始聆聽") { model.start() }.disabled(!model.ready)
                } else if model.state != .preparing {
                    Button("停止", role: .destructive) { model.stop() }
                }
            }
            LabeledContent("音訊路徑", value: model.routeDescription)
                .font(.caption)
            LabeledContent("輸入音量", value: String(format: "%.0f dB", model.levelDb))
                .font(.caption)
            Button("把我最近一句用擴音播給對方") { model.replayLastMineToThem() }
                .disabled(model.state == .idle)
            if !model.lastError.isEmpty {
                Text(model.lastError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - 對話

    private var turnsSection: some View {
        Section("對話（最新在上，請標記語種判斷對不對）") {
            if model.turns.isEmpty {
                Text("還沒有對話").foregroundStyle(.secondary)
            }
            ForEach(model.turns) { turn in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(turn.side == .them ? "對方" : "我")
                            .font(.caption).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(turn.side == .them ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                            .clipShape(Capsule())
                        Text(turn.decisionNote).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button { model.judge(turn, correct: true) } label: {
                            Image(systemName: turn.judgedCorrect == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                        }.buttonStyle(.borderless)
                        Button { model.judge(turn, correct: false) } label: {
                            Image(systemName: turn.judgedCorrect == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        }.buttonStyle(.borderless)
                    }
                    Text(turn.original)
                    Text(turn.translated.isEmpty ? "（翻譯失敗）" : turn.translated).bold()
                    if !turn.currencyNote.isEmpty {
                        Text(turn.currencyNote).font(.caption).foregroundStyle(.orange)
                    }
                    Text("辨識 \(Int(turn.asrMs)) ms，翻譯 \(Int(turn.translateMs)) ms，端到端 \(Int(turn.e2eMs)) ms")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
