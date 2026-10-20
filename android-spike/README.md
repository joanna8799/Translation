# ReadTrans Spike：Android 無障礙讀字驗證

對應 [docs/09-build-plan.md](../docs/09-build-plan.md) 第 3.1 節與第 7 節。這不是產品，只驗一件事：

**在 Naver Series、Kakao Page、Ridi、Piccoma、LINE Manga 這些 app 的小說畫面上，AccessibilityService 能不能直接讀到文字節點，以及該 app 有沒有 FLAG_SECURE。**

讀得到，Android 小說功能就走這條主路徑，不怕內容保護、不用 OCR、不跳系統對話框。讀不到，才退到螢幕擷取加 OCR；再被 FLAG_SECURE 擋，這個 app 在 Android 上就只能引導去網頁版。

## 這份程式碼的狀態：已編譯、已組成可安裝的 APK

[dist/readtrans-spike-debug.apk](dist/readtrans-spike-debug.apk)（約 1 MB，debug 自簽金鑰，minSdk 26、targetSdk 35）可以直接裝：

```
adb install -r android-spike/dist/readtrans-spike-debug.apk
```

或把檔案傳到手機點開安裝（要允許安裝未知來源 app）。Android 13 以上側載的 app 要在「應用程式資訊 → 右上角選單 → 允許受限設定」之後，才能在無障礙設定裡開啟它。

這個環境連不上 dl.google.com，裝不了 Android SDK，所以 APK 是用 [tools/build-without-sdk.sh](tools/build-without-sdk.sh) 組出來的：android.jar 來自 GitHub 的 Sable/android-platforms（API 35），d8 來自 r8-releases 的 r8lib.jar，aapt2 來自 npm 套件 aaptjs3 內附的 Linux 執行檔，簽章用 npm 套件 apk_sign_ts（v1 加 v2 加 v3，含 zipalign）。Kotlin 編譯零錯誤零警告。已核對過：簽章區塊存在、resources.arsc 未壓縮且 4 byte 對齊、manifest 與無障礙設定檔解析正確、`canRetrieveWindowContent=true`。

為了只靠 Maven Central 就能編譯，這份驗證專案刻意不用 androidx 與 ML Kit：

- `MainActivity` 繼承框架的 `Activity`，不用 AppCompat。
- `L0Translator` 用 Google 翻譯公開的 gtx 端點（Shinkansen 的「Google Translate」引擎用的同一個），不需要 key，直接出繁體中文。產品版換成 ML Kit 端側翻譯，介面不變。
- 真正要驗的東西（AccessibilityService 讀字、`TYPE_ACCESSIBILITY_OVERLAY` 面板、去抖去重）完全不受這兩個替換影響。

在 Android Studio 用 `build.gradle.kts` 開也可以，依賴只有 kotlinx-coroutines-android。

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
3. 接實機（Android 10 以上），Run。或直接 `adb install -r dist/readtrans-spike-debug.apk`，跳過 1 到 3。
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

- 翻譯走 Google 翻譯 gtx 公開端點，需要網路；它只是驗證用替身，產品版換 ML Kit 端側。
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
