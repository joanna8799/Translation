# ReadTrans Spike：Android 無障礙讀字驗證

對應 [docs/08-build-plan.md](../docs/08-build-plan.md) 第 3.1 節與第 7 節。這不是產品，只驗一件事：

**在 Naver Series、Kakao Page、Ridi、Piccoma、LINE Manga 這些 app 的小說畫面上，AccessibilityService 能不能直接讀到文字節點，以及該 app 有沒有 FLAG_SECURE。**

讀得到，Android 小說功能就走這條主路徑，不怕內容保護、不用 OCR、不跳系統對話框。讀不到，才退到螢幕擷取加 OCR；再被 FLAG_SECURE 擋，這個 app 在 Android 上就只能引導去網頁版。

## 這份程式碼的狀態

在沒有 Android SDK 的環境裡寫的（dl.google.com 被網路白名單擋住），沒有編譯過。API 用法都對照過 Android 文件，第一次用 Android Studio 開預期會有幾處要修，應該是 import 或簽章的小差異，不是架構問題。修完請把 diff 丟回來。

## 架構

```
目標 app（Kakao Page、Naver Series…）
   │ 無障礙事件：內容變更、捲動、視窗切換
   ▼
ReaderAccessibilityService
   ├ 只收目標 package 的事件（TargetApps，可在 app 內勾選）
   ├ 300 ms 去抖
   ├ NodeCollector：走訪 rootInActiveWindow，收可見且有文字的節點與螢幕座標
   ├ 全部文字做 SHA-1，跟上一輪相同就跳過
   ├ L0Translator：ML Kit 端側翻譯（ko / ja → zh），LruCache 去重
   ├ OverlayPanel：TYPE_ACCESSIBILITY_OVERLAY 底部面板顯示譯文（不需要「顯示在其他 app 上層」權限）
   └ Metrics：每輪寫一行 JSONL
   │
   ▼ TextBus（StateFlow）
MainActivity：開無障礙設定、勾目標 app、看最新一輪節點、匯出紀錄
```

## 設定步驟

1. Android Studio 開 `android-spike/`，等 Gradle 同步。
2. 改 `app/build.gradle.kts` 的 `applicationId`（預設 `dev.readtrans.spike`，可以不改）。
3. 接實機（Android 10 以上），Run。
4. app 裡按「開啟無障礙設定」，找到 ReadTrans Spike，開啟。Android 13 以上從 APK 側載的 app 要先在「應用程式資訊」裡允許受限設定，Play 內部測試軌道發的不用。
5. 回 app，勾選要測的目標 app。package 名稱若不對，用 `adb shell pm list packages | grep -i <關鍵字>` 查，在「自訂 package」欄位補。

## 操作流程

對每一個目標 app 做一次，結果記到 [RESULTS.md](RESULTS.md)：

1. 在 Spike app 按「清除紀錄」。
2. 打開目標 app，進一本小說，停在正文頁 2 秒，再往下捲一頁，再停 2 秒。
3. 這時底部應該浮出譯文面板。沒有的話回 Spike app 看「最新一輪」。
4. 在正文頁按系統截圖。黑的、或跳出「無法擷取」訊息，就是 FLAG_SECURE，記下。
5. 回 Spike app，「最新一輪」會顯示 package、節點數、字數、走訪毫秒。
6. 判定：

| 看到什麼 | 判定 | 代表 |
|---|---|---|
| 節點數 ≥ 5、字數 ≥ 200，文字就是畫面上的正文 | A 可用 | 主路徑，不受 FLAG_SECURE 影響 |
| 節點數 ≥ 5，但文字是 UI 文字（按鈕、章名），沒有正文 | A 不可用，閱讀器自繪 | 看截圖黑不黑決定 B 行不行 |
| 節點數 0 到 2、字數 < 20 | A 不可用，可能是 canvas 或 accessibilityDataSensitive | 同上 |
| 文字有，但順序亂或被截斷 | A 可用但要排版處理 | 記下範例 |

7. 全部測完按「匯出紀錄」，`metrics.jsonl` 會存到「下載」資料夾，連同 RESULTS.md 一起回傳。

## 已知的簡化

- ML Kit 翻譯的中文目標只有簡體，面板顯示簡體。產品版會接 OpenCC 轉繁體，這裡不影響驗證目的。
- 語言判斷用字元範圍：韓文字母佔三成以上判 ko，有平假名或片假名判 ja，否則跳過不翻。
- 面板是唯讀的、觸控穿透，不能拖動。就地雙語模式不在這次範圍。
- 只處理 `rootInActiveWindow`，不處理分割畫面或多視窗。
- 走訪上限 1,500 個節點、收集上限 400 個，超過就截斷並在紀錄裡標 `truncated`。

## 紀錄格式

`metrics.jsonl` 每行一個 JSON：

```json
{"t":1760000000000,"ev":"a11y.snapshot","pkg":"com.kakao.page","nodes":37,"chars":1842,"walkMs":12,"truncated":false}
{"t":1760000000400,"ev":"l0.translate","pkg":"com.kakao.page","src":"ko","chunks":37,"cacheHit":12,"ms":610}
{"t":1760000001000,"ev":"a11y.skip","pkg":"com.kakao.page","reason":"same-hash"}
{"t":1760000002000,"ev":"a11y.empty","pkg":"com.initialcoms.ridi","nodes":1,"chars":6}
```
