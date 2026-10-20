# ReadTrans 瀏覽器擴充：打開小說或漫畫網頁就自動翻

沉浸式翻譯的鋪法。裝好之後不用按任何東西：

- 小說網頁（なろう、カクヨム、Munpia、Naver Series 網頁版、Ridi 網頁閱讀器…）：韓文、日文的段落下面自動接上中文，雙語對照。
- 漫畫網頁：看到的每一張圖自動偵測對話框、在瀏覽器裡 OCR、翻譯、把譯文畫回氣泡，疊在原圖上。點一下疊圖看原圖，再點一下看譯圖。
- 圖片不離開瀏覽器，只有文字送去翻譯。

## 安裝

**電腦 Chrome／Edge／Brave**

1. 下載 repo（Code → Download ZIP）解壓，或 `git clone`。
2. 開 `chrome://extensions`，右上角打開「開發人員模式」，按「載入未封裝項目」，選 `extension/` 資料夾。
3. 工具列會出現「譯」的圖示。預設「所有網站自動翻譯」已開，直接去開一個小說或漫畫網頁。

**Android**

Chrome 不能裝擴充。用 Kiwi Browser 或 Microsoft Edge（Android 版有擴充功能）：把 `extension/` 打包成 zip 傳到手機，在 Kiwi 的 `chrome://extensions` 用「+(from .zip)」載入；Edge Android 在 設定 → 擴充功能 載入。

**iPhone**：Safari 擴充要用 Xcode 包成 app，排在後面做。

## 翻譯引擎

| 引擎 | 要什麼 | 品質 |
|---|---|---|
| Google 翻譯公開端點（預設） | 不用 key | 看得懂 |
| Gemini | 自備 API key（aistudio.google.com 免費申請） | 好，會依上下文修 OCR 錯字 |
| OpenAI 相容端點 | 端點加 key | 依模型 |

在圖示 → 設定 裡切換。這三個就是 docs/03 說的 L0、L1、BYOK 三層；之後我們自己的 proxy 也走 OpenAI 相容端點這一格。

## 漫畫的限制（這一版）

- 對話框偵測是像素法：白底、有框、夠大的氣泡才抓得到；無框對白、花俏氣泡會漏。
- OCR 是 Tesseract 的 fast 模型：印刷體日文直書、韓文可以，手寫體與特效字會錯。設定裡要選對「漫畫原文」（日文直式／橫式／韓文）。
- 第一張圖要等 OCR 引擎載入（約 2 到 5 秒），之後每張約 1 到 3 秒。

這兩個零件在產品版會換成偵測模型與 manga-ocr，流程與格式不變。

## 結構

```
manifest.json          MV3
background.js          翻譯引擎（gtx / Gemini / OpenAI 相容）、跨網域抓圖、offscreen OCR 轉接
offscreen/             tesseract.js 在這裡跑（service worker 不能開 Worker）
content/common.js      氣泡偵測、擦字排版、訊息
content/novel.js       段落偵測、批次翻譯、雙語注入、動態內容補翻
content/manga.js       圖片觀察、OCR、疊圖、捲動跟隨、換圖重翻
content/main.js        自動翻譯判斷、popup 指令
popup/、options/       開關與設定
vendor/tesseract/      tesseract.js 5.1.1、core wasm、jpn / jpn_vert / kor 語言檔（21 MB）
```
