# TalkSpike：用一般耳機做旅行即時口譯的技術驗證

這是 [docs/07-travel-conversation.md](../docs/07-travel-conversation.md) 第 5 節說的驗證專案。
它回答一個問題：**沒有 AirPods，用一般藍牙或有線耳機，自己寫的 app 能不能做到「對方講外語、我在耳機裡聽中文；我講中文、手機把外語顯示並唸給對方」？**

答案在技術上是能。所有運算（語音辨識、翻譯、合成語音）都在 iPhone 上跑，耳機只負責播聲音。
Apple 把即時翻譯鎖在自家耳機是產品決定，不是技術限制。真正要驗證的是下面五件事，每件事都會在 app 畫面上直接打勾或打叉，並把數字寫進可匯出的紀錄檔。

| # | 驗證什麼 | 通過標準 |
|---|---|---|
| 1 | 音訊路徑：手機內建麥克風收對方、耳機 A2DP 播放，沒有掉到藍牙 HFP 電話音質 | 所有路徑紀錄的輸入都是 MicrophoneBuiltIn、輸出有 BluetoothA2DP 或 Headphones、HFP 出現 0 次 |
| 2 | 雙辨識器判斷「現在是誰在講」準不準 | 中文 20 句加外語 20 句以上，標記後準確率 90% 以上 |
| 3 | 端到端延遲：對方講完到耳機裡出中文 | 20 回合以上，中位數低於 1.5 秒 |
| 4 | 「播給對方」時切到擴音、播完切回耳機 | 10 次以上全部成功，切換中位數低於 300 ms |
| 5 | 連續運作與耗電（手機在口袋、螢幕鎖住） | 連續 30 分鐘不中斷，每 30 分鐘掉電低於 20% |

## 這份程式碼的狀態

**已用 Xcode 26.4.1 編譯通過（GitHub Actions macos-26 runner，iOS 模擬器 SDK，arm64 與 x86_64，零錯誤），尚未在實機上跑過。**

這些檔案是在沒有 Xcode 的 Linux 環境裡寫的，本機沒辦法編譯 iOS 專案。補救的方式有兩個：

1. **API 簽章逐一對照 Apple 官方文件的資料檔**（developer.apple.com 的文件 JSON），已確認：`SpeechTranscriber.init(locale:transcriptionOptions:reportingOptions:attributeOptions:)`、`ResultAttributeOption.transcriptionConfidence`、`AttributeScopes.SpeechAttributes.transcriptionConfidence`（值為 0 到 1）、`SpeechAnalyzer.analyzeSequence(_:) -> CMTime?`、`finalizeAndFinish(through: CMTime)`、`prepareToAnalyze(in: AVAudioFormat?)`、`AssetInventory.assetInstallationRequest(supporting:)`、`SpeechTranscriber.supportedLocale(equivalentTo:)`、`AVAudioSession.CategoryOptions.allowBluetoothA2DP` 與 `allowBluetoothHFP`。
2. **GitHub Actions 在 macOS runner 上編譯**：`.github/workflows/ios-build.yml` 每次推送都會用 Xcode 26 對模擬器 SDK 編譯這個專案（不簽章），編譯紀錄在 Actions 的 artifact 裡。編譯過了不代表能跑，五個驗證項目仍然要實機。

iOS 26 還多了兩個可以之後用上的 API：`TranslationSession(installedSource:target:)` 可以不經 SwiftUI 直接建翻譯 session（語言包已安裝時），iOS 26.4 的 `TranslationSession.Strategy.lowLatency` 是專門給即時對話的低延遲模型。目前先沿用 `TranslationBridge` 的做法，驗證過延遲再換。

## 架構

```
AVAudioEngine 內建麥克風 tap
  → AudioCapture：轉成辨識器格式
  → TurnSegmenter：能量式語音活動偵測，切出一回合（開口到停頓 700 ms）
  → TalkModel.handle(segment)
       ├ Transcriber ×2 同時跑：中文（zh-TW）、外語（例如 ja-JP），SpeechAnalyzer 端側
       ├ LanguageDecider：比信心值，決定是「我」還是「對方」在講
       ├ TranslationBridge：Translation framework 端側翻譯（兩個方向各一個 session）
       ├ CurrencyConverter：對方那句裡的金額加「≈ NT$」
       └ Speaker：AVSpeechSynthesizer
            對方的話 → 中文 → 耳機（耳機模式）或擴音（擴音模式）
            我的話   → 外語 → 螢幕文字；按「播給對方」或開自動播放時切擴音唸出
AudioSessionManager：playAndRecord + allowBluetoothA2DP，不加 allowBluetooth（HFP），
                     輸入固定內建麥克風（可選背面心形指向），擴音切換用 overrideOutputAudioPort
Metrics：一行一個 JSON 寫到 Documents/talkspike_metrics.jsonl
```

為什麼這樣設計：

- **耳機麥克風不能用來收對方**。它在你嘴邊，而且藍牙耳機一開麥克風（HFP）整條音訊會掉到 8 到 16 kHz 的電話音質，辨識率跟播放音質一起變差。所以只用內建麥克風，耳機純播放。這就是 AirPods 即時翻譯的做法，差別只在它多了主動降噪把對方原聲壓低。
- **一回合一回合處理，不做串流**。要同時用兩個語言的辨識器比對，一段一段最單純，也最好量延遲。每段重建 analyzer 的成本會記在 `setupMs`，太高再改。
- **TTS 播放時暫停偵測**。不然擴音播出來的聲音會被當成對方又講了一句，無限循環。

## 設定步驟

