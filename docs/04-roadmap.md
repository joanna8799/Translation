# MVP 路線圖

原則：先驗證「翻譯品質夠不夠好」，再擴平台，最後才做最難的 iOS PiP。

## Phase 0：核心 pipeline 與網頁版（2 到 3 週）

- 目標：上傳一頁，回傳翻好的圖。驗證 OCR 與翻譯品質。
- 技術：現成模型跑在伺服器（Python：PP-OCRv5 或 manga-ocr，加你選的 LLM），前端一個上傳頁。可以直接用 manga-image-translator 的 web server 當對照組。
- 產出：pipeline 的介面定義（bubbles JSON schema），之後所有平台共用。
- 驗收：日文直式、韓文條漫、簡中各 20 頁，人工評分。

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
- 氣泡偵測先用像素法，再視需要加 TFLite 模型。
- 小說：AccessibilityService 讀文字節點，讀不到退到 OCR；整頁翻譯面板。
- 共用同一個雲端 LLM proxy 與帳號系統。

## Phase 4：iOS（4 到 6 週）

- 順序：截圖捷徑跨 app 翻譯（EasyComix 主打模式，最容易）與 app 內閱讀器（貼網址追更小說、匯入 EPUB 與 CBZ）一起做，兩者共用同一套辨識與排版程式碼；再 Safari 擴充；PiP Live Captions 最後，甚至可以不做。
- Vision OCR 與 Apple Translation framework 當 L0。
- 如果決定走 EasyComix 的路，這個階段可以提前到 Phase 0 之後，因為截圖捷徑不需要瀏覽器擴充的任何東西。

## Phase 5：Pro 訂閱與營運

- RevenueCat 串 App Store、Play、Stripe（擴充版用 Stripe 或授權碼）。
- Pro token 額度、高品質模式加倍扣額、降級、BYOK。
- 整本預翻走 Batch API。
- 用量與成本儀表板：每日 LLM 花費、快取命中率、每用戶頁數。

## 風險

| 風險 | 影響 | 對策 |
|---|---|---|
| 版權：使用者拿來看盜版 | 商店審核、法律 | 文案定位為「翻譯你正在看的內容」，不內建任何來源、不推薦網站 |
| FLAG_SECURE 的 app 抓不到畫面 | Android 功能失效 | FAQ 明講，提供截圖路徑 |
| Apple 對 ReplayKit 與 PiP 用途審核 | iOS Live Captions 可能被拒 | 最後做，先有其他價值 |
| 免費額度被刷 | LLM 帳單 | 登入、裝置指紋、異常偵測、每日硬上限 |
| 模型價格變動 | 毛利 | 供應商抽象層隨時可換；Pro 有上限 |
| 瀏覽器內建翻譯 API 只在桌面 | 手機瀏覽器免費層要走雲端 | 手機用戶導到 Android app 或 iOS app 的端側引擎；手機瀏覽器版限額 |
| 端側模型下載體積 | 首次體驗差 | 分語言按需下載，先給雲端結果再切端側 |
