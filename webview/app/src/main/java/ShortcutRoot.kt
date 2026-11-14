package io.github.yawasau.speedbackup.webview

import com.topjohnwu.superuser.Shell

/** Check the actual cached shell, not a different su process or the app UID. */
internal fun checkedShortcutRootShell(): Shell {
    val shell = Shell.getShell()
    try {
        check(shell.isRoot) { "請先授予 SpeedBackup Root 權限" }
        val output = ArrayList<String>()
        val result = shell.newJob().add(
            "while read -r key value rest; do case \"\$key\" in CapEff:) printf '%s\\n' \"\$value\"; break;; esac; done < /proc/\$\$/status"
        ).to(output).exec()
        val cap = output.singleOrNull()?.trim()
        check(result.isSuccess && cap != null && cap.matches(Regex("[0-9a-fA-F]{1,16}"))) {
            "無法確認 Root 權能，請關閉後重新授權 SpeedBackup"
        }
        check(cap.any { it != '0' }) {
            "Root 權能為零：雖然 UID 是 0，仍無法存取備份目錄或切換掛載環境。請在 Root 管理器將 SpeedBackup 的自訂 Root 設定檔恢復預設，或修正權能設定，再按重試。"
        }
        return shell
    } catch (e: Exception) {
        // A profile change cannot repair credentials of an already-running cached shell.
        runCatching { shell.close() }
        throw e
    }
}
