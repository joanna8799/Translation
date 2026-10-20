package dev.readtrans.spike

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * 讀目標 app 畫面上的文字節點，去抖、去重、端側翻譯、畫到底部面板。
 * 事件只會從 serviceInfo.packageNames 列的 app 送進來。
 */
class ReaderAccessibilityService : AccessibilityService() {

    companion object {
        var instance: ReaderAccessibilityService? = null
            private set
        private const val DEBOUNCE_MS = 300L
        private const val EMPTY_THRESHOLD_CHARS = 20
    }

    private val handler = Handler(Looper.getMainLooper())
    private var pending: Runnable? = null
    private var lastHash: String? = null
    private var overlay: OverlayPanel? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var translateJob: Job? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        refreshTargets()
        overlay = OverlayPanel(this)
        TextBus.serviceRunning.value = true
        Metrics.log(this, "svc.connected", mapOf("targets" to TargetApps.enabled(this).joinToString(",")))
    }

    /** 使用者改了目標清單時重設 packageNames，讓系統端就過濾。 */
    fun refreshTargets() {
        val info = serviceInfo ?: return
        val targets = TargetApps.enabled(this)
        info.packageNames = if (targets.isEmpty()) null else targets.toTypedArray()
        serviceInfo = info
        lastHash = null
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return
        if (pkg !in TargetApps.enabled(this)) return
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            AccessibilityEvent.TYPE_VIEW_SCROLLED,
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> schedule(pkg)
        }
    }

    private fun schedule(pkg: String) {
        pending?.let(handler::removeCallbacks)
        val r = Runnable { collect(pkg) }
        pending = r
        handler.postDelayed(r, DEBOUNCE_MS)
    }

    private fun collect(pkg: String) {
        val root = rootInActiveWindow ?: run {
            Metrics.log(this, "a11y.noroot", mapOf("pkg" to pkg))
            return
        }
        // 前景視窗可能已經不是目標 app（例如使用者切回桌面）。
        val rootPkg = root.packageName?.toString()
        if (rootPkg != null && rootPkg != pkg) {
            overlay?.hide()
            return
        }

        val t0 = SystemClock.elapsedRealtime()
        val result = NodeCollector.collect(root)
        val walkMs = SystemClock.elapsedRealtime() - t0
        val hash = Snapshot.hashOf(result.nodes)

        if (hash == lastHash) {
            Metrics.log(this, "a11y.skip", mapOf("pkg" to pkg, "reason" to "same-hash"))
            return
        }
        lastHash = hash

        val snap = Snapshot(pkg, System.currentTimeMillis(), result.nodes, hash, walkMs, result.truncated)
        TextBus.latest.value = snap
        Metrics.log(
            this, "a11y.snapshot",
            mapOf("pkg" to pkg, "nodes" to snap.nodes.size, "chars" to snap.charCount,
                  "walkMs" to walkMs, "truncated" to result.truncated)
        )

        if (snap.charCount < EMPTY_THRESHOLD_CHARS) {
            Metrics.log(this, "a11y.empty", mapOf("pkg" to pkg, "nodes" to snap.nodes.size, "chars" to snap.charCount))
            overlay?.showHint("讀不到正文（${snap.nodes.size} 個節點、${snap.charCount} 字）。這個畫面可能是自繪的，要走 OCR 備援。")
            return
        }

        translateJob?.cancel()
        translateJob = scope.launch { translateAndRender(snap) }
    }

    private suspend fun translateAndRender(snap: Snapshot) {
        val texts = snap.nodes.map { it.text }
        val src = texts.firstNotNullOfOrNull { L0Translator.detect(it) }
        if (src == null) {
            overlay?.showHint("偵測不到韓文或日文，不翻譯。讀到 ${snap.nodes.size} 個節點、${snap.charCount} 字。")
            Metrics.log(this, "l0.skip", mapOf("pkg" to snap.pkg, "reason" to "no-src-lang"))
            return
        }
        overlay?.showHint("翻譯中…（${snap.nodes.size} 段）")
        val t0 = SystemClock.elapsedRealtime()
        val (translated, hits) = L0Translator.translateAll(src, texts)
        val ms = SystemClock.elapsedRealtime() - t0
        // 翻完時畫面可能已經換了，過期結果不畫。
        if (TextBus.latest.value?.hash != snap.hash) return
        val pairs = texts.zip(translated)
        TextBus.latestTranslation.value = pairs
        overlay?.render(pairs)
        Metrics.log(
            this, "l0.translate",
            mapOf("pkg" to snap.pkg, "src" to src, "chunks" to texts.size, "cacheHit" to hits, "ms" to ms)
        )
    }

    override fun onInterrupt() {
        pending?.let(handler::removeCallbacks)
    }

    override fun onDestroy() {
        pending?.let(handler::removeCallbacks)
        scope.cancel()
        overlay?.destroy()
        overlay = null
        TextBus.serviceRunning.value = false
        if (instance === this) instance = null
        Metrics.log(this, "svc.destroyed")
        super.onDestroy()
    }
}
