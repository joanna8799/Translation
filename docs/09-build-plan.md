# 建置計畫：用 Shinkansen 補網頁那一半，自己只做 Android、iOS 截圖與雲端 proxy

> 2026-10-20。這份文件回答三件事：
> 1. 你問的兩個問題：金融 app 明明能截圖，為什麼說 iOS 截圖會黑；以及「讀螢幕」會不會也觸發黑畫面。
> 2. Shinkansen（https://github.com/jimmysu0309/shinkansen）能替我們省掉什麼、不能替我們做什麼。
> 3. 接下來六週每一週要交出什麼、用什麼 API、哪個檔案。
>
> 程式碼：[android-spike/](../android-spike/README.md)（Android 無障礙讀字驗證，對應 Phase 0c）。已編譯並組成可安裝的 APK：[android-spike/dist/readtrans-spike-debug.apk](../android-spike/dist/readtrans-spike-debug.apk)。

## 0. 先回答你的兩個問題

### 0.1 「黑畫面但金融都還是能截圖欸」

你說得對，我上一版寫得太重。精確的說法是：

- **iOS 沒有任何官方 API 可以擋截圖。** 所以絕大多數 app，包括台灣多數銀行 app，截圖都是正常的。
- **但有一個非官方手法**：把要保護的內容掛在一個 `isSecureTextEntry = true` 的 UITextField 的圖層底下。這個欄位是給密碼用的，系統為了不讓密碼被截到，會把它整個圖層從截圖與錄影裡抹掉。有些影音與閱讀 app 拿這個副作用來擋截圖。這是 opt-in、少見，不是 iOS 的常態。
- **在我們的目標 app 裡，誰用了**（搜尋到的使用者回報，不是官方文件）：

| app | iOS 截圖 | Android 截圖 | 依據 |
|---|---|---|---|
| Kakao Page | 可以截（使用者回報「蘋果裝置因技術原因截得到」；app 內另有「官方擷取」功能，有次數上限） | 被擋，跳「因保安政策無法擷取」訊息，即 FLAG_SECURE | X 貼文、韓文部落格多篇，2022 到 2024 |
| Piccoma | 黑畫面並跳警告「無法儲存圖片」 | 付費內容黑畫面 | 知恵袋與多篇日文整理 |
| Naver Series | 未查到回報；app 有官方「選句分享成圖」功能 | 未查到回報 | PC 閱讀器有 Fasoo DRM，擷取黑畫面 |
| Ridi | 未查到 | 未查到 | 網頁閱讀器官方說明主動提到可用瀏覽器翻譯 |

結論：iOS 截圖捷徑對 Kakao Page 可用，對 Piccoma 不可用，Naver Series 與 Ridi 要實測。這些都要寫進產品的「支援清單」，不能一句「iOS 任何 app 都行」。

### 0.2 「閱讀螢幕畫面也會觸發嗎」

要分「讀像素」和「讀文字節點」，兩者完全不同：

| 保護機制 | 截圖 | 螢幕錄影、MediaProjection、ReplayKit 廣播（我們的即時模式） | 無障礙服務讀文字節點 |
|---|---|---|---|
| Android `FLAG_SECURE` | 擋 | 擋，拿到全黑 | **不擋**。FLAG_SECURE 作用在 Surface 合成層，無障礙樹是另一條路，`AccessibilityNodeInfo.getText()` 照常回傳 |
| Android 14 `accessibilityDataSensitive` | 不相關 | 不相關 | 擋。app 可以把特定 view 標成只給「真正的無障礙工具」讀。閱讀 app 目前沒看到有人這樣做，要實測 |
| iOS secure text field 圖層 | 擋 | 擋，同一條合成路徑 | iOS 第三方 app 根本沒有讀別人無障礙樹的 API，這格不存在 |
| iOS `UIScreen.isCaptured` 偵測 | 不擋 | app 自己決定遮不遮 | 不存在 |

所以：

