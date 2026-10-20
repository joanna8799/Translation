package dev.readtrans.spike

import android.util.LruCache
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.tasks.await

/**
 * L0 端側翻譯：ML Kit Translation。免費、離線、第一次要下載模型（每個語言對約 30 MB）。
 * 目標語言 ML Kit 只有簡體中文，產品版再接 OpenCC 轉繁體。
 */
object L0Translator {
    private val cache = LruCache<String, String>(4000)
    private val clients = HashMap<String, Translator>()
    private val ready = HashSet<String>()

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
        if (hangul * 10 >= letters * 3) return TranslateLanguage.KOREAN
        if (kana > 0) return TranslateLanguage.JAPANESE
        return null
    }

    private fun client(src: String): Translator = clients.getOrPut(src) {
        Translation.getClient(
            TranslatorOptions.Builder()
                .setSourceLanguage(src)
                .setTargetLanguage(TranslateLanguage.CHINESE)
                .build()
        )
    }

    suspend fun ensureModel(src: String) {
        if (src in ready) return
        client(src).downloadModelIfNeeded(DownloadConditions.Builder().build()).await()
        ready.add(src)
    }

    /** 回傳 (譯文列表, 快取命中數)。 */
    suspend fun translateAll(src: String, texts: List<String>): Pair<List<String>, Int> {
        ensureModel(src)
        val t = client(src)
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
                t.translate(s).await()
            } catch (e: Exception) {
                "[翻譯失敗 ${e.javaClass.simpleName}]"
            }
            cache.put(key, r)
            out.add(r)
        }
        return out to hits
    }
}
