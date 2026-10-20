# 需求對照盤點：你要的五件事，現在的文件各覆蓋到哪裡

> 2026-10-20 重新盤點。你重申的需求是：
>
> 1. 像沉浸式翻譯那樣的產品級 app，PC、iOS、Android 都能用。
> 2. 要有付費量級設計，或免費資源的使用方式。
> 3. 文字（小說）翻譯要像沉浸式翻譯。
> 4. Naver 這類平台會要求使用者下載自家電子書 app，網頁文字抓不到，要有替代方案。
> 5. 漫畫參考 EasyComix。
>
> 現有 docs/01 到 06 與 ios-spike 是前幾輪產出，重心偏在「漫畫即時模式」。這份文件把五項需求逐一對照，標出已覆蓋、部分覆蓋、尚未處理，並補上第 4 項的完整方案。

## 0. 一頁結論

| # | 需求 | 覆蓋程度 | 現有文件 | 主要缺口 |
|---|---|---|---|---|
| 1 | 全平台產品級 app | 部分 | docs/02、04 | PC 端只有瀏覽器擴充，沒有桌面 app；Android 瀏覽器用 Chrome 的人沒有擴充可裝；「產品級」需要的帳號、同步、設定、客服、更新機制沒有盤點 |
| 2 | 付費量級與免費資源 | 已覆蓋 | docs/01、03、05 | 分層是以漫畫頁數起步再補 token，沒有一張統一的最終分層表；沒有對照沉浸式翻譯的 Pro／Max 兩級結構 |
| 3 | 小說像沉浸式翻譯 | 部分 | docs/05 | 只講網頁小說與 app 內小說的取字方式；沉浸式翻譯小說體驗的核心（雙語對照、EPUB 匯入與雙語匯出、PDF、段落級快取、人名表）只有零散幾句 |
| 4 | Naver 等 app 鎖定內容的替代方案 | 不足 | docs/02 §6、05 §1 | 只有一行「AccessibilityService 讀不到退到 OCR」，沒有針對內容保護（FLAG_SECURE、DRM）之後的最後手段，沒有逐平台實測清單，沒有法律邊界 |
| 5 | 漫畫參考 EasyComix | 已覆蓋，且超出 | docs/01、02、06、ios-spike | 無。反而是即時模式投入過重，相對於需求 3、4 失衡 |

**最重要的修正**：第 4 項是這個產品與沉浸式翻譯真正的差異點，但目前文件把它當成小說章節裡的一個註腳。Android 的 AccessibilityService 是唯一能繞過 FLAG_SECURE 內容保護讀到文字的公開 API，應該升格為小說功能的主路徑，而不是備案。詳見第 3 節。

**第二個修正**：docs/02 與 06 說「iOS 無法阻止截圖」，這不完全對。iOS 沒有官方 API 擋截圖，但有一個被串流與金融 app 廣泛使用的手法（把內容掛在 secure text field 的圖層上），可以讓截圖與錄影都變黑。Naver Series、Kakao Page、Piccoma 的 iOS 版有沒有用，要實測，不能假設截圖捷徑一定可用。已在 ios-spike/RESULTS.md 加了一欄。

## 1. 需求 1：全平台產品級 app

### 1.1 平台矩陣（修訂版）

| 使用情境 | PC（Windows／macOS） | Android | iOS |
|---|---|---|---|
| 網頁小說、網頁漫畫 | 瀏覽器擴充（Chrome、Edge、Firefox、Safari） | 內建瀏覽器的 app（沉浸式翻譯 Android 版就是這樣做），加上第三方瀏覽器擴充 | Safari 擴充 |
| 平台自家 app 內的小說 | 平台 PC 閱讀器多半有 DRM（見 §3.2），擷取到黑畫面。替代：引導用網頁版（Ridi 網頁閱讀器、Kakao Page EPUB 作品），或手機處理 | AccessibilityService 讀文字，退到螢幕擷取 OCR | 截圖捷徑加 Vision OCR；自家閱讀器 |
| 平台自家 app 內的漫畫 | 同上 | 螢幕擷取加懸浮窗（docs/06） | 截圖捷徑；廣播加 PiP（docs/06） |
| 檔案（EPUB、TXT、PDF、CBZ） | 桌面 app 或網頁版匯入 | 自家閱讀器 | 自家閱讀器 |

跟現有 docs/02 §0 總表的差別：