- **Android**：FLAG_SECURE 的 app（Kakao Page、Piccoma），螢幕擷取 OCR 這條路死，但無障礙讀字活著。這是為什麼 Android 小說要以無障礙讀字為主路徑。
- **iOS**：Piccoma 這類用了 secure 圖層的 app，截圖與 PiP 即時模式都黑，iOS 上對它完全沒有辦法，只能引導去網頁或自家閱讀器。Kakao Page 這類沒用的 app，截圖捷徑與 PiP 都可用。
- **我們自己的即時模式**（docs/06）在 Android 上是用 MediaProjection，所以會被 FLAG_SECURE 擋；在 iOS 上是 ReplayKit，所以會被 secure 圖層擋。即時模式只能在沒做保護的 app 上宣傳。

## 1. Shinkansen 替我們做掉哪一半

### 1.1 它是什麼

- 瀏覽器擴充，v2.6.2，約 750 次 commit，Chrome Web Store、Firefox Add-ons、Mac App Store、iOS/iPadOS App Store 四處上架。
- 功能已經覆蓋你需求 3 的全部：單語替換或雙語對照、懸停翻譯、自動翻譯網域白名單、全域與網域術語表、禁用詞、翻譯快取（SHA-1 key，LRU 9.5 MB）、用量與費用追蹤、EPUB／PDF／Word／TXT／Markdown／HTML／字幕檔整份翻譯、EPUB 全書術語表與一致性掃描、雙語 EPUB 匯出。
- 引擎：Gemini（自備 key）、Google Translate 非官方免費端點、**任何 OpenAI 相容的自訂 provider**（OpenRouter、Ollama、Groq）。
- 不做：漫畫、圖片 OCR、Android。
- 授權 **Elastic License 2.0**。允許複製、修改、散布、做衍生作品；禁止「把這個軟體當託管或受管理服務提供給第三方」、禁止繞過授權金鑰功能、禁止移除版權聲明。
- 規格文件 SPEC.md 有 70 KB，但多處引用「SPEC-PRIVATE §32」，注入演算法、序列化協定、Content Guard 的細節不在公開 repo。

### 1.2 它對我們的意義

你的需求 1（PC、iOS 瀏覽器）與需求 3（小說像沉浸式翻譯）在網頁與檔案這一塊，Shinkansen 已經做完了，而且品質是上架四個商店的等級。重寫一套只是為了掛自己的名字，要花 Phase 1 加 Phase 2 共六到七週，還追不上它兩年的細節修正。

剩下的才是沒人做、也是你真正的差異點：

- Android（Shinkansen 沒有，沉浸式翻譯只有內建瀏覽器 app）。
- 平台 app 內的小說（需求 4，沒有任何現成產品做）。
- 漫畫 OCR 與畫回氣泡（需求 5，EasyComix 只有 iOS）。
- 雲端 LLM proxy 與訂閱（讓不想自己申請 API key 的人付月費）。

### 1.3 接法：三個選項，建議第三個

| 選項 | 做法 | ELv2 風險 | 工作量 |
|---|---|---|---|
| A 不碰 | 官網引導使用者裝 Shinkansen，我們只做 app 與 proxy | 零 | 零 |
| B fork | fork 後改名改 UI，加上我們的登入與額度，上架自己的擴充 | 中。散布衍生作品 ELv2 允許；但擴充內建我們的付費 proxy 等於把它的功能包進付費服務，是否算「hosted service」有解釋空間。要先取得作者書面同意 | Phase 1 省七成 |
| **C proxy 當 provider** | 我們的雲端 proxy 實作 OpenAI 相容的 `/v1/chat/completions`。Pro 使用者在 Shinkansen「自訂模型」填我們的網址與訂閱金鑰，就能用我們的 LLM 額度與共享快取。瀏覽器端零程式碼 | 零。Shinkansen 原封不動，我們只是它支援的 provider 之一 | proxy 多一個端點，約兩天 |

建議 C 起步，同時寫信給作者談 B。C 的好處是第一個月就能把「PC、Mac、iOS Safari 小說雙語 + 我們的訂閱」賣出去，而我們的工程時間全部放在 Android 與漫畫。

