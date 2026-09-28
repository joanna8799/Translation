# 全平台漫畫翻譯：可行性評估與架構草案

目標：做一款像 EasyComix 那樣「在你原本的閱讀環境裡就地翻譯漫畫」的產品，
但採用沈浸式翻譯的鋪法：所有瀏覽器都能裝、手機上任何 app 內的漫畫都能翻。

這個 repo 目前只有評估文件，尚未開始寫程式。

## 文件索引

| 文件 | 內容 |
|---|---|
| [docs/01-easycomix-cost-analysis.md](docs/01-easycomix-cost-analysis.md) | EasyComix 拆解：免費／Pro 分層、六個成本控制手法、與沈浸式翻譯的比較 |
| [docs/02-platform-feasibility.md](docs/02-platform-feasibility.md) | 全平台可行性：瀏覽器擴充、Android、iOS、桌面，哪些做得到、哪些只能折衷 |
| [docs/03-architecture-and-cost-model.md](docs/03-architecture-and-cost-model.md) | 建議架構、三層翻譯引擎、每頁／每用戶成本試算、定價、授權注意 |
| [docs/04-roadmap.md](docs/04-roadmap.md) | MVP 路線圖與風險 |
| [docs/references.md](docs/references.md) | 所有參考來源 |

## 一頁結論

**EasyComix 怎麼控制成本**

1. 免費層完全在裝置上跑：自訓的漫畫 OCR 模型 + iOS 系統翻譯框架，所以「無限離線翻譯」對開發者是零邊際成本。
2. 唯一會花錢的是 LLM，所以只有它被限額：登入後每日 10 次，Pro 才無限。
3. 雲端只收 OCR 後的文字，不收圖片，每頁成本壓低一個數量級。
4. 逐頁翻（捲到哪翻到哪），整章預翻鎖 Pro，不浪費沒看到的頁。
5. 週／月／年訂閱把 LLM 支出變成可預測的收入；週訂抓「追完就走」的人。
6. 只要功能會花伺服器錢或很難做，就放進 Pro；免費層只放邊際成本為零的東西。

**「全平台」實際做得到的範圍**

| 你要的 | 能做到的 |
|---|---|
| 所有瀏覽器 | 可以。一份 WebExtension 出 Chrome、Edge、Firefox、Safari 桌面版，再包成 iOS Safari 擴充。 |
| 手機任何 app 內 | Android 可以，用螢幕擷取 + 懸浮窗，已有可商用的開源專案證明。iOS 不允許覆蓋在其他 app 上，只能用「截圖捷徑」或「子母畫面字幕條」折衷，這正是 EasyComix 的做法。 |
| 就地把氣泡換成中文 | 瀏覽器可以、Android 可以、iOS 只在自家 app 內可以。 |

**建議架構的一句話**：看得到圖片的地方做辨識，雲端只收文字，免費層不碰雲端。

**每頁 LLM 成本量級**（純文字、一頁約 10 個氣泡）

| 模型 | 每頁 | 1,000 頁 |
|---|---|---|
| Gemini 2.5 Flash-Lite 級 | 約 US$0.0002 | 約 US$0.2 |
| Claude Haiku 4.5 | 約 US$0.002 | 約 US$2 |
| Claude Sonnet 5 | 約 US$0.004 | 約 US$4 |

固定成本第一年約 US$200（開發者帳號）加每月 US$5（serverless）。細節見 docs/03。

## 關於資料來源

Threads 貼文本身無法從這個工作環境讀取（網路白名單擋住 threads.com），
EasyComix 的資訊來自 App Store 頁面摘要、官網摘要與第三方整理。
文中標示「推測」的部分是根據公開資訊的推論，不是開發者本人證實的。
