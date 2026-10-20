package dev.readtrans.spike

import android.util.LruCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * 驗證用的 L0 翻譯。
 *
 * 產品版走 ML Kit Translation（端側、免費、離線），但 ML Kit 只在 Google Maven 上，
 * 這份驗證專案為了能在沒有 Google Maven 的環境編譯，改用 Google 翻譯的公開 gtx 端點
 * （Shinkansen 的「Google Translate」引擎用的也是它）。不需要 key，直接出繁體中文。
 * 它只是驗證「讀到的文字能不能翻」的替身，不要拿去上線。
 */
object L0Translator {
    private val cache = LruCache<String, String>(4000)

    /** 用字元範圍判斷來源語言。韓文字母佔三成以上判 ko；有假名判 ja；否則 null。 */
    fun detect(text: String): String? {
        var hangul = 0
        var kana = 0
        var letters = 0
        for (c in text) {
            when {
                c in '가'..'힣' || c in 'ᄀ'..'ᇿ' || c in '㄰'..'㆏' -> { hangul++; letters++ }
                c in '぀'..'ヿ' -> { kana++; letters++ }
                c.isLetter() -> letters++
            }
        }
        if (letters == 0) return null
        if (hangul * 10 >= letters * 3) return "ko"
        if (kana > 0) return "ja"
        return null
    }

    /** 回傳 (譯文列表, 快取命中數)。 */
    suspend fun translateAll(src: String, texts: List<String>): Pair<List<String>, Int> =
        withContext(Dispatchers.IO) {
            var hits = 0
            val out = ArrayList<String>(texts.size)
            for (s in texts) {
                val key = "$src|$s"
                val cached = cache.get(key)
                if (cached != null) {
                    hits++
                    out.add(cached)
                    continue
                }
                val r = try {
                    gtx(src, "zh-TW", s)
                } catch (e: Exception) {
                    "[翻譯失敗 ${e.javaClass.simpleName}]"
                }
                cache.put(key, r)
                out.add(r)
            }
            out to hits
        }

    private fun gtx(src: String, tgt: String, text: String): String {
        val q = URLEncoder.encode(text, "UTF-8")
        val url = URL("https://translate.googleapis.com/translate_a/single?client=gtx&sl=$src&tl=$tgt&dt=t&q=$q")
        val conn = url.openConnection() as HttpURLConnection
        conn.connectTimeout = 8000
        conn.readTimeout = 8000
        conn.setRequestProperty("User-Agent", "Mozilla/5.0")
        try {
            val body = conn.inputStream.bufferedReader().readText()
            // 格式：[[["譯文","原文",...],["譯文2","原文2",...]], null, "ko", ...]
            val segments = JSONArray(body).getJSONArray(0)
            val sb = StringBuilder()
            for (i in 0 until segments.length()) {
                val seg = segments.optJSONArray(i) ?: continue
                sb.append(seg.optString(0))
            }
            return sb.toString()
        } finally {
            conn.disconnect()
        }
    }
}
