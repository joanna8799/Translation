// 在 offscreen 文件裡跑 tesseract.js。語言檔與 wasm 都在擴充套件內，不連任何伺服器。
const workers = new Map(); // lang -> Promise<Worker>
function langsFor(mode) { return mode === 'ko' ? ['kor'] : mode === 'ja_vert' ? ['jpn_vert'] : ['jpn']; }
function getWorker(mode) {
  const key = langsFor(mode).join('+');
  if (!workers.has(key)) {
    workers.set(key, Tesseract.createWorker(langsFor(mode), 1, {
      workerPath: chrome.runtime.getURL('vendor/tesseract/worker.min.js'),
      corePath: chrome.runtime.getURL('vendor/tesseract/'),
      langPath: chrome.runtime.getURL('vendor/tesseract/lang/'),
      gzip: false,
      workerBlobURL: false,
      logger: () => {},
    }).catch((e) => { workers.delete(key); throw e; }));
  }
  return workers.get(key);
}
function clean(t, mode) {
  t = t.replace(/[\\\/|<>_~^`]/g, '');
  return mode.startsWith('ja') ? t.replace(/\s+/g, '') : t.replace(/[ \t]+/g, ' ').replace(/\n+/g, ' ').trim();
}
let chain = Promise.resolve();
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || msg.type !== 'rt:ocr-run') return false;
  const { images, mode } = msg.payload || {};
  chain = chain.then(async () => {
    try {
      const w = await getWorker(mode || 'ja_vert');
      const vertical = mode === 'ja_vert';
      await w.setParameters({ tessedit_pageseg_mode: vertical ? '5' : '6', preserve_interword_spaces: '1' });
      const out = [];
      for (const dataURL of images || []) {
        const { data } = await w.recognize(dataURL);
        out.push({ text: clean(data.text || '', mode || 'ja_vert'), confidence: Math.round(data.confidence || 0) });
      }
      sendResponse({ ok: true, results: out });
    } catch (e) {
      sendResponse({ ok: false, error: e && e.message ? e.message : String(e) });
    }
  });
  return true;
});