C 的限制：Shinkansen 的翻譯快取在使用者本機，我們的跨使用者共享快取在 proxy 端，兩層都在；術語表由 Shinkansen 送進 prompt，我們的 proxy 看得到但不用管。Shinkansen 不會顯示我們的額度餘量，要在我們的網頁帳號頁顯示。

## 2. 產品組成（定稿）

```
使用者看到的三個東西
├ 瀏覽器與檔案：Shinkansen（他們的）+ 我們的 proxy 當 provider
├ Android app「ReadTrans」（暫名）
│   ├ 小說：AccessibilityService 讀字 → 覆蓋層面板或就地雙語
│   ├ 小說備援：MediaProjection + ML Kit OCR（非 FLAG_SECURE app）
│   ├ 漫畫：MediaProjection + 氣泡偵測 + OCR + 懸浮窗就地覆蓋（docs/06 §1）
│   ├ 內建瀏覽器（WebView）給用 Chrome 的人，之後再評估要不要塞 Shinkansen 進去
│   └ 自家閱讀器：EPUB、TXT、貼網址追更
└ iOS app
    ├ 截圖捷徑：App Intent 收截圖 → Vision OCR → Translation → 結果頁（小說與漫畫共用）
    ├ 自家閱讀器：同 Android
    └ PiP 即時模式：Phase 0b 驗證通過才做

雲端：Cloudflare Workers
├ POST /v1/chat/completions   OpenAI 相容，給 Shinkansen 與 BYOK 工具
├ POST /v1/translate          我們自己的格式 {kind: text|bubbles, chunks:[...]}
├ GET  /v1/me                 額度、方案
├ KV: quota:{uid}:{yyyymm} → 已用 token；cache:{sha1(src+tgt+tier)} → 譯文
└ RevenueCat webhook → entitlement
```

## 3. Android：具體到類別與 API

### 3.1 小說讀字（主路徑）

| 元件 | 用什麼 | 關鍵點 |
|---|---|---|
| 讀字 | `AccessibilityService`，`accessibility_service_config.xml` 設 `canRetrieveWindowContent="true"`、`accessibilityFlags="flagRetrieveInteractiveWindows\|flagReportViewIds"`、`accessibilityEventTypes="typeWindowContentChanged\|typeViewScrolled\|typeWindowStateChanged"`、`packageNames` 只列目標 app | 只列目標 package，其他 app 的事件系統根本不會送進來，隱私聲明站得住 |
| 收集節點 | 從 `rootInActiveWindow` 深度優先走訪，取 `isVisibleToUser && text != null`，記 `getBoundsInScreen`、`className`、`viewIdResourceName`。WebView 內容在 Android 7 以上預設暴露，不用額外旗標 | 每個節點用完 `recycle()`（API 33 以下）；每輪走訪限 400 個節點、50 ms 內結束 |
| 去抖 | 事件進來後 300 ms 沒有新事件才處理；處理前比對「所有可見文字的 SHA-1」，跟上一輪相同就跳過 | 這一步決定 LLM 呼叫次數 |
| 畫覆蓋 | 在 AccessibilityService 內用 `WindowManager.addView`，型別 `TYPE_ACCESSIBILITY_OVERLAY` | **不需要 SYSTEM_ALERT_WINDOW 權限**，這是走無障礙服務的額外好處；懸浮窗設 `FLAG_NOT_FOCUSABLE \| FLAG_NOT_TOUCHABLE` 讓觸控穿透 |
| 兩種顯示 | 面板模式：底部一塊可拖高度的半透明面板，列出可見段落的譯文。就地模式：對每個文字節點的 bounds 畫一個同大小的 TextView，底色取不透明的紙色，字級自動縮到塞得下 | 就地模式會遮住原文，提供「長按顯示原文」。先做面板模式 |
| 翻譯 L0 | ML Kit Translation，`com.google.mlkit:translate:17.0.3`，ko→zh、ja→zh 模型各約 30 MB，第一次下載 | 免費、離線 |
| 翻譯 L1/L2 | 我們的 proxy `/v1/translate`，整屏段落打包一次 | Pro 才有 |
| 讀不到字的判斷 | 走訪後可見文字總長 < 20 字，且前景 package 在目標清單內 → 判定自繪 canvas，提示切 OCR 備援 | Ridi 一般電子書很可能走這條 |

