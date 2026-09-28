# 建議架構與成本模型

## 1. 設計原則

從 EasyComix 學來的一句話：**看得到圖片的地方做辨識，雲端只收文字，免費層不碰雲端。**

## 2. 三層翻譯引擎

| 層 | 誰能用 | 翻譯引擎 | 你的邊際成本 |
|---|---|---|---|
| L0 離線 | 所有人，無限 | 瀏覽器：Chrome Translator API；Android：ML Kit Translation；iOS：Apple Translation framework | 0 |
| L1 免費 AI | 登入用戶，每日 N 頁（建議 10 到 20 頁） | 最便宜的純文字 LLM（Gemini Flash-Lite 級，或 Claude Haiku 4.5） | 每頁約 US$0.0002 到 0.002 |
| L2 Pro | 付費訂閱 | 較好的模型，加故事背景與詞彙表（Claude Sonnet 5 或同級） | 每頁約 US$0.003 到 0.005 |
| BYOK | 任何人 | 使用者自己的 API key（OpenAI 相容、Anthropic、Gemini） | 0 |

BYOK 是沈浸式翻譯、MangaLens、overlay-translator 都有的功能，對重度用戶和開發者社群很重要，而且完全不花你的錢。

## 3. 系統架構

```
┌──────────── 各平台前端：辨識與排版都在這裡 ────────────────────┐
│ WebExtension          Android app             iOS app             │
│ (Chrome/Edge/         (MediaProjection        (app 內閱讀器 /      │
│  Firefox/Safari)       + 懸浮窗)               捷徑 / PiP)         │
│   找圖或截圖            擷取畫面                 截圖或匯入          │
│   文字偵測 (ONNX)       氣泡偵測                 Vision OCR         │
│   OCR (ONNX/WebGPU)     ML Kit OCR              Apple Translation   │
│   L0 翻譯 (內建 API)    ML Kit 翻譯 (L0)         畫回氣泡            │
│   覆蓋層與擦字          擦字與懸浮窗                                 │
└──────────────────────────┬─────────────────────────────────────┘
                           │ 只傳文字：{page_hash, target, bubbles:[{id, text, lang}]}
                           ▼
┌──────────── 極薄的雲端：Cloudflare Workers，無狀態 ───────────────┐
│ 1. 驗證登入 token（Sign in with Apple / Google；Firebase 或 Supabase 免費層）│
│ 2. 查額度（KV：user_id → 今日已用頁數）                                   │
│ 3. 查共享快取（KV：hash(page_hash + target + tier) → 譯文）                │
│ 4. 未命中才呼叫 LLM（key 只存在伺服器），結果寫回快取                       │
│ 5. 訂閱狀態由 RevenueCat 或商店收據 webhook 更新                            │
└────────────────────────────────────────────────────────────────┘
```

伺服器不存圖片、不做 OCR，所以固定成本接近零，也不會有 GPU 帳單。

### 為什麼不要自架 manga-image-translator 當後端

它是完整的 GPU pipeline（Docker 映像約 15 GB，需要 CUDA 或 ROCm）。一台 GPU 機器每月 US$100 到 300 起跳，而且是固定成本，使用者多少都要付。這是沈浸式翻譯的模式，他們有規模所以划得來，不是獨立開發者的模式。

它的授權是 GPL-3.0：當成獨立服務用 API 呼叫沒問題，但不能把它的程式碼包進閉源 app。它適合拿來在 Phase 0 驗證品質，以及當 Pro 的「高品質整章預翻」後端選項。

### 資料格式

所有平台共用一個 JSON schema，這樣雲端、快取、各前端都不用改：

```json
{
  "page_hash": "phash-of-image-or-screen-region",
  "source_lang": "ja",
  "target_lang": "zh-TW",
  "tier": "L1",
  "context": { "title": "...", "glossary": { "…": "…" } },
  "bubbles": [
    { "id": 0, "box": [x, y, w, h], "text": "原文", "vertical": true }
  ]
}
```

