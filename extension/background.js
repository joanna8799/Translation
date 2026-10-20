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
  story: '',
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

// ---------- 給語言模型的調教 ----------
// 跟 EasyComix 的「故事背景／上下文翻譯」同一個思路：詞彙表、作品背景、最近翻過的句子都放進提示，
// 名詞與語氣才會前後一致；對白要短；OCR 錯字要靠上下文還原。
const CTX_MAX = 40, CTX_SEND = 20;
async function loadContext(host) {
  const area = chrome.storage.session || chrome.storage.local;
  const r = await area.get('ctx:' + host).catch(() => ({}));
  return (r && r['ctx:' + host]) || [];
}
async function saveContext(host, pairs) {
  const area = chrome.storage.session || chrome.storage.local;
  const cur = await loadContext(host);
  const next = cur.concat(pairs.filter((p) => p.src && p.dst)).slice(-CTX_MAX);
  await area.set({ ['ctx:' + host]: next }).catch(() => {});
}
function llmPrompt(texts, s, kind, ctx) {
  const target = s.target === 'zh-TW' ? '台灣用語的繁體中文' : s.target === 'zh-CN' ? '簡體中文' : s.target;
  const glossary = s.glossary && s.glossary.trim() ? `\n詞彙表（原文=譯名，務必照用）：\n${s.glossary.trim()}\n` : '';
  const story = s.story && s.story.trim() ? `\n作品背景：${s.story.trim()}\n` : '';
  const prior = ctx && ctx.length ? `\n前文對照（這個網站最近翻過的句子，名詞、稱呼、語氣要跟它一致）：\n${ctx.slice(-CTX_SEND).map((c) => `${c.src} => ${c.dst}`).join('\n')}\n` : '';
  const kindRules = kind === 'manga'
    ? `這是漫畫對話框裡的句子，依閱讀順序排列。
- 對白要短，像台灣出版社的正式譯本，塞得進對話框；不要把一句拆成兩句。
- 原文是 OCR 結果：直書斷行造成的空格、換行、錯字、漏字、多字，先依上下文還原再翻。
- 狀聲詞、語氣詞翻成中文漫畫常見寫法；驚訝、命令、疑問的情緒要保留。
- 只有「……」或單一標點的句子，照原樣回傳。`
    : `這是小說段落，依閱讀順序排列。
- 文學語氣，通順自然，像台灣出版社的譯本；敘述與對白要分得出來。
- 原文若來自 OCR 或網頁，可能有斷行與錯字，依上下文還原再翻。
- 敬語、稱呼（哥哥、前輩、大人）依人物關係翻，前後一致。`;
  return `你是專業的日文、韓文譯者，把每一段原文翻成${target}。
${kindRules}
- 人名、地名照詞彙表；詞彙表沒有的，第一次出現後要跟前文對照一致，不要換譯法。
- 不要加註解、不要解釋、不要保留原文。${glossary}${story}${prior}
只回傳 JSON：{"items":[{"id":0,"text":"譯文"}]}，id 與輸入一一對應，不要 markdown。

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
async function translateGemini(texts, s, kind, ctx) {
  if (!s.geminiKey) throw new Error('沒有設定 Gemini API key');
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(s.geminiModel)}:generateContent?key=${encodeURIComponent(s.geminiKey)}`;
  const r = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: llmPrompt(texts, s, kind, ctx) }] }], generationConfig: { temperature: 0.3, responseMimeType: 'application/json' } }) });
  if (!r.ok) throw new Error(`Gemini 回應 ${r.status}：${(await r.text()).slice(0, 200)}`);
  const j = await r.json();
  const text = (((j.candidates || [])[0] || {}).content || {}).parts?.map((p) => p.text).join('') || '';
  return mapItems(parseJsonLoose(text), texts.length);
}
async function translateOpenAI(texts, s, kind, ctx) {
  const base = (s.openaiBase || '').replace(/\/$/, '');
  if (!base) throw new Error('沒有設定 OpenAI 相容端點');
  const headers = { 'content-type': 'application/json' };
  if (s.openaiKey) headers.authorization = `Bearer ${s.openaiKey}`;
  const r = await fetch(`${base}/chat/completions`, { method: 'POST', headers,
    body: JSON.stringify({ model: s.openaiModel, temperature: 0.3, messages: [{ role: 'user', content: llmPrompt(texts, s, kind, ctx) }] }) });
  if (!r.ok) throw new Error(`端點回應 ${r.status}：${(await r.text()).slice(0, 200)}`);
  const j = await r.json();
  const text = (((j.choices || [])[0] || {}).message || {}).content || '';
  return mapItems(parseJsonLoose(text), texts.length);
}
async function translate(texts, kind, host) {
  const s = await getSettings();
  if (!texts.length) return [];
  let out;
  if (s.provider === 'gemini' || s.provider === 'openai') {
    const ctx = await loadContext(host || '');
    const fn = s.provider === 'gemini' ? translateGemini : translateOpenAI;
    out = await batched(texts, 40, (b) => fn(b, s, kind, ctx));
    await saveContext(host || '', texts.map((t, i) => ({ src: t, dst: out[i] })));
  } else {
    out = await translateGtx(texts, s);
  }
  return out;
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

// ---------- OCR ----------
// Chrome：service worker 不能開 Web Worker，OCR 放在 offscreen 文件。
// Firefox、Safari：背景是一般頁面（manifest 的 background.scripts），tesseract 直接在這裡跑。
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
const localWorkers = new Map();
function langsFor(mode) { return mode === 'ko' ? ['kor'] : mode === 'ja_vert' ? ['jpn_vert'] : ['jpn']; }
function localWorker(mode) {
  const key = langsFor(mode).join('+');
  if (!localWorkers.has(key)) {
    localWorkers.set(key, Tesseract.createWorker(langsFor(mode), 1, {
      workerPath: chrome.runtime.getURL('vendor/tesseract/worker.min.js'),
      corePath: chrome.runtime.getURL('vendor/tesseract/'),
      langPath: chrome.runtime.getURL('vendor/tesseract/lang/'),
      gzip: false, workerBlobURL: false, logger: () => {},
    }).catch((e) => { localWorkers.delete(key); throw e; }));
  }
  return localWorkers.get(key);
}
function cleanOcr(t, mode) { t = t.replace(/[\\\/|<>_~^`]/g, ''); return mode.startsWith('ja') ? t.replace(/\s+/g, '') : t.replace(/[ \t]+/g, ' ').replace(/\n+/g, ' ').trim(); }
let localChain = Promise.resolve();
function localOcr(payload) {
  const { images, mode } = payload || {};
  const run = localChain.then(async () => {
    const w = await localWorker(mode || 'ja_vert');
    await w.setParameters({ tessedit_pageseg_mode: mode === 'ja_vert' ? '5' : '6', preserve_interword_spaces: '1' });
    const results = [];
    for (const dataURL of images || []) { const { data } = await w.recognize(dataURL); results.push({ text: cleanOcr(data.text || '', mode || 'ja_vert'), confidence: Math.round(data.confidence || 0) }); }
    return { ok: true, results };
  });
  localChain = run.catch(() => {});
  return run.catch((e) => ({ ok: false, error: e && e.message ? e.message : String(e) }));
}
async function ocr(payload) {
  if (!chrome.offscreen || typeof Worker === 'undefined' && typeof Tesseract !== 'undefined') {
    if (typeof Tesseract === 'undefined') return { ok: false, error: '這個瀏覽器的背景頁沒有載入 tesseract' };
    return localOcr(payload);
  }
  if (typeof Tesseract !== 'undefined' && typeof Worker !== 'undefined' && typeof document !== 'undefined') return localOcr(payload);
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
      if (msg.type === 'rt:translate') return sendResponse({ ok: true, translations: await translate(msg.texts || [], msg.kind || 'novel', msg.host || (sender.url ? new URL(sender.url).hostname : '')) });
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
