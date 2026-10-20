# 桌面閱讀器讀字驗證

對應 docs/09 第 5a 節。回答一個問題：Ridi PC 閱讀器、Naver Series 閱讀器這類桌面 app，Windows 的 UI Automation 讀不讀得到正文？

| 結果 | 代表 | 桌面版小說怎麼做 |
|---|---|---|
| 字數 ≥ 200，內容是正文 | 閱讀器用原生或 Chromium 控制項渲染，暴露了無障礙樹 | 讀無障礙樹，不用 OCR，DRM 擋截圖也沒差，跟 Android 無障礙服務同一條路 |
| 只有按鈕、章名、頁碼 | 閱讀器自繪（canvas 或 DRM 外殼） | 只能截圖 OCR；再看截圖黑不黑 |
| 截圖全黑 | DRM（SetWindowDisplayAffinity） | 這個閱讀器在桌面上只能引導去網頁版 |

## 怎麼跑（Windows）

1. 把閱讀器開到正文頁。
2. 開 PowerShell，執行 `powershell -ExecutionPolicy Bypass -File .\uia-dump.ps1`。
3. 5 秒內點一下閱讀器視窗。
4. 把印出來的最後一行「節點 N 個，字數 M」與前面幾行貼回來；完整結果在 `uia-dump.txt`。
5. 同一頁按 Win+Shift+S 截圖，看是不是黑的。

每個閱讀器各跑一次。macOS 的對應工具是 Accessibility API，之後再補腳本。

## 記錄

| 閱讀器 | 節點數 | 字數 | 內容是正文嗎 | 截圖黑嗎 | 判定 |
|---|---|---|---|---|---|
| Ridi PC 閱讀器 | | | | | |
| Naver Series | | | | | |
| Kakao Page（網頁） | | | | 應該不黑 | 走擴充 |
| Kindle for PC | | | | | |
