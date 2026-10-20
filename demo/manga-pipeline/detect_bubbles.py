#!/usr/bin/env python3
"""氣泡偵測：像素法，不用模型。

找「夠大、夠飽滿、幾乎純白」的連通區域當氣泡。這是 MangaLens 的做法，
對白底黑框的對話框很準，對不規則氣泡與無框對白會漏，產品版要換成偵測模型
（docs/03 §10 的授權清單）。輸出每個氣泡的外框與遮罩。

用法：python3 detect_bubbles.py page.png out.json [mask_dir]
"""
import json
import sys
from pathlib import Path

import cv2
import numpy as np


def detect(img_bgr):
    H, W = img_bgr.shape[:2]
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    white = (gray > 235).astype(np.uint8)
    # 把文字造成的小洞補起來，讓氣泡內部連成一塊
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))
    white = cv2.morphologyEx(white, cv2.MORPH_CLOSE, k)
    n, labels, stats, _ = cv2.connectedComponentsWithStats(white, connectivity=4)
    page_area = H * W
    out = []
    for i in range(1, n):
        x, y, w, h, area = stats[i]
        if area < page_area * 0.002 or area > page_area * 0.15:
            continue
        fill = area / float(w * h)
        aspect = w / float(h)
        if fill < 0.55 or not (0.2 < aspect < 6.5):
            continue
        # 貼著頁面邊緣的大白塊多半是頁邊，不是氣泡
        if x <= 2 or y <= 2 or x + w >= W - 2 or y + h >= H - 2:
            continue
        out.append({"label": i, "box": [int(x), int(y), int(w), int(h)], "fill": round(float(fill), 3)})
    # 閱讀順序：日漫右到左、上到下；這裡先依 y 再依 x 反向，夠用於示範
    out.sort(key=lambda b: (b["box"][1] // 150, -b["box"][0]))
    for idx, b in enumerate(out):
        b["id"] = idx
    return out, labels


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    mask_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else None
    img = cv2.imread(src)
    bubbles, labels = detect(img)
    if mask_dir:
        mask_dir.mkdir(parents=True, exist_ok=True)
        for b in bubbles:
            m = (labels == b["label"]).astype(np.uint8) * 255
            cv2.imwrite(str(mask_dir / f"mask_{b['id']}.png"), m)
            # OCR 用的裁切：遮罩內縮 6 px 去掉框線，遮罩外全部塗白，放大 3 倍
            x, y, w, h = b["box"]
            er = cv2.erode(m, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13)))
            crop = img[y:y + h, x:x + w].copy()
            crop[er[y:y + h, x:x + w] == 0] = 255
            crop = cv2.resize(crop, None, fx=3, fy=3, interpolation=cv2.INTER_CUBIC)
            cv2.imwrite(str(mask_dir / f"crop_{b['id']}.png"), crop)
    for b in bubbles:
        b.pop("label")
    Path(dst).write_text(json.dumps({"page": Path(src).stem, "bubbles": bubbles}, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{src}: {len(bubbles)} bubbles")