- 加了 Android「內建瀏覽器的 app」。用 Chrome 的 Android 使用者裝不了擴充，沉浸式翻譯的解法是把 app 做成一個內嵌擴充的瀏覽器。我們的 Android app 本來就要有自家閱讀器，多包一個 WebView 加 content script 成本不高。
- 加了 PC 端對平台閱讀器的評估：Ridi PC 閱讀器與 Naver Series PC 閱讀器都有 DRM（Fasoo 類），擷取與剪貼簿都會被擋。PC 不做螢幕 OCR 桌面 app，改用網頁版引導，省一條產品線。
- 檔案匯入與雙語匯出列為正式功能，不只是「iOS 自家閱讀器」的附帶。

### 1.2 「產品級」還缺的非功能項目

現有文件沒有盤點的，列在這裡，不展開：

- 帳號與同步：登入（Apple、Google）、設定同步、詞彙表同步、閱讀進度同步（自家閱讀器）。
- 訂閱：RevenueCat 串三個商店加 Stripe，擴充版用授權碼或網頁登入。docs/04 Phase 5 已提。
- 隱私聲明：螢幕擷取、無障礙服務、截圖處理，三個商店各要一份用途說明與 app 內宣告畫面。
- 更新機制：擴充走商店自動更新；端側模型分語言按需下載，要有版本與回滾。
- 客服與回報：翻錯回報按鈕（附原文與譯文，不附圖），這是品質迭代的資料來源。
- 多語言 UI：至少繁中、簡中、英、日、韓。

## 2. 需求 2：付費量級與免費資源

### 2.1 統一分層表（取代 docs/03 §2、§7、§11 與 05 §2 的分散描述）

額度一律用 token 計，漫畫一頁約 300 到 800 token，小說一章約 5,000 進 3,500 出。

| 層 | 價格（US$） | 翻譯引擎 | 每月額度 | 開放的功能 |
|---|---|---|---|---|
| 免費 | 0 | L0 端側（Chrome Translator、ML Kit、Apple Translation） | 無限 | 網頁小說雙語、網頁漫畫、Android 無障礙讀字、iOS 截圖捷徑、Android 即時模式（只給 L0） |
| 免費登入 | 0 | 加 L1 便宜 LLM | 300K token（約 35 章小說或 300 頁漫畫） | 同上，加 AI 翻譯試用 |
| Pro | 月 4.99／年 29.99／週 1.99 | L1 預設，L2 高品質模式扣 3 到 4 倍 | 5M token | 整章預翻、整本 Batch 預翻、故事背景與詞彙表、iOS PiP 即時模式、EPUB 雙語匯出 |
| Max | 月 12.99／年 79.99 | L2 預設 | 20M token，加 2M 頂級模型 | 同 Pro，加頂級模型、更高並行 |
| BYOK | 0 | 使用者自己的 key | 無限 | Pro 全部功能，不扣我們的額度 |

對照沉浸式翻譯（2025-10 會員條款）：Pro 月 ¥69 給 20M token，Max 月 ¥199 給 50M 加 2M 頂級模型。我們的 token 價格比他便宜是因為 OCR 在端側、免費層完全不碰雲端，LLM 是唯一變動成本（docs/01 §3）。

### 2.2 免費資源清單

每一個都是零邊際成本，是免費層能寫「無限」的理由：

| 資源 | 平台 | 用途 | 限制 |
|---|---|---|---|
| Chrome Translator API | Chrome 138+ 桌面、Edge | L0 翻譯 | 桌面限定，機器要 16 GB RAM 或 4 GB VRAM |
| ML Kit Translation、Text Recognition v2 | Android | L0 翻譯、OCR | 翻譯品質「看得懂」等級 |
| Apple Translation framework、Vision | iOS 17.4+ | L0 翻譯、OCR | 翻譯要在 SwiftUI 視圖內觸發；Vision 直式文字不穩 |
| AccessibilityService | Android | 讀 app 內文字 | 商店審核嚴 |
| Cloudflare Workers、KV 免費額度 | 雲端 | proxy 與快取 | MVP 夠用，之後 US$5/月 |
| Firebase 或 Supabase 認證免費層 | 雲端 | 登入 | |
| RevenueCat 免費層 | 雲端 | 訂閱 | 月收入 US$2,500 以下免費 |
| Anthropic Message Batches | 雲端 | 整本預翻 | 標準價一半，非即時 |
| Prompt caching | 雲端 | 詞彙表與故事背景前綴 | 快取讀取約 0.1 倍 |