### 3.2 小說 OCR 備援與漫畫

同 docs/06 §1，不重複。只補一條：在啟動 MediaProjection 前先拿第一幀，全黑（亮度均值 < 8 且標準差 < 2）就判定 FLAG_SECURE，直接提示「這個 app 有內容保護，只能用文字模式」，不要讓使用者看著黑畫面等。

### 3.3 Play 商店

- `AccessibilityService` 用途宣告：Play Console 的「無障礙服務」表單選「非無障礙用途」，說明「讀取使用者正在閱讀的外語小說文字並顯示翻譯」。
- app 內首次啟用前要有宣告畫面，列出：讀取哪些 app（目標清單）、讀什麼（畫面上的文字）、送去哪（端側模型，或在 Pro 開啟時送到我們的伺服器只送文字不存原文）。
- `MediaProjection` 的前景服務型別宣告與 Android 14 以上要求，照 docs/02 §2.1。
- 文案不出現任何平台名稱的商標圖、不內建連結。

### 3.4 相依與版本

```kotlin
// app/build.gradle.kts
android { compileSdk = 35; defaultConfig { minSdk = 26; targetSdk = 35 } }
dependencies {
    implementation("com.google.mlkit:translate:17.0.3")
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")   // 漫畫與 OCR 備援
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
```

minSdk 26 是因為 `TYPE_ACCESSIBILITY_OVERLAY` 與 ML Kit 的下限，而且 Android 8 以下的市占可以放棄。

## 4. iOS：具體到 API

| 元件 | 用什麼 |
|---|---|
| 截圖捷徑 | `AppIntent` 接收 `IntentFile`（圖片），使用者在捷徑 app 建「截圖 → 傳給 ReadTrans」並綁到動作按鈕或背面輕點。我們提供一鍵安裝的捷徑連結 |
| OCR | `VNRecognizeTextRequest`，`recognitionLanguages = ["ko", "ja", "zh-Hant"]`，`usesLanguageCorrection = true`。直式日文在 iOS 18 的 Vision 可用但不穩，漫畫場景要測 |
| 翻譯 L0 | `Translation` framework，`TranslationSession`，要在 SwiftUI 視圖有 `translationTask` 的情況下跑，所以 Intent 開啟 app 的結果頁後才翻，不在 Intent 背景翻 |
| 顯示 | Intent 回傳 `opensIntent` 開 app 的結果頁；結果頁是全螢幕的雙語或就地（漫畫）畫面，往下滑關閉回到原 app |
| 不支援清單 | Piccoma 的截圖是黑的，app 偵測到整張黑圖時提示「這個 app 有截圖保護，請改用網頁版」 |
| PiP 即時模式 | 等 ios-spike 五項驗證結果 |

## 5. 雲端 proxy：端點與資料

```
POST /v1/chat/completions         # OpenAI 相容，給 Shinkansen
  Authorization: Bearer rt_live_xxx（訂閱金鑰）
  body 照 OpenAI 格式；model 允許 "rt-fast"（L1）、"rt-quality"（L2）
  → 查 quota → 查 cache（key = sha1(model + 全部 messages)）→ 未命中呼叫上游 → 寫回
  → usage 欄位回報實際 token，Shinkansen 會顯示在它的費用統計

POST /v1/translate                # 我們的 app 用
  { "kind": "text" | "bubbles", "src": "ko", "tgt": "zh-TW", "tier": "L1",
    "glossary": {...}, "chunks": [ { "id": 0, "text": "..." } ] }
  → 回 { "chunks": [ { "id": 0, "text": "..." } ], "usage": {...} }
  → structured output，段落級快取 key = sha1(text + tgt + tier + glossary_hash)

GET /v1/me → { "plan": "pro", "quota": 5000000, "used": 123456, "reset": "2026-11-01" }

KV
  quota:{uid}:{yyyymm}  → used_tokens
  cache:{sha1}          → 譯文（TTL 90 天）
  key:{apikey}          → uid, plan, expires
```

