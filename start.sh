#!/system/bin/sh
if [ -f "${0%/*}/tools/tools.sh" ]; then
	MODDIR="${0%/*}"
	conf_path="${0%/*}/backup_settings.conf"
	[ ! -f "$conf_path" ] && . "${0%/*}/tools/tools.sh"
else
	echo "${0%/*}/tools/tools.sh遺失"
fi
# 入口腳本自己的 log 目錄必須自行建立；不能引用 tools.sh 上一次 run 的 speed_debug 路徑。
_log_dir="${0%/*}/log"
mkdir -p "$_log_dir" 2>/dev/null || _log_dir="/data/local/tmp"
logfile="$_log_dir/log_$(date +%Y-%m-%d_%H-%M).txt"
: > "$logfile" 2>/dev/null || logfile="/dev/null"
# 由入口腳本啟動時，trap 收尾訊息只寫 speed_debug，不刷終端，避免單獨恢復開頭出現 trap 訊息。
export SPEEDBACKUP_ENTRY_QUIET_TRAP=1
export SPEEDBACKUP_ENTRY_MODE="0"
export SPEEDBACKUP_ENTRY_SCRIPT="$0"
# 防止舊入口腳本 / 父 shell 殘留上一輪 speed_debug run_xxx 變數，導致單獨腳本誤寫已被 final 刪除的 main.log/stderr.log。
unset SPEED_DEBUG_RUN_DIR SPEED_DEBUG_MAIN_LOG SPEED_DEBUG_PENDING_ERR_LOG SPEED_DEBUG_CMD_LOG SPEED_DEBUG_INFO_LOG SPEED_DEBUG_DEX_HUMAN_LOG SPEED_DEBUG_ARCHIVE SPEED_DEBUG_PACKED SPEED_DEBUG_SNAPSHOT_DONE SPEED_DEBUG_RUN_DIR_REMOVED SPEED_DEBUG_ERR_LOG
set -o pipefail 2>/dev/null || true
. "${0%/*}/tools/tools.sh" 2>&1 | tee "$logfile"
_entry_rc=$?
case "$_entry_rc" in
	''|*[!0-9]*) _entry_rc=1 ;;
esac
if [ "$logfile" != "/dev/null" ] && [ -f "$logfile" ]; then
	sed -i "$(printf 's/\033\[[0-9;]*m//g')" "$logfile" 2>/dev/null || true
fi
exit "$_entry_rc"