## 3. 需求 4：平台 app 鎖定的小說，替代方案

這是沉浸式翻譯做不到、也是本產品該主打的地方。先把問題講清楚，再逐平台給路徑。

### 3.1 問題是什麼

韓國與日本的付費小說平台，很多作品只能在自家 app 看，網頁版沒有或只有部分：

| 平台 | 網頁版能不能讀小說 | 自家 app 的保護 | 來源等級 |
|---|---|---|---|
| Naver Series | 有網頁版，但大量作品只在 app；PC 閱讀器裝 Fasoo 類 DRM，擷取黑畫面、剪貼簿失效 | Android 是否設 FLAG_SECURE 未證實；要實測 | 二手（Namu Wiki）加推論 |
| Kakao Page | 2022-09 改版後 EPUB 類作品可在 PC 網頁讀；「專用行動閱讀器」作品 PC 不能讀，新作多屬此類 | 未證實；要實測 | 二手（Namu Wiki） |
| Ridi | 網頁閱讀器已支援網路小說，官方說明還主動提到可搭配瀏覽器翻譯；一般電子書要裝 PC 閱讀器，逐書標示支援裝置 | PC 閱讀器有 DRM | 官方客服文件 |
| Piccoma | 主要是 app；付費內容截圖黑畫面 | FLAG_SECURE，證實於第三方整理 | 二手 |
| LINE Manga、Kakao Webtoon 小說區 | 主要是 app | 推測與 Piccoma 同 | 推論 |
| 文피아（Munpia）、조아라、小説家になろう、カクヨム、Alphapolis | 網頁可讀 | 無 | 已知 |

結論：網頁可讀的平台走瀏覽器擴充，不是問題。問題集中在 Naver Series、Kakao Page 專用閱讀器作品、Piccoma、LINE Manga 這四類，它們的共同點是「只在 app 內，而且可能有內容保護」。

### 3.2 四條路徑，依可靠度排序

```
平台 app 內的小說
   │
   ├ 路徑 A（Android）AccessibilityService 讀 UI 樹上的文字節點
   │    FLAG_SECURE 擋的是像素，擋不住無障礙樹。這是唯一能穿過內容保護的公開 API。
   │    條件：閱讀器用原生 TextView 或有暴露無障礙節點的 WebView 渲染。
   │    不行的情況：閱讀器自繪 canvas（EPUB 引擎常見），樹上沒有文字。
   │
   ├ 路徑 B（Android）MediaProjection 擷取加 ML Kit OCR
   │    純文字 OCR 很準。但 FLAG_SECURE 的 app 擷取到黑畫面，整條路作廢。
   │
   ├ 路徑 C（iOS）截圖捷徑加 Vision OCR
   │    iOS 沒有官方 API 擋截圖，但 secure text field 圖層手法可以讓截圖變黑，要逐 app 實測。
   │    每頁要按一下，動作按鈕或背面輕點可以讓它接近無縫。
   │
   └ 路徑 D（任何平台）引導使用者改用網頁版，交給瀏覽器擴充
        Ridi 網頁閱讀器、Kakao Page EPUB 作品、Naver Series 有網頁版的作品。
        在 app 內偵測到該作品有網頁版時提示「這本在網頁也能看，網頁版可以就地雙語」。
```

對每一個目標平台，產品只需要回答一個問題：A 行不行？A 行就是最好的體驗（零誤字、不跳系統對話框、不怕內容保護、不耗電）。A 不行再看 B 有沒有被 FLAG_SECURE 擋。兩個都不行，Android 上這個平台就只剩 D。

### 3.3 路徑 A 的實作要點

- 註冊 `AccessibilityService`，`canRetrieveWindowContent = true`，`flagRetrieveInteractiveWindows`，WebView 要加 `flagRequestEnhancedWebAccessibility` 的後繼旗標（Android 7 以後 WebView 預設暴露節點）。
- 監聽 `TYPE_WINDOW_CONTENT_CHANGED` 與捲動事件，從目前前景 app 的根節點收集可見文字節點與它們的螢幕座標。
- 只處理白名單裡的目標 package（Naver Series、Kakao Page、Ridi、Piccoma、LINE Manga），其他 app 不讀，隱私聲明才站得住。
- 顯示方式兩種：懸浮窗整頁譯文面板（最簡單）；或把譯文畫在每個文字節點的座標上，做成就地雙語（體驗接近沉浸式翻譯，但閱讀器排版會被遮，要可切換）。
- 文字進來後的流程跟網頁小說一樣：段落切 chunk、文字雜湊去重、L0 草稿加 LLM 潤稿、段落級快取。這部分程式碼可以跟瀏覽器擴充共用，差別只是文字來源。
- 讀不到文字的判斷：根節點下可見文字節點的總字數低於閾值，而畫面明顯有內容，就判定為自繪 canvas，提示切到路徑 B，B 擷取到全黑再提示路徑 D。

