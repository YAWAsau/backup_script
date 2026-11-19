package io.github.yawasau.speedbackup.webview

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.topjohnwu.superuser.Shell
import java.lang.ref.WeakReference

/** App su authority only. Never inferred from the Rust connection or Dex health. */
object AppRootAuthorization {
    var state by mutableStateOf("checking")
        private set
    private val main = Handler(Looper.getMainLooper())
    private var running = false
    private var prompted = false
    private var owner = WeakReference<Activity>(null)
    private var explicitRetry = false

    // Use the explicit app language, not the device locale (including before a catalog loads).
    private fun localized(hant: String, hans: String) = if (NativeLanguage.get() == "zh-Hans") hans else hant
    fun title(): String = localized("App Root 授權", "App Root 授权")
    fun value(): String = when (state) {
        "granted" -> localized("已授權", "已授权")
        "denied" -> localized("未授權（點按重試）", "未授权（点按重试）")
        "unavailable" -> localized("無法確認（點按重試）", "无法确认（点按重试）")
        else -> localized("檢查中…", "检查中…")
    }
    @JvmStatic fun resume(activity: Activity) = check(activity, false)
    fun retry(activity: Activity) = check(activity, true)
    private fun check(activity: Activity, retry: Boolean) {
        owner = WeakReference(activity)
        explicitRetry = explicitRetry || retry
        if (running) return // Resume while the su dialog is open joins the same check.
        running = true
        state = "checking" // Never present a previous grant as current on return.
        Thread({
            var result = "unavailable"
            var shell: Shell? = null
            try {
                // A fresh, uncached libsu shell validates current manager policy. It cannot
                // close or disrupt the cached shell used by a running shortcut job.
                shell = Shell.Builder.create().setFlags(Shell.FLAG_MOUNT_MASTER).setTimeout(30).build()
                result = if (!shell.isRoot) "denied" else "unavailable"
                validateShortcutRootShell(shell)
                result = "granted"
            } catch (_: Exception) {
                // Missing su / timeouts / malformed capability output are unavailable,
                // distinct from an explicitly non-root shell.
            } finally {
                runCatching { shell?.close() }
            }
            val checked = result
            main.post {
                running = false
                state = checked
                val target = owner.get()
                if (checked != "granted" && (!prompted || explicitRetry) && target != null && !target.isFinishing && !target.isDestroyed) {
                    prompted = true
                    Toast.makeText(target, localized(
                        "請在 Root 管理器授權 SpeedBackup，再返回或重試。",
                        "请在 Root 管理器授权 SpeedBackup，再返回或重试。"
                    ), Toast.LENGTH_LONG).show()
                }
                explicitRetry = false
            }
        }, "app-root-check").start()
    }
}
