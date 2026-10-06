# 出國旅行即時對話翻譯：設備需求與實施方法評估

這份文件跟漫畫、小說無關，回答的是另一個問題：
「出國旅行時，對方講的不是中文，就自動幫我收音、辨識、翻成中文，用語音或文字給我；
我用中文回答，再翻回對方的語言給他；另外要有幣值轉換。」

前提：iPhone 17（iOS 26）、沒有 AI 耳機（一般藍牙或有線耳機）。
評估日期 2026-10，價格與功能以當時公開資料為準，出發前請再核對一次。

## 0. 結論先講

| 方案 | 要花什麼 | 做到你要的幾成 | 一句話 |
|---|---|---|---|
| A. 手機內建「翻譯」app 對話模式 | NT$0，現在就能用 | 七成 | 離線、自動判斷誰在講哪種語言、兩邊都唸出來；但要把手機放在兩人中間，靠擴音 |
| B. Google 翻譯的「即時翻譯」（耳機） | NT$0，任何耳機都行 | 七到八成 | 對方講話直接在你耳機裡變中文，70 多種語言自動偵測；要網路，台灣是否已開放要確認 |
| C. 買一副支援即時翻譯的 AirPods | 約 NT$6,000 到 7,500 | 九成 | 最貼近你描述的流程：耳機裡聽中文，你講中文、手機把對方語言顯示出來並唸出來；全程在手機上處理、可離線、支援繁中 |
| D. 專用翻譯機 | US$300 到 700 | 九成 | 給長期多國旅行、要遞給對方、不想耗手機電量的人；對一般旅行是過度投資 |
| E. 自己寫 app | 2 到 4 週開發 | 可達九成 | 技術上做得到，但只有當你要做產品才值得；純自用請選 A、B、C |

**建議**：出發前先把 A 設定好當底（不用錢、離線能用）。
如果這趟旅行你會頻繁用到「對方講我聽」的場景，加一副 AirPods 4 主動降噪版（走 C）；
不想花錢的話，先試 B 能不能在你的帳號／所在國家打開。
幣值轉換用 iOS 內建計算機就夠了，不需要另外裝 app。

## 1. 需求拆解：這件事其實是六個零件

| 零件 | 你的要求 | 說明 |
|---|---|---|
| 收音 | 自動收對方的聲音 | 手機麥克風或耳機麥克風；環境噪音是最大的敵人 |
| 語言判斷 | 自動知道對方講的不是中文 | 有兩種做法：事先選好兩種語言，系統只判斷「現在是哪一邊在講」（Apple、傳統 Google 對話模式）；或在 70 多種語言裡自動偵測（Google Gemini 即時翻譯） |
| 語音辨識 | 把對方的話變成文字 | 端側（離線、快、隱私）或雲端（語言多、噪音下較準） |
| 翻譯 | 外語到中文、中文到外語 | 端側模型或雲端 LLM；旅行對話句子短，端側已經夠用 |
| 輸出 | 給你語音或文字；給對方語音或文字 | 給你：耳機語音或螢幕文字。給對方：手機擴音或螢幕文字 |
| 幣值轉換 | 看到價格換算成台幣 | 跟翻譯是兩回事，沒有一個翻譯 app 把它做得好，用系統內建工具 |

「輪替」是隱藏的第七個零件：系統要知道對方講完了、該換你講了。
Apple 的對話模式用語音停頓判斷；Google 新版是「邊聽邊翻」不等句尾。

## 2. 設備需求

| 項目 | 你現在有的 | 需不需要加 |
|---|---|---|
| 手機 | iPhone 17，A19 晶片，支援 Apple Intelligence | 夠了。方案 C 要求 iPhone 15 Pro 以上，你符合 |
| 系統版本 | iOS 26 | **要更新到 iOS 26.1 以上**：AirPods 即時翻譯的繁體中文、Apple Intelligence 的繁體中文都是 26.1 才加入 |
| 耳機 | 一般藍牙或有線耳機 | 方案 A、B 直接用。方案 C 必須是 AirPods 4（主動降噪版）、AirPods Pro 2、AirPods Pro 3 或 AirPods Max 2 |
| 網路 | 看你的漫遊或 eSIM | 方案 A、C 下載語言包後離線可用；方案 B 全程要網路；方案 D 多半內建全球流量 |
| 儲存空間 | | 每種語言包幾百 MB，翻譯 app 和 AirPods 翻譯是分開下載的，兩邊都要下 |
| 電力 | | 即時收音加翻譯很耗電，帶行動電源 |
| Apple 帳號地區 | 台灣 | AirPods 即時翻譯在歐盟曾經受限，2025 年 11 月已開放；台灣帳號沒有這個問題 |

