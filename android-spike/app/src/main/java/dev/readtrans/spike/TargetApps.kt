package dev.readtrans.spike

import android.content.Context

/**
 * 目標閱讀 app 清單。package 名稱請用 `adb shell pm list packages | grep -i <關鍵字>` 核對，
 * 不對的在 app 內「自訂 package」欄位補。
 */
object TargetApps {
    data class App(val label: String, val pkg: String)

    val KNOWN = listOf(
        App("Naver Series", "com.nhn.android.nbooks"),
        App("Kakao Page", "com.kakao.page"),
        App("Ridi", "com.initialcoms.ridi"),
        App("Piccoma", "jp.kakao.piccoma"),
        App("LINE Manga", "jp.naver.linemanga.android"),
        App("Chrome（對照組）", "com.android.chrome"),
    )

    private const val PREFS = "targets"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_CUSTOM = "custom"

    fun enabled(ctx: Context): Set<String> {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val base = p.getStringSet(KEY_ENABLED, null) ?: KNOWN.map { it.pkg }.toSet()
        val custom = p.getString(KEY_CUSTOM, "")!!
            .split(',', '\n', ' ')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        return base + custom
    }

    fun setEnabled(ctx: Context, pkgs: Set<String>) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putStringSet(KEY_ENABLED, pkgs).apply()
        ReaderAccessibilityService.instance?.refreshTargets()
    }

    fun custom(ctx: Context): String =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_CUSTOM, "")!!

    fun setCustom(ctx: Context, raw: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_CUSTOM, raw).apply()
        ReaderAccessibilityService.instance?.refreshTargets()
    }
}
