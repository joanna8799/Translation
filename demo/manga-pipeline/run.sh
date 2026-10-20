#!/usr/bin/env bash
# 漫畫翻譯 pipeline 示範：產生測試頁 → 氣泡偵測 → OCR → （LLM 翻譯）→ 擦字排版。
#
# 第一次執行會準備工具（全部不經 dl.google.com、huggingface.co）：
#   tesseract.js（npm）、tessdata_fast 語言檔（raw.githubusercontent.com）、Noto Sans CJK KR（raw.githubusercontent.com）、
#   sharp（npm）、opencv-python-headless、numpy、Pillow（PyPI）。
#
# 翻譯那一步是雲端 LLM。這個環境沒有 API key，所以 run.sh 停在 ocr.json，
# 由 LLM 讀 ocr.json 寫出 translation.json（格式見 translate_prompt.md），再跑 render。
# 有 ANTHROPIC_API_KEY 時可以把 translate.py 接上去自動跑。
#
# 用法：./run.sh prepare | detect | render
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
mkdir -p out vendor/tessdata vendor/fonts

prepare() {
  [ -d node_modules/tesseract.js ] || npm install tesseract.js@5 sharp --no-audit --no-fund >/dev/null
  for l in jpn jpn_vert kor; do
    [ -s vendor/tessdata/$l.traineddata ] || curl -sSL -o vendor/tessdata/$l.traineddata "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/$l.traineddata"
  done
  [ -s vendor/fonts/NotoSansCJKkr-Regular.otf ] || curl -sSL -o vendor/fonts/NotoSansCJKkr-Regular.otf "https://raw.githubusercontent.com/googlefonts/noto-cjk/main/Sans/OTF/Korean/NotoSansCJKkr-Regular.otf"
  python3 -c "import cv2, numpy, PIL" 2>/dev/null || pip install -q opencv-python-headless numpy Pillow
  echo "prepared"
}

detect() {
  python3 make_sample_page.py out
  for p in ja ko; do
    python3 detect_bubbles.py out/sample_$p.png out/sample_$p.bubbles.json out/masks_$p
    node ocr.mjs out/sample_$p.png out/sample_$p.bubbles.json $p out/sample_$p.ocr.json out/masks_$p
  done
  echo "接下來：依 translate_prompt.md 把 out/sample_*.ocr.json 翻成 out/sample_*.translation.json，再 ./run.sh render"
}

render() {
  for p in ja ko; do
    python3 render.py out/sample_$p.png out/sample_$p.ocr.json out/sample_$p.translation.json out/masks_$p out/sample_${p}_translated.png
  done
  python3 compare.py out
}

case "${1:-}" in
  prepare) prepare ;;
  detect) detect ;;
  render) render ;;
  *) echo "usage: $0 prepare|detect|render"; exit 1 ;;
esac
