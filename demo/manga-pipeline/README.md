# 漫畫翻譯 pipeline 示範：一張頁面進去，翻好的頁面出來

這是 docs/04 Phase 0 的東西，在這個環境裡實際跑完了。結果在 [results/](results/)：`compare_ja.png`、`compare_ko.png` 是原圖與翻好的圖並排，`*.ocr.json` 與 `*.translation.json` 是中間資料。

```
頁面 PNG
  │
  ├ 1. detect_bubbles.py   像素法找白色對話框，輸出外框、遮罩、去框線的乾淨裁切
  ├ 2. ocr.mjs             每個氣泡跑 OCR（直式日文 / 韓文），輸出 ocr.json
  ├ 3. LLM                 讀 ocr.json 寫 translation.json（契約見 translate_prompt.md）
  └ 4. render.py           擦字（氣泡遮罩填紙色）、排版（直書或橫書、自動字級），輸出翻好的 PNG
```

資料格式就是 docs/03 §3 的 bubbles JSON，之後瀏覽器擴充、Android、iOS 三個前端都吃同一份。

## 這次跑出來的數字

| 頁 | 氣泡（真值 / 偵測到） | OCR 結果 | 翻譯 |
|---|---|---|---|
| sample_ja（直式日文，四格） | 6 / 6 | 6 句全部可讀，1 個多字（いららっしゃい） | 6 / 6 |
| sample_ko（韓文條漫） | 5 / 5 | 5 句全部可讀，1 個錯字（진짜아） | 5 / 5 |

OCR 的錯字由 LLM 依上下文修正，這正是 docs/03 把「LLM 吃 OCR 文字」當主路線的理由之一。

## 這個示範用的替身，與產品版的差別

| 步驤 | 示範用 | 產品版 | 為什麼示範不用產品版 |
|---|---|---|---|
| 測試頁 | `make_sample_page.py` 自己畫的頁面，對白自己寫 | 使用者正在看的任何頁 | 不能拿有版權的漫畫進 repo |
| 氣泡偵測 | OpenCV 連通區域（白、飽滿、夠大） | 偵測模型（docs/03 §10 挑非 GPL 的） | 像素法對無框對白、不規則氣泡會漏 |
| OCR | tesseract.js，tessdata_fast 的 jpn_vert、kor | manga-ocr、PP-OCR、ML Kit、Vision | 這個環境只連得到 raw.githubusercontent.com，拿不到 manga-ocr 與 PP-OCR 模型 |
| 翻譯 | Claude（這個工作階段裡的子代理） | Cloudflare proxy 後的 LLM，含共享快取與額度 | 環境沒有 API key；契約一樣 |
| 擦字 | 遮罩填紙色 | 同（MangaLens 做法），有需要再加 inpainting | 無 |
| 排版 | 內接矩形自動字級，直書右到左 | 同，再加字型與標點規則 | 無 |

## 自己跑

```
cd demo/manga-pipeline
./run.sh prepare     # 第一次：npm 裝 tesseract.js 與 sharp、抓語言檔與字型、pip 裝 opencv
./run.sh detect      # 產生測試頁、偵測、OCR → out/sample_*.ocr.json
# 把 out/sample_*.ocr.json 交給 LLM，依 translate_prompt.md 寫出 out/sample_*.translation.json
./run.sh render      # 擦字排版 → out/sample_*_translated.png、out/compare_*.png、out/compare.html
```

要換成自己的頁面：把 PNG 放進 `out/`，跳過 `make_sample_page.py`，對它跑 `detect_bubbles.py` 與 `ocr.mjs` 即可。
