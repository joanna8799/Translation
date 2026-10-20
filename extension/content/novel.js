// 小說：找正文段落，批次翻譯，譯文接在原段落下面（雙語對照）。
(function (RT) {
  'use strict';
  const BLOCK = new Set(['P', 'DIV', 'LI', 'BLOCKQUOTE', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'TD', 'DD', 'DT', 'SECTION', 'ARTICLE', 'FIGCAPTION', 'SPAN']);
  const SKIP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEXTAREA', 'INPUT', 'BUTTON', 'SELECT', 'CODE', 'PRE', 'NAV', 'FOOTER', 'HEADER', 'FORM', 'SVG', 'CANVAS', 'IFRAME']);
  const state = { queue: [], running: false, done: 0, observer: null, enabled: false };

  function ownText(el) {
    // 只取直接文字與行內子元素的文字；有帶字的區塊子元素時這個元素不是葉段落
    let t = '';
    for (const n of el.childNodes) {
      if (n.nodeType === 3) t += n.nodeValue;
      else if (n.nodeType === 1) {
        if (n.classList && n.classList.contains('rt-tr')) continue;
        const disp = BLOCK.has(n.tagName) && n.tagName !== 'SPAN';
        if (disp && (n.textContent || '').trim().length > 20) return null;
        if (!SKIP.has(n.tagName)) t += n.textContent;
      }
    }
    return t.replace(/\s+/g, ' ').trim();
  }
  function isVisible(el) { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; }
  function collect(root) {
    const out = [];
    const walker = document.createTreeWalker(root || document.body, NodeFilter.SHOW_ELEMENT, {
      acceptNode(el) {
        if (SKIP.has(el.tagName) || el.closest('[contenteditable]') || el.classList.contains('rt-tr') || el.closest('.rt-overlay')) return NodeFilter.FILTER_REJECT;
        if (el.dataset.rtDone) return NodeFilter.FILTER_SKIP;
        return BLOCK.has(el.tagName) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
      },
    });
    let el;
    while ((el = walker.nextNode())) {
      const t = ownText(el);
      if (!t || t.length < 4 || !RT.isSource(t) || !isVisible(el)) continue;
      if (el.tagName === 'SPAN' && el.parentElement && BLOCK.has(el.parentElement.tagName) && el.parentElement.tagName !== 'SPAN') continue; // 行內 span 交給外層
      out.push({ el, text: t });
    }
    return out;
  }
  function inject(el, translated) {
    if (!translated) return;
    const d = document.createElement('div'); d.className = 'rt-tr'; d.textContent = translated;
    el.appendChild(d);
  }
  async function flush() {
    if (state.running) return; state.running = true;
    try {
      while (state.queue.length) {
        // 先翻離視窗近的
        state.queue.sort((a, b) => Math.abs(a.el.getBoundingClientRect().top) - Math.abs(b.el.getBoundingClientRect().top));
        const batch = []; let chars = 0;
        while (state.queue.length && batch.length < 25 && chars < 3000) { const it = state.queue.shift(); batch.push(it); chars += it.text.length; }
        batch.forEach((it) => { it.el.dataset.rtDone = '1'; });
        const r = await RT.send({ type: 'rt:translate', texts: batch.map((b) => b.text), kind: 'novel' });
        if (!r.ok) { RT.log('翻譯失敗', r.error); batch.forEach((it) => { inject(it.el, `[翻譯失敗：${r.error}]`); }); continue; }
        batch.forEach((it, i) => { inject(it.el, r.translations[i]); state.done++; });
        document.dispatchEvent(new CustomEvent('rt:progress'));
      }
    } finally { state.running = false; }
  }
  RT.novel = {
    scan(root) {
      const found = collect(root).filter((f) => !state.queue.some((q) => q.el === f.el));
      if (!found.length) return 0;
      state.queue.push(...found); flush(); return found.length;
    },
    start() {
      state.enabled = true; const n = RT.novel.scan();
      if (!state.observer) {
        let t = null;
        state.observer = new MutationObserver(() => { if (!state.enabled) return; clearTimeout(t); t = setTimeout(() => RT.novel.scan(), 700); });
        state.observer.observe(document.body, { childList: true, subtree: true, characterData: true });
      }
      return n;
    },
    stop() { state.enabled = false; },
    restore() {
      state.enabled = false; state.queue.length = 0;
      document.querySelectorAll('.rt-tr').forEach((n) => n.remove());
      document.querySelectorAll('[data-rt-done]').forEach((n) => { delete n.dataset.rtDone; });
      state.done = 0;
    },
    get done() { return state.done; },
    get pending() { return state.queue.length; },
  };
})(window.RT);