免費層完全不碰這個 proxy，所以 Workers 付費方案 US$5/月加 KV 就夠撐到幾千個 Pro。

## 5a. 電腦上的閱讀器 app（Ridi PC 閱讀器、Kindle、BookWalker 桌面版）

網頁版走擴充，但平台的桌面閱讀器 app 跟手機 app 一樣碰不到。桌面有跟 Android 無障礙服務對應的東西：Windows 的 UI Automation、macOS 的 Accessibility API，可以讀別的視窗的文字節點，Electron 與 Chromium 做的閱讀器（Ridi PC 閱讀器就是）通常會暴露無障礙樹。螢幕擷取被 DRM 擋住時，這條路可能還通，跟 Android 的狀況一樣。

所以桌面要多一個小程式：讀前景視窗的無障礙樹（小說）或擷取視窗畫面做 OCR（漫畫，DRM 擋得住的就不行），譯文用置頂的半透明視窗疊上去。做法與 Android app 一對一對應，排在 Android app 之後；之前「PC 不做桌面 app」的判斷要改。先驗證的清單：Ridi PC 閱讀器、Kindle for PC、BookWalker、Kakao Page 網頁在 Electron 殼裡的版本，各看一次 UI Automation 讀不讀得到正文。

## 5b. Phase 0 已經跑通

[demo/manga-pipeline/](../demo/manga-pipeline/README.md) 在這個環境裡完整跑了一遍：自製測試頁 → 像素法氣泡偵測（11/11）→ Tesseract OCR（11 句全部可讀，2 個錯字）→ LLM 翻譯（錯字被上下文修正）→ 擦字與直書／橫書排版。資料格式就是 §5 的 bubbles JSON。產品版只換三個零件：偵測模型、OCR 模型、翻譯 proxy，介面不變。

## 5c. 不付費的路線：哪些真的要錢、哪些不用

| 項目 | 要不要付費 | 說明 |
|---|---|---|
| Android 驗證與測試 | 不用 | APK 直接側載，CI 已產出 |
| Android 上架 Google Play | US$25 一次 | 之後再說，測試期不需要 |
| 瀏覽器與檔案（Shinkansen） | 不用 | 它已上架，我們不碰 |
| iOS 驗證專案裝到自己手機 | 不用 | TalkSpike 與 LiveSpike 都走 AltStore 加免費 Apple ID，7 天續簽、最多 3 個 app。LiveSpike 的 App Group 由 CI 用 ad-hoc 簽章嵌入，app 執行期讀 `ALTAppGroups` |
| iOS 給別人測（TestFlight） | US$99/年 | 之後再說 |
| iOS 上架 App Store | US$99/年 | 之後再說 |
| 雲端 proxy（Cloudflare Workers） | 免費額度先用 | 每日 10 萬次請求夠 MVP，付費方案 US$5/月 |
| LLM API | 用量計費 | 驗證期間可以先用 BYOK，或 Gemini 免費層 |
| 端側 OCR 與翻譯（ML Kit、Vision、Apple Translation） | 不用 | 這是整個設計的前提 |

結論：到 Phase 5 之前一毛錢都不用付。第一筆必要支出是上架時的 Apple US$99，可以等產品驗證完再決定。

## 6. 六週計畫，每週交付物

