#!/usr/bin/env python3
"""測試用本機網站加假翻譯端點。

- /novel.html   韓文網路小說頁（自己寫的段落）
- /manga.html   漫畫頁（demo/manga-pipeline 產生的測試頁）
- /v1/chat/completions  OpenAI 相容的假端點：用對照表回譯文，對不上的回「[譯] 原文」。
  這只是讓擴充的流程在沒有網路的環境裡跑得通；真實使用時擴充會接 Google 翻譯、Gemini 或 OpenAI 相容端點。

用法：python3 server.py 8765
"""
import difflib
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent

NOVEL_KO = [
    ("오늘도 야근이야?", "今天也要加班嗎？"),
    ("응, 이번 주만 참으면 돼. 이번엔 진짜야. 끝나면 밥 사줄게.", "嗯，撐過這週就好。這次是真的，忙完請你吃飯。"),
    ("그 말 지난주에도 했잖아. 약속한 거다?", "你上週也這麼說過啊。說好了喔？"),
    ("창밖으로 비가 내리기 시작했다. 우산을 챙기지 않은 것이 이제야 생각났다.", "窗外開始下起雨。這時才想起沒帶傘。"),
    ("서연은 가방을 열어 보았지만, 역시 우산은 없었다.", "瑞妍打開包包看了看，果然沒有傘。"),
]
DICT = dict(NOVEL_KO)
for p in ("sample_ja", "sample_ko"):
    try:
        truth = json.loads((ROOT / "demo/manga-pipeline/results" / f"{p}.ocr.json").read_text(encoding="utf-8"))
        tr = json.loads((ROOT / "demo/manga-pipeline/results" / f"{p}.translation.json").read_text(encoding="utf-8"))
        tmap = {b["id"]: b["text"] for b in tr["bubbles"]}
        for b in truth["bubbles"]:
            DICT[b["text"]] = tmap.get(b["id"], "")
    except FileNotFoundError:
        pass


def lookup(text):
    if text in DICT:
        return DICT[text]
    best = difflib.get_close_matches(text, DICT.keys(), n=1, cutoff=0.6)
    return DICT[best[0]] if best else f"[譯] {text}"


NOVEL_HTML = """<!doctype html><html lang="ko"><head><meta charset="utf-8"><title>테스트 소설</title>
<style>body{font-family:sans-serif;max-width:640px;margin:40px auto;line-height:1.8}nav{color:#888}</style></head>
<body><nav>홈 › 소설 › 1화</nav><h1>1화 비 오는 날</h1><article>
%s
</article><footer>© 테스트</footer></body></html>""" % "\n".join(f"<p>{k}</p>" for k, _ in NOVEL_KO)

MANGA_HTML = """<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>テスト漫画</title>
<style>body{background:#eee;margin:0}img{display:block;margin:20px auto;max-width:600px}</style></head>
<body><h1 style="text-align:center">第1話</h1><img src="/sample_ja.png" width="600"><img src="/sample_ko.png" width="480"></body></html>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="text/html; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/novel.html":
            return self._send(200, NOVEL_HTML.encode())
        if self.path == "/manga.html":
            return self._send(200, MANGA_HTML.encode())
        if self.path in ("/sample_ja.png", "/sample_ko.png"):
            return self._send(200, (ROOT / "demo/manga-pipeline/results" / self.path[1:]).read_bytes(), "image/png")
        self._send(404, b"not found")

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(n) or b"{}")
        prompt = req.get("messages", [{}])[-1].get("content", "")
        items = []
        try:
            # 提示文字裡「格式」那一行也有 {"items"…}，要取最後一個（輸入）
            items = json.loads(prompt[prompt.rindex('{"items"'):])["items"]
        except Exception:
            pass
        out = {"items": [{"id": it["id"], "text": lookup(it["text"])} for it in items]}
        body = json.dumps({"choices": [{"message": {"role": "assistant", "content": json.dumps(out, ensure_ascii=False)}}]}, ensure_ascii=False).encode()
        self._send(200, body, "application/json")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print(f"serving on http://127.0.0.1:{port}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