1. 安裝 XcodeGen：`brew install xcodegen`
2. 改 `project.yml` 的 `DEVELOPMENT_TEAM`，把 `com.example.talkspike` 換成你的 bundle ID。
3. `cd ios-talk-spike && xcodegen generate && open TalkSpike.xcodeproj`
4. 接實機，iOS 26.1 以上（SpeechAnalyzer 需要 iOS 26；繁體中文的 Apple Intelligence 是 26.1）。模擬器沒有麥克風路徑可測。
5. 第一次 Run 之後：選對方語言、按「準備」。會下載兩個語音模型（每個幾百 MB）和兩個方向的翻譯語言包，並抓一次匯率。全部顯示就緒後才能「開始聆聽」。

## 操作流程

每次驗證前先按「清除量測紀錄」。

### 項目 1：音訊路徑

1. 接上你的藍牙耳機（或有線耳機）。
2. 按「開始聆聽」，看「音訊路徑」那一行。正確是 `in: MicrophoneBuiltIn/Back → out: BluetoothA2DP`（有線則是 Headphones）。
3. 如果看到 `BluetoothHFP`，項目 1 不過。原因通常是系統選了耳機麥克風；確認 `AudioSessionManager.configure` 沒有加 `.allowBluetooth`，並檢查 `selectBuiltInMic` 有沒有成功。iOS 26 的 SDK 把 `.allowBluetooth` 改名為 `.allowBluetoothHFP`，兩個都不要加。
4. 拔掉耳機再插回去，路徑應該自動恢復，沒耳機時輸出應該是 Speaker 不是 Receiver。

### 項目 2：語種判斷

1. 耳機模式，對方語言選日文（或你要去的國家）。
2. 用另一支手機或電腦播日文 YouTube（新聞、Vlog 都好），一句一句播，每句停一下讓它切段。
3. 自己用中文講 20 句旅行會講的話（這個多少錢、有沒有素食、廁所在哪）。
4. 對話區每一句右邊按 👍 或 👎 標記它判斷的「我／對方」對不對。要標滿 40 句以上項目 2 才算數。
5. 看每句下面的 `conf 中0.xx 外0.xx`。如果 method 顯示 `heur` 而不是 `conf`，代表信心值沒拿到，先回去修 Transcriber。

不過的話，備案是 WhisperKit 的語種偵測（見最後一節）。

### 項目 3：延遲

跟項目 2 同一次測。每回合下面的「端到端 N ms」就是對方講完到耳機出聲的時間。
按「重新整理摘要」看中位數。拆解：辨識 ms（含 setup）、翻譯 ms、剩下的是 TTS 起音。

- setup 超過 300 ms：改成長駐 analyzer，用 `finalize(through:)` 在每回合結束時收結果，不要每段重建。
- 辨識本身超過 800 ms：先只跑一個辨識器判語種，再跑另一個，或改用較小的 VAD 段。
- 翻譯超過 300 ms：確認語言包已安裝，不是每次都在等下載。

### 項目 4：擴音切換

1. 戴耳機，耳機模式，自己講一句中文，等螢幕出現外語。
2. 按「把我最近一句用擴音播給對方」。聲音應該從手機喇叭出來，播完後再講一句對方的話，應該回到耳機。
3. 重複 10 次。摘要會算成功率和切換時間。

失敗的樣子有兩種：按了還是從耳機出來（override 被忽略），或播完沒切回耳機。前者試把 category 加上 `.defaultToSpeaker` 再量；後者看 `route.override` 事件裡 `to: preferred` 之後的 route。

### 項目 5：連續運作

1. 開始聆聽後把手機放口袋、按電源鍵鎖螢幕，耳機繼續戴著。
2. 播 30 分鐘外語影片或 podcast，偶爾講中文。
3. 30 分鐘後解鎖，按停止，看摘要的「最長秒數」和「每 30 分鐘掉電」。
4. 如果鎖螢幕幾秒後就停了，看 `project.yml` 的 `UIBackgroundModes: audio` 有沒有進到 Info.plist，以及 AVAudioSession 是否仍是 active。

### 幣值換算

對方那句話有數字時，下面會出現橘色的「1,200 JPY ≈ NT$260」。數字旁邊有幣別記號（円、¥、€ 等）就用那個，沒有就用對方語言的預設幣別並加問號。
已知限制：日文的「千円」「万円」這種數字加單位的講法目前不會展開，要加一個日文數詞解析。

## 匯出結果

用 iPhone 的「檔案」app > 我的 iPhone > TalkSpike，把 `talkspike_metrics.jsonl` AirDrop 到 Mac，連同填好的 `RESULTS.md` 一起回傳。

## 如果項目 2 不過：WhisperKit 備案

Apple 的辨識器要事先指定語言，沒有「聽一段自動判斷語種」的 API。WhisperKit（Argmax，MIT 授權）在裝置上跑 Whisper，有語種偵測：

1. `project.yml` 加 SwiftPM 套件 `https://github.com/argmaxinc/WhisperKit`。
2. 初始化 `WhisperKit(model: "base")`（約 40 MB，第一次會下載），`small` 更準但慢。
3. 每回合先把音訊轉成 16 kHz 的 `[Float]`，呼叫 `detectLangauge(audioArray:)`（WhisperKit 的方法名就是這樣拼的），拿到語言碼和機率。
4. 在 `LanguageDecider` 加一個策略：語言碼是 `zh` 就當「我」，否則當「對方」，然後只跑對應的 Apple 辨識器做正式轉寫。

這條路多一個模型、多幾百毫秒，但能支援「對方語言不只一種」，是做成產品時的正解。
