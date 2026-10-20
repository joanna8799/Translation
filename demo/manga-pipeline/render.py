#!/usr/bin/env python3
"""擦字加排版：把譯文畫回氣泡。

擦字不用 inpainting 模型：氣泡遮罩內填氣泡自己的紙色（取遮罩內像素的中位數）。
排版：在氣泡內接矩形裡找最大能塞進去的字級；日文頁直書由右到左，韓文頁橫書。

用法：python3 render.py page.png ocr.json translation.json mask_dir out.png
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FONT = str(HERE / "vendor" / "fonts" / "NotoSansCJKkr-Regular.otf")  # 涵蓋繁中、日、韓


PUNCT_NO_START = "，。！？、：；」』）…"


def wrap_greedy(draw, font, text, box_w):
    lines, cur = [], ""
    for ch in text:
        if cur and draw.textlength(cur + ch, font=font) > box_w and ch not in PUNCT_NO_START:
            lines.append(cur)
            cur = ch
        else:
            cur += ch
    lines.append(cur)
    return lines


def wrap_balanced(draw, font, text, n, box_w):
    """把 n 行的字數平均分配，再套標點不開頭的規則。"""
    per = -(-len(text) // n)
    lines = [text[i:i + per] for i in range(0, len(text), per)]
    for i in range(1, len(lines)):
        while lines[i] and lines[i][0] in PUNCT_NO_START:
            lines[i - 1] += lines[i][0]
            lines[i] = lines[i][1:]
    lines = [l for l in lines if l]
    if any(draw.textlength(l, font=font) > box_w for l in lines):
        return None
    return lines


def fit_horizontal(draw, text, box_w, box_h, max_size=36, min_size=14):
    for size in range(max_size, min_size - 1, -2):
        font = ImageFont.truetype(FONT, size)
        lines = wrap_greedy(draw, font, text, box_w)
        lh = int(size * 1.25)
        if len(lines) * lh <= box_h and all(draw.textlength(l, font=font) <= box_w for l in lines):
            if len(lines) > 1:
                balanced = wrap_balanced(draw, font, text, len(lines), box_w)
                if balanced:
                    lines = balanced
            return font, lines, lh
    font = ImageFont.truetype(FONT, min_size)
    return font, [text], int(min_size * 1.25)


VERT_PUNCT = str.maketrans({"，": "︐", "。": "︒", "！": "︕", "？": "︖", "、": "︑", "：": "︓", "；": "︔",
                            "「": "﹁", "」": "﹂", "『": "﹃", "』": "﹄", "（": "︵", "）": "︶", "…": "︙", "—": "︱"})


def fit_vertical(text, box_w, box_h, max_size=40, min_size=14):
    text = text.translate(VERT_PUNCT)
    for size in range(max_size, min_size - 1, -2):
        col_w = int(size * 1.3)
        ch_h = int(size * 1.1)
        per_col = max(1, box_h // ch_h)
        cols = [text[i:i + per_col] for i in range(0, len(text), per_col)]
        if len(cols) * col_w <= box_w:
            return ImageFont.truetype(FONT, size), cols, col_w, ch_h
    size = min_size
    col_w, ch_h = int(size * 1.3), int(size * 1.1)
    per_col = max(1, box_h // ch_h)
    cols = [text[i:i + per_col] for i in range(0, len(text), per_col)]
    return ImageFont.truetype(FONT, size), cols, col_w, ch_h


def main(page_path, ocr_path, tr_path, mask_dir, out_path):
    img = Image.open(page_path).convert("RGB")
    arr = np.array(img)
    ocr = json.loads(Path(ocr_path).read_text(encoding="utf-8"))
    tr = {b["id"]: b["text"] for b in json.loads(Path(tr_path).read_text(encoding="utf-8"))["bubbles"]}

    # 1. 擦字
    for b in ocr["bubbles"]:
        m = np.array(Image.open(Path(mask_dir) / f"mask_{b['id']}.png").convert("L")) > 0
        if m.sum() == 0:
            continue
        paper = np.median(arr[m], axis=0).astype(np.uint8)
        x, y, w, h = b["box"]
        # 只在外框內縮一點的範圔內擦，不碰框線
        inset = int(min(w, h) * 0.10)
        sub = np.zeros_like(m)
        sub[y + inset:y + h - inset, x + inset:x + w - inset] = True
        arr[m & sub] = paper
    img = Image.fromarray(arr)
    d = ImageDraw.Draw(img)

    # 2. 排版
    for b in ocr["bubbles"]:
        text = tr.get(b["id"], "").strip()
        if not text:
            continue
        x, y, w, h = b["box"]
        # 橢圓內接矩形約為外框的 0.7 倍
        iw, ih = int(w * 0.70), int(h * 0.70)
        cx, cy = x + w // 2, y + h // 2
        if b.get("vertical"):
            font, cols, col_w, ch_h = fit_vertical(text, iw, ih)
            total_w = len(cols) * col_w
            right = cx + total_w // 2
            for ci, col in enumerate(cols):
                xx = right - (ci + 1) * col_w + (col_w - font.size) // 2
                col_h = len(col) * ch_h
                yy = cy - col_h // 2
                for ch in col:
                    d.text((xx, yy), ch, font=font, fill=(0, 0, 0))
                    yy += ch_h
        else:
            font, lines, lh = fit_horizontal(d, text, iw, ih)
            total_h = len(lines) * lh
            yy = cy - total_h // 2
            for line in lines:
                lw = d.textlength(line, font=font)
                d.text((cx - lw / 2, yy), line, font=font, fill=(0, 0, 0))
                yy += lh
    img.save(out_path)
    print("wrote", out_path)


if __name__ == "__main__":
    main(*sys.argv[1:6])
