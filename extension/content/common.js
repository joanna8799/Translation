// ReadTrans 內容腳本共用：設定、訊息、氣泡偵測、擦字排版。
window.RT = window.RT || {};
(function (RT) {
  'use strict';
  RT.send = (msg) => new Promise((res) => {
    try { chrome.runtime.sendMessage(msg, (r) => { if (chrome.runtime.lastError) res({ ok: false, error: chrome.runtime.lastError.message }); else res(r || { ok: false, error: '沒有回應' }); }); }
    catch (e) { res({ ok: false, error: e.message }); }
  });
  RT.settings = null;
  RT.loadSettings = async () => { const r = await RT.send({ type: 'rt:settings' }); RT.settings = r.ok ? r.settings : null; return RT.settings; };
  RT.log = (...a) => console.debug('[ReadTrans]', ...a);

  // 來源語言判斷：韓文字母或假名佔字母三成以上才當成要翻的文字
  RT.isSource = (text) => {
    let hangul = 0, kana = 0, letters = 0;
    for (const c of text) {
      const code = c.codePointAt(0);
      if ((code >= 0xAC00 && code <= 0xD7A3) || (code >= 0x1100 && code <= 0x11FF)) { hangul++; letters++; }
      else if (code >= 0x3040 && code <= 0x30FF) { kana++; letters++; }
      else if (/\p{L}/u.test(c)) letters++;
    }
    return letters >= 4 && (hangul + kana) * 10 >= letters * 3;
  };

  // ---------- 氣泡偵測（像素法） ----------
  RT.detectBubbles = function (img, drawSource) {
    const maxW = 1100; const scale = Math.min(1, maxW / img.width);
    const dw = Math.round(img.width * scale), dh = Math.round(img.height * scale);
    const c = document.createElement('canvas'); c.width = dw; c.height = dh;
    const ctx = c.getContext('2d', { willReadFrequently: true }); ctx.drawImage(drawSource || img, 0, 0, dw, dh);
    const px = ctx.getImageData(0, 0, dw, dh).data;
    let m = new Uint8Array(dw * dh);
    for (let i = 0, j = 0; i < px.length; i += 4, j++) { const l = (px[i] * 299 + px[i + 1] * 587 + px[i + 2] * 114) / 1000; m[j] = l > 235 ? 1 : 0; }
    const dil = (a) => { const o = new Uint8Array(a.length); for (let y = 0; y < dh; y++) for (let x = 0; x < dw; x++) { const i = y * dw + x; if (a[i]) { o[i] = 1; continue; } let v = 0; for (let yy = Math.max(0, y - 1); yy <= Math.min(dh - 1, y + 1) && !v; yy++) for (let xx = Math.max(0, x - 1); xx <= Math.min(dw - 1, x + 1); xx++) if (a[yy * dw + xx]) { v = 1; break; } o[i] = v; } return o; };
    const ero = (a) => { const o = new Uint8Array(a.length); for (let y = 0; y < dh; y++) for (let x = 0; x < dw; x++) { const i = y * dw + x; if (!a[i]) continue; let v = 1; for (let yy = Math.max(0, y - 1); yy <= Math.min(dh - 1, y + 1) && v; yy++) for (let xx = Math.max(0, x - 1); xx <= Math.min(dw - 1, x + 1); xx++) if (!a[yy * dw + xx]) { v = 0; break; } o[i] = v; } return o; };
    m = ero(ero(dil(dil(m))));
    const labels = new Int32Array(dw * dh); let n = 0; const stats = []; const stack = new Int32Array(dw * dh);
    for (let s = 0; s < m.length; s++) {
      if (!m[s] || labels[s]) continue;
      n++; let sp = 0; stack[sp++] = s; labels[s] = n; let minx = dw, miny = dh, maxx = 0, maxy = 0, area = 0;
      while (sp) { const i = stack[--sp]; const y = (i / dw) | 0, x = i - y * dw; area++;
        if (x < minx) minx = x; if (x > maxx) maxx = x; if (y < miny) miny = y; if (y > maxy) maxy = y;
        if (x > 0 && m[i - 1] && !labels[i - 1]) { labels[i - 1] = n; stack[sp++] = i - 1; }
        if (x < dw - 1 && m[i + 1] && !labels[i + 1]) { labels[i + 1] = n; stack[sp++] = i + 1; }
        if (y > 0 && m[i - dw] && !labels[i - dw]) { labels[i - dw] = n; stack[sp++] = i - dw; }
        if (y < dh - 1 && m[i + dw] && !labels[i + dw]) { labels[i + dw] = n; stack[sp++] = i + dw; } }
      stats.push({ label: n, x: minx, y: miny, w: maxx - minx + 1, h: maxy - miny + 1, area });
    }
    const pageArea = dw * dh; const boxes = [];
    for (const s of stats) {
      if (s.area < pageArea * 0.002 || s.area > pageArea * 0.15) continue;
      const fill = s.area / (s.w * s.h), aspect = s.w / s.h;
      if (fill < 0.55 || aspect < 0.2 || aspect > 6.5) continue;
      if (s.x <= 2 || s.y <= 2 || s.x + s.w >= dw - 2 || s.y + s.h >= dh - 2) continue;
      boxes.push(s);
    }
    boxes.sort((a, b) => ((a.y / 150) | 0) - ((b.y / 150) | 0) || b.x - a.x);
    boxes.forEach((b, i) => { b.id = i; });
    return { boxes, labels, dw, dh, scale };
  };
  RT.bubbleCrop = function (source, det, b) {
    const inv = 1 / det.scale; const x = Math.round(b.x * inv), y = Math.round(b.y * inv), w = Math.round(b.w * inv), h = Math.round(b.h * inv);
    const up = Math.max(1, Math.min(3, Math.round(900 / Math.max(w, h))));
    const c = document.createElement('canvas'); c.width = w * up; c.height = h * up;
    const ctx = c.getContext('2d', { willReadFrequently: true }); ctx.drawImage(source, x, y, w, h, 0, 0, w * up, h * up);
    const id = ctx.getImageData(0, 0, c.width, c.height); const d = id.data; const er = 6;
    for (let yy = 0; yy < c.height; yy++) for (let xx = 0; xx < c.width; xx++) {
      const dx = b.x + Math.floor(xx / up * det.scale), dy = b.y + Math.floor(yy / up * det.scale);
      let inside = true;
      for (let k = -er; k <= er && inside; k += er) for (let l = -er; l <= er; l += er) { const px = dx + k, py = dy + l; if (px < 0 || py < 0 || px >= det.dw || py >= det.dh || det.labels[py * det.dw + px] !== b.label) { inside = false; break; } }
      if (!inside) { const i = (yy * c.width + xx) * 4; d[i] = d[i + 1] = d[i + 2] = 255; }
    }
    ctx.putImageData(id, 0, 0); return c;
  };

  // ---------- 排版 ----------
  const VERT = { '，': '︐', '。': '︒', '！': '︕', '？': '︖', '、': '︑', '：': '︓', '；': '︔', '「': '﹁', '」': '﹂', '『': '﹃', '』': '﹄', '（': '︵', '）': '︶', '…': '︙', '—': '︱' };
  const NOSTART = '，。！？、：；」』）…';
  const FONT = '"Noto Sans TC","PingFang TC","Microsoft JhengHei","Noto Sans CJK TC",sans-serif';
  function fitHorizontal(ctx, text, bw, bh) {
    for (let size = 36; size >= 12; size -= 2) {
      ctx.font = `${size}px ${FONT}`;
      let lines = [], cur = '';
      for (const ch of text) { if (cur && ctx.measureText(cur + ch).width > bw && !NOSTART.includes(ch)) { lines.push(cur); cur = ch; } else cur += ch; }
      lines.push(cur); const lh = Math.round(size * 1.25);
      if (lines.length * lh <= bh && lines.every((l) => ctx.measureText(l).width <= bw)) {
        if (lines.length > 1) { const per = Math.ceil(text.length / lines.length); const bal = []; for (let i = 0; i < text.length; i += per) bal.push(text.slice(i, i + per));
          for (let i = 1; i < bal.length; i++) while (bal[i] && NOSTART.includes(bal[i][0])) { bal[i - 1] += bal[i][0]; bal[i] = bal[i].slice(1); }
          const b2 = bal.filter(Boolean); if (b2.every((l) => ctx.measureText(l).width <= bw)) lines = b2; }
        return { size, lines, lh };
      }
    }
    return { size: 12, lines: [text], lh: 15 };
  }
  function fitVertical(text, bw, bh) {
    text = [...text].map((c) => VERT[c] || c).join('');
    for (let size = 40; size >= 12; size -= 2) {
      const colW = Math.round(size * 1.3), chH = Math.round(size * 1.1), per = Math.max(1, Math.floor(bh / chH));
      const cols = []; for (let i = 0; i < text.length; i += per) cols.push(text.slice(i, i + per));
      if (cols.length * colW <= bw) return { size, cols, colW, chH };
    }
    const size = 12, colW = 16, chH = 13, per = Math.max(1, Math.floor(bh / chH)); const cols = []; for (let i = 0; i < text.length; i += per) cols.push(text.slice(i, i + per));
    return { size, cols, colW, chH };
  }
  RT.renderTranslated = function (source, width, height, det, items, vertical) {
    const c = document.createElement('canvas'); c.width = width; c.height = height;
    const ctx = c.getContext('2d', { willReadFrequently: true }); ctx.drawImage(source, 0, 0, width, height);
    const id = ctx.getImageData(0, 0, width, height); const d = id.data; const inv = 1 / det.scale;
    for (const it of items) {
      const b = it.box; const x = Math.round(b.x * inv), y = Math.round(b.y * inv), w = Math.round(b.w * inv), h = Math.round(b.h * inv);
      let r = 0, g = 0, bl = 0, cnt = 0;
      for (let yy = y; yy < Math.min(height, y + h); yy += 3) for (let xx = x; xx < Math.min(width, x + w); xx += 3) { const dx = Math.floor(xx * det.scale), dy = Math.floor(yy * det.scale); if (det.labels[dy * det.dw + dx] === b.label) { const i = (yy * width + xx) * 4; if (d[i] > 200) { r += d[i]; g += d[i + 1]; bl += d[i + 2]; cnt++; } } }
      if (!cnt) continue; r = Math.round(r / cnt); g = Math.round(g / cnt); bl = Math.round(bl / cnt);
      const inset = Math.round(Math.min(w, h) * 0.08);
      for (let yy = y + inset; yy < Math.min(height, y + h - inset); yy++) for (let xx = x + inset; xx < Math.min(width, x + w - inset); xx++) { const dx = Math.floor(xx * det.scale), dy = Math.floor(yy * det.scale); if (det.labels[dy * det.dw + dx] === b.label) { const i = (yy * width + xx) * 4; d[i] = r; d[i + 1] = g; d[i + 2] = bl; } }
    }
    ctx.putImageData(id, 0, 0); ctx.fillStyle = '#111'; ctx.textBaseline = 'top';
    for (const it of items) {
      const t = (it.translated || '').trim(); if (!t) continue;
      const b = it.box; const x = b.x * inv, y = b.y * inv, w = b.w * inv, h = b.h * inv;
      const iw = w * 0.7, ih = h * 0.7, cx = x + w / 2, cy = y + h / 2;
      if (vertical) {
        const f = fitVertical(t, iw, ih); ctx.font = `${f.size}px ${FONT}`;
        const totalW = f.cols.length * f.colW; const right = cx + totalW / 2;
        f.cols.forEach((col, ci) => { const xx = right - (ci + 1) * f.colW + (f.colW - f.size) / 2; let yy = cy - (col.length * f.chH) / 2; for (const ch of col) { ctx.fillText(ch, xx, yy); yy += f.chH; } });
      } else {
        const f = fitHorizontal(ctx, t, iw, ih); let yy = cy - (f.lines.length * f.lh) / 2;
        for (const line of f.lines) { const lw = ctx.measureText(line).width; ctx.fillText(line, cx - lw / 2, yy); yy += f.lh; }
      }
    }
    return c;
  };
})(window.RT);