### 3.4 路徑 A 要在 Phase 3 之前先驗證的清單

這跟 ios-spike 是同一個性質的驗證，一天內可以做完，用一個最小的 AccessibilityService 把前景 app 的文字節點 dump 出來：

| 平台 app | 文字節點讀得到嗎 | 是否 FLAG_SECURE（截圖測） | 判定路徑 |
|---|---|---|---|
| Naver Series | | | |
| Kakao Page（專用閱讀器作品） | | | |
| Kakao Page（EPUB 作品） | | | |
| Ridi（網路小說） | | | |
| Ridi（一般電子書） | | | |
| Piccoma（小說區） | | | |
| LINE Manga（小說區） | | | |
| Munpia app | | | |

結果決定 Android 小說功能能宣傳的範圍，跟 docs/06 §3 的即時模式清單一樣。

### 3.5 法律與商店邊界

- 無障礙服務讀取畫面文字不是破解 DRM，沒有解密、沒有繞過存取控制，但各平台的服務條款多半禁止「擷取內容」。產品要做的是：只處理當前畫面、不存原文、不做整章匯出，翻譯結果只在裝置與快取 key 裡，而且快取只存譯文不存原文全文。
- Google Play 對 AccessibilityService 的要求：上架表單要勾選「非無障礙用途」並說明；app 內要有宣告畫面，說明讀取哪些 app、做什麼、資料去哪。拒審風險存在，先例是螢幕翻譯類 app 多數有過。
- 不要內建任何平台的連結、搜尋或推薦，文案只說「翻譯你正在看的畫面」。docs/04 風險表已有這條。

### 3.6 PC 上的 app 鎖定內容

Naver Series 與 Ridi 的 PC 閱讀器都有 DRM，螢幕擷取拿到黑畫面，剪貼簿也被停用，桌面 app 做螢幕 OCR 這條路在這些平台上是死的。PC 的替代方案只有路徑 D，引導到網頁版。Windows 的 Android 子系統已停止，模擬器方案不符合「產品級」，不列入。

## 4. 需求 3：小說體驗要像沉浸式翻譯

docs/05 講了取字與成本，沒講體驗。沉浸式翻譯小說相關功能逐項對照：

| 沉浸式翻譯有的 | 我們現有文件 | 要補的 |
|---|---|---|
| 網頁雙語對照，原文下方插譯文 | docs/05 §1 一句 | 版面規則：段落對齊、譯文樣式（底線、底色、字型縮放）、「只顯示譯文」切換、懸停顯示原文 |
| 整頁與段落兩種觸發 | 無 | 捲到哪翻到哪為預設；整頁翻譯為手動；快捷鍵與浮動按鈕 |
| 網站適配規則與使用者自訂規則 | docs/05 說「最長文字區塊」通用規則 | 保留通用規則，加使用者自訂 CSS 選擇器與分享規則的機制 |
| EPUB 匯入翻譯與雙語 EPUB 匯出，支援 epub、mobi、fb2 | docs/04 Phase 4a 一句「匯入 EPUB」 | 列為正式功能：擴充版的網頁閱讀器、Android 與 iOS 自家閱讀器三處共用一個 EPUB 解析加雙語重組模組；匯出走 Pro |
| PDF 翻譯 | 無 | 小說 PDF 多為文字層，直接抽字；掃描 PDF 走 OCR；MVP 後 |
| 多引擎切換、BYOK | docs/03 §2 | 已覆蓋 |
| 詞彙表（術語庫） | docs/05 §3 | 加：跨裝置同步、按作品綁定、自動從前幾章抽人名建議加入 |
| 字幕、輸入框翻譯、滑鼠懸停 | 無 | 不在範圍，明確排除 |
| 行動端 app（iOS Safari 擴充、Android 內建瀏覽器） | docs/02 | Android 內建瀏覽器要補進 app 規格（§1.1） |

小說專屬且沉浸式翻譯沒有、我們該做的：

