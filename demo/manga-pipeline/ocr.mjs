// OCR：對每個氣泡裁切後跑 tesseract.js。
//
// 這裡用 Tesseract 是因為這個環境只拿得到它的語言檔（raw.githubusercontent.com 的 tessdata_fast）。
// 產品版的 OCR 是 manga-ocr / PP-OCR（瀏覽器、Android）、ML Kit（Android）、Vision（iOS），
// 對漫畫字型與直式文字都比 Tesseract 準很多。這一步只要證明「氣泡裁切 → 文字」的介面。
//
// 用法：node ocr.mjs page.png bubbles.json ja|ko out.json
import { readFileSync, writeFileSync } from 'node:fs';
import { createWorker, PSM } from 'tesseract.js';
import sharp from 'sharp';

const [,, pagePath, bubblesPath, lang, outPath, maskDir] = process.argv;
const here = new URL('.', import.meta.url).pathname;
const tessdata = `${here}vendor/tessdata`;

const langs = lang === 'ja' ? ['jpn_vert'] : ['kor'];
const worker = await createWorker(langs, 1, { langPath: tessdata, cachePath: tessdata, gzip: false, logger: () => {} });
await worker.setParameters({
  tessedit_pageseg_mode: lang === 'ja' ? PSM.SINGLE_BLOCK_VERT_TEXT : PSM.SINGLE_BLOCK,
  preserve_interword_spaces: '1',
});

const page = sharp(pagePath);
const meta = await page.metadata();
const input = JSON.parse(readFileSync(bubblesPath, 'utf8'));
const out = [];
for (const b of input.bubbles) {
  // detect_bubbles.py 已經把遮罩外塗白、去掉框線、放大三倍
  const crop = await sharp(`${maskDir}/crop_${b.id}.png`).grayscale().png().toBuffer();
  const t0 = Date.now();
  const { data } = await worker.recognize(crop);
  let text = data.text.replace(/\s+/g, lang === 'ja' ? '' : ' ').replace(/[\\\/|<>_~^`]/g, '').trim();
  out.push({ id: b.id, box: b.box, text, vertical: lang === 'ja', ocr_ms: Date.now() - t0, confidence: Math.round(data.confidence) });
}
await worker.terminate();

const result = {
  page: input.page,
  source_lang: lang,
  target_lang: 'zh-TW',
  image_size: [meta.width, meta.height],
  bubbles: out,
};
writeFileSync(outPath, JSON.stringify(result, null, 1));
for (const b of out) console.log(`#${b.id} (${b.confidence}%) ${b.text}`);