出發前要做的下載：
1. 「翻譯」app：下載「中文（國語，台灣）」加目的地語言，開「裝置上模式」。
2. 若走方案 C：設定 > AirPods > 翻譯（Beta）> 語言，下載同樣兩種語言。
3. 若走方案 B：Google 翻譯裝好、登入、先在家試一次「即時翻譯」按鈕有沒有出現。
4. 計算機 app 開一次貨幣換算，讓它抓到最新匯率（離線時會用最後一次抓的）。

## 3. 各方案逐項對照

| | A. Apple 翻譯 app | B. Google 翻譯 即時翻譯 | C. AirPods 即時翻譯 | D. 專用翻譯機 |
|---|---|---|---|---|
| 自動判斷語言 | 兩種語言內自動分辨誰在講 | 70 多種語言自動偵測 | 事先選對方語言，之後自動 | 多數要事先選 |
| 離線 | 可（下載語言包） | 不可 | 可（下載後全在手機處理） | 看機型，T1 有離線模型 |
| 繁體中文 | 有，「中文（國語，台灣）」 | 有中文；繁中輸出要實測 | 有，iOS 26.1 起 | 多數有 |
| 給你的輸出 | 擴音唸出加螢幕文字 | 耳機語音加螢幕文字 | 耳機語音加螢幕文字 | 機器喇叭或耳機 |
| 給對方的輸出 | 擴音唸出加螢幕文字 | 螢幕文字（回覆要切到對話模式） | 螢幕文字，按播放可擴音唸出 | 機器喇叭加螢幕 |
| 延遲 | 等你講完一句才翻 | 邊聽邊翻，最快 | 等一句講完 | 等一句講完 |
| 語言數 | 約 20 種 | 70 多種 | 11 種（英、法、德、西、葡、義、日、韓、簡中、繁中） | 40 到 110 種 |
| 噪音環境 | 普通 | 普通到好 | 好（主動降噪會把對方原聲壓低） | 好（專用麥克風） |
| 幣值轉換 | 無 | 無 | 無 | 無 |
| 費用 | 0 | 0 | 耳機錢 | US$300 到 700 |
| 台灣能不能用 | 能 | **要確認**，2026 年 3 月的開放名單是美、印、墨、德、西、法、奈、義、英、日、孟、泰，沒有台灣；但人在日本、泰國時可能就能用 | 能 | 能 |

### 方案 A 的用法

翻譯 app > 對話 > 左右各選一種語言 > 右上角開「自動翻譯」和「偵測語言」，
再選「面對面」檢視，手機橫放在桌上，兩個人各看自己那一面。
誰講話，它就自動判斷是哪種語言、翻好、唸出來。
這是零成本、零網路的底線方案，餐廳點菜、櫃檯問路夠用。
缺點是手機要放在兩人中間，而且擴音在吵的地方不好用；接耳機的話對方就聽不到翻譯，所以對話模式請用擴音。

### 方案 B 的用法

Google 翻譯 app > 「即時翻譯」> 戴上任何耳機 > 手機對著對方。
對方講話，你的耳機裡會出現中文語音，螢幕同時顯示原文和譯文；
2026 年 6 月後改用 Gemini 3.5 Live Translate，會保留對方的語氣和節奏，而且不等句尾就開始翻。
你回覆時，目前的設計是回到對話模式或讓對方看螢幕。
限制：全程要網路；開放地區逐步擴大，你的帳號在台灣能不能用要實際打開 app 看。

### 方案 C 的用法

這是最接近你描述的流程：

