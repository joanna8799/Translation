package dev.readtrans.spike

import android.graphics.Rect
import android.os.Build
import android.view.accessibility.AccessibilityNodeInfo

/**
 * 走訪無障礙樹，收集可見且有文字的節點。
 *
 * 只取 text，不取 contentDescription：小說正文一定在 text，contentDescription 多半是圖片與按鈕說明。
 * 走訪有上限，避免在巨大的 RecyclerView 上卡住主執行緒。
 */
object NodeCollector {
    data class Result(val nodes: List<TextNode>, val truncated: Boolean)

    private const val MAX_VISIT = 1500
    private const val MAX_COLLECT = 400
    private const val MIN_CHARS = 2

    fun collect(root: AccessibilityNodeInfo): Result {
        val out = ArrayList<TextNode>(64)
        val stack = ArrayDeque<AccessibilityNodeInfo>()
        stack.addLast(root)
        var visited = 0
        var truncated = false
        val rect = Rect()

        while (stack.isNotEmpty()) {
            val node = stack.removeLast()
            visited++
            if (visited > MAX_VISIT || out.size >= MAX_COLLECT) {
                truncated = true
                recycle(node)
                break
            }

            if (node.isVisibleToUser) {
                val text = node.text?.toString()?.trim()
                if (!text.isNullOrEmpty() && text.length >= MIN_CHARS && !isEditable(node)) {
                    node.getBoundsInScreen(rect)
                    if (!rect.isEmpty) {
                        out.add(
                            TextNode(
                                text = text,
                                bounds = Rect(rect),
                                className = node.className?.toString() ?: "",
                                viewId = node.viewIdResourceName,
                            )
                        )
                    }
                }
                // 反向壓入，讓彈出順序維持原本的子節點順序。
                for (i in node.childCount - 1 downTo 0) {
                    node.getChild(i)?.let(stack::addLast)
                }
            }
            if (node !== root) recycle(node)
        }
        while (stack.isNotEmpty()) recycle(stack.removeLast())

        // 依畫面位置排序：由上到下，同列由左到右。閱讀器的樹順序通常已經正確，這是保險。
        out.sortWith(compareBy<TextNode>({ it.bounds.top / 8 }, { it.bounds.left }))
        return Result(out, truncated)
    }

    private fun isEditable(node: AccessibilityNodeInfo): Boolean =
        node.isEditable || node.className?.toString()?.endsWith("EditText") == true

    @Suppress("DEPRECATION")
    private fun recycle(node: AccessibilityNodeInfo) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) node.recycle()
    }
}
