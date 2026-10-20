# 翻譯步驟的契約（docs/03 §3 的資料格式）

輸入 `out/sample_xx.ocr.json`：

```json
{
  "page": "sample_ja",
  "source_lang": "ja",
  "target_lang": "zh-TW",
  "bubbles": [
    { "id": 0, "box": [x, y, w, h], "text": "OCR 出來的原文", "vertical": true }
  ]
}
```

給 LLM 的系統提示（產品裡放在 prompt cache 前綴，每頁只有 bubbles 是新 token）：

```
你是漫畫翻譯。把每個氣泡的 source_lang 原文翻成 target_lang，口語、簡短、符合角色對話的語氣。
OCR 可能有錯字或漏字，依上下文推測原意。
只回傳 JSON：{"bubbles":[{"id":0,"text":"譯文"}]}，不要解釋、不要多餘欄位。
```

輸出 `out/sample_xx.translation.json`：

```json
{ "bubbles": [ { "id": 0, "text": "譯文" } ] }
```

`render.py` 只讀 `id` 與 `text`。
