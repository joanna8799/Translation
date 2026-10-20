// 漫畫：看到的圖片逐張處理，氣泡偵測、OCR（擴充內的 offscreen 文件）、翻譯、擦字排版，疊一層畫布在原圖上。
(function (RT) {
  'use strict';
  const MIN_SIDE = 350;
  const state = { io: null, queue: [], running: false, overlays: new Map(), enabled: false, done: 0, mo: null };

  function eligible(img) {
    if (!(img instanceof HTMLImageElement) || img.closest('.rt-overlay')) return false;
    if (img.dataset.rtState && img.dataset.rtState !== 'retry') return false;
    const r = img.getBoundingClientRect();
    return img.naturalWidth >= MIN_SIDE && img.naturalHeight >= MIN_SIDE && r.width >= 200 && r.height >= 200;
  }
  async function pixelsOf(img) {
    // 先試同網域直接畫；跨網域會 taint，退到由背景抓位元組
    try {
      const c = document.createElement('canvas'); c.width = img.naturalWidth; c.height = img.naturalHeight;
      const ctx = c.getContext('2d', { willReadFrequently: true }); ctx.drawImage(img, 0, 0); ctx.getImageData(0, 0, 1, 1);
      return c;
    } catch (e) {}
    const r = await RT.send({ type: 'rt:fetchImage', url: img.currentSrc || img.src });
    if (!r.ok) throw new Error(r.error);
    const im = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error('圖片解碼失敗')); i.src = r.dataURL; });
    const c = document.createElement('canvas'); c.width = im.width; c.height = im.height; c.getContext('2d').drawImage(im, 0, 0);
    return c;
  }
  function place(img, ov) {
    const r = img.getBoundingClientRect();
    ov.style.left = `${r.left + window.scrollX}px`; ov.style.top = `${r.top + window.scrollY}px`;
    ov.style.width = `${r.width}px`; ov.style.height = `${r.height}px`;
  }
  function attachOverlay(img, canvas) {
    const ov = document.createElement('div'); ov.className = 'rt-overlay'; ov.title = '點一下看原圖，再點一下看譯圖';
    ov.appendChild(canvas); document.body.appendChild(ov); place(img, ov);
    ov.addEventListener('click', () => { ov.classList.toggle('rt-hidden'); });
    state.overlays.set(img, ov);
    const ro = new ResizeObserver(() => place(img, ov)); ro.observe(img);
    new MutationObserver(() => { if (img.currentSrc !== ov.dataset.src) { ov.remove(); ro.disconnect(); state.overlays.delete(img); img.dataset.rtState = ''; if (state.enabled) enqueue(img); } }).observe(img, { attributes: true, attributeFilter: ['src', 'srcset'] });
    ov.dataset.src = img.currentSrc;
  }
  async function process(img) {
    img.dataset.rtState = 'working';
    try {
      const src = await pixelsOf(img);
      const det = RT.detectBubbles({ width: src.width, height: src.height }, src);
      if (!det.boxes.length) { img.dataset.rtState = 'none'; return; }
      const mode = (RT.settings && RT.settings.mangaLang) || 'ja_vert';
      const crops = det.boxes.map((b) => RT.bubbleCrop(src, det, b).toDataURL('image/png'));
      const o = await RT.send({ type: 'rt:ocr', payload: { images: crops, mode } });
      if (!o.ok) throw new Error(o.error);
      const items = det.boxes.map((b, i) => ({ box: b, text: (o.results[i] || {}).text || '', translated: '' }));
      const withText = items.filter((it) => it.text.length >= 1);
      if (!withText.length) { img.dataset.rtState = 'none'; return; }
      const t = await RT.send({ type: 'rt:translate', texts: withText.map((it) => it.text), kind: 'manga' });
      if (!t.ok) throw new Error(t.error);
      withText.forEach((it, i) => { it.translated = t.translations[i] || ''; });
      const canvas = RT.renderTranslated(src, src.width, src.height, det, items, mode === 'ja_vert');
      attachOverlay(img, canvas);
      img.dataset.rtState = 'done'; state.done++;
      document.dispatchEvent(new CustomEvent('rt:progress'));
    } catch (e) {
      img.dataset.rtState = 'error'; RT.log('漫畫處理失敗', e);
    }
  }
  async function run() {
    if (state.running) return; state.running = true;
    try { while (state.queue.length) { const img = state.queue.shift(); if (!img.isConnected) continue; await process(img); } }
    finally { state.running = false; }
  }
  function enqueue(img) { if (!state.queue.includes(img)) { state.queue.push(img); run(); } }
  function observe(img) {
    if (!state.io) state.io = new IntersectionObserver((entries) => { for (const e of entries) if (e.isIntersecting && eligible(e.target)) enqueue(e.target); }, { rootMargin: '150% 0px' });
    state.io.observe(img);
  }
  function scan() {
    let n = 0;
    for (const img of document.images) { if (img.dataset.rtObserved) continue; img.dataset.rtObserved = '1'; n++; if (img.complete) observe(img); else img.addEventListener('load', () => observe(img), { once: true }); }
    return n;
  }
  let repositionScheduled = false;
  function reposition() { if (repositionScheduled) return; repositionScheduled = true; requestAnimationFrame(() => { repositionScheduled = false; for (const [img, ov] of state.overlays) place(img, ov); }); }
  window.addEventListener('scroll', reposition, { passive: true }); window.addEventListener('resize', reposition);

  RT.manga = {
    start() {
      state.enabled = true; const n = scan();
      if (!state.mo) { let t = null; state.mo = new MutationObserver(() => { if (!state.enabled) return; clearTimeout(t); t = setTimeout(scan, 700); }); state.mo.observe(document.body, { childList: true, subtree: true }); }
      return n;
    },
    stop() { state.enabled = false; },
    restore() {
      state.enabled = false; state.queue.length = 0;
      for (const [img, ov] of state.overlays) { ov.remove(); delete img.dataset.rtState; }
      state.overlays.clear(); state.done = 0;
      document.querySelectorAll('img[data-rt-state]').forEach((i) => { delete i.dataset.rtState; });
    },
    get done() { return state.done; },
    get pending() { return state.queue.length + (state.running ? 1 : 0); },
  };
})(window.RT);
