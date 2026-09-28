# 全平台可行性：哪些做得到、哪些只能折衷

目標拆成三層：

- A. 所有桌面瀏覽器都能裝（沈浸式翻譯的鋪法）
- B. 手機瀏覽器
- C. 手機上「任何 app 內」的漫畫都能翻

## 0. 總表

| 平台 | 做得到嗎 | 做法 | 主要限制 |
|---|---|---|---|
| Chrome、Edge、Brave、Arc（桌面） | 可以 | WebExtension MV3 | 跨網域圖片要用 host_permissions 抓 bytes |
| Firefox（桌面） | 可以 | 同一份 WebExtension | WebGPU 支援較晚，端側 OCR 可能退到 WASM |
| Safari（macOS） | 可以 | Safari Web Extension（Xcode 包裝同一份程式碼） | 要付 Apple 開發者費、要上 App Store |
| Safari（iOS、iPadOS） | 可以，只限 Safari 內 | Safari Web Extension | 手機 Safari 記憶體限制嚴，端側 OCR 要很小 |
| Android 瀏覽器 | 部分 | Kiwi、Firefox Android、Edge Android 支援擴充 | 用 Chrome 的人裝不了；可由 Android app 覆蓋 |
| Android 任何 app 內 | 可以，唯一真正做得到的 | MediaProjection 螢幕擷取 + 前景服務 + 懸浮窗 | 每次開始要按一次系統對話框；FLAG_SECURE 的 app 抓到黑畫面 |
| iOS 任何 app 內 | 折衷 | 截圖捷徑或分享至 app；ReplayKit 廣播擷取 + 子母畫面字幕條 | iOS 不允許覆蓋在其他 app 上；擴充只有 50 MB 記憶體 |
| Windows、macOS 任何視窗 | 可以 | 桌面 app 擷取螢幕區域 + 覆蓋層 | 優先度低 |
| 純網頁版（上傳或貼網址） | 可以 | 任何裝置都能用的最後手段 | 沒有「就地」體驗 |

## 1. 瀏覽器擴充（A 與 B）

一份 WebExtension 程式碼可以同時出 Chrome、Edge、Firefox、Safari 版，這正是沈浸式翻譯的做法。

### 1.1 找到圖片的兩條路

1. DOM 路：content script 掃 `<img>`、`<canvas>`、CSS background-image，用 IntersectionObserver 只處理進入視窗的圖。沈浸式翻譯只支援白名單網站，就是因為每個漫畫站的 DOM、懶載入、圖片切片或打亂方式都不同，通用處理會漏。
2. 截圖路：用 `tabs.captureVisibleTab` 直接截整個分頁畫面，OCR 後把覆蓋層畫在 viewport 座標上。這條路對任何網站都有效，包括 canvas 打亂的閱讀器。代價是捲動時要重新截圖，覆蓋層不會跟著圖片捲動。

建議：DOM 路當預設、截圖路當 fallback，就不需要維護網站白名單。

### 1.2 跨網域圖片

content script 的 canvas 讀不到跨網域圖片的像素（tainted canvas）。解法是 background service worker 用 `host_permissions: ["<all_urls>"]` 去 fetch 圖片 bytes。商店審核會問「為什麼要所有網站的權限」，沈浸式翻譯一樣有這個權限，說明用途即可。

### 1.3 OCR 跑在哪

- 端側：onnxruntime-web，WebGPU 可用時走 GPU，否則退到 WASM。PP-OCRv5 mobile 的 ONNX 模型：偵測約 84 MB、韓文辨識約 13 MB、中日辨識約 81 MB、英文約 7.5 MB。manga-ocr（日文直式最強）ONNX 約 400 MB，對瀏覽器太大，要用 mobile 版或量化版。第一次使用要下載模型，之後快取在 extension storage。
- 雲端：最簡單、開發最快，但每頁都有伺服器成本，而且要上傳圖片。
- 建議：MVP 先雲端 OCR，快速驗證品質；第二階段搬到端側，讓免費層邊際成本歸零。

### 1.4 翻譯跑在哪

- Chrome 138 以上桌面版有內建 Translator API 與 Language Detector API（Gemini Nano，端側、免費、不需要 key），擴充可以直接呼叫，50 種以上語言。限制：桌面限定（Windows、macOS、Linux、ChromeOS），機器需要 4 GB VRAM 的 GPU 或 16 GB RAM 加 4 核 CPU，模型第一次用才下載。Edge 148 起也支援 Language Detector。
- Firefox 有內建翻譯但沒開 API 給擴充，退到雲端或額度制。
- 這表示瀏覽器版也可以有「免費無限離線翻譯層」，跟 EasyComix 一樣。

### 1.5 覆蓋層怎麼畫

- 簡單版：在圖片上用絕對定位的 `<div>` 蓋白底方塊加譯文，不動原圖。
- 進階版：把圖片複製到 canvas，用「取氣泡內部顏色填滿」的方法擦掉原文（MangaLens 的做法，不需要 inpainting 模型），再用 canvas 排版譯文。LaMa 這類 inpainting 模型在瀏覽器裡太重，MVP 不要碰。

## 2. Android「任何 app 內」（C）

這是三個目標裡最能完整做到的。已經有開源專案證明可行，而且授權允許商業使用：