1. 兩邊 AirPods 柄同時按住，或翻譯 app > 「即時」> 開始翻譯。
2. 對方講話，手機麥克風收音，你的耳機裡聽到中文，螢幕也有文字記錄。主動降噪會把對方的原聲壓低，你聽的是中文。
3. 你用中文回答，手機螢幕上顯示翻成對方語言的文字，把手機轉給他看，或按播放鍵讓手機唸出來。
4. 如果對方也有支援的 AirPods，兩個人都直接在耳機裡聽，不用看螢幕。

全程在手機上處理，下載語言包後不用網路，對話內容不離開手機。
硬體選擇：AirPods 4 主動降噪版（約 NT$5,990）是最便宜的入門；AirPods Pro 3（約 NT$7,490）降噪更好、多心率等功能。
沒有主動降噪的 AirPods 4（約 NT$4,490）不支援即時翻譯，別買錯。
價格請以 Apple 台灣官網為準。

### 方案 D 什麼時候才值得

- 一次出國一個月以上、跨多國，不想每天擔心手機電量和漫遊費。
- 要把裝置遞給對方講（沒人會把自己的手機遞給陌生人）。
- 常在很吵的地方（市場、工地、車站）講話。

代表機型：Timekettle W4 Pro 耳機（US$449，42 種語言、13 組離線語言對）、
X1 多人會議機（US$699.99）、Fluentalk T1 手持機（US$299.99，內建離線小模型）；
Pocketalk S2 Plus（內含 5 年 LTE）；Vasco V4（112 種語言，近 200 國終身免費網路）。
以旅行為目的，T1 或 Vasco 這類手持機比耳機型實用，因為能遞給對方。

### 不建議的

- Microsoft 翻譯：多人各用自己手機加入同一對話的「Converse」功能 2026 年 6 月底已停掉，剩下的功能沒有比 A、B 好。
- ChatGPT、Gemini 語音模式當口譯：能用（跟它說「他講的翻成中文、我講的翻成日文」），但不是為兩人輪流講設計的，常搶話或自己接話，當備案可以，不當主力。

## 4. 幣值轉換怎麼做

沒有任何一個翻譯 app 把幣值轉換做好，用系統內建的就好：

- **計算機 app**：左下角切到「轉換」> 貨幣，自動抓即時匯率，離線時用上次抓到的。
- **Spotlight 或 Siri**：直接輸入「5000 日圓」或問 Siri，立刻出台幣。
- **拍價目表**：相機的「視覺智慧」或翻譯 app 的相機模式翻文字；數字換算再丟給計算機。

要「看到價格自動換算」只有自己寫 app 才做得到（見第 5 節），對自用不划算。

## 5. 自己寫一個 app 的評估

只有在你想把它做成產品（或跟本專案的翻譯引擎共用）才值得走這條路。
技術上 iOS 26 把需要的零件都給了，而且免費、離線。

### 5.1 架構

```
麥克風（AVAudioEngine）
  → 語音活動偵測（SpeechDetector）
  → 語音辨識（SpeechTranscriber，端側，iOS 26）
  → 語言判斷（見 5.2，這是最難的一塊）
  → 翻譯（Translation framework，端側，iOS 17.4+ / 18+）
  → 輸出：文字（畫面）＋ 語音（AVSpeechSynthesizer，走耳機或擴音）
  ↑ 你的回覆走同一條路，方向相反
幣值：匯率 API（Frankfurter、open.er-api 這類免費來源）＋ 離線快取 ＋ 畫面上的數字自動加註台幣
```

| 零件 | iOS API | 費用 | 備註 |
|---|---|---|---|
| 語音辨識 | SpeechAnalyzer + SpeechTranscriber（iOS 26） | 0 | 端側、低延遲、支援長音訊；Apple 公布乾淨語音字錯率 2.12%、噪音下 4.56%，優於 Whisper Small。支援的語言要在裝置上用 supportedLocales 查 |
| 翻譯 | Translation framework（TranslationSession） | 0 | 端側，語言包和翻譯 app 共用，含「中文（繁體）」；第一次用某組語言要下載 |
| 語音合成 | AVSpeechSynthesizer | 0 | 品質普通；要自然語音可改接雲端 TTS |
| 幣值 | 免費匯率 API | 0 | 出國前抓一次存起來，離線用 |
| 潤稿（選配） | 雲端 LLM | 見下 | 旅行句子短，端側翻譯通常夠；LLM 用在俚語、語氣 |

