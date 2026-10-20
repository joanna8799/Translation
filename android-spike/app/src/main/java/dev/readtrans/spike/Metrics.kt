package dev.readtrans.spike

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import org.json.JSONObject
import java.io.File

/** 每輪一行 JSONL，存在 app 私有目錄，匯出時複製到「下載」。 */
object Metrics {
    private const val FILE = "metrics.jsonl"

    private fun file(ctx: Context) = File(ctx.filesDir, FILE)

    @Synchronized
    fun log(ctx: Context, ev: String, fields: Map<String, Any?> = emptyMap()) {
        val o = JSONObject()
        o.put("t", System.currentTimeMillis())
        o.put("ev", ev)
        for ((k, v) in fields) o.put(k, v ?: JSONObject.NULL)
        file(ctx).appendText(o.toString() + "\n")
    }

    fun clear(ctx: Context) {
        file(ctx).delete()
    }

    fun tail(ctx: Context, n: Int = 30): List<String> {
        val f = file(ctx)
        if (!f.exists()) return emptyList()
        return f.readLines().takeLast(n)
    }

    /** 回傳匯出位置的描述。 */
    fun export(ctx: Context): String {
        val src = file(ctx)
        if (!src.exists()) return "沒有紀錄"
        val name = "readtrans-metrics-${System.currentTimeMillis()}.jsonl"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "application/x-ndjson")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val uri = ctx.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return "建立下載檔失敗"
            ctx.contentResolver.openOutputStream(uri)!!.use { out ->
                src.inputStream().use { it.copyTo(out) }
            }
            return "已存到「下載」/$name"
        }
        return "Android 9 以下請用 adb 取檔：${src.absolutePath}"
    }
}
