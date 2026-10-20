package dev.readtrans.spike

import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.text.InputType
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * 驗證用控制台：開無障礙設定、勾目標 app、看最新一輪、匯出紀錄。
 * 全部用程式碼建 view，避免多一層 layout 資源出錯。
 */
class MainActivity : AppCompatActivity() {

    private lateinit var status: TextView
    private lateinit var latest: TextView
    private lateinit var log: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pad = (16 * resources.displayMetrics.density).toInt()
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
        }
        setContentView(ScrollView(this).apply { addView(col) })

        status = TextView(this)
        col.addView(status)

        col.addView(Button(this).apply {
            text = "開啟無障礙設定"
            setOnClickListener { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
        })

        col.addView(TextView(this).apply { text = "\n目標 app（沒勾的事件不會送進服務）" })
        val enabled = TargetApps.enabled(this).toMutableSet()
        for (app in TargetApps.KNOWN) {
            col.addView(CheckBox(this).apply {
                text = "${app.label}  ${app.pkg}"
                isChecked = app.pkg in enabled
                setOnCheckedChangeListener { _, on ->
                    if (on) enabled.add(app.pkg) else enabled.remove(app.pkg)
                    TargetApps.setEnabled(this@MainActivity, enabled.filter { p -> TargetApps.KNOWN.any { it.pkg == p } }.toSet())
                }
            })
        }
        col.addView(TextView(this).apply { text = "自訂 package（逗號或換行分隔）" })
        col.addView(EditText(this).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            setText(TargetApps.custom(this@MainActivity))
            setOnFocusChangeListener { _, hasFocus -> if (!hasFocus) TargetApps.setCustom(this@MainActivity, text.toString()) }
        })

        col.addView(Button(this).apply {
            text = "預先下載翻譯模型（ko、ja）"
            setOnClickListener {
                lifecycleScope.launch {
                    try {
                        L0Translator.ensureModel("ko")
                        L0Translator.ensureModel("ja")
                        toast("模型就緒")
                    } catch (e: Exception) {
                        toast("下載失敗：${e.message}")
                    }
                }
            }
        })

        col.addView(TextView(this).apply { text = "\n最新一輪" })
        latest = TextView(this).apply { setTextIsSelectable(true) }
        col.addView(latest)

        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(Button(this).apply {
            text = "匯出紀錄"
            setOnClickListener { toast(Metrics.export(this@MainActivity)) }
        })
        row.addView(Button(this).apply {
            text = "清除紀錄"
            setOnClickListener { Metrics.clear(this@MainActivity); refreshLog() }
        })
        row.addView(Button(this).apply {
            text = "重新整理"
            setOnClickListener { refreshLog() }
        })
        col.addView(row)

        col.addView(TextView(this).apply { text = "\n最近 30 筆紀錄" })
        log = TextView(this).apply { textSize = 11f; setTextIsSelectable(true) }
        col.addView(log)

        lifecycleScope.launch {
            TextBus.latest.collectLatest { snap ->
                latest.text = if (snap == null) "尚無資料。開啟服務後到目標 app 的小說頁停 2 秒。" else buildString {
                    appendLine("package：${snap.pkg}")
                    appendLine("節點數：${snap.nodes.size}　字數：${snap.charCount}　走訪：${snap.walkMs} ms${if (snap.truncated) "　（已截斷）" else ""}")
                    appendLine("hash：${snap.hash.take(12)}")
                    appendLine("--- 前 8 個節點 ---")
                    for (n in snap.nodes.take(8)) {
                        appendLine("[${n.bounds.top},${n.bounds.left}] ${n.className.substringAfterLast('.')}：${n.text.take(60)}")
                    }
                }
                refreshLog()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        val on = isServiceEnabled()
        status.text = if (on) "服務狀態：已啟用" else "服務狀態：未啟用，請按下方按鈕到設定裡開啟 ReadTrans Spike"
        refreshLog()
    }

    private fun isServiceEnabled(): Boolean {
        val expected = ComponentName(this, ReaderAccessibilityService::class.java).flattenToString()
        val list = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        return list.split(':').any { it.equals(expected, ignoreCase = true) }
    }

    private fun refreshLog() {
        log.text = Metrics.tail(this).joinToString("\n")
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
}
