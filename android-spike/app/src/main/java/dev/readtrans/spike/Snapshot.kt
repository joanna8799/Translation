package dev.readtrans.spike

import android.graphics.Rect
import kotlinx.coroutines.flow.MutableStateFlow
import java.security.MessageDigest

/** 一個可見且有文字的無障礙節點。 */
data class TextNode(
    val text: String,
    val bounds: Rect,
    val className: String,
    val viewId: String?,
)

/** 一輪走訪的結果。 */
data class Snapshot(
    val pkg: String,
    val at: Long,
    val nodes: List<TextNode>,
    val hash: String,
    val walkMs: Long,
    val truncated: Boolean,
) {
    val charCount: Int get() = nodes.sumOf { it.text.length }

    companion object {
        fun hashOf(nodes: List<TextNode>): String {
            val md = MessageDigest.getInstance("SHA-1")
            for (n in nodes) {
                md.update(n.text.toByteArray(Charsets.UTF_8))
                md.update(0.toByte())
            }
            return md.digest().joinToString("") { "%02x".format(it) }
        }
    }
}

/** 服務與畫面之間的匯流排。 */
object TextBus {
    val serviceRunning = MutableStateFlow(false)
    val latest = MutableStateFlow<Snapshot?>(null)
    val latestTranslation = MutableStateFlow<List<Pair<String, String>>>(emptyList())
}
