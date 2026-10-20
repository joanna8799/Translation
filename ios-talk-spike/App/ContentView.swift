import SwiftUI

/// 兩個分頁：「對話」是旅行時真正用的畫面，「驗證」是技術驗證的數字。
struct ContentView: View {
    @EnvironmentObject private var model: TalkModel

    var body: some View {
        TabView {
            Tab("對話", systemImage: "bubble.left.and.bubble.right.fill") {
                ConversationView()
            }
            Tab("驗證", systemImage: "checklist") {
                VerifyView()
            }
        }
        .background(TranslationHost(bridge: model.toChinese))
        .background(TranslationHost(bridge: model.toForeign))
    }
}

// MARK: - 對話

struct ConversationView: View {
    @EnvironmentObject private var model: TalkModel
    @State private var showSettings = false
    @State private var showToThem = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusHeader
                Divider()
                transcript
                Divider()
                bottomBar
            }
            .navigationTitle("\(model.foreign.displayName) ↔ 中文")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { languageMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsSheet() }
            .fullScreenCover(isPresented: $showToThem) { ShowToThemView() }
            .task {
                // 開 app 就準備；語言模型已經裝過時幾秒就好，沒裝會跳下載。
                if !model.ready && model.state == .idle { await model.prepare() }
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            Picker("對方語言", selection: Binding(get: { model.foreign }, set: { model.setForeign($0) })) {
                ForEach(LanguageProfile.foreignChoices) { p in Text(p.displayName).tag(p) }
            }
        } label: {
            Label(model.foreign.displayName, systemImage: "globe")
        }
        .disabled(model.state == .listening || model.state == .processing || model.state == .speaking)
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)
            Text(stateText)
                .font(.subheadline.weight(.semibold))
            Spacer()
            if model.state != .idle && model.state != .preparing {
                ProgressView(value: levelFraction)
                    .frame(width: 60)
                    .tint(.green)
            }
            Label(model.routeShort, systemImage: routeIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var stateText: String {
        switch model.state {
        case .idle: return model.ready ? "就緒，按開始聆聽" : "準備中…"
        case .preparing: return model.assetStatus
        case .listening: return model.outputMode == .earbuds ? "聆聽中，對方的話會在耳機裡變中文" : "聆聽中，兩邊都從喇叭出聲"
        case .processing: return "辨識翻譯中…"
        case .speaking: return "播放中…"
        }
    }

    private var stateColor: Color {
        switch model.state {
        case .idle: return model.ready ? .gray : .orange
        case .preparing: return .orange
        case .listening: return .green
        case .processing: return .blue
        case .speaking: return .purple
        }
    }

    private var routeIcon: String {
        model.routeShort.contains("耳機") ? "headphones" : "speaker.wave.2"
    }

    private var levelFraction: Double {
        max(0, min(1, (model.levelDb + 60) / 50))
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if model.turns.isEmpty {
                        emptyHint
                    }
                    ForEach(model.turns) { turn in
                        BubbleView(turn: turn)
                            .id(turn.id)
                    }
                    if !model.lastError.isEmpty {
                        Text(model.lastError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: model.turns.count) { _, _ in
                if let last = model.turns.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("按下方「開始聆聽」")
                .font(.headline)
            Text("對方講\(model.foreign.displayName)，你在耳機裡聽到中文。\n你講中文，翻好的\(model.foreign.displayName)顯示在這裡，按「給對方看」或「播給對方」。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .padding(.horizontal, 32)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    showToThem = true
                } label: {
                    Label("給對方看", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.lastMine == nil)

                Button {
                    model.replayLastMineToThem()
                } label: {
                    Label("播給對方", systemImage: "speaker.wave.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.lastMine == nil || model.state == .idle)

                Button {
                    model.replayLastTheirsToMe()
                } label: {
                    Label("再聽一次", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.lastTheirs == nil || model.state == .idle)
            }
            .font(.footnote)

            if model.state == .idle {
                Button {
                    model.start()
                } label: {
                    Label("開始聆聽", systemImage: "mic.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.ready)
            } else if model.state != .preparing {
                Button(role: .destructive) {
                    model.stop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView(model.assetStatus)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }
}

// MARK: - 氣泡

struct BubbleView: View {
    @EnvironmentObject private var model: TalkModel
    let turn: Turn

    private var isMe: Bool { turn.side == .me }

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 4) {
                Text(turn.original)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(turn.translated.isEmpty ? "（翻譯失敗）" : turn.translated)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                if !turn.currencyNote.isEmpty {
                    Label(turn.currencyNote, systemImage: "dollarsign.circle")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    Text(isMe ? "我" : "對方")
                        .font(.caption2.weight(.bold))
                    Text("\(Int(turn.e2eMs > 0 ? turn.e2eMs : turn.asrMs + turn.translateMs)) ms · \(turn.decisionNote)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { model.judge(turn, correct: true) } label: {
                        Image(systemName: turn.judgedCorrect == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                    }
                    Button { model.judge(turn, correct: false) } label: {
                        Image(systemName: turn.judgedCorrect == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isMe ? Color.green.opacity(0.18) : Color.blue.opacity(0.14))
            )
            if !isMe { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - 給對方看：全螢幕大字，預設轉 180 度讓對面的人直接讀

struct ShowToThemView: View {
    @EnvironmentObject private var model: TalkModel
    @Environment(\.dismiss) private var dismiss
    @State private var flipped = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title)
                    }
                    Spacer()
                    Button { flipped.toggle() } label: {
                        Image(systemName: "arrow.up.and.down").font(.title2)
                    }
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding()

                Spacer()
                Text(model.lastMine?.translated ?? "")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                    .rotationEffect(.degrees(flipped ? 180 : 0))
                    .padding(.horizontal, 24)
                    .onTapGesture { flipped.toggle() }
                Spacer()

                Button {
                    model.replayLastMineToThem()
                } label: {
                    Label("用喇叭唸出來", systemImage: "speaker.wave.3.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.25))
                .foregroundStyle(.white)
                .disabled(model.state == .idle)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .statusBarHidden()
    }
}
