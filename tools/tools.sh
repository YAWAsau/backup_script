#!/system/bin/sh
# === Oh My Pi 備份腳本 ===
# 單文件整合版 (合併自 modules/)
backup_version="202605161105"

# ---- env.sh ----
. "${0%/*}/tools/modules/env.sh"

# ---- core.sh ----
. "${0%/*}/tools/modules/core.sh"

# 進程鎖
kill_Serve

# ---- remote.sh ----
. "${0%/*}/tools/modules/remote.sh"

# ---- backup.sh ----
. "${0%/*}/tools/modules/backup.sh"

# ---- restore.sh ----
. "${0%/*}/tools/modules/restore.sh"

# 完整 EXIT trap
trap "rm -rf '/data/.backup_lock'; remote_cleanup" EXIT

# ---- menu.sh ----
. "${0%/*}/tools/modules/menu.sh"
