# LiveSpike：iOS 即時模式技術驗證

這是 [docs/06-live-mode.md](../docs/06-live-mode.md) 第 5 節說的驗證專案。
它不是產品，只驗五件事，每件事都會在 app 畫面上直接打勾或打叉，並把數字寫進可匯出的紀錄檔。

| # | 驗證什麼 | 通過標準 |
|---|---|---|
| 1 | 廣播擴充在 50 MB 內能否穩定跑 Vision OCR | 最高記憶體低於 45 MB，沒有因記憶體跳過任何一幀 |
| 2 | PiP 能否讓主 app 在背景存活 | 連續背景存活 600 秒以上 |
| 3 | Apple Translation framework 在背景能不能翻 | 背景狀態下有成功翻譯、沒有失敗 |
| 4 | 目標 app 錄影時會不會黑掉 | 沒有偵測到全黑，且畫面上看得到 OCR 出來的原文 |
| 5 | 端到端延遲 | 從擷取到 PiP 顯示譯文的中位數低於 1.5 秒 |

## 這份程式碼的狀態

這些檔案是在沒有 Xcode 的環境裡寫的。**已用 Xcode 26.4.1 在 GitHub Actions（macos-26 runner）對 iOS 模擬器 SDK 編譯通過，主 app 與廣播擴充兩個 target 都零錯誤**，見 `.github/workflows/ios-build.yml`。尚未在實機上跑過，五個驗證項目仍要真機。

## 架構

```
LiveSpike（主 app）                     LiveSpikeBroadcast（廣播擴充，50 MB 上限）
  SpikeModel        ← Darwin 通知 ←       SampleHandler
    ├ 讀 latest_ocr.json（App Group）        ├ 每 330 ms 取一幀
    ├ 文字雜湊去重                            ├ 只讀區域內像素做 32x32 亮度縮圖
    ├ TranslationBridge → Translation        ├ 靜止且內容有變才跑 Vision OCR
    └ PiPController.render → FrameRenderer   ├ 寫 latest_ocr.json
         └ AVSampleBufferDisplayLayer → PiP  └ 送 Darwin 通知
  兩邊各寫自己的 metrics_*.jsonl
```

## 設定步驟

1. 安裝 XcodeGen：`brew install xcodegen`
2. 改 `project.yml` 的 `DEVELOPMENT_TEAM`，並把 `com.example.livespike` 換成你自己的 bundle prefix（連同 `group.` 開頭的那個）。
3. 把 `Shared/AppGroup.swift` 裡的 `id` 與 `broadcastExtensionBundleID` 改成一樣的值。
4. `cd ios-spike && xcodegen generate && open LiveSpike.xcodeproj`
5. 在 Xcode 的 Signing & Capabilities 確認兩個 target 都有同一個 App Group。第一次通常要在開發者網站建 App Group，Automatic signing 才會過。
6. 接實機（iOS 18 以上，PiP 需要真機，模擬器不支援廣播擴充）。Run。

## 操作流程

每次驗證前先按「清除量測紀錄」。

### 驗證 1、5：擴充記憶體與延遲

1. 在 app 裡把「擷取區域」調到大約螢幕中間 60% 的高度，避開頂部狀態列與底部。
2. 按「開始螢幕廣播」旁邊的系統按鈕，選 LiveSpike 擷取，開始。狀態列會出現紅色指示。
3. 打開任何有日文或韓文文字的 app 或網頁，讓文字停在區域內兩秒。
4. 回到 LiveSpike，看「最新一次」有沒有 OCR 文字、「最近事件」有沒有 `ext.ocr`。
5. 重複幾次不同頁面，然後按「重新整理摘要」。項目 1 與 5 會顯示數字。

如果項目 1 的記憶體超過 45 MB，把 `SampleHandler.swift` 的 `checkInterval` 調大，或把區域縮小，再測一次。若仍然超過，代表 Vision 在擴充內不可行，要改成把縮圖傳給主 app 做 OCR（README 最後有說明）。

### 驗證 2、3：PiP 背景存活與背景翻譯

1. 先在前景按「測試翻譯」，確認翻譯 session 正常，語言包已下載（第一次會跳系統下載提示）。
2. 按「開始 PiP」，PiP 視窗會浮出來，顯示「等待字幕…」。
3. 按 Home 回桌面，打開閱讀 app，把 PiP 視窗拖到擷取區域外面。
4. 正常看漫畫 10 分鐘以上。每次畫面停下來，PiP 應該在 1 到 2 秒內更新譯文。
5. 回到 LiveSpike 按「重新整理摘要」。項目 2 看連續秒數，項目 3 看背景翻譯成功次數。

如果 PiP 視窗更新了原文卻沒有譯文，代表 Translation framework 在背景不能用，項目 3 不通過，要改用 ML Kit 或雲端翻譯。

### 驗證 4：目標 app 會不會黑掉

對每一個目標 app 各做一次，把結果記到 `RESULTS.md`：

- Kakao Page / Kakao Webtoon
- Naver Series / Naver Webtoon
- Piccoma
- LINE Manga
- Webtoon（LINE 系）
- Safari 開網頁版漫畫（對照組，應該一定成功）

黑掉的判斷：廣播中該 app 的畫面本身變黑或出現警告，或 LiveSpike 的「最近事件」出現 `app.blackout`。

## 匯出結果

按「匯出量測紀錄」把兩個 `metrics_*.jsonl` 存到檔案 app 或 AirDrop 到 Mac，再連同填好的 `RESULTS.md` 一起回傳。

## 已知的簡化

- 擷取區域假設手機直立（orientation = up）。橫向時 Vision 的 regionOfInterest 座標要另外轉換，紀錄裡有 orientation 欄位可以看到實際值。
- PiP 影格固定 720×360，字幕模式。鏡像模式（把區域畫面翻好放進 PiP）不在這次驗證範圍。
- 沒有做 PiP 自我擷取的遮罩，只在 PiP 影格外圍畫了洋紅色框，之後遮罩用。驗證時請把 PiP 放在區域外。
- 沒有雲端 LLM，翻譯全部走 Apple Translation framework，這正是要驗證的東西。

## 如果驗證 1 失敗：把 OCR 移到主 app

擴充改成只把區域縮圖（JPEG，長邊 720）寫到 App Group 再送通知，主 app 在收到通知後用 Vision 跑 OCR。代價是 IPC 多傳一張圖（約 50 到 150 KB）與主 app 多一次解碼，延遲大約多 100 到 200 ms。`FrameAnalyzer` 與 `SampleHandler` 的靜止偵測邏輯可以原封不動沿用。