### 5.2 最難的一塊：對方講的是哪種語言

Apple 的語音辨識要你事先指定語言，沒有「聽一段自動判斷語種」的 API；
NLLanguageRecognizer 只能判斷文字，不能判斷語音。做法有三種：

1. **事先選定目的地語言**（Apple 自己的做法）：中文加一種外語，兩個辨識器同時跑，誰的信心高就用誰。簡單、離線，一趟旅行通常只有一種外語，夠用。
2. **雲端語音辨識附語種偵測**：Gemini Live API（Gemini 3.5 Live Translate 已開放給開發者）、OpenAI Realtime、Deepgram 這類都能自動偵測。要網路、要錢、延遲多幾百毫秒。
3. **先用端側辨識出一小段，丟給 LLM 判斷語種再切換**：折衷，但第一句會慢。

建議 1 當預設、2 當線上模式，跟本專案的三層引擎邏輯一樣。

### 5.3 延遲與成本

| 段落 | 端側 | 雲端 |
|---|---|---|
| 對方講完到你聽到中文 | 0.5 到 1.5 秒 | 1 到 3 秒（含網路） |
| 一句話的 LLM 潤稿成本（約 600 進 / 50 出 token，含系統提示） | 0 | Claude Haiku 4.5 約 US$0.001；Claude Sonnet 5.5 約 US$0.002 |
| 一天 200 句 | 0 | US$0.2 到 0.4 |

雲端成本對自用是零頭，對產品才需要像 docs/03 那樣設計額度。

### 5.4 工作量

| 階段 | 時間（一個人） | 內容 |
|---|---|---|
| 技術驗證 | 2 到 3 天 | SpeechTranscriber 串流辨識、Translation 端側翻譯、耳機輸出，三件事接起來 |
| MVP | 1 到 2 週 | 兩語言輪替、文字加語音輸出、語言包下載 UI、幣值換算 |
| 可用版本 | 再 1 到 2 週 | 噪音處理、輪替判斷調校、雲端模式、歷史記錄 |

風險：語音輪替判斷（誰講完了）比想像中難調；SpeechTranscriber 支援的語言比翻譯 app 少，要實機確認目的地語言在不在；
耳機麥克風收不到對方的聲音，要用手機麥克風收對方、耳機只負責播放，這跟 AirPods 即時翻譯的設計一樣。

### 5.5 結論

自用：不要寫，方案 C 已經是同一套架構的成品，而且 Apple 做了語言包和輪替調校。
做產品：可行，端側零件免費，差異化要放在語種自動偵測、幣值與價格情境、噪音處理，
而且這條路跟本專案的翻譯引擎（docs/03 的三層架構）可以共用翻譯層。

## 6. 建議的實施步驟

**出發前一週**
1. iPhone 更新到 iOS 26.1 以上，設定 > Apple Intelligence 與 Siri 開啟，語言選繁體中文。
2. 翻譯 app 下載「中文（國語，台灣）」和目的地語言，開裝置上模式。
3. 決定要不要走方案 C。要的話買 AirPods 4 主動降噪版或 Pro 3，設定裡下載翻譯語言。
4. 裝 Google 翻譯，登入，看「即時翻譯」有沒有出現；順便下載目的地語言的離線包當文字翻譯備案。
5. 在家用 YouTube 放一段目的地語言的影片，三個方案各試五分鐘，看哪個最順手。
6. 計算機開一次貨幣換算。

**旅行中的預設流程（方案 C）**
- 走進店裡先戴一邊 AirPods，按住兩邊柄開始翻譯。
- 對方講，耳機聽中文；你講中文，把手機轉給對方看或按播放。
- 看到價格，Spotlight 輸入數字加幣別。

**沒有 AirPods 的預設流程（方案 A 加 B）**
- 安靜的地方（櫃檯、餐廳）：翻譯 app 對話模式，手機放中間、面對面檢視、擴音。
- 吵的地方或只需要聽懂對方（導覽、廣播、店員解說）：Google 即時翻譯加你現有的耳機。
- 兩者都不行時退到文字：翻譯 app 打字給對方看。

