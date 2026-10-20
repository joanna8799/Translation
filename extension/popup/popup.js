(async function () {
  const $ = (id) => document.getElementById(id);
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  let host = ''; try { host = new URL(tab.url).hostname; } catch (e) {}
  $('host').textContent = host || '（這個分頁不能翻譯）';
  const { settings } = await chrome.storage.sync.get('settings');
  const s = Object.assign({ autoAll: true, autoHosts: [], offHosts: [] }, settings || {});
  const autoHere = () => !s.offHosts.includes(host) && (s.autoAll || s.autoHosts.includes(host));
  $('autoAll').checked = !!s.autoAll; $('autoHere').checked = autoHere();
  async function save() { await chrome.storage.sync.set({ settings: s }); }
  $('autoAll').onchange = async () => { s.autoAll = $('autoAll').checked; await save(); $('autoHere').checked = autoHere(); };
  $('autoHere').onchange = async () => {
    const on = $('autoHere').checked;
    s.offHosts = s.offHosts.filter((h) => h !== host); s.autoHosts = s.autoHosts.filter((h) => h !== host);
    if (on && !s.autoAll) s.autoHosts.push(host); if (!on && s.autoAll) s.offHosts.push(host);
    await save();
    if (on) send('rt:page-translate'); else send('rt:page-restore');
  };
  function send(type) { return new Promise((res) => { if (!tab) return res(null); chrome.tabs.sendMessage(tab.id, { type }, (r) => { void chrome.runtime.lastError; res(r || null); }); }); }
  $('translate').onclick = async () => { $('status').textContent = '開始翻譯…'; const r = await send('rt:page-translate'); if (!r) $('status').textContent = '這個分頁還沒載入擴充，重新整理頁面後再試。'; refresh(); };
  $('restore').onclick = async () => { await send('rt:page-restore'); refresh(); };
  $('options').onclick = () => chrome.runtime.openOptionsPage();
  async function refresh() {
    const r = await send('rt:page-status');
    if (!r) { $('status').textContent = '這個分頁還沒載入擴充，重新整理頁面後再試。'; return; }
    $('status').textContent = r.active ? `小說段落 ${r.novelDone} 段（待翻 ${r.novelPending}）、漫畫 ${r.mangaDone} 張（待翻 ${r.mangaPending}）` : '這一頁尚未翻譯';
  }
  refresh(); setInterval(refresh, 1500);
})();
