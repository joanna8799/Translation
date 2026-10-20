// 用 Playwright 把擴充載進 Chromium，開本機測試網站，確認小說頁自動出雙語、漫畫頁自動疊譯圖。
// 用法：node run.mjs <playwright 模組所在目錄> <輸出目錄>
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const [,, pwDir, outDir] = process.argv;
const require = createRequire(path.join(pwDir, 'package.json'));
const { chromium } = require('playwright');
const EXT = path.resolve(new URL('..', import.meta.url).pathname);
const BASE = 'http://127.0.0.1:8765';
mkdirSync(outDir, { recursive: true });

const ctx = await chromium.launchPersistentContext(path.join(outDir, 'profile'), {
  executablePath: process.env.CHROME_PATH || undefined,
  headless: false,
  args: ['--headless=new', `--disable-extensions-except=${EXT}`, `--load-extension=${EXT}`, '--no-sandbox'],
  viewport: { width: 900, height: 1200 },
});
let sw = ctx.serviceWorkers()[0];
if (!sw) sw = await ctx.waitForEvent('serviceworker');
const extId = new URL(sw.url()).host;
console.log('extension id', extId);

// 設定：OpenAI 相容端點指到本機假伺服器
const opt = await ctx.newPage();
await opt.goto(`chrome-extension://${extId}/options/options.html`);
await opt.evaluate((base) => chrome.storage.sync.set({ settings: { provider: 'openai', openaiBase: base + '/v1', openaiKey: 'x', openaiModel: 'mock', target: 'zh-TW', mangaLang: 'ja_vert', autoAll: true, autoHosts: [], offHosts: [], novel: true, manga: true, glossary: '' } }), BASE);
await opt.close();

const results = {};
// 小說
const novel = await ctx.newPage();
novel.on('console', (m) => { if (m.text().includes('ReadTrans')) console.log('  novel:', m.text()); });
await novel.goto(`${BASE}/novel.html`);
await novel.waitForSelector('.rt-tr', { timeout: 30000 });
await novel.waitForFunction(() => document.querySelectorAll('.rt-tr').length >= 5, null, { timeout: 30000 });
results.novel = await novel.$$eval('article p', (ps) => ps.map((p) => ({ src: p.firstChild.textContent.trim(), tr: (p.querySelector('.rt-tr') || {}).textContent || '' })));
await novel.screenshot({ path: path.join(outDir, 'novel.png'), fullPage: true });
console.log('novel paragraphs translated:', results.novel.length);

// 漫畫
const manga = await ctx.newPage();
manga.on('console', (m) => { if (m.text().includes('ReadTrans')) console.log('  manga:', m.text()); });
await manga.goto(`${BASE}/manga.html`);
await manga.waitForSelector('.rt-overlay', { timeout: 120000 });
await manga.waitForFunction(() => document.querySelectorAll('img[data-rt-state="done"], img[data-rt-state="none"], img[data-rt-state="error"]').length >= 1, null, { timeout: 120000 });
results.manga = await manga.$$eval('img', (imgs) => imgs.map((i) => ({ src: i.getAttribute('src'), state: i.dataset.rtState })));
await manga.screenshot({ path: path.join(outDir, 'manga.png'), fullPage: false });
console.log('manga images:', JSON.stringify(results.manga));

writeFileSync(path.join(outDir, 'results.json'), JSON.stringify(results, null, 1));
await ctx.close();
