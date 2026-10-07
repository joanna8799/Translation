# 把 TalkSpike 裝到自己的 iPhone：三條路

iOS app 要裝到真機一定要經過 Apple 的簽章，沒有繞法。依你手邊有什麼選一條：

| | A. 有 Mac | B. 沒 Mac，但願意付 Apple Developer Program（US$99/年） | C. 沒 Mac、不付費，有 Windows 或 Mac 電腦 |
|---|---|---|---|
| 要準備什麼 | Mac（macOS 15.6 以上）、Xcode 26、傳輸線 | Apple 開發者帳號、App Store Connect API 金鑰 | 一台電腦裝 AltServer、免費 Apple ID |
| 誰做簽章 | Xcode 用你的免費 Apple ID | GitHub Actions 用你的開發者憑證，上傳 TestFlight | AltStore 用你的免費 Apple ID |
| 裝好後能用多久 | 7 天，接回 Mac 再按一次 Run 就續期 | 90 天，重新推送就自動更新 | 7 天，電腦跟手機同一個 Wi-Fi 時 AltStore 會自動續期 |
| 完全不碰電腦也行嗎 | 不行 | 行，之後只要手機上的 TestFlight | 不行，第一次和每次續期都要電腦 |
| 適合 | 想自己改程式、看 log | 之後打算上架、想長期用 | 只想先試功能 |

三條路共同的前置條件：

1. iPhone 更新到 **iOS 26.1 以上**（設定 > 一般 > 軟體更新）。SpeechAnalyzer 是 26.0 才有，繁體中文模型是 26.1。
2. 開 **開發者模式**：設定 > 隱私權與安全性 > 開發者模式（裝了非 App Store 的 app 之後才會出現這個選項，或接上 Xcode 後出現）。
3. 空間留 2 GB 以上給語音與翻譯的語言模型。
4. 一副一般耳機、另一支會播外語影片的裝置。

## A. 有 Mac：10 分鐘

1. 裝 Xcode 26（App Store），裝 XcodeGen：`brew install xcodegen`。
2. `git clone https://github.com/joanna8799/Translation && cd Translation/ios-talk-spike`
3. `xcodegen generate && open TalkSpike.xcodeproj`
4. Xcode 左側點專案 > TalkSpike target > Signing & Capabilities：勾 Automatically manage signing，Team 選你的 Apple ID（免費的 Personal Team 就夠，沒有的話 Xcode > Settings > Accounts 加一個）。Bundle Identifier 若撞名就改成自己的，例如 `com.你的名字.talkspike`。
5. iPhone 接上 Mac，上方裝置選你的 iPhone，按 Run。第一次會要你在 iPhone 上信任這台電腦、開開發者模式，再到 設定 > 一般 > VPN 與裝置管理 信任你的 Apple ID。
6. 之後每次改程式碼：`git pull`，Xcode 按 Run。

免費 Apple ID 的限制：app 7 天後打不開，接回 Mac 再 Run 一次；同時最多 3 個這樣裝的 app。

## B. 沒 Mac、付 US$99：GitHub Actions 直接上 TestFlight

全部在 CI 上做，你手機只要裝 TestFlight。要你提供三樣東西，放進 GitHub repo 的 Secrets（Settings > Secrets and variables > Actions）：

1. 在 https://developer.apple.com 加入 Apple Developer Program（審核 1 到 2 天）。
2. App Store Connect > 使用者與存取 > 整合 > App Store Connect API：建一把 **Admin** 權限的金鑰，下載 `.p8`。記下 Issuer ID 和 Key ID。
3. App Store Connect > App > 新增 App：平台 iOS、名稱隨意、Bundle ID 新建一個（例如 `com.你的名字.talkspike`）、SKU 隨意。

Secrets 名稱：`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8`（整個 .p8 檔內容）、`APPLE_TEAM_ID`、`BUNDLE_ID`。
提供後我會加一個 `ios-testflight.yml` workflow：用 Xcode 的雲端簽章（`-allowProvisioningUpdates` 加 API 金鑰）打包、上傳 TestFlight，約 10 分鐘後手機上的 TestFlight 會出現新版本。

這條路也是之後要上架的必經之路，付了就不浪費。

## C. 沒 Mac、不付費：AltStore

GitHub Actions 已經會產出未簽章的 `TalkSpike-unsigned.ipa`（Actions > 最新一次 iOS build > Artifacts > TalkSpike-unsigned-ipa）。用 AltStore 以免費 Apple ID 簽章裝到手機：

1. 電腦裝 AltServer：https://altstore.io （Windows 要先從 Apple 官網裝 iTunes 與 iCloud，不能用 Microsoft Store 版）。
2. iPhone 接電腦，AltServer > Install AltStore > 選你的 iPhone，輸入 Apple ID（建議用一個專門的免費 Apple ID）。
3. iPhone 上開 AltStore，設定 > 一般 > VPN 與裝置管理 信任那個 Apple ID；設定 > 隱私權與安全性 > 開發者模式打開。
4. 把下載的 `TalkSpike-unsigned.ipa` AirDrop 或傳到手機，用 AltStore 的「+」選那個檔案，它會簽章並安裝。
5. 7 天到期前讓手機和電腦在同一個 Wi-Fi、AltServer 開著，AltStore 會自動續期。

限制跟 A 一樣：7 天、最多 3 個 app。TalkSpike 不需要 App Group 之類的特殊權限，免費帳號簽得過；LiveSpike（漫畫那個）有廣播擴充和 App Group，用 AltStore 不一定裝得起來，那個還是走 A 或 B。

## 裝好之後

照 [README.md](README.md) 的「操作流程」做五個驗證，數字填進 [RESULTS.md](RESULTS.md)，連同 `talkspike_metrics.jsonl`（檔案 app > 我的 iPhone > TalkSpike）回傳。