回傳只有 `{ "bubbles": [ { "id": 0, "text": "譯文" } ] }`，用 structured output 強制格式。

## 4. 成本控制清單（依效果排序）

1. **OCR 在端側**：雲端沒有 image token，也沒有 GPU。省最多。
2. **免費層用端側翻譯**：免費用戶邊際成本為零，你可以放心開「無限」。
3. **跨使用者共享快取**：熱門作品同一頁只翻一次。key 用「圖片感知雜湊 + OCR 文字雜湊 + 目標語言 + 層級」。這是 EasyComix 公開資訊裡沒提、但我們一定要做的。
4. **整頁一個請求**：一頁 10 個氣泡打包成一次呼叫，不是 10 次；LLM 有上下文品質也更好。
5. **只翻看到的頁**：逐頁懶翻譯，整章預翻鎖 Pro。
6. **額度綁帳號**：Sign in with Apple 與 Google 登入都免費，額度存 KV；再加裝置指紋防多帳號。
7. **輸出只要 JSON 譯文**：用 structured output，不要模型解釋。output token 是 input 的 4 到 5 倍價錢。
8. **系統提示與詞彙表用 prompt caching**：Anthropic 快取讀取約 0.1 倍 input 價格。故事背景與詞彙表放在快取前綴，每頁只有對白是新的。
9. **Pro 也設合理上限**：例如每月 3,000 頁後降到 L1 模型，避免單一用戶把 API 刷爆。
10. **BYOK**：重度用戶自己付。
11. **無狀態 serverless**：Cloudflare Workers 付費方案 US$5/月起，KV 免費額度夠 MVP。

## 5. 每頁成本試算

假設：一頁漫畫約 10 個氣泡，OCR 後約 200 到 400 字；加上系統提示與詞彙表後 input 約 800 token（其中 500 可快取），output 約 250 token。

| 模型 | Input US$/M | Output US$/M | 每頁（無快取） | 每頁（前綴命中快取） | 1,000 頁 |
|---|---|---|---|---|---|
| Gemini 2.5 Flash-Lite（第三方整理，請以官方為準） | 0.10 | 0.40 | 0.00018 | 約 0.00015 | 0.18 |
| Claude Haiku 4.5 | 1.00 | 5.00 | 0.0021 | 0.0016 | 2.1 |
| Claude Sonnet 5 | 2.00 | 10.00 | 0.0041 | 0.0032 | 4.1 |
| Claude Opus 5.5 | 4.00 | 20.00 | 0.0082 | 0.0064 | 8.2 |
| Claude Opus 5 | 5.00 | 25.00 | 0.0103 | 0.0080 | 10.3 |
| 改送整張圖片（vision） | | | 每頁多 260 到 1,600 input token，且文字快取失效 | | 約 2 到 4 倍 |

Anthropic 價格來自本工作階段內載入的官方價目表（2026-06 快取）。Gemini 價格來自第三方整理，上線前請查官方頁面。

## 6. 每位使用者每月成本

| 使用者類型 | 頁數/月 | Flash-Lite 級 | Haiku 4.5 | Sonnet 5 |
|---|---|---|---|---|
| 免費，只用 L0 離線 | 任意 | 0 | 0 | 0 |
| 免費，L1 每日 10 頁全用滿 | 300 | 0.05 | 0.6 | |
| 免費，L1 實際平均（約 3 成用滿） | 約 100 | 0.02 | 0.2 | |
| Pro 一般（每天一章） | 600 | | 1.2 | 2.5 |
| Pro 重度（每天三章） | 1,800 | | 3.7 | 7.4 |
| Pro 上限（3,000 頁後降級） | 3,000 | | 6.2 | 12.3 |

以上用無快取數字，是保守估計。共享快取命中率做到 30 到 50%（熱門作品很容易），數字再打 5 到 7 折。

## 7. 定價建議

