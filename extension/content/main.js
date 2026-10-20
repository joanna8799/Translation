// 入口：依設定決定這個網站要不要自動翻；接 popup 的指令。
(function (RT) {
  'use strict';
  const host = location.hostname;
  let active = false;

  function shouldAuto(s) {
    if (!s) return false;
    if (s.offHosts.includes(host)) return false;
    return s.autoAll || s.autoHosts.includes(host);
  }
  function start() {
    if (!RT.settings) return;
    active = true;
    if (RT.settings.novel) RT.novel.start();
    if (RT.settings.manga) RT.manga.start();
  }
  function restore() { active = false; RT.novel.restore(); RT.manga.restore(); }

  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (!msg || typeof msg.type !== 'string') return false;
    if (msg.type === 'rt:page-translate') { RT.loadSettings().then(() => { start(); sendResponse({ ok: true }); }); return true; }
    if (msg.type === 'rt:page-restore') { restore(); sendResponse({ ok: true }); return false; }
    if (msg.type === 'rt:page-status') { sendResponse({ ok: true, active, host, novelDone: RT.novel.done, novelPending: RT.novel.pending, mangaDone: RT.manga.done, mangaPending: RT.manga.pending }); return false; }
    return false;
  });
  chrome.storage.onChanged.addListener((changes) => { if (changes.settings) RT.loadSettings(); });

  (async () => {
    const s = await RT.loadSettings();
    if (shouldAuto(s)) {
      // 等頁面安靜一下再掃，避免跟網站自己的渲染打架
      setTimeout(start, 600);
    }
  })();
})(window.RT);
