# 把 TalkSpike 裝到自己的 iPhone：三條路

iOS app 要裝到真機一定要經過 Apple 的簽章，沒有繞法。依你手邊有什麼選一條：

| | A. 有 Mac | B. 沒 Mac，但願意付 Apple Developer Program（US$99/年） | C. 沒 Mac、不付費，有 Windows 電腦 |
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

## C. 沒 Mac、不付費：Windows 電腦加 AltStore

原理：GitHub Actions 每次推送都會產出未簽章的 `TalkSpike-unsigned.ipa`，固定網址：

```
https://github.com/joanna8799/Translation/releases/download/talkspike-latest/TalkSpike-unsigned.ipa
```

AltStore 用你的免費 Apple ID 幫它簽章後裝到手機。限制：7 天到期（AltStore 會自動續）、同時最多 3 個這樣裝的 app、免費帳號一週最多註冊 10 個不同的 bundle ID（重裝同一個不算）。

### C1. 電腦端，只做一次

1. 到 Apple 官網裝 **iTunes** 與 **iCloud**（Windows 版，一定要 Apple 官網的安裝檔，不能用 Microsoft Store 版，AltServer 認不到；已經裝了 Store 版的先解除安裝）：
   - iTunes 64 位元直接下載：https://www.apple.com/itunes/download/win64 （Apple 的 iTunes 頁面在 Windows 10/11 上會把你導去 Microsoft Store，所以要用這個直接連結）
   - iCloud：Apple 的支援頁現在只導去 Microsoft Store，請用 AltStore 官方 FAQ 提供的直接安裝檔：
     https://updates.cdn-apple.com/2020/windows/001-39935-20200911-1A70AA56-F448-11EA-8CC0-99D41950005E/iCloudSetup.exe
     （這是較舊的 iCloud 7.x，AltServer 只需要它的登入元件，裝完不用登入、不用開）
2. 到 https://altstore.io 按 **Download AltServer for Windows**（AltStore Classic），解壓 `AltInstaller.zip` 後執行 `Setup.exe`。裝好後在 Windows 搜尋列打 AltServer，以系統管理員身分執行，系統匣會多一個圖示。
   官方圖文步驟：https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
3. 可以用自己的 Apple ID，也可以另外申請一個小號（差別只在要不要把主帳號密碼打進第三方工具）。**全新申請的 Apple ID 要先做兩件事，否則 AltServer 會登入失敗**：
   - 到 https://account.apple.com 登入，確認「雙重認證」已開啟（用手機號碼當信任號碼即可）。
   - 到 https://developer.apple.com/account 用同一個 Apple ID 登入一次，勾選同意 Apple Developer Agreement。免費，不用付錢，這一步會把帳號變成「免費開發者帳號」，AltServer 才簽得了章。
   - 還是失敗的話，在 iPhone 上 設定 > 你的名字 > 媒體與購買項目 > 登出，改用小號登入一次再登出換回來，讓 Apple 認得這個帳號用過 iOS 裝置。
4. Windows 跳出「Windows 已保護您的電腦」時按「其他資訊 > 仍要執行」，AltServer 與舊版 iCloud 安裝檔都沒有 Microsoft 的簽章，這是正常的。

### C2. 手機端，只做一次

1. iPhone 用傳輸線接電腦，手機上按「信任這部電腦」。iTunes 若跳出來，關掉即可。
   （「透過 Wi-Fi 同步」不是必要的：接著線 AltServer 就能透過 USB 跟手機通訊。只有想每週不接線自動續簽、而且電腦和手機在同一個 Wi-Fi 時才需要勾。）
2. 系統匣右鍵 AltServer 圖示 > **Install AltStore** > 選你的 iPhone > 輸入 Apple ID 與密碼（會要兩步驟驗證碼）。
3. 手機上出現 AltStore，但還不能開。到 設定 > 一般 > VPN 與裝置管理 > 點你的 Apple ID > **信任**。
4. 設定 > 隱私權與安全性 > **開發者模式** 打開，手機會重開機。（這個選項要裝過非 App Store 的 app 才會出現，做完第 2 步再去找。）
5. 開 AltStore，左下 Settings 登入同一個 Apple ID。

### C3. 裝 TalkSpike，每次有新版都這樣做

1. 手機上用 **Safari** 開上面那個固定網址，下載 `.ipa`（檔案會進「檔案」app 的下載項目）。
2. 開 AltStore > My Apps > 左上角「+」> 選剛下載的 `TalkSpike-unsigned.ipa`。AltStore 會簽章並安裝，約 30 秒到 1 分鐘。
   做這一步時電腦上的 AltServer 要開著（簽章是電腦做的），手機要能連到 AltServer：**用傳輸線接著就可以**，不需要同一個 Wi-Fi。
3. 第一次開 TalkSpike 會要麥克風權限，允許。
4. 之後有新 commit 推上去，重複 1 到 2，直接覆蓋安裝，之前的量測紀錄會留著。

### C4. 讓它不過期

每 7 天要續簽，三種方式擇一：

- **接線**：手機接電腦、AltServer 開著，開 AltStore > My Apps 按 **Refresh All**，30 秒。電腦和手機不必在同一個 Wi-Fi。
- **同一 Wi-Fi 自動續**：iTunes 裝置頁勾「透過 Wi-Fi 同步」，之後手機和電腦在同一個 Wi-Fi 且 AltServer 開著時，AltStore 會在背景自動續。
- **手機熱點**：電腦連上 iPhone 的個人熱點，兩者就在同一個網路，再按 Refresh All。

到期的 app 圖示還在但打不開，續簽後資料不會掉。

### 另一個選擇：Sideloadly

不想在手機上多裝 AltStore 的話，用 https://sideloadly.io ：同樣要先裝 Apple 官網的 iTunes，開 Sideloadly 把 `.ipa` 拖進去、填 Apple ID、按 Start 就裝好。缺點是續簽要手動（或讓電腦一直開著並開它的 Wi-Fi 自動續簽）。兩個都用免費 Apple ID，限制一樣。

### 常見錯誤

| 看到什麼 | 原因與解法 |
|---|---|
| AltServer 找不到裝置 | iTunes 不是 Apple 官網版、或手機沒按「信任這部電腦」。重裝 iTunes（官網版）後重新接線。 |
| 「無法安裝，開發者不受信任」 | 設定 > 一般 > VPN 與裝置管理 去信任那個 Apple ID。 |
| 安裝後點 app 沒反應、或跳「需要開發者模式」 | 設定 > 隱私權與安全性 > 開發者模式打開。 |
| 「You have reached the maximum number of apps」 | 免費帳號最多 3 個，刪掉一個再裝。 |
| 「Could not register App ID」 | 一週 10 個 App ID 的上限到了，等幾天，或換一個 Apple ID。 |
| AltStore 說找不到 AltServer | 電腦和手機不在同一個 Wi-Fi，或防火牆擋了 AltServer；先用傳輸線接著再試。 |
| TalkSpike 開了但「準備」卡在下載語言模型 | 這是 Apple 的伺服器在下載 Speech 模型，要穩定的網路，第一次每個語言幾百 MB。 |

TalkSpike 不需要 App Group 之類的特殊權限，免費帳號簽得過。LiveSpike（漫畫那個）有廣播擴充和 App Group，AltStore 不一定裝得起來，那個還是走 A 或 B。

## 裝好之後

照 [README.md](README.md) 的「操作流程」做五個驗證，數字填進 [RESULTS.md](RESULTS.md)，連同 `talkspike_metrics.jsonl`（檔案 app > 我的 iPhone > TalkSpike）回傳。
