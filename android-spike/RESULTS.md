# 驗證結果

填寫日期：
裝置、Android 版本、廠牌 ROM：
Android Studio 與 AGP 版本：

## 編譯

| 項目 | 結果 |
|---|---|
| Gradle 同步成功 | |
| 需要修改的檔案與原因 | |
| 無障礙服務能在設定裡開啟 | |

## 目標 app 讀字測試

每個 app 至少測一本小說、兩個畫面（停住、捲一頁後停住）。

| app | package | 作品類型 | 節點數 | 字數 | 文字是正文嗎 | 截圖黑或被擋 | 判定（A 可用 / B 可用 / 只能網頁） | 備註 |
|---|---|---|---|---|---|---|---|---|
| Naver Series | com.nhn.android.nbooks | 網路小說 | | | | | | |
| Kakao Page | com.kakao.page | 專用行動閱讀器作品 | | | | | | |
| Kakao Page | com.kakao.page | EPUB 類作品 | | | | | | |
| Ridi | com.initialcoms.ridi | 網路小說 | | | | | | |
| Ridi | com.initialcoms.ridi | 一般電子書 | | | | | | |
| Piccoma | jp.kakao.piccoma | 小說 | | | | | | |
| LINE Manga | jp.naver.linemanga.android | 小說 | | | | | | |
| Munpia | （請查） | 網路小說 | | | | | | |
| Chrome 開 Ridi 網頁閱讀器（對照組） | com.android.chrome | 網路小說 | | | | | 應該 A 可用 | |

## 面板體驗

| 項目 | 數字或印象 |
|---|---|
| 停住到面板出現的時間（秒） | |
| 捲動時面板有沒有閃爍或殘留 | |
| ML Kit 翻譯品質（看得懂 / 一半 / 不行） | |
| 同一頁重複觸發的次數（看 `a11y.skip` 比例） | |

## 結論

- Android 小說以無障礙讀字為主路徑可行嗎：
- 哪些 app 只能走 OCR 備援：
- 哪些 app 在 Android 上只能引導去網頁：
- 下一步：