| 週 | 交付 | 驗收 |
|---|---|---|
| 1 | android-spike 在實機跑起來，填完 RESULTS.md：Naver Series、Kakao Page（兩種作品）、Ridi（兩種）、Piccoma 小說、LINE Manga 小說、Munpia 各一次 | 每個 app 有「讀到幾個節點、幾個字、是不是 FLAG_SECURE」三個數字 |
| 1（並行） | iOS 實機：對同一批 app 截圖，記錄黑不黑；ios-spike 編譯起來 | RESULTS.md 的「截圖是否黑掉」欄填滿 |
| 2 | proxy `/v1/chat/completions` 與 `/v1/me` 上線，Shinkansen 自訂 provider 填進去能翻 | 一頁なろう小說經 Shinkansen → 我們 proxy → Haiku 翻完，費用統計顯示正確 token |
| 3 | Android app 骨架：宣告畫面、啟用無障礙的引導、目標 app 清單、面板模式覆蓋層、ML Kit L0 | 在 Kakao Page 小說裡捲動，面板 1 秒內更新中文 |
| 4 | Android 接 proxy L1 潤稿、段落雜湊去重、文字來源切換（無障礙 → OCR 備援）、FLAG_SECURE 偵測提示 | 同一章捲完，LLM 呼叫次數 ≤ 段落數，無重複 |
| 5 | iOS 截圖捷徑 app：Intent、Vision、Translation、結果頁、一鍵安裝捷徑 | Kakao Page 小說頁用背面輕點 2 秒內看到中文；Piccoma 跳保護提示 |
| 6 | RevenueCat 串 Play 與 App Store，網頁帳號頁顯示額度，封閉測試上架 | 付費後金鑰在 Shinkansen 與兩個 app 都能用 |

漫畫（MediaProjection 氣泡 OCR 就地覆蓋）排在第 7 到 10 週，走 docs/06 §1 與 docs/04 Phase 3 的設計，不在這六週。

## 7. 這週就要在實機上做的事

Android（任何一台 Android 10 以上的手機）：

1. 直接 `adb install -r android-spike/dist/readtrans-spike-debug.apk`，或把 APK 傳到手機安裝。不用 Android Studio。
2. 設定 → 無障礙 → ReadTrans Spike → 開。
3. 開 Kakao Page，進一本「專用行動閱讀器」的小說，捲兩頁。回 Spike app 看「最新一輪」有沒有文字、幾個節點。
4. 在同一頁按截圖。黑或跳訊息就是 FLAG_SECURE，記下來。
5. 重複 3 到 4 給 Naver Series、Ridi 網路小說、Ridi 一般電子書、Piccoma 小說、LINE Manga 小說、Munpia。
6. 按「匯出紀錄」，把 `metrics.jsonl` 與填好的 RESULTS.md 丟回來。

iOS（iPhone 一台）：

1. 同一批 app 各進一本小說，按截圖，看相簿。黑的記下來。
2. 有 Xcode 的話把 ios-spike 編起來，照它的 README 跑五項驗證。

兩份 RESULTS.md 回來後，支援清單就能定稿，Android app 的第 3 週開始寫就不會白做。

## 8. 來源

- Shinkansen repo、README、SPEC.md、LICENSE：https://github.com/jimmysu0309/shinkansen
- Elastic License 2.0 全文：https://www.elastic.co/licensing/elastic-license
- FLAG_SECURE 不影響無障礙服務：https://wwws.nightwatchcybersecurity.com/2016/04/13/research-securing-android-applications-from-screen-capture/ 、https://ptkd.com/journal/flag-secure-screen-share-capture-bypass
- `accessibilityDataSensitive`（API 34）：https://developer.android.com/reference/android/view/View#setAccessibilityDataSensitive(int)
- `TYPE_ACCESSIBILITY_OVERLAY`：https://developer.android.com/reference/android/view/WindowManager.LayoutParams#TYPE_ACCESSIBILITY_OVERLAY
- iOS secure text field 擋截圖與錄影的說明（BytePlus 文件）：https://docs.byteplus.com/en/docs/byteplus-vos/docs-anti-screen-recording
- Kakao Page iPhone 可截圖、Android 擋：https://x.com/CZi_ruha/status/1553766537110368256 、https://endless9rowth.com/entry/카카오페이지-스크린샷-방법
- Piccoma iPhone 截圖黑畫面與警告：https://detail.chiebukuro.yahoo.co.jp/qa/question_detail/q11307348611 、https://dvdfab.org/bookfab/piccoma-screenshot-risk-or-not.htm
- ML Kit Translation：https://developers.google.com/ml-kit/language/translation/android
