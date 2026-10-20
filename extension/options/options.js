(async function () {
  const $ = (id) => document.getElementById(id);
  const DEF = { provider: 'gtx', geminiKey: '', geminiModel: 'gemini-2.5-flash-lite', openaiBase: 'https://api.openai.com/v1', openaiKey: '', openaiModel: 'gpt-4o-mini', target: 'zh-TW', mangaLang: 'ja_vert', autoAll: true, autoHosts: [], offHosts: [], novel: true, manga: true, glossary: '' };
  const { settings } = await chrome.storage.sync.get('settings');
  const s = Object.assign({}, DEF, settings || {});
  document.querySelector(`input[name=provider][value="${s.provider}"]`).checked = true;
  for (const k of ['geminiKey', 'geminiModel', 'openaiBase', 'openaiKey', 'openaiModel', 'glossary']) $(k).value = s[k] || '';
  for (const k of ['novel', 'manga', 'autoAll']) $(k).checked = !!s[k];
  $('mangaLang').value = s.mangaLang; $('target').value = s.target;
  $('autoHosts').value = (s.autoHosts || []).join('\n'); $('offHosts').value = (s.offHosts || []).join('\n');
  $('save').onclick = async () => {
    s.provider = document.querySelector('input[name=provider]:checked').value;
    for (const k of ['geminiKey', 'geminiModel', 'openaiBase', 'openaiKey', 'openaiModel', 'glossary']) s[k] = $(k).value.trim();
    for (const k of ['novel', 'manga', 'autoAll']) s[k] = $(k).checked;
    s.mangaLang = $('mangaLang').value; s.target = $('target').value;
    const lines = (v) => v.split('\n').map((x) => x.trim()).filter(Boolean);
    s.autoHosts = lines($('autoHosts').value); s.offHosts = lines($('offHosts').value);
    await chrome.storage.sync.set({ settings: s });
    $('saved').textContent = '已儲存'; setTimeout(() => { $('saved').textContent = ''; }, 2000);
  };
})();
