// ReadTrans 背景工作：抓跨網域圖片、翻譯（三種引擎）、把 OCR 轉給 offscreen 文件。
// 內容腳本永遠只送文字去翻譯；圖片只在瀏覽器裡流動，不上傳。

const DEFAULTS = {
  provider: 'gtx',            // gtx（Google 翻譯公開端點，免費不用 key）| gemini | openai
  geminiKey: '', geminiModel: 'gemini-2.5-flash-lite',
  openaiBase: 'https://api.openai.com/v1', openaiKey: '', openaiModel: 'gpt-4o-mini',
  target: 'zh-TW',
  mangaLang: 'ja_vert',       // ja_vert | ja | ko
  autoAll: true, autoHosts: [], offHosts: [],
  novel: true, manga: true,
  glossary: '',
};

async function getSettings() {
  const { settings } = await chrome.storage.sync.get('settings');
  return Object.assign({}, DEFAULTS, settings || {});
}

// ---------- 翻譯引擎 ----------
function gtxOne(text, tl) {
  const url = `https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=${encodeURIComponent(tl)}&dt=t&q=${encodeURIComponent(text)}`;
  return fetch(url).then(async (r) => {
    if (!r.ok) throw new Error(`Google 翻譯回應 ${r.status}`);
    const j = await r.json();
    return (j[0] || []).map((seg) => seg[0] || '').join('');
  });
}
async function translateGtx(texts, s) {
  const out = new Array(texts.length);
  const N = 4;
  for (let i = 0; i < texts.length; i += N) {
    const slice = texts.slice(i, i + N);
    const res = await Promise.all(slice.map((t) => gtxOne(t, s.target).catch((e) => `[翻譯失敗：${e.message}]`)));
    res.forEach((r, k) => { out[i + k] = r; });
  }
  return out;
}