## 7. 參考來源

- Apple 翻譯 app（App Store，功能說明含對話模式、自動翻譯、面對面、離線）：https://apps.apple.com/app/translate/id1514844618
- Apple 翻譯 app 支援語言（維基）：https://en.wikipedia.org/wiki/Translate_(Apple)
- TechRepublic：用 Apple 翻譯 app 做即時對話：https://www.techrepublic.com/article/how-to-use-apples-translate-app-to-translate-a-real-time-conversation/
- Apple 支援：用 AirPods 翻譯面對面對話：https://support.apple.com/guide/airpods/dev9c215ca94
- Apple 支援：AirPods 即時翻譯：https://support.apple.com/en-lamr/123185
- 9to5mac：iOS 26.1 AirPods 即時翻譯新增語言：https://9to5mac.com/2025/11/07/ios-26-1-makes-airpods-pros-latest-feature-even-better-heres-whats-new/
- TechNews：iOS 26.1 Beta 1 即時翻譯加入繁體中文：https://technews.tw/2025/09/23/ios-26-1-beta-1-apple-intelligence-traditional-chinese/
- Apple Newsroom：AirPods 即時翻譯擴展到歐盟（2025-11）：https://www.apple.com/ie/newsroom/2025/11/live-translation-on-airpods-expands-to-the-eu/
- Boostlingo：AirPods 即時翻譯實測：https://boostlingo.com/blog/testing-new-airpods-live-translation/
- AppleInsider：iOS 26 通話、訊息、FaceTime 即時翻譯：https://appleinsider.com/articles/25/06/11/new-ios-26-translation-tool-works-inside-calls-chats-video
- 瘋先生：AirPods Pro 3 台灣開賣與規格：https://mrmad.com.tw/airpods-pro-3-taiwan-specs-review
- Google 部落格：Gemini 翻譯能力進入 Google 翻譯：https://blog.google/products/search/gemini-capabilities-translation-upgrades/
- 9to5google：Google 翻譯耳機即時翻譯（2025-12）：https://9to5google.com/2025/12/12/google-translate-gemini-headphones/
- Notebookcheck：Google 翻譯 iOS 版加入即時翻譯（2026-03）：https://www.notebookcheck.net/Google-Translate-for-iOS-gets-game-changing-Live-Translate-feature.1260287.0.html
- AlternativeTo：即時翻譯擴展到 iOS 與更多國家（含開放名單）：https://alternativeto.net/news/2026/3/google-translate-s-real-time-headphone-translation-feature-expands-to-ios-and-more-countries
- Gigazine：Gemini 3.5 Live Translate（2026-06）：https://gigazine.net/gsc_news/en/20260610-google-gemini-3-5-live-translate/
- 瘋先生：Google 翻譯耳機即時翻譯 iOS 更新：https://mrmad.com.tw/google-gemini-real-time-translation-headphones-update
- TechRadar：Timekettle Fluentalk T1 評測：https://www.techradar.com/reviews/timekettle-fluentalk-t1-handheld-translator-review
- Timekettle 產品與價格：https://www.timekettle.co/collections
- 2026 Vasco 與 Pocketalk 比較：https://foliumbiosciences.com/vasco-vs-pocketalk-which-translator-is-best-for-travel/
- Android Authority：Microsoft 翻譯 Converse 功能停用：https://cellphoneplans.androidauthority.com/CellPhones/Guides/is-microsoft-translator-worth-downloading
- Apple 開發者文件：SpeechTranscriber：https://developer.apple.com/documentation/speech/speechtranscriber
- Gigazine：SpeechAnalyzer 與 Whisper 速度及準確率比較：https://gigazine.net/gsc_news/en/20250619-apple-speech-analyzer
- Blake Crosley：Apple Translation framework 端側翻譯：https://blakecrosley.com/blog/apple-translation-framework-on-device
- WWDC24 Meet the Translation API 筆記：https://wwdcnotes.com/documentation/wwdc24-10117-meet-the-translation-api/
- Anthropic 價格：本工作階段載入的官方價目表（2026-09 快取）
