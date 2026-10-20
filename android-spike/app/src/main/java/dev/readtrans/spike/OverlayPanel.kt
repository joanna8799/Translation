package dev.readtrans.spike

import android.accessibilityservice.AccessibilityService
import android.graphics.Color
import android.graphics.PixelFormat
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * 底部譯文面板。用 TYPE_ACCESSIBILITY_OVERLAY，從無障礙服務加視窗不需要 SYSTEM_ALERT_WINDOW。
 * 觸控穿透，不搶焦點。
 */
class OverlayPanel(private val service: AccessibilityService) {
    private val wm = service.getSystemService(WindowManager::class.java)
    private val root: ScrollView
    private val list: LinearLayout
    private var attached = false

    private val params = WindowManager.LayoutParams(
        WindowManager.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.BOTTOM
    }

    init {
        list = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            val pad = dp(12)
            setPadding(pad, pad, pad, pad)
        }
        root = ScrollView(service).apply {
            setBackgroundColor(Color.argb(225, 20, 20, 24))
            addView(list)
            visibility = View.GONE
        }
    }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), service.resources.displayMetrics).toInt()

    private fun ensureAttached() {
        if (attached) return
        val maxH = (service.resources.displayMetrics.heightPixels * 0.40f).toInt()
        params.height = maxH
        wm.addView(root, params)
        attached = true
    }

    fun showHint(text: String) {
        ensureAttached()
        list.removeAllViews()
        list.addView(line(text, Color.rgb(255, 200, 120), 14f))
        root.visibility = View.VISIBLE
    }

    /** pairs = (原文, 譯文)。只顯示譯文，原文留給長按功能（這次不做）。 */
    fun render(pairs: List<Pair<String, String>>) {
        ensureAttached()
        list.removeAllViews()
        if (pairs.isEmpty()) {
            root.visibility = View.GONE
            return
        }
        for ((_, tr) in pairs) {
            list.addView(line(tr, Color.WHITE, 15f))
        }
        root.visibility = View.VISIBLE
        root.scrollTo(0, 0)
    }

    fun hide() {
        if (attached) root.visibility = View.GONE
    }

    fun destroy() {
        if (attached) {
            wm.removeView(root)
            attached = false
        }
    }

    private fun line(text: String, color: Int, sp: Float): TextView =
        TextView(service).apply {
            this.text = text
            setTextColor(color)
            textSize = sp
            setLineSpacing(0f, 1.25f)
            setPadding(0, dp(4), 0, dp(4))
        }
}