function llmPrompt(texts, s, kind) {
  const glossary = s.glossary && s.glossary.trim() ? `\n詞彙表（務必採用）：\n${s.glossary.trim()}\n` : '';
  const what = kind === 'manga' ? '漫畫對話框裡的句子（OCR 結果，可能有錯字漏字，依上下文推測原意）' : '小說段落';
  return `把下面每一段${what}翻成${s.target === 'zh-TW' ? '台灣繁體中文' : s.target}，口語、通順、符合角色語氣，人名音譯前後一致。${glossary}
只回傳 JSON：{"items":[{"id":0,"text":"譯文"}]}，id 與輸入一一對應，不要解釋、不要 markdown。

輸入：
${JSON.stringify({ items: texts.map((t, i) => ({ id: i, text: t })) })}`;
}
function parseJsonLoose(str) {
  try { return JSON.parse(str); } catch (e) {}
  const m = str.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (m) { try { return JSON.parse(m[1]); } catch (e) {} }
  const a = str.indexOf('{'), b = str.lastIndexOf('}');
  if (a >= 0 && b > a) { try { return JSON.parse(str.slice(a, b + 1)); } catch (e) {} }
  throw new Error('模型回覆不是 JSON');
}
function mapItems(json, n) {
  const out = new Array(n).fill('');
  for (const it of (json && json.items) || []) { const id = Number(it.id); if (id >= 0 && id < n) out[id] = String(it.text || ''); }
  return out;
}
async function translateGemini(texts, s, kind) {
  if (!s.geminiKey) throw new Error('沒有設定 Gemini API key');
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(s.geminiModel)}:generateContent?key=${encodeURIComponent(s.geminiKey)}`;
  const r = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: llmPrompt(texts, s, kind) }] }], generationConfig: { temperature: 0.3, responseMimeType: 'application/json' } }) });
  if (!r.ok) throw new Error(`Gemini 回應 ${r.status}：${(await r.text()).slice(0, 200)}`);
  const j = await r.json();
  const text = (((j.candidates || [])[0] || {}).content || {}).parts?.map((p) => p.text).join('') || '';
  return mapItems(parseJsonLoose(text), texts.length);
}
async function translateOpenAI(texts, s, kind) {
  const base = (s.openaiBase || '').replace(/\/$/, '');
  if (!base) throw new Error('沒有設定 OpenAI 相容端點');
  const headers = { 'content-type': 'application/json' };
  if (s.openaiKey) headers.authorization = `Bearer ${s.openaiKey}`;
  const r = await fetch(`${base}/chat/completions`, { method: 'POST', headers,
    body: JSON.stringify({ model: s.openaiModel, temperature: 0.3, messages: [{ role: 'user', content: llmPrompt(texts, s, kind) }] }) });
  if (!r.ok) throw new Error(`端點回應 ${r.status}：${(await r.text()).slice(0, 200)}`);
  const j = await r.json();
  const text = (((j.choices || [])[0] || {}).message || {}).content || '';
  return mapItems(parseJsonLoose(text), texts.length);
}
async function translate(texts, kind) {
  const s = await getSettings();
  if (!texts.length) return [];
  if (s.provider === 'gemini') return batched(texts, 40, (b) => translateGemini(b, s, kind));
  if (s.provider === 'openai') return batched(texts, 40, (b) => translateOpenAI(b, s, kind));
  return translateGtx(texts, s);
}
async function batched(texts, n, fn) {
  const out = [];
  for (let i = 0; i < texts.length; i += n) out.push(...(await fn(texts.slice(i, i + n))));
  return out;
}

// ---------- 跨網域圖片 ----------
async function fetchImageDataURL(url) {
  const r = await fetch(url, { credentials: 'include' });
  if (!r.ok) throw new Error(`圖片回應 ${r.status}`);
  const blob = await r.blob();
  return new Promise((res, rej) => { const fr = new FileReader(); fr.onload = () => res(fr.result); fr.onerror = () => rej(fr.error); fr.readAsDataURL(blob); });
}

// ---------- OCR：offscreen 文件（MV3 的 service worker 不能開 Web Worker） ----------
let offscreenReady = null;
async function ensureOffscreen() {
  if (offscreenReady) return offscreenReady;
  offscreenReady = (async () => {
    const has = chrome.runtime.getContexts ? (await chrome.runtime.getContexts({ contextTypes: ['OFFSCREEN_DOCUMENT'] })).length > 0 : false;
    if (!has) {
      await chrome.offscreen.createDocument({ url: 'offscreen/offscreen.html', reasons: ['WORKERS'], justification: '在瀏覽器裡跑 OCR（tesseract.js 需要 Web Worker）' }).catch((e) => { if (!String(e).includes('single offscreen')) throw e; });
    }
  })();
  return offscreenReady;
}
async function ocr(payload) {
  await ensureOffscreen();
  const timeout = new Promise((res) => setTimeout(() => res({ ok: false, error: 'OCR 逾時（120 秒）' }), 120000));
  const r = await Promise.race([chrome.runtime.sendMessage({ type: 'rt:ocr-run', payload }), timeout]);
  return r || { ok: false, error: 'offscreen 文件沒有回應' };
}

// ---------- 訊息路由 ----------
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || typeof msg.type !== 'string' || !msg.type.startsWith('rt:')) return false;
  if (msg.type === 'rt:ocr-run') return false; // 給 offscreen 的，背景不處理
  (async () => {
    try {
      if (msg.type === 'rt:settings') return sendResponse({ ok: true, settings: await getSettings() });
      if (msg.type === 'rt:translate') return sendResponse({ ok: true, translations: await translate(msg.texts || [], msg.kind || 'novel') });
      if (msg.type === 'rt:fetchImage') return sendResponse({ ok: true, dataURL: await fetchImageDataURL(msg.url) });
      if (msg.type === 'rt:ocr') return sendResponse(await ocr(msg.payload));
      sendResponse({ ok: false, error: `未知訊息 ${msg.type}` });
    } catch (e) {
      sendResponse({ ok: false, error: e && e.message ? e.message : String(e) });
    }
  })();
  return true;
});

chrome.runtime.onInstalled.addListener(async () => {
  const { settings } = await chrome.storage.sync.get('settings');
  if (!settings) await chrome.storage.sync.set({ settings: DEFAULTS });
});
