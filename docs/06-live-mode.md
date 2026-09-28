# 即時模式：捲動就自動更新，兩個平台各怎麼做

你要的是「在別人的 app 裡捲動，翻譯自動跟著更新」，不是每頁按一下。這份文件只講這件事。

## 0. 結論先講

| | Android | iOS |
|---|---|---|
| 做得到嗎 | 做得到，而且是就地覆蓋在氣泡上 | 做得到「自動更新」，但顯示在一個浮動視窗裡，不是就地 |
| 機制 | MediaProjection 連續擷取加懸浮窗 | ReplayKit 廣播擷取加子母畫面（PiP）視窗 |
| 使用者看到什麼 | 原 app 畫面，氣泡被換成中文 | 原 app 畫面，加一個可拖曳的浮動視窗，裡面是字幕或翻好的區域鏡像 |
| 啟動方式 | 按一次系統「開始擷取」對話框 | 在 app 裡按一次「開始廣播」，之後在控制中心停止 |
| 系統提示 | 狀態列有擷取中的晶片 | 狀態列有紅色錄製指示 |
| 難度 | 中，有兩個可商用的開源專案可參考 | 高，記憶體 50 MB、跨程序通訊、自我擷取迴圈都要處理 |
| 擋得住它的 app | 設 FLAG_SECURE 的 app 擷取到黑畫面 | 偵測到錄影就把內容遮掉的 app |

EasyComix 的 Live Captions 就是右欄的做法，顯示的是字幕條。

## 1. Android：連續擷取加就地覆蓋

每一幀的流程：

1. MediaProjection 建 VirtualDisplay，ImageReader 拿到畫面。
2. 靜止偵測：連續兩幀差異小於閾值持續約 150 到 300 ms 才往下走（MangaLens 的做法）。使用者捲動中不做任何事。
3. 氣泡偵測加 OCR，ML Kit 端側。
4. 文字雜湊去重：跟上一輪相同的氣泡不重翻，直接沿用結果。這是即時模式最重要的省錢點，捲動慢的時候同一個氣泡會出現在幾十幀裡。
5. 翻譯分兩段：L0 端側先出草稿（200 ms 內），L1 或 L2 再用 LLM 潤稿替換（1 到 3 秒）。MangaLens 就是「免費草稿約 1 秒、AI 潤稿 2 到 5 秒」。
6. 懸浮窗畫覆蓋：擦字加排版，座標對齊畫面。使用者一捲動立刻清掉覆蓋層，避免譯文跟畫面錯位，靜止後重畫。

要點：

- 前景服務 mediaProjection 型別、`SYSTEM_ALERT_WINDOW` 權限。
- Shizuku 可免每次授權對話框，overlay-translator 有實作。
- 覆蓋層設 `FLAG_NOT_TOUCHABLE`，讓觸控穿透到底下的 app。
- 電池：靜止偵測加只在畫面變化時跑 OCR，待機時幾乎不耗電。

## 2. iOS：廣播擷取加 PiP

### 2.1 為什麼只能這樣

- iOS 沒有 `SYSTEM_ALERT_WINDOW` 的對應物。唯一能浮在其他 app 上面的公開 API 是子母畫面（`AVPictureInPictureController`），它只能播影片。
- 唯一能在背景連續讀螢幕的公開 API 是 ReplayKit 的 Broadcast Upload Extension，這是系統錄影與直播用的。
- 所以做法是：擴充讀螢幕，主 app 翻譯，把譯文畫成影片影格餵給 PiP 視窗。

### 2.2 元件與資料流

```
其他 app（Kakao Page、Piccoma、Webtoon…）
   │ 螢幕影格，每秒數幀
   ▼
Broadcast Upload Extension（獨立程序，50 MB 記憶體上限）
   ├ 只裁切使用者框選的區域，縮到 720p 以下
   ├ 靜止偵測，有變化才處理
   ├ 選項 A：在擴充裡直接跑 Vision OCR，只把文字送出去（資料量小）
   └ 選項 B：把縮圖送給主 app（資料量大，但擴充更省記憶體）
   │ App Group 共享容器加 Darwin 通知，或 Unix domain socket
   ▼
主 app（靠 PiP 播放維持在背景不被暫停，需開 audio 背景模式）
   ├ 文字雜湊去重
   ├ 翻譯：Apple Translation framework（L0）或雲端 LLM（L1、L2）
   ├ 排版：把譯文畫成 CVPixelBuffer
   └ 餵進 AVSampleBufferDisplayLayer
   ▼
PiP 視窗（浮在任何 app 上，可拖曳、可雙指縮放）
```

### 2.3 PiP 視窗能顯示什麼

兩種產品形態都做得到：

