# 全平台漫畫與小說翻譯：可行性評估與架構草案

目標：做一款像 EasyComix 那樣「在你原本的閱讀環境裡就地翻譯漫畫與小說」的產品，
但採用沈浸式翻譯的鋪法：所有瀏覽器都能裝、手機上任何 app 內的內容都能翻。

目前內容：評估文件（docs/）與 iOS 即時模式技術驗證專案（ios-spike/，Phase 0b，尚未在 Xcode 編譯過）。
另附一份獨立的旅行即時對話翻譯評估（docs/07）與對應的技術驗證專案（ios-talk-spike/），回答「出國時用 iPhone 加一般耳機自己做即時口譯」怎麼做。

## 文件索引

| 文件 | 內容 |
|---|---|
| [docs/01-easycomix-cost-analysis.md](docs/01-easycomix-cost-analysis.md) | EasyComix 拆解：免費／Pro 分層、六個成本控制手法、與沈浸式翻譯的比較 |
| [docs/02-platform-feasibility.md](docs/02-platform-feasibility.md) | 全平台可行性：瀏覽器擴充、Android、iOS、桌面，哪些做得到、哪些只能折衷；為什麼 EasyComix 只做 iOS |
| [docs/03-architecture-and-cost-model.md](docs/03-architecture-and-cost-model.md) | 建議架構、三層翻譯引擎、每頁／每用戶成本試算、定價、授權注意 |
| [docs/04-roadmap.md](docs/04-roadmap.md) | MVP 路線圖與風險 |
| [docs/05-novels.md](docs/05-novels.md) | 小說：三種來源的做法、token 計費的成本模型、小說專屬省錢手法 |
| [docs/06-live-mode.md](docs/06-live-mode.md) | 即時模式（捲動自動更新）：Android 就地覆蓋與 iOS 廣播加 PiP 的完整設計、內容保護的限制、即時模式的成本控制、先做的技術驗證 |
| [docs/07-travel-conversation.md](docs/07-travel-conversation.md) | 旅行即時對話翻譯（與漫畫無關）：iPhone 17 無 AI 耳機的五種方案比較、設備需求、出發前設定步驟、幣值轉換、自製 app 的架構與工作量評估 |
| [docs/references.md](docs/references.md) | 所有參考來源 |
| [ios-spike/README.md](ios-spike/README.md) | iOS 即時模式技術驗證專案：廣播擴充加 PiP 的最小實作、五項驗證的操作步驟、結果記錄表 |
| [ios-talk-spike/README.md](ios-talk-spike/README.md) | 旅行即時口譯技術驗證專案：用一般耳機（不需 AirPods）做雙向語音翻譯，iOS 26 端側語音辨識加翻譯，五項驗證與結果記錄表 |

## 一頁結論

**EasyComix 怎麼控制成本**

1. 免費層完全在裝置上跑：自訓的漫畫 OCR 模型 + iOS 系統翻譯框架，所以「無限離線翻譯」對開發者是零邊際成本。
2. 唯一會花錢的是 LLM，所以只有它被限額：登入後每日 10 次，Pro 才無限。
3. 雲端只收 OCR 後的文字，不收圖片，每頁成本壓低一個數量級。
4. 逐頁翻（捲到哪翻到哪），整章預翻鎖 Pro，不浪費沒看到的頁。
5. 週／月／年訂閱把 LLM 支出變成可預測的收入；週訂抓「追完就走」的人。
6. 只要功能會花伺服器錢或很難做，就放進 Pro；免費層只放邊際成本為零的東西。

**EasyComix 怎麼在 iOS 上做到「在別人的 app 上翻譯」**

他主打的模式是截圖加捷徑：在任何 app 看漫畫時用背面輕點、動作按鈕、AssistiveTouch 或 Siri 觸發，iOS 截圖交給 EasyComix，端側偵測氣泡、OCR、翻譯、畫回氣泡，翻好的整頁顯示在原 app 上方，滑掉繼續看下一頁。
這條路在 iOS 上容易做、沒有審核風險，是 iOS 上「任何 app 內」的正解，只是每頁要按一下。
另外他有自家閱讀器（貼網址、匯入 PDF/CBZ、相簿選圖）和 Pro 限定的 Live Captions（背景錄影加子母畫面字幕條，即時但只能顯示字幕）。

**本專案的目標是「捲動就自動更新」的即時模式**

| | Android | iOS |
|---|---|---|
| 做得到嗎 | 做得到，就地覆蓋在氣泡上 | 做得到自動更新，但顯示在浮動的子母畫面視窗裡（字幕或翻好的區域鏡像），不是就地 |
| 機制 | 螢幕擷取加懸浮窗 | ReplayKit 廣播擷取加 PiP，EasyComix Live Captions 的做法 |
| 難度 | 中 | 高，要先做 1 到 2 週技術驗證 |
| 擋得住的 app | 設 FLAG_SECURE 的 app 黑畫面 | 偵測到錄影就遮內容的 app；截圖捷徑仍可用當備案 |

細節見 docs/06。iOS 上真正「就地又自動」只有 Safari 擴充（網頁內容），原生 app 只能 PiP。

**「全平台」實際做得到的範圍**

| 你要的 | 能做到的 |
|---|---|
| 所有瀏覽器 | 可以。一份 WebExtension 出 Chrome、Edge、Firefox、Safari 桌面版，再包成 iOS Safari 擴充。網頁小說在這一層幾乎是免費附送。 |
| 手機任何 app 內，自動更新 | Android 可以，就地覆蓋。iOS 可以，但在 PiP 浮動視窗裡顯示；截圖捷徑當所有 app 都能用的備案。 |
| 就地把氣泡換成中文 | 瀏覽器可以、Android 可以、iOS 只在 Safari 擴充、自家閱讀器與截圖捷徑裡可以，PiP 視窗裡是鏡像不是就地。 |

**建議架構的一句話**：看得到內容的地方做辨識，雲端只收文字，免費層不碰雲端。

**成本量級**（純文字送 LLM）

| 內容 | 每單位 token | Flash-Lite 級 | Claude Haiku 4.5 | Claude Sonnet 5 |
|---|---|---|---|---|
| 一頁漫畫（約 10 個氣泡） | 約 800 進 / 250 出 | US$0.0002 | US$0.002 | US$0.004 |
| 一章小說 | 約 5,000 進 / 3,500 出 | US$0.002 | US$0.023 | US$0.045 |

一章小說是一頁漫畫的十倍以上，所以額度要用「每月 token 數」計，不能用頁數。
固定成本第一年約 US$200（開發者帳號）加每月 US$5（serverless）。細節見 docs/03 與 docs/05。

## 關於資料來源

Threads 貼文本身無法從這個工作環境讀取（網路白名單擋住 threads.com），
EasyComix 的資訊來自 App Store 頁面摘要、官網摘要與第三方整理。
文中標示「推測」的部分是根據公開資訊的推論，不是開發者本人證實的。