- App 內小說的無障礙讀字（§3）。
- 追更：貼網址後定時抓新章、預翻、通知。EasyComix Pro 有「每日更新章節」，沉浸式翻譯沒有。
- 人名與稱謂一致性：作品級詞彙表放快取前綴，前幾章摘要當上下文（docs/05 §4 已有，但要落到規格）。

## 5. 需求 5：漫畫參考 EasyComix

已覆蓋，不重複。要調整的只有一點：

- docs/02、06 關於「iOS 截圖捷徑是所有 app 都能用的備案」的說法要改為「iOS 截圖捷徑在未使用 secure 圖層手法的 app 上可用，要逐 app 實測」。原因見 §0 第二個修正。已在 ios-spike/RESULTS.md 的目標 app 表加了「截圖是否黑掉」欄，與錄影測試一起做。

## 6. 對路線圖的影響

docs/04 的順序是 Phase 0 pipeline、0b iOS 驗證、1 瀏覽器擴充、2 端側 OCR、3 Android、4 iOS、5 訂閱。依這次盤點建議改成：

| Phase | 原本 | 建議 | 理由 |
|---|---|---|---|
| 0 | 漫畫 pipeline 網頁版 | 不變，但同時定義文字請求格式 | 小說請求格式在 docs/05 §5 已有 |
| 0b | iOS PiP 驗證 | 不變 | 已有 ios-spike |
| 0c（新） | 無 | Android 無障礙讀字驗證，一天 | §3.4 的表決定小說功能範圍，比 iOS PiP 更影響產品定位 |
| 1 | 瀏覽器擴充，小說「順便做」 | 瀏覽器擴充，小說雙語為主要驗收項目，漫畫為次 | 需求 3 要求小說體驗對標沉浸式翻譯，不是附帶 |
| 2 | 端側 OCR 進瀏覽器 | 不變 | |
| 3 | Android 漫畫即時模式為主，小說無障礙為次 | 兩者並列，小說無障礙先做 | 它是差異點，而且比漫畫即時模式簡單 |
| 4 | iOS | 不變，4a 加「截圖捷徑翻小說」與 EPUB 閱讀器 | |
| 5 | 訂閱 | 不變，分層改用 §2.1 的表 | |

## 7. 待你決定的事

1. **Android 小說無障礙路徑升格為主路徑**，是否同意，並排在 Phase 0c 先做一天驗證。
2. **分層採用 §2.1 的四層加 BYOK**，包括新增 Max 層。或維持 Pro 單層。
3. **PC 上不做桌面螢幕 OCR app**，平台閱讀器用網頁版引導。或仍要做一個 Windows／macOS 桌面 app 處理非 DRM 的視窗。
4. **EPUB 匯入與雙語匯出列為 Phase 1 到 4 的正式功能**，還是推到 MVP 之後。
5. **即時模式的優先度**：維持「核心」，或降為 Pro 功能、在小說與截圖捷徑之後。

## 8. 這次新增的參考來源

- Ridi 客服：網頁閱讀器功能說明（提到可搭配瀏覽器翻譯）https://ridihelp.ridibooks.com/support/solutions/articles/154000207690
- Ridi 客服：PC 閱讀器使用方式 https://ridihelp.ridibooks.com/support/solutions/articles/154000204319
- Namu Wiki：Kakao Page 問題點（專用閱讀器作品 PC 不可讀；2022-09 改版）https://namu.wiki/w/카카오페이지/문제점
- Namu Wiki：Naver Series（PC 閱讀器 DRM 黑畫面與剪貼簿）https://en.namu.wiki/w/네이버%20시리즈
- 截圖黑畫面與 FLAG_SECURE 說明（含 Piccoma 付費內容）https://www.wakaran.net/en/articles/cant-take-screenshots-with-your-smartphone-screen-turns-blac
- 沉浸式翻譯會員條款（Pro ¥69 月 20M token；Max ¥199 月 50M 加 2M）https://immersivetranslate.com/zh-Hant/docs/MEMBERSHIP-TERMS/
- 沉浸式翻譯下載中心（v6.3.9，EPUB 目錄級進度）https://immersive-translate.com/download/
- 沉浸式翻譯 iOS app https://apps.apple.com/tw/app/id6447957425
- Android AccessibilityServiceInfoCompat（WebView 無障礙旗標）https://developer.android.com/reference/androidx/core/accessibilityservice/AccessibilityServiceInfoCompat
