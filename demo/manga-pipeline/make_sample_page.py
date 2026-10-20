#!/usr/bin/env python3
"""產生測試用的漫畫頁。對白是自己寫的，沒有版權問題。

兩頁：
- sample_ja.png：直式日文，四格，六個氣泡。背景用淺灰網點模擬畫面，氣泡是純白。
- sample_ko.png：韓文條漫式，直向長條，五個氣泡。

用法：python3 make_sample_page.py out_dir
"""
import json
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FONT_JA = "/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf"
FONT_KO = str(HERE / "vendor" / "fonts" / "NotoSansCJKkr-Regular.otf")

JA_BUBBLES = [
    # (panel, text, 相對位置)
    (0, "この街に来るのは三年ぶりだな", "right"),
    (0, "あの店、まだあるかな", "left"),
    (1, "いらっしゃい！久しぶりじゃないか", "right"),
    (1, "覚えててくれたんですか", "left"),
    (2, "当たり前だ。毎日ここで宿題してたやつを忘れるわけがない", "right"),
    (3, "……ただいま", "center"),
]

KO_BUBBLES = [
    "오늘도 야근이야?",
    "응, 이번 주만 참으면 돼.",
    "그 말 지난주에도 했잖아.",
    "이번엔 진짜야. 끝나면 밥 사줄게.",
    "약속한 거다?",
]


def screentone(draw, box, seed=0):
    """淺灰底加細點，模擬畫面，讓氣泡的純白跟背景分得開。"""
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill=(205, 205, 205))
    rnd = random.Random(seed)
    for _ in range(int((x1 - x0) * (y1 - y0) / 180)):
        x = rnd.randint(x0, x1 - 1)
        y = rnd.randint(y0, y1 - 1)
        draw.point((x, y), fill=(150, 150, 150))
    # 幾條隨機線條當作背景物件
    for i in range(6):
        xa, ya = rnd.randint(x0, x1), rnd.randint(y0, y1)
        xb, yb = rnd.randint(x0, x1), rnd.randint(y0, y1)
        draw.line((xa, ya, xb, yb), fill=(90, 90, 90), width=rnd.randint(2, 5))


def vertical_text_size(font, text, cols_max_chars):
    lines = [text[i:i + cols_max_chars] for i in range(0, len(text), cols_max_chars)]
    ch = font.size
    w = len(lines) * int(ch * 1.25)
    h = max(len(l) for l in lines) * int(ch * 1.1)
    return lines, w, h


def draw_vertical(draw, font, lines, right_x, top_y):
    """直書：由右往左一欄一欄，每欄由上往下。"""
    ch = font.size
    x = right_x - ch
    for line in lines:
        y = top_y
        for c in line:
            draw.text((x, y), c, font=font, fill=(0, 0, 0))
            y += int(ch * 1.1)
        x -= int(ch * 1.25)


def make_ja(out_dir):
    W, H = 1000, 1450
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)
    margin, gap = 40, 20
    pw = (W - 2 * margin - gap) // 2
    ph = (H - 2 * margin - gap) // 2
    panels = [
        (margin, margin, margin + pw, margin + ph),
        (margin + pw + gap, margin, W - margin, margin + ph),
        (margin, margin + ph + gap, margin + pw, H - margin),
        (margin + pw + gap, margin + ph + gap, W - margin, H - margin),
    ]
    for i, p in enumerate(panels):
        screentone(d, p, seed=i)
        d.rectangle(p, outline="black", width=5)

    font = ImageFont.truetype(FONT_JA, 30)
    truth = []
    for bi, (pi, text, pos) in enumerate(JA_BUBBLES):
        px0, py0, px1, py1 = panels[pi]
        lines, tw, th = vertical_text_size(font, text, 7)
        bw, bh = tw + 70, th + 70
        if pos == "right":
            cx = px1 - bw // 2 - 25
            cy = py0 + bh // 2 + 25
        elif pos == "left":
            cx = px0 + bw // 2 + 25
            cy = py1 - bh // 2 - 70
        else:
            cx = (px0 + px1) // 2
            cy = (py0 + py1) // 2
        box = (cx - bw // 2, cy - bh // 2, cx + bw // 2, cy + bh // 2)
        d.ellipse(box, fill="white", outline="black", width=4)
        # 尾巴
        d.polygon([(cx - 15, box[3] - 8), (cx + 15, box[3] - 8), (cx - 5, box[3] + 35)], fill="white", outline="black")
        d.line([(cx - 15, box[3] - 8), (cx + 15, box[3] - 8)], fill="white", width=4)
        draw_vertical(d, font, lines, cx + tw // 2, cy - th // 2)
        truth.append({"id": bi, "box": [box[0], box[1], box[2] - box[0], box[3] - box[1]], "text": text, "vertical": True})

    img.save(out_dir / "sample_ja.png")
    (out_dir / "sample_ja.truth.json").write_text(json.dumps(truth, ensure_ascii=False, indent=1), encoding="utf-8")


def make_ko(out_dir):
    W, H = 800, 2000
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)
    screentone(d, (0, 0, W, H), seed=7)
    font = ImageFont.truetype(FONT_KO, 30)
    truth = []
    y = 120
    for bi, text in enumerate(KO_BUBBLES):
        tw = int(d.textlength(text, font=font))
        bw, bh = tw + 90, 30 + 90
        cx = 220 if bi % 2 == 0 else W - 220
        cx = max(bw // 2 + 30, min(W - bw // 2 - 30, cx))
        box = (cx - bw // 2, y, cx + bw // 2, y + bh)
        d.rounded_rectangle(box, radius=40, fill="white", outline="black", width=4)
        d.text((cx - tw // 2, y + 45 - 15), text, font=font, fill=(0, 0, 0))
        truth.append({"id": bi, "box": [box[0], box[1], bw, bh], "text": text, "vertical": False})
        y += 360
    img.save(out_dir / "sample_ko.png")
    (out_dir / "sample_ko.truth.json").write_text(json.dumps(truth, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "out"
    out.mkdir(parents=True, exist_ok=True)
    make_ja(out)
    make_ko(out)
    print("wrote", out / "sample_ja.png", out / "sample_ko.png")