| 方案 | 建議價（US$） | 理由 |
|---|---|---|
| 免費 | 0 | 離線無限，登入後每日 10 頁 AI |
| Pro 週 | 1.99 | 追完一部就走的人；EasyComix 也有週訂 |
| Pro 月 | 4.99 | 比沈浸式翻譯（約 8 到 9）便宜，比 Sumi（6.99 換 1,500 頁）便宜 |
| Pro 年 | 29.99 | 折合每月 2.5 |

損益：Pro 月費 4.99，扣掉商店抽成 30%（小型開發者計畫 15%）後約 3.5 到 4.2。一般 Pro 用戶用 Sonnet 5 的成本約 2.5，重度用戶會虧。所以「3,000 頁後降級」和共享快取不是選配，是必要。

如果 Pro 預設用 Haiku 4.5、只有「故事背景模式」才切到 Sonnet 5，重度用戶也能維持正毛利。

## 8. 固定成本

| 項目 | 費用 |
|---|---|
| Apple Developer Program | US$99/年 |
| Google Play 開發者 | US$25 一次 |
| Chrome Web Store | US$5 一次 |
| Cloudflare Workers 付費 | US$5/月 |
| 網域 | 約 US$10/年 |
| Firebase 或 Supabase 認證 | 免費層 |
| RevenueCat | 免費至每月 2,500 美元收入 |
| 合計 | 約 US$200 第一年，加每月 US$5 |

## 9. 免費層可以開多大

每日 10 頁 L1、Flash-Lite 級模型、10,000 個活躍免費用戶、3 成用滿：10,000 × 0.02 = 每月約 US$200。改用 Haiku 4.5 則約 US$2,000。

這就是為什麼免費層的 LLM 一定要用最便宜的模型，品質好的留給 Pro。

## 10. 授權注意

| 元件 | 授權 | 能否包進閉源 app |
|---|---|---|
| manga-ocr（kha-white） | Apache-2.0 | 可以 |
| comic-text-detector（dmMaze） | GPL-3.0 | 不行，要換或自訓，或只當獨立服務 |
| manga-image-translator（zyddnys） | GPL-3.0 | 不行，同上 |
| PaddleOCR、PP-OCRv5 | Apache-2.0 | 可以 |
| ML Kit | Google 條款 | 可以 |
| overlay-translator（ciddwd） | Apache-2.0 | 可以 |
| MangaLens（mkisontop） | MIT | 可以 |
| YOLO 氣泡偵測模型（ogkalu 等） | 各自不同，Ultralytics 系多為 AGPL | 逐一確認 |

如果自己的專案要開源，選 GPL 就沒有這些問題；如果要閉源賣訂閱，偵測模型要避開 GPL 與 AGPL。

## 11. 加入小說後，額度要改用 token 計

一章小說約 5,000 token 輸入、3,500 token 輸出，是一頁漫畫的十倍以上。若沿用「每日 10 頁」這種計法，小說讀者會把 API 刷爆。

- 免費層：L0 端側翻譯無限；L1 每月固定 token 額度（例如 300K token，約 300 頁漫畫或 35 章小說）。
- Pro：每月 token 額度（例如 5M token），預設走便宜模型；切到高品質模型時同一內容扣 3 到 4 倍額度。
- 漫畫與小說共用同一個額度，前端在送出前先估 token 數，超額時提示或降級到 L0。
- 整本預翻走 Batch API，標準價的一半，鎖在 Pro。

每章成本試算、共享快取與段落級快取的做法見 [05-novels.md](05-novels.md)。

## 12. 即時模式不會增加雲端成本，只要做對四件事

即時模式讓端側 OCR 跑得更頻繁，但那是免費的。LLM 呼叫次數靠這四件事壓住：畫面靜止才處理、文字雜湊去重、L0 草稿加 LLM 潤稿的兩段式、300 ms 合併視窗。免費用戶的即時模式只給 L0，雲端成本為零；Pro 才有 LLM 潤稿。細節見 [06-live-mode.md](06-live-mode.md) 第 4 節。
