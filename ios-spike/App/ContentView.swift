import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: SpikeModel
    @ObservedObject private var bridge = TranslationBridge.shared

    var body: some View {
        NavigationStack {
            List {
                checklistSection
                controlsSection
                zoneSection
                latestSection
                eventsSection
            }
            .navigationTitle("LiveSpike")
            .background(TranslationHost())
            .onAppear { model.refreshSummary() }
        }
    }

    // MARK: - 五個驗證項目

    private var checklistSection: some View {
        Section("驗證項目") {
            let s = model.summary
            row("1 擴充記憶體",
                "\(fmt(max(s.extMaxFootprintMB, model.extMaxFootprintMB))) MB，跳過 \(s.extMemorySkips) 次",
                pass: s.ocrCount > 0 && max(s.extMaxFootprintMB, model.extMaxFootprintMB) < 45 && s.extMemorySkips == 0)
            row("2 背景存活（PiP 中）",
                "最長連續 \(Int(s.maxBackgroundSeconds)) 秒",
                pass: s.maxBackgroundSeconds >= 600)
            row("3 背景翻譯",
                "成功 \(s.backgroundTranslateOK)，失敗 \(s.backgroundTranslateFail)",
                pass: s.backgroundTranslateOK > 0 && s.backgroundTranslateFail == 0)
            row("4 黑畫面",
                s.blackouts == 0 ? "沒有偵測到" : "偵測到 \(s.blackouts) 次",
                pass: s.ocrCount > 0 && s.blackouts == 0)
            row("5 延遲中位數",
                "OCR \(Int(s.ocrMsMedian)) ms，IPC \(Int(s.ipcMsMedian)) ms，翻譯 \(Int(s.translateMsMedian)) ms，端到端 \(Int(s.e2eMsMedian)) ms",
                pass: s.e2eMsMedian > 0 && s.e2eMsMedian < 1500)
            LabeledContent("Vision 支援語言", value: s.visionLanguages.isEmpty ? "廣播開始後顯示" : s.visionLanguages)
            LabeledContent("PiP 影格尺寸", value: s.pipRenderSize.isEmpty ? "尚未回報" : s.pipRenderSize)
            Button("重新整理摘要") { model.refreshSummary() }
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

    // MARK: - 控制

    private var controlsSection: some View {
        Section("控制") {
            HStack {
                Text("1. 開始螢幕廣播")
                Spacer()
                BroadcastPicker().frame(width: 60, height: 44)
            }
            HStack {
                Text("2. PiP")
                Spacer()
                PiPHostView(layer: model.pip.displayLayer) { model.pip.attach() }
                    .frame(width: 120, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                Button(model.pip.isActive ? "停止 PiP" : "開始 PiP") {
                    if model.pip.isActive {
                        model.pip.stop()
                    } else {
                        model.pip.start()
                    }
                }
                .disabled(!model.pip.isSupported)
                Spacer()
                Text(model.pip.isSupported ? (model.pip.isPossible ? "可啟動" : "尚不可啟動") : "此裝置不支援 PiP")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.pip.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            LabeledContent("翻譯 session", value: bridge.status)
            LabeledContent("語言包", value: bridge.availability)
            HStack {
                Picker("來源", selection: $bridge.sourceLanguage) {
                    Text("日文").tag("ja")
                    Text("韓文").tag("ko")
                    Text("簡中").tag("zh-Hans")
                    Text("英文").tag("en")
                }
                Picker("目標", selection: $bridge.targetLanguage) {
                    Text("繁中").tag("zh-Hant")
                    Text("英文").tag("en")
                }
            }
            .pickerStyle(.menu)
            Button("測試翻譯（不用廣播）") { model.testTranslate() }
            LabeledContent("場景狀態", value: model.scenePhaseName)
            LabeledContent("主 app 記憶體", value: "\(fmt(model.appFootprintMB)) MB")
            LabeledContent("擴充看過的幀數", value: "\(model.extFramesSeen)，OCR \(model.extOCRCount) 次")
            if !model.extLastError.isEmpty {
                Text("擴充錯誤：\(model.extLastError)").font(.caption).foregroundStyle(.red)
            }
            ShareLink("匯出量測紀錄", items: Metrics.fileURLs)
            Button("清除量測紀錄", role: .destructive) { model.resetMetrics() }
        }
    }

    // MARK: - 擷取區域

    private var zoneSection: some View {
        Section("擷取區域（左上為原點，0 到 1）") {
            ZonePreview(zone: model.zone)
                .frame(height: 220)
            slider("x", $model.zone.x)
            slider("y", $model.zone.y)
            slider("寬", $model.zone.width)
            slider("高", $model.zone.height)
            Text("PiP 視窗要放在區域外，否則會把自己的字幕錄進去。廣播開始後改區域要重新開始廣播才生效。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label).frame(width: 24, alignment: .leading)
            Slider(value: value, in: 0...1, step: 0.01)
            Text(String(format: "%.2f", value.wrappedValue)).monospacedDigit().frame(width: 44)
        }
    }

    // MARK: - 最新結果

    private var latestSection: some View {
        Section("最新一次") {
            if let frame = model.lastFrame {
                Text("#\(frame.seq)  OCR \(Int(frame.ocrMs)) ms  擴充 \(fmt(frame.footprintMB)) MB  \(frame.pixelFormat) \(frame.frameWidth)×\(frame.frameHeight)  方向 \(frame.orientation)  亮度 \(String(format: "%.2f", frame.meanLuma))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(frame.joinedText.isEmpty ? "（沒有文字）" : frame.joinedText)
                    .font(.body)
            } else {
                Text("尚未收到擴充的 OCR 結果").foregroundStyle(.secondary)
            }
            if !model.lastTranslation.isEmpty {
                Text(model.lastTranslation).font(.body).foregroundStyle(.blue)
            }
        }
    }

    private var eventsSection: some View {
        Section("最近事件") {
            ForEach(Array(model.recent.enumerated()), id: \.offset) { _, e in
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(e.src)  \(e.event)").font(.caption.monospaced())
                    if let v = e.v, !v.isEmpty {
                        Text(v.map { "\($0.key)=\(fmt($0.value))" }.sorted().joined(separator: "  "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let s = e.s, !s.isEmpty {
                        Text(s.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "  "))
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private func fmt(_ x: Double) -> String {
        String(format: "%.1f", x)
    }
}

/// 用手機螢幕比例畫出目前框選的區域。
struct ZonePreview: View {
    let zone: Zone

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = h * 9 / 19.5
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.secondary, lineWidth: 1)
                    .frame(width: w, height: h)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.25))
                    .frame(width: w * zone.width, height: h * zone.height)
                    .offset(x: w * zone.x, y: h * zone.y)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