| 專案 | 授權 | 擷取 | OCR | 翻譯 | 值得學的地方 |
|---|---|---|---|---|---|
| ciddwd/overlay-translator | Apache-2.0 | MediaProjection 或 Shizuku | ML Kit、PaddleOCR、manga-ocr（端側）加雲端選項 | 端側 Sakura、Hy-MT2、ML Kit 加各家 LLM | 引擎抽象層設計；Shizuku 免每次授權 |
| mkisontop/MangaLens | MIT | MediaProjection，畫面靜止約 150 ms 才觸發 | ML Kit（韓、日、中） | Google 免費引擎加 BYOK LLM | 像素法找氣泡；用氣泡自己的紙色擦字；整頁一次送 LLM；氣泡快取 |
| Yuu18id/manga-image-translator-android | 需確認 | 匯入圖片 | ONNX（comic-text-detector 加 manga-ocr） | LLM | 證明 manga-image-translator 的模型可在手機端跑 |

### 2.1 技術要點

- Android 14 以上：MediaProjection 必須在 `foregroundServiceType="mediaProjection"` 的前景服務內啟動，manifest 要宣告 `FOREGROUND_SERVICE` 與 `FOREGROUND_SERVICE_MEDIA_PROJECTION`。每次新 session 使用者都要按一次系統對話框，token 不能跨啟動快取。
- Android 15 QPR1 以上：狀態列會有「正在擷取螢幕」的晶片，鎖屏會自動停止。Android 15 也不允許從 BOOT_COMPLETED 啟動 mediaProjection 前景服務。
- 懸浮窗需要 `SYSTEM_ALERT_WINDOW`（「顯示在其他應用程式上層」）。
- OCR：ML Kit Text Recognition v2 端側支援中、日、韓、拉丁，免費，最省事的起點。日文直式漫畫字型再補 manga-ocr ONNX（約 140 MB）給講究品質的用戶選配下載。
- 翻譯：ML Kit Translation 端側 58 種語言，免費，當免費層；LLM 走額度或 Pro。
- 硬限制：`FLAG_SECURE` 的 app（部分正版漫畫平台、銀行 app、影音 app）擷取到的是黑畫面，無解，要在 FAQ 講清楚。
- Play 商店政策：螢幕擷取加懸浮窗的 app 審核會要求說明用途，文案不能暗示盜版。
- 部分廠牌 ROM 會殺背景服務或擋懸浮窗，需要引導使用者關閉電池最佳化。

## 3. iOS「任何 app 內」（C）

iOS 不允許任何 app 畫在別的 app 上面，也不允許背景即時讀取別的 app 畫面。所以「在原本的 app 裡把氣泡就地換成中文」在 iOS 上做不到，EasyComix 也做不到，他用兩個折衷。

### 3a. 系統捷徑或分享至 app（EasyComix 的「system-wide iOS Shortcut」）

使用者截圖，捷徑或分享表單把圖丟給我們的 app，app 短暫跳到前景顯示翻譯好的整頁，再返回。體驗是兩步，但簡單穩定，任何 app 都適用，也不會有審核風險。

### 3b. ReplayKit 廣播擷取加子母畫面字幕（EasyComix 的「Live Captions」）

- Broadcast Upload Extension 可以在背景擷取整個螢幕，這是系統錄影與直播用的機制。
- 擴充程序只有 50 MB 記憶體上限，超過就被殺。所以只能跑很小的 OCR，或用系統的 Vision framework（`VNRecognizeTextRequest`，支援中、日、韓，但直式文字支援仍不穩，需要實測）。
- 顯示端用 Picture-in-Picture 視窗。PiP 只能播「影片」，所以要把譯文畫成影格塞進 `AVSampleBufferDisplayLayer`。這就是為什麼 EasyComix 的 Live Captions 是一個浮動字幕條，而不是就地替換氣泡。
- 使用者要先框選一個區域，之後在自己的閱讀 app 裡捲動，字幕條跟著更新。
- 這是整個計畫裡技術風險最高的一塊，Apple 審核對 ReplayKit 的用途也會盤問。建議放到最後做，先做 3a 與 Safari 擴充。

### 3c. Safari Web Extension

給用 Safari 看網頁漫畫的人，就地翻譯，跟桌面版共用程式碼。手機 Safari 擴充的記憶體有限，端側 OCR 要用最小的模型，或走雲端。

### 3d. App 內閱讀器

匯入圖片、CBZ、貼網址，在自己的 app 裡看。這是唯一能在 iOS 上做到「畫回氣泡」的方式，EasyComix 的主體也是這個。OCR 用 Vision framework，翻譯用 Apple Translation framework，兩者都免費、離線。

## 4. 「全平台」的實際定義

| 你要的 | 能給的 |
|---|---|
| 所有瀏覽器 | 一份 WebExtension 出 Chrome、Edge、Firefox、Safari 桌面版，加 iOS Safari，加 Android 第三方瀏覽器 |
| 手機任何 app 內 | Android 真正的懸浮覆蓋；iOS 用截圖捷徑（穩）加 PiP 字幕條（難） |
| 就地畫回氣泡 | 瀏覽器可以、Android 可以、iOS 只在自家 app 內可以 |

先接受這個差異，再決定要不要投資 iOS 的 PiP 字幕。
