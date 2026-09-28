# MVP 路線圖

原則：先驗證「翻譯品質夠不夠好」，再擴平台。即時模式是本專案的核心，Android 在 Phase 3 直接做就地覆蓋，iOS 的 PiP 即時模式提前做技術驗證（Phase 0 可並行），驗證通過才進 Phase 4。

## Phase 0：核心 pipeline 與網頁版（2 到 3 週）

- 目標：上傳一頁，回傳翻好的圖。驗證 OCR 與翻譯品質。
- 技術：現成模型跑在伺服器（Python：PP-OCRv5 或 manga-ocr，加你選的 LLM），前端一個上傳頁。可以直接用 manga-image-translator 的 web server 當對照組。
- 產出：pipeline 的介面定義（bubbles JSON schema），之後所有平台共用。
- 驗收：日文直式、韓文條漫、簡中各 20 頁，人工評分。

## Phase 0b（並行）：iOS 即時模式技術驗證（1 到 2 週）

- 一個最小 Xcode 專案：Broadcast Upload Extension 加 PiP，不做任何產品 UI。程式碼在 [ios-spike/](../ios-spike/README.md)，用 XcodeGen 產生專案。
- 驗證五件事：擴充在 50 MB 內跑 Vision OCR 的穩定度；PiP 讓主 app 背景存活 10 分鐘以上；Translation framework 在背景能否翻；目標 app（Kakao Page、Naver Series、Piccoma、LINE Manga、Webtoon）錄影時是否黑掉；端到端延遲。
- 結果決定 iOS 即時模式的產品形態（字幕、鏡像、或只能做部分 app）。清單見 [06-live-mode.md](06-live-mode.md) 第 5 節。

## Phase 1：瀏覽器擴充（3 到 4 週）

- MV3，Chrome 與 Edge 先上，Firefox 與 Safari 隨後。
- 找圖：DOM 路加截圖 fallback，不做網站白名單。
- OCR：先雲端（重用 Phase 0），量測每頁延遲與成本。
- 翻譯：Chrome Translator API 當 L0，雲端 LLM 當 L1。
- 覆蓋層：絕對定位方塊版。
- 網頁小說：找正文容器、逐段翻、雙語對照。文字翻譯比漫畫簡單，在這一階段順便做。
- 帳號、token 額度、共享快取上線。

## Phase 2：端側 OCR 搬進瀏覽器（2 到 3 週）

- onnxruntime-web 加 WebGPU，模型量化到 50 MB 以下。
- 免費層邊際成本歸零，伺服器只剩 LLM proxy。

## Phase 3：Android（4 到 6 週）

- 參考 overlay-translator 與 MangaLens 的架構，兩者都可商用。
- MediaProjection、前景服務、懸浮窗；ML Kit OCR 與 ML Kit 翻譯當 L0。
- 即時模式：靜止偵測、文字雜湊去重、L0 草稿加 LLM 潤稿兩段式、捲動時清覆蓋層。設計見 [06-live-mode.md](06-live-mode.md) 第 1 節。
- 氣泡偵測先用像素法，再視需要加 TFLite 模型。
- 小說：AccessibilityService 讀文字節點，讀不到退到 OCR；整頁翻譯面板。
- 共用同一個雲端 LLM proxy 與帳號系統。

## Phase 4：iOS（6 到 8 週）

- 4a：截圖捷徑跨 app 翻譯與 app 內閱讀器（貼網址追更小說、匯入 EPUB 與 CBZ）一起做，共用同一套辨識與排版程式碼。截圖捷徑是所有 app 都能用的備案，內容保護擋不住它。
- 4b：即時模式，廣播擷取加 PiP，先做字幕模式，再視回饋加鏡像模式。以 Phase 0b 的驗證結果為準。設計見 [06-live-mode.md](06-live-mode.md) 第 2 節。
- 4c：Safari 擴充，iOS 上唯一「就地又自動」的路，給網頁內容。
- Vision OCR 與 Apple Translation framework 當 L0。
- 如果 iOS 是首要平台，4a 與 4b 可以提前到 Phase 0 與 0b 之後，不需要等瀏覽器擴充。

## Phase 5：Pro 訂閱與營運

- RevenueCat 串 App Store、Play、Stripe（擴充版用 Stripe 或授權碼）。
- Pro token 額度、高品質模式加倍扣額、降級、BYOK。
- 整本預翻走 Batch API。
- 用量與成本儀表板：每日 LLM 花費、快取命中率、每用戶頁數。

## 風險

| 風險 | 影響 | 對策 |
|---|---|---|
| 版權：使用者拿來看盜版 | 商店審核、法律 | 文案定位為「翻譯你正在看的內容」，不內建任何來源、不推薦網站 |
| 內容保護：Android FLAG_SECURE 黑畫面、iOS 偵測錄影後遮內容 | 即時模式在部分正版平台上失效 | Phase 0b 逐一實測目標 app，宣傳只列實測可用的；iOS 保留截圖捷徑當備案 |
| Apple 對 ReplayKit 與 PiP 用途審核 | iOS 即時模式可能被拒 | 同類 app 已上架多款；用系統的廣播選擇器由使用者手動啟動，不自動錄 |
| iOS 擴充 50 MB 記憶體、PiP 保活、背景翻譯 | iOS 即時模式做不出來或不穩 | Phase 0b 先驗證，失敗則退到字幕模式或只支援部分 app |
| PiP 視窗被錄進擷取畫面（自我迴圈） | 譯文疊譯文 | 使用者先框選區域；PiP 影格畫辨識用細框，擴充遮掉 |
| 免費額度被刷 | LLM 帳單 | 登入、裝置指紋、異常偵測、每日硬上限 |
| 模型價格變動 | 毛利 | 供應商抽象層隨時可換；Pro 有上限 |
| 瀏覽器內建翻譯 API 只在桌面 | 手機瀏覽器免費層要走雲端 | 手機用戶導到 Android app 或 iOS app 的端側引擎；手機瀏覽器版限額 |
| 端側模型下載體積 | 首次體驗差 | 分語言按需下載，先給雲端結果再切端側 |
