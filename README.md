# 全平台漫畫與小說翻譯：可行性評估與架構草案

目標：做一款像 EasyComix 那樣「在你原本的閱讀環境裡就地翻譯漫畫與小說」的產品，
但採用沈浸式翻譯的鋪法：所有瀏覽器都能裝、手機上任何 app 內的內容都能翻。

這個 repo 目前只有評估文件，尚未開始寫程式。

## 文件索引

| 文件 | 內容 |
|---|---|
| [docs/01-easycomix-cost-analysis.md](docs/01-easycomix-cost-analysis.md) | EasyComix 拆解：免費／Pro 分層、六個成本控制手法、與沈浸式翻譯的比較 |
| [docs/02-platform-feasibility.md](docs/02-platform-feasibility.md) | 全平台可行性：瀏覽器擴充、Android、iOS、桌面，哪些做得到、哪些只能折衷；為什麼 EasyComix 只做 iOS |
| [docs/03-architecture-and-cost-model.md](docs/03-architecture-and-cost-model.md) | 建議架構、三層翻譯引擎、每頁／每用戶成本試算、定價、授權注意 |
| [docs/04-roadmap.md](docs/04-roadmap.md) | MVP 路線圖與風險 |
| [docs/05-novels.md](docs/05-novels.md) | 小說：三種來源的做法、token 計費的成本模型、小說專屬省錢手法 |
| [docs/references.md](docs/references.md) | 所有參考來源 |

## 一頁結論

**EasyComix 怎麼控制成本**

1. 免費層完全在裝置上跑：自訓的漫畫 OCR 模型 + iOS 系統翻譯框架，所以「無限離線翻譯」對開發者是零邊際成本。
2. 唯一會花錢的是 LLM，所以只有它被限額：登入後每日 10 次，Pro 才無限。
3. 雲端只收 OCR 後的文字，不收圖片，每頁成本壓低一個數量級。
4. 逐頁翻（捲到哪翻到哪），整章預翻鎖 Pro，不浪費沒看到的頁。
5. 週／月／年訂閱把 LLM 支出變成可預測的收入；週訂抓「追完就走」的人。
6. 只要功能會花伺服器錢或很難做，就放進 Pro；免費層只放邊際成本為零的東西。

**EasyComix 只做 iOS，為什麼文件說 iOS 最難**

這是兩件事。EasyComix 的主體是「自家 app 內的閱讀器」，這在 iOS 上是最容易的：Apple 免費提供端側 OCR 與端側翻譯，機型單純，使用者願意付費。
難的是「在別的 app 裡面翻」：iOS 不允許任何 app 畫在其他 app 上面，EasyComix 的 Live Captions（背景錄影加子母畫面字幕條）和截圖捷徑都是折衷，不是就地換氣泡。
Android 剛好相反，跨 app 覆蓋很直接。要走 EasyComix 的路就 iOS 自家閱讀器先做；「任何 app 內」是核心賣點就 Android 先做。

**「全平台」實際做得到的範圍**

| 你要的 | 能做到的 |
|---|---|
| 所有瀏覽器 | 可以。一份 WebExtension 出 Chrome、Edge、Firefox、Safari 桌面版，再包成 iOS Safari 擴充。網頁小說在這一層幾乎是免費附送。 |
| 手機任何 app 內 | Android 可以，漫畫用螢幕擷取 + 懸浮窗，小說多一條 AccessibilityService 直接讀文字的路。iOS 只能用「截圖捷徑」或「子母畫面字幕條」折衷。 |
| 就地把氣泡換成中文 | 瀏覽器可以、Android 可以、iOS 只在自家 app 內可以。 |

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
