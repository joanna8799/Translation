#!/usr/bin/env python3
"""把原圖與翻好的圖並排成一張對照圖，另外輸出一頁 HTML。用法：python3 compare.py out_dir"""
import sys
from pathlib import Path

from PIL import Image

out = Path(sys.argv[1])
html = ["<!doctype html><meta charset='utf-8'><title>Manga pipeline demo</title>",
        "<style>body{font-family:sans-serif;background:#222;color:#eee;margin:16px}figure{display:inline-block;margin:8px;vertical-align:top}img{max-height:900px;border:1px solid #555}figcaption{text-align:center;margin-top:4px}</style>",
        "<h1>漫畫翻譯 pipeline 示範：原圖 → 翻好的圖</h1>"]
for p in ["ja", "ko"]:
    a = Image.open(out / f"sample_{p}.png")
    b = Image.open(out / f"sample_{p}_translated.png")
    side = Image.new("RGB", (a.width + b.width + 30, max(a.height, b.height) + 20), (40, 40, 40))
    side.paste(a, (10, 10))
    side.paste(b, (a.width + 20, 10))
    side.save(out / f"compare_{p}.png")
    html.append(f"<h2>sample_{p}</h2><figure><img src='sample_{p}.png'><figcaption>原圖</figcaption></figure>"
                f"<figure><img src='sample_{p}_translated.png'><figcaption>翻譯後</figcaption></figure>")
(out / "compare.html").write_text("\n".join(html), encoding="utf-8")
print("wrote", out / "compare_ja.png", out / "compare_ko.png", out / "compare.html")