- 字幕模式：只顯示框選區域內氣泡的譯文，一行一句。EasyComix Live Captions 是這個。視窗小，不擋畫面。
- 鏡像模式：顯示框選區域翻好的圖，氣泡已換成中文。使用者其實是在 PiP 視窗裡讀，底下的 app 只負責捲動。視窗要開大一點，比較像「就地」，但 PiP 最大尺寸受系統限制，大約半個螢幕。

建議先做字幕模式，再視回饋加鏡像模式。

### 2.4 五個非做不可的細節

1. **自我擷取迴圈。** PiP 視窗自己也會被錄進來。解法是要求使用者先框選一個區域，PiP 放在區域外；再在 PiP 影格外圍畫一圈特定顏色的細框，擴充偵測到這個框就把該區域遮掉。EasyComix 要使用者「先框一個 zone」就是為了這個。
2. **50 MB 記憶體。** 擴充裡不能載大模型。Vision 是系統框架可以用；裁切加縮圖後再處理；翻譯與排版都不放擴充。
3. **主 app 保活。** PiP 播放中的 app 不會被暫停，但要開「Audio, AirPlay, and Picture in Picture」背景模式。PiP 一關，主 app 幾秒內就會被暫停，翻譯跟著停，這是設計上要接受的。
4. **Translation framework 只能在有 SwiftUI 視圖的地方用**（`translationTask` 修飾器），所以翻譯放主 app，不放擴充。背景時能否持續運作需要實測，備案是端側 ML Kit 翻譯或雲端。
5. **延遲。** 擴充到 IPC 到翻譯到畫影格到 PiP 顯示，目標 1 秒內出 L0 草稿。IPC 傳文字很快，傳圖要壓成 JPEG。

### 2.5 審核與政策

- App Store 上已有多款「PiP 螢幕翻譯」類 app（Live Caption-Screen Translate、PiP Screen Translate、iTranscreen 等），所以這條路是 Apple 允許的。
- 錄影期間系統顯示紅色指示，使用者知情。
- 要在 app 內用 `RPSystemBroadcastPickerView` 讓使用者手動啟動，不能自動啟動。

### 2.6 Safari 是 iOS 上唯一的「就地又自動」

如果內容是網頁（Webtoon 網頁版、MangaDex、なろう、Pixiv），iOS Safari 擴充可以做到真正的就地、自動、不用 PiP。所以 iOS 的產品策略是：能用網頁看的引導去 Safari，原生 app 用 PiP。

## 3. 兩個平台共同的天敵：內容保護

| | Android | iOS |
|---|---|---|
| app 能做什麼 | `FLAG_SECURE`：截圖與錄影都變黑畫面，無解 | 不能擋截圖；能偵測 `isCaptured` 然後自己把內容遮掉或黑掉 |
| 對即時模式的影響 | 該 app 完全不能用 | 該 app 在錄影時可能黑掉 |
| 對截圖捷徑的影響 | 一樣不能用 | 仍然可用，iOS 無法阻止截圖 |

正版付費平台（韓國與日本的幾家大平台）普遍會做內容保護，是否擋、怎麼擋要逐一實測。這張清單會直接決定即時模式能宣傳的範圍。iOS 的截圖捷徑是唯一在所有 app 上都能用的模式，所以即使主打即時，截圖捷徑也要保留當備案。

## 4. 即時模式的成本控制

即時模式讓 OCR 跑得更頻繁，但 OCR 在端側是免費的。真正要控的是 LLM 呼叫次數：

1. 靜止才處理，捲動中不處理。
2. 文字雜湊去重，同一個氣泡只翻一次；跨章節、跨使用者共享快取照舊。
3. 兩段式：L0 端側草稿立即顯示，LLM 潤稿在背景做；使用者捲走了就取消還沒送出的請求。
4. 合併視窗：300 ms 內出現的新氣泡合併成一次 LLM 呼叫。
5. 免費用戶的即時模式只給 L0，Pro 才有 LLM 潤稿。這樣免費即時模式的雲端成本是零，跟 EasyComix 的邏輯一致。

## 5. 建議先做的技術驗證（iOS，1 到 2 週）

在寫任何產品功能之前，先用一個最小專案驗證：

1. 廣播擴充在 50 MB 內，能否對 720p 裁切區穩定跑 Vision OCR，每秒 2 到 3 次。
2. PiP 能否讓主 app 在背景持續跑 10 分鐘以上不被殺。
3. Translation framework 在背景是否能翻，不能就換 ML Kit。
4. 目標 app 清單（Kakao Page、Naver Series、Piccoma、LINE Manga、Webtoon）在錄影時是否黑掉。
5. 端到端延遲。

驗證失敗的項目決定產品形態，不要先做 UI。
