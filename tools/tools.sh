#!/system/bin/sh
if [ "$(whoami)" != root ]; then
	echo "你是憨批？不給Root用你媽 爬"
	exit 1
fi
# 正規化 TMPDIR 提前到最開頭: 呼叫端終端 (如 MT 管理器內建終端) 可能繼承自己的 $TMPDIR
# (例如 app 私有目錄), 若晚於憑證檔/暫存檔建立才重設, 那些檔案會建在錯誤/不可靠的路徑。
TMPDIR="/data/local/tmp"
# 早期不再把 set -x 寫到 /data/cache；如需命令追蹤，請設 _dex_debug=1，會寫入 speed_debug/xtrace.log。
shell_language="zh-TW"
MODDIR_NAME="${MODDIR##*/}"
tools_path="$MODDIR/tools"
script="${0##*/}"
backup_version="202606211326"
speedbackup_patch_build="v24.20.14-7.66-402-device-list-residue-clean-20260719"
# mksh/管線/command substitution 情境下，$$ 不一定是目前實際 shell process。
# WebDAV daemon owner watch 必須綁真正執行 tools.sh 的 process，否則 owner 誤判死亡會讓 daemon 每次 request 後退出。
_SPEEDBACKUP_SELF_PID=""
IFS=' ' read -r _SPEEDBACKUP_SELF_PID _ < /proc/self/stat 2>/dev/null || _SPEEDBACKUP_SELF_PID=""
case "$_SPEEDBACKUP_SELF_PID" in ''|*[!0-9]*) _SPEEDBACKUP_SELF_PID="$$" ;; esac
SPEEDBACKUP_MAIN_PID="$_SPEEDBACKUP_SELF_PID"
unset _SPEEDBACKUP_SELF_PID
# 私有 LAN 遠端操作期間臨時啟動 native netwatch。
# ============================================================
# SpeedBackup 內部策略
# ============================================================
# 對外只保留 diagnostic_mode=0/1；dex 自檢內容已分離到 tools/dex_check.sh。
diagnostic_mode="${diagnostic_mode:-0}"
SPEED_DEBUG_BASE="/data/speed_debug"
SPEED_DEBUG_ERR_LOG="/dev/null"
SPEED_DEBUG_TS="$(date +%Y%m%d-%H%M%S 2>/dev/null)"
[[ -z "$SPEED_DEBUG_TS" ]] && SPEED_DEBUG_TS="unknown-$$"
SPEED_DEBUG_RUN_DIR="$SPEED_DEBUG_BASE/run_$SPEED_DEBUG_TS-$$"
SPEED_DEBUG_MAIN_LOG="$SPEED_DEBUG_RUN_DIR/main.log"
SPEED_DEBUG_PENDING_ERR_LOG="$SPEED_DEBUG_RUN_DIR/stderr.log"
SPEED_DEBUG_CMD_LOG="$SPEED_DEBUG_RUN_DIR/command.log"
SPEED_DEBUG_INFO_LOG="$SPEED_DEBUG_RUN_DIR/info.log"
SPEED_DEBUG_DEX_HUMAN_LOG="$SPEED_DEBUG_RUN_DIR/dex_human.log"
SPEED_DEBUG_ARCHIVE=""
SPEED_DEBUG_PACKED=0
SPEED_DEBUG_SNAPSHOT_DONE=0
SPEED_DEBUG_FIRST_BOOT=0

_speedbackup_bool_on() {
	case "$1" in 1|true|True|TRUE|yes|YES|on|ON) return 0 ;; *) return 1 ;; esac
}

_speedbackup_apply_internal_policy() {
	diagnostic_mode="${diagnostic_mode:-0}"
	SPEED_DEBUG_ENABLE=1
	SPEED_DEBUG_MAX_KB=2048
	SPEED_DEBUG_SNAPSHOT_ON_NORMAL=1
	SPEED_DEBUG_SNAPSHOT_ON_EXIT=0
	SPEED_DEBUG_DEX_FIRST_TEST=1
	SPEED_DEBUG_DEX_TRANSLATE=1
	SPEED_DEBUG_DEX_TRANSLATE_TERMINAL=0
	RESTORE_APPSTATE_BATCH_CHUNK_SIZE=80
	VERIFY_APPSTATE_BATCH_CHUNK_SIZE=80
	backup_wifi_enable=1
	WIFI_BACKUP_TIMEOUT=20
	_restore_defaults="restore_pm_install_with_installer=1 restore_play_install_keep_workdir=0 restore_play_install_verify_source=1 restore_play_install_bypass_low_target=auto restore_play_install_allow_test=1 restore_play_install_allow_downgrade=0 restore_play_install_grant_runtime_permissions=0 restore_play_install_dont_kill=0 restore_play_install_require_user_action=not_required restore_play_install_package_source=store restore_play_install_reason=user restore_play_install_location=auto restore_play_install_extra_flags= restore_play_install_human_log=0 restore_play_install_log_mode=summary"
	for _kv in $_restore_defaults; do eval "$_kv"; done
	if _speedbackup_bool_on "$diagnostic_mode"; then
		_dex_debug=1
		_stream_debug=1
		_INCREMENTAL_DEBUG=1
		SPEED_DEBUG_DEEP_SELF_TEST=1
	else
		_dex_debug=0
		_stream_debug=0
		_INCREMENTAL_DEBUG=0
		SPEED_DEBUG_DEEP_SELF_TEST=0
	fi
}
_speedbackup_apply_internal_policy

_speed_debug_size_kb() {
	du -sk "$SPEED_DEBUG_BASE" 2>/dev/null | awk '{print $1}' 2>/dev/null
}
_speed_debug_init() {
	[[ "$SPEED_DEBUG_ENABLE" = 1 ]] || { SPEED_DEBUG_ERR_LOG="/dev/null"; return 0; }
	# /data/speed_debug 是持久化目錄；只有此目錄不存在時，才視為第一次啟動腳本。
	# 後續清理只刪除目錄內舊 log/壓縮包，不刪除 /data/speed_debug 本身，避免重複觸發首次 dex 完整度測試。
	if [[ ! -d "$SPEED_DEBUG_BASE" ]]; then
		SPEED_DEBUG_FIRST_BOOT=1
	else
		SPEED_DEBUG_FIRST_BOOT=0
	fi
	mkdir -p "$SPEED_DEBUG_BASE" 2>/dev/null || { SPEED_DEBUG_ENABLE=0; SPEED_DEBUG_ERR_LOG="/dev/null"; return 0; }
	local _kb
	_kb="$(_speed_debug_size_kb)"
	[[ -z "$_kb" ]] && _kb=0
	if [[ $_kb -ge ${SPEED_DEBUG_MAX_KB:-2048} ]]; then
		echo "[speed_debug] /data/speed_debug 已達 ${_kb}KB，超過 ${SPEED_DEBUG_MAX_KB}KB，啟動時自動清除舊除錯日誌，保留目錄本身"
		find "$SPEED_DEBUG_BASE" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
	fi
	# run dir 必須先存在；stderr.log 也要先 touch，之後才切換 SPEED_DEBUG_ERR_LOG
	mkdir -p "$SPEED_DEBUG_RUN_DIR" 2>/dev/null || { SPEED_DEBUG_ENABLE=0; SPEED_DEBUG_ERR_LOG="/dev/null"; return 0; }
	: > "$SPEED_DEBUG_PENDING_ERR_LOG" 2>/dev/null || { SPEED_DEBUG_ENABLE=0; SPEED_DEBUG_ERR_LOG="/dev/null"; return 0; }
	SPEED_DEBUG_ERR_LOG="$SPEED_DEBUG_PENDING_ERR_LOG"
	: > "$SPEED_DEBUG_MAIN_LOG" 2>>"$SPEED_DEBUG_ERR_LOG"
	: > "$SPEED_DEBUG_CMD_LOG" 2>>"$SPEED_DEBUG_ERR_LOG"
	: > "$SPEED_DEBUG_INFO_LOG" 2>>"$SPEED_DEBUG_ERR_LOG"
	: > "$SPEED_DEBUG_DEX_HUMAN_LOG" 2>>"$SPEED_DEBUG_ERR_LOG"
	{
		echo "time=$(date '+%Y-%m-%d %H:%M:%S' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		echo "pid=$SPEEDBACKUP_MAIN_PID shell_dollar_pid=$$"
		echo "script=$0"
		echo "entry_script=${SPEEDBACKUP_ENTRY_SCRIPT:-}"
		echo "entry_mode=${SPEEDBACKUP_ENTRY_MODE:-}"
		echo "tools_path=${tools_path:-}"
		echo "version=$backup_version"
		echo "shell=$SHELL"
		echo "user=$(id 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		echo "android=$(getprop ro.build.version.release 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) sdk=$(getprop ro.build.version.sdk 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		echo "device=$(getprop ro.product.manufacturer 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) $(getprop ro.product.model 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	} >> "$SPEED_DEBUG_INFO_LOG" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	printf '[speed_debug] 本次除錯目錄: %s\n' "$SPEED_DEBUG_RUN_DIR" >> "$SPEED_DEBUG_MAIN_LOG" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}
_speed_debug_disarm_if_run_gone() {
	# 正常流程/子流程已 final 打包並刪除 run_xxx 後，父 shell 的 EXIT trap 可能仍持有舊 stderr.log 路徑。
	# 只要偵測到 run 目錄不存在，就立即把所有 debug 重定向切到 /dev/null，避免 mksh 在開檔階段刷 can't create。
	local _dir="${SPEED_DEBUG_RUN_DIR:-}" _base="${SPEED_DEBUG_BASE:-}"
	[[ -n $_dir && -n $_base ]] || return 0
	case "$_dir" in "$_base"/run_*) ;; *) return 0 ;; esac
	[[ -d "$_dir" ]] && return 0
	SPEED_DEBUG_RUN_DIR_REMOVED=1
	SPEED_DEBUG_ERR_LOG="/dev/null"
	SPEED_DEBUG_PENDING_ERR_LOG="/dev/null"
	SPEED_DEBUG_MAIN_LOG="/dev/null"
	SPEED_DEBUG_CMD_LOG="/dev/null"
	SPEED_DEBUG_INFO_LOG="/dev/null"
	SPEED_DEBUG_DEX_HUMAN_LOG="/dev/null"
	return 0
}
_speed_debug_stderr_target() {
	_speed_debug_disarm_if_run_gone
	local _err="${SPEED_DEBUG_ERR_LOG:-/dev/null}"
	[[ -n $_err ]] || _err="/dev/null"
	if [[ $_err != "/dev/null" && -n ${SPEED_DEBUG_RUN_DIR:-} && ! -d "$SPEED_DEBUG_RUN_DIR" ]]; then
		_err="/dev/null"
		SPEED_DEBUG_ERR_LOG="/dev/null"
	fi
	printf '%s\n' "$_err"
}
_speed_debug_ensure_run_dir() {
	# 單獨入口、遠端預檢、或父 shell 殘留環境時，run_xxx 可能不存在；
	# 所有 debug 檔寫入前都先安全確認，避免 can't create /data/speed_debug/run_xxx/*.log 刷到終端。
	[[ "${SPEED_DEBUG_ENABLE:-1}" = 1 ]] || return 1
	_speed_debug_disarm_if_run_gone
	# final 已完成後不允許任何晚到的 log 寫入重建 run_xxx；這類訊息只留 pack.log 或直接丟棄。
	if [[ "${SPEED_DEBUG_PACKED:-0}" = 1 || "${SPEED_DEBUG_RUN_DIR_REMOVED:-0}" = 1 ]]; then
		SPEED_DEBUG_ERR_LOG="/dev/null"
		return 1
	fi
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} ]] || return 1
	mkdir -p "$SPEED_DEBUG_RUN_DIR" 2>/dev/null || return 1
	[[ -d "$SPEED_DEBUG_RUN_DIR" ]] || return 1
	[[ -n ${SPEED_DEBUG_PENDING_ERR_LOG:-} ]] || SPEED_DEBUG_PENDING_ERR_LOG="$SPEED_DEBUG_RUN_DIR/stderr.log"
	: >> "$SPEED_DEBUG_PENDING_ERR_LOG" 2>/dev/null && SPEED_DEBUG_ERR_LOG="$SPEED_DEBUG_PENDING_ERR_LOG"
	[[ -n ${SPEED_DEBUG_MAIN_LOG:-} ]] || SPEED_DEBUG_MAIN_LOG="$SPEED_DEBUG_RUN_DIR/main.log"
	: >> "$SPEED_DEBUG_MAIN_LOG" 2>/dev/null || return 1
	return 0
}
_speed_debug_log_path() {
	local _name="$1"
	[[ -n $_name ]] || { echo /dev/null; return 1; }
	if _speed_debug_ensure_run_dir; then
		echo "$SPEED_DEBUG_RUN_DIR/$_name"
		return 0
	fi
	echo /dev/null
	return 1
}

_speed_debug_append_file() {
	# Android / mksh 對「重定向目標不存在」的錯誤有時不會被同一條命令的 2>/dev/null 完全吞掉；
	# 所有可選 debug 檔寫入統一包進 subshell，確保 run_xxx 不存在時也不刷終端。
	local _file="$1"
	shift
	[[ -n $_file ]] || _file=/dev/null
	if [[ $_file != /dev/null ]]; then
		mkdir -p "${_file%/*}" 2>/dev/null || _file=/dev/null
	fi
	(
		for _line in "$@"; do
			printf '%s\n' "$_line"
		done >> "$_file"
	) 2>/dev/null || true
}

_speed_debug_append_cat() {
	local _file="$1" _src="$2" _prefix="$3"
	[[ -s $_src ]] || return 0
	[[ -n $_file ]] || _file=/dev/null
	if [[ $_file != /dev/null ]]; then
		mkdir -p "${_file%/*}" 2>/dev/null || _file=/dev/null
	fi
	(
		[[ -n $_prefix ]] && printf '%s\n' "$_prefix"
		sed -E 's#://[^/@[:space:]]+:[^/@[:space:]]+@#://[REDACTED]@#g; s/(password[[:space:]]*=[[:space:]]*).*/\1[REDACTED]/I' "$_src"
	) >> "$_file" 2>/dev/null || true
}
_speed_debug_log() {
	[[ "$SPEED_DEBUG_ENABLE" = 1 ]] || return 0
	_speed_debug_ensure_run_dir || return 0
	printf '[%s] %s
' "$(date '+%H:%M:%S' 2>/dev/null)" "$*" >> "$SPEED_DEBUG_MAIN_LOG" 2>/dev/null
}
_speed_debug_pack_log() {
	local _msg="$*" _ts
	_ts="$(date '+%H:%M:%S' 2>/dev/null)"
	[[ -z $_ts ]] && _ts="unknown"
	# 打包階段可能即將刪除 run 目錄；因此同時寫 root pack.log，避免為了記錄成功訊息又重建 run 目錄。
	mkdir -p "$SPEED_DEBUG_BASE" 2>/dev/null
	printf '[%s] %s\n' "$_ts" "$_msg" >> "$SPEED_DEBUG_BASE/pack.log" 2>/dev/null
	if [[ -n ${SPEED_DEBUG_MAIN_LOG:-} && -f "$SPEED_DEBUG_MAIN_LOG" ]]; then
		printf '[%s] %s\n' "$_ts" "$_msg" >> "$SPEED_DEBUG_MAIN_LOG" 2>/dev/null
	fi
}
_speed_debug_safe_remove_run_dir() {
	local _dir="${1:-}" _base="${SPEED_DEBUG_BASE:-}"
	# 只允許刪除本腳本建立的 /data/speed_debug/run_* 目錄，避免任何 rm -rf /* 類事故。
	[[ -n $_dir && -n $_base ]] || { _speed_debug_pack_log "[speed_debug] 刪除run目錄跳過: path/base為空 dir=$_dir base=$_base"; return 1; }
	[[ $_base != "/" && $_base != "/*" ]] || { _speed_debug_pack_log "[speed_debug] 刪除run目錄拒絕: base危險 $_base"; return 1; }
	[[ $_dir != "/" && $_dir != "/*" ]] || { _speed_debug_pack_log "[speed_debug] 刪除run目錄拒絕: path危險 $_dir"; return 1; }
	[[ $_dir = "$_base"/run_* ]] || { _speed_debug_pack_log "[speed_debug] 刪除run目錄拒絕: 不在speed_debug run範圍 dir=$_dir base=$_base"; return 1; }
	case "${_dir##*/}" in run_*) ;; *) _speed_debug_pack_log "[speed_debug] 刪除run目錄拒絕: basename不是run_* dir=$_dir"; return 1 ;; esac
	case "$_dir" in *".."*|*"//"*|*"*"*) _speed_debug_pack_log "[speed_debug] 刪除run目錄拒絕: path含危險字元 dir=$_dir"; return 1 ;; esac
	[[ -d $_dir ]] || { _speed_debug_pack_log "[speed_debug] 刪除run目錄跳過: 目錄不存在 $_dir"; return 0; }
	rm -rf "$_dir" 2>/dev/null || { _speed_debug_pack_log "[speed_debug] 刪除run目錄失敗: $_dir"; return 1; }
	SPEED_DEBUG_RUN_DIR_REMOVED=1
	# final 打包成功後 run_xxx 已不存在，後續任何晚到的 debug redirection 都只能丟棄，不能再指向已刪除的 run 內 log。
	SPEED_DEBUG_ERR_LOG="/dev/null"
	SPEED_DEBUG_MAIN_LOG="/dev/null"
	_speed_debug_pack_log "[speed_debug] 已刪除原run目錄: $_dir"
	return 0
}

_speed_debug_pack_common() {
	local _mode="$1" _ec="${2:-0}" _delete="${3:-0}"
	# 打包以 run 目錄存在為準，不再只看 SPEED_DEBUG_ENABLE；
	# 因為 debug 已建立後，conf 或環境若改動 SPEED_DEBUG_ENABLE，也不應讓打包靜默跳過。
	if [[ -z ${SPEED_DEBUG_RUN_DIR:-} ]]; then
		_speed_debug_pack_log "[speed_debug] ${_mode}打包跳過: SPEED_DEBUG_RUN_DIR為空"
		return 0
	fi
	if [[ ! -d "$SPEED_DEBUG_RUN_DIR" ]]; then
		_speed_debug_pack_log "[speed_debug] ${_mode}打包跳過: run目錄不存在: $SPEED_DEBUG_RUN_DIR"
		return 0
	fi
	mkdir -p "$SPEED_DEBUG_BASE" 2>/dev/null || {
		_speed_debug_pack_log "[speed_debug] ${_mode}打包失敗: 無法建立 $SPEED_DEBUG_BASE"
		return 1
	}
	# v24.20.14-7.66-194：tools_version 是除錯資料，不再阻塞進入可操作選單；打包前才補寫。
	if [[ ! -s "$SPEED_DEBUG_RUN_DIR/tools_version.log" ]]; then
		SPEED_DEBUG_TOOLS_VERSION_SILENT=1 print_tools_version 2>/dev/null
		SPEED_DEBUG_TOOLS_VERSION_SILENT=0
	fi
	{
		echo "${_mode}_time=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
		echo "${_mode}_exit_code=$_ec"
	} >> "$SPEED_DEBUG_INFO_LOG" 2>/dev/null
	SPEED_DEBUG_ARCHIVE="$SPEED_DEBUG_BASE/speed_debug_$SPEED_DEBUG_TS.tar"
	local _pack_err="$SPEED_DEBUG_BASE/.speed_debug_pack_$SPEED_DEBUG_TS.err"
	local _tar_bin
	_tar_bin="$(command -v tar 2>/dev/null)"
	[[ -z $_tar_bin && -x /data/backup_tools/tar ]] && _tar_bin="/data/backup_tools/tar"
	[[ -z $_tar_bin ]] && _tar_bin="tar"
	_speed_debug_pack_log "[speed_debug] ${_mode}打包: run=$SPEED_DEBUG_RUN_DIR out=$SPEED_DEBUG_ARCHIVE tar=$_tar_bin"
	rm -f "$SPEED_DEBUG_ARCHIVE" "$_pack_err" 2>/dev/null
	(
		cd "$SPEED_DEBUG_BASE" || exit 70
		"$_tar_bin" -cf "$(basename "$SPEED_DEBUG_ARCHIVE")" "$(basename "$SPEED_DEBUG_RUN_DIR")"
	) 2>"$_pack_err"
	local _tar_rc=$?
	if [[ $_tar_rc = 0 && -s "$SPEED_DEBUG_ARCHIVE" ]]; then
		rm -f "$_pack_err" 2>/dev/null
		if [[ $_delete = 1 ]]; then
			_speed_debug_safe_remove_run_dir "$SPEED_DEBUG_RUN_DIR"
			_speed_debug_pack_log "[speed_debug] 除錯日誌已打包: $SPEED_DEBUG_ARCHIVE"
		else
			_speed_debug_pack_log "[speed_debug] 除錯日誌快照已打包: $SPEED_DEBUG_ARCHIVE"
		fi
		return 0
	fi
	_speed_debug_pack_log "[speed_debug] ${_mode}打包失敗 rc=$_tar_rc，保留目錄: $SPEED_DEBUG_RUN_DIR"; echo "[speed_debug] ${_mode}打包失敗 rc=$_tar_rc，保留目錄: $SPEED_DEBUG_RUN_DIR"
	[[ -s "$_pack_err" ]] && sed 's/^/[speed_debug][tar] /' "$_pack_err" 2>/dev/null
	return 1
}
_speed_debug_snapshot_pack() {
	_speed_debug_pack_common "snapshot" "${1:-0}" 0
	local _rc=$?
	[[ $_rc = 0 ]] && SPEED_DEBUG_SNAPSHOT_DONE=1
	return $_rc
}
_speed_debug_pack() {
	_speed_debug_disarm_if_run_gone
	if [[ "${SPEED_DEBUG_PACKED:-0}" = 1 ]]; then
		SPEED_DEBUG_ERR_LOG="/dev/null"
		_speed_debug_pack_log "[speed_debug] 最終打包跳過: 已打包過"
		return 0
	fi
	SPEED_DEBUG_PACKED=1
	_speed_debug_pack_common "final" "${1:-0}" 1
}

_speed_debug_merge_numbered_logs() {
	# v24.20.14-7.66-191：若舊流程或中途殘留 *_001.log / *_002.log，收尾前合併回 base.log 後移除。
	# 目標是批量備份/恢復時 speed_debug 包只保留少量 aggregate log，不再產生大量分片檔。
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d "$SPEED_DEBUG_RUN_DIR" ]] || return 0
	local _base _dup _merged=0 _basefile
	for _base in \
		compress extract checksum \
		app_state_stdinput \
		verify_app_state_stdinput; do
		_basefile="$SPEED_DEBUG_RUN_DIR/${_base}.log"
		for _dup in "$SPEED_DEBUG_RUN_DIR/${_base}_"[0-9][0-9][0-9].log; do
			[[ -f $_dup ]] || continue
			if [[ -f $_basefile ]] && cmp -s "$_basefile" "$_dup" 2>/dev/null; then
				rm -f "$_dup" 2>/dev/null && _merged=$((_merged + 1))
				continue
			fi
			{
				echo
				echo "===== MERGED ${_dup##*/} BEGIN ====="
				cat "$_dup" 2>/dev/null
				echo "===== MERGED ${_dup##*/} END ====="
			} >> "$_basefile" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			rm -f "$_dup" 2>/dev/null && _merged=$((_merged + 1))
		done
	done
	[[ $_merged -gt 0 ]] && _speed_debug_pack_log "[speed_debug] 已合併分片debug log: $_merged 個"
	return 0
}

_speed_debug_dedupe_logs() {
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d "$SPEED_DEBUG_RUN_DIR" ]] || return 0
	local _removed=0
	_speed_debug_merge_numbered_logs
	# command.log 若完全為空，沒有診斷價值；stderr.log 即使 0 bytes 仍保留作為清潔度證明。
	[[ -f "$SPEED_DEBUG_RUN_DIR/command.log" && ! -s "$SPEED_DEBUG_RUN_DIR/command.log" ]] && rm -f "$SPEED_DEBUG_RUN_DIR/command.log" 2>/dev/null && _removed=$((_removed + 1))
	[[ $_removed -gt 0 ]] && _speed_debug_pack_log "[speed_debug] 已清理空debug log: $_removed 個"
	return 0
}

_speed_debug_normal_finish_pack() {
	# 正常流程主動建立 final 包並刪除 run_xxx，避免單獨入口 / pipeline subshell 的 EXIT trap 沒有執行時留下 run 目錄。
	# 若 EXIT trap 之後仍觸發，_speed_debug_pack 會因 SPEED_DEBUG_PACKED=1 自動跳過，不會重複打包。
	_speed_debug_dedupe_logs
	if [[ "${SPEED_DEBUG_SNAPSHOT_ON_NORMAL:-1}" = 1 && "${SPEED_DEBUG_SNAPSHOT_DONE:-0}" != 1 ]]; then
		_speed_debug_snapshot_pack "${1:-0}"
	fi
	_speed_debug_pack "${1:-0}"
	_speed_debug_disarm_if_run_gone
}

_speed_debug_init
# _dex_debug=1 時才啟用 shell xtrace；輸出固定寫入本次 speed_debug run 目錄。
if [[ "${_dex_debug:-0}" = 1 && -d "$SPEED_DEBUG_RUN_DIR" ]]; then
	set -x 2> "$SPEED_DEBUG_RUN_DIR/xtrace.log"
fi
[[ $SHELL = *mt* ]] && echo "請勿使用MT管理器拓展包環境執行,請更換系統環境" && exit 2
# 產生 backup_settings.conf 的內容模板 (寫到 stdout)
# 透過重定向到檔案來生成或更新備份設定檔
update_backup_settings_conf() {
	echo "#低電量提示 (電量≤15%且未充電時的行為)
#1低電量強制拒絕操作  2無需提示繼續執行  留空音量鍵選擇 (音量上=無視風險繼續操作, 音量下=退出)
low_battery_mode="${low_battery_mode:-}"

#輸入方式 (1=改用鍵盤輸入確認  留空/其他=音量鍵選擇)
keyboard_input="${keyboard_input:-}"

#後台執行腳本
#0不能關閉當前終端，有壓縮速率
#1終端有可能完全無顯示，但是log會持續刷新，可直接完全關閉終端
background_execution="${background_execution:-0}"

#通知欄顯示與進度條
#1開啟 0關閉
#獨立於後台執行與偽裝亮屏
notification_enable="${notification_enable:-1}"

#腳本語言設置 留空則自動識別系統語言環境並翻譯
#1簡體中文 0繁體中文
Shell_LANG="$Shell_LANG"

#備份開始後偽裝亮屏
#1開啟 0關閉
setDisplayPowerMode="${setDisplayPowerMode:-0}"

#自定義備份文件輸出位置 支持相對路徑(留空則默認當前路徑)
Output_path=\""$Output_path"\"

#自定義備份目錄後綴(留空則不添加後綴)
#支持日期時間變量：%yyyymmdd %hhmmss %yyyymmddhhmmss %yyyy %mm %dd
#例：_daily  → Backup_zstd_0_daily
#例：_%yyyymmdd  → Backup_zstd_0_20260522
Backup_suffix=\""$Backup_suffix"\"

#自定義applist.txt位置 支持相對路徑(留空則默認當前路徑)
list_location=\""$list_location"\"

#自動更新腳本(留空強制選擇)
#1開啟 0關閉
update="${update:-1}"

#自動更新的cdn節點，針對國內用戶使用，無牆或是使用VPN請設置0
#0 直鏈下載
#1 https://ghfast.top
#2 https://shrill-pond-3e81.hunsh.workers.dev
cdn=${cdn:-1}

#自定義屏蔽外部掛載點 例：OTG 虛擬SD等 多個掛載點請使用 | 區隔
#屏蔽後不會提示音量鍵選擇，不影響Output_path指定外置存儲位置
mount_point=\""${mount_point:-rannki|0000-1}"\"

#使用者(如0 999等用戶，如存在多個用戶留空強制選擇，無多個用戶則默認用戶0不詢問)
user="$user"

#備份模式
#1包含數據+安裝包，0僅包安裝包
#此選項設置1時Backup_obb_data，Backup_user_data，blacklist_mode將可設置 0時Backup_user_data，Backup_obb_data，blacklist_mode選項不生效
#此外設置0時將同時忽略appList.txt的!與任何黑名單設置（包括黑名單列表）
Backup_Mode="${Backup_Mode:-1}"

#是否備份使用者數據 (1備份 0不備份 留空強制選擇)
Backup_user_data="${Backup_user_data:-1}"

#是否備份外部數據 例：原神的數據包(1備份 0不備份 留空強制選擇)
Backup_obb_data="${Backup_obb_data:-1}"

#是否在應用數據備份完成後備份自定義目錄
#1開啟 0關閉
backup_media="${backup_media:-0}"

#存在進程忽略備份(1忽略0備份)
Background_apps_ignore="${Background_apps_ignore:-0}"

#添加自定義備份路徑 例：Download DCIM等文件夾 請使用絕對路徑，請勿刪除\"\"
Custom_path=\""$Custom_path"\"

#黑名單模式(1完全忽略，不備份  0僅備份安裝包，注意！此選項Backup_Mode=1時黑名單模式才能使用)
blacklist_mode="${blacklist_mode:-0}"

#備份黑名單（備份策略由「黑名單模式」控制，此處只作為黑名單應用列表）
blacklist=\""${blacklist:-
#com.esunbank
#com.chailease.tw.app.android.ccfappcust}"\"

#位於data的預裝應用白名單 例：相冊 錄音機 天氣 計算器等(默認屏蔽備份預裝應用，如需備份請添加預裝應用白名單)
whitelist=\""${whitelist:-
com.xiaomi.xmsf
com.xiaomi.xiaoailite
com.xiaomi.hm.health
com.duokan.phone.remotecontroller
com.miui.weather2
com.milink.service
com.android.soundrecorder
com.miui.virtualsim
com.xiaomi.vipaccount
com.miui.fm
com.xiaomi.shop
com.xiaomi.smarthome
com.miui.notes
com.xiaomi.router
com.xiaomi.mico
dev.miuiicons.pedroz}"\"

#可被備份的系統應用白名單(默認屏蔽備份系統應用，如需備份請添加系統應用白名單)
system=\""${system:-
com.google.android.calendar
com.google.android.gm
com.google.android.googlequicksearchbox
com.google.android.tts
com.google.android.apps.maps
com.google.android.apps.messaging
com.google.android.inputmethod.latin
com.instagram.android
com.facebook.orca
sh.siava.AOSPMods
com.facebook.katana
com.android.chrome}"\"

#壓縮算法(可用zstd tar，tar為僅打包 有什麼好用的壓縮算法請聯系我
#zstd擁有良好的壓縮率與速度
Compression_method=${Compression_method:-zstd}

#色彩設定 (256 色 ANSI 編號)
#常用值: 39藍 51青 82綠 196紅 208橘 213粉 220黃 165紫
#主色 (一般資訊, 預設亮黃)
rgb_a="${rgb_a:-220}"
#輔色1 (提示/進度, 預設亮青)
rgb_b="${rgb_b:-51}"
#輔色2 (強調/變數值, 預設粉紅)
rgb_c="${rgb_c:-213}"

#遠程備份類型 (留空不啟用)
#推薦 webdav (穩定)
#smb 支援 SMB2/SMB3 (本腳本拒絕 SMB1/CIFS, 會自動協商到伺服器支援的最高版本)
remote_type="${_CONF_SRC_remote_type:-${remote_type:-}}"
#遠程地址 (兩種協議分開設定, 切換 remote_type 免重輸)
#SMB例:    smb://192.168.1.100/backup/
smb_url="${_CONF_SRC_smb_url:-${smb_url:-}}"
#認證用戶名
smb_remote_user="${_CONF_SRC_smb_remote_user:-${smb_remote_user:-}}"
#認證密碼
smb_remote_pass=\""${_CONF_SRC_smb_remote_pass:-$smb_remote_pass}"\"
#WebDAV例: http://192.168.1.100:8080/dav/
webdav_url="${_CONF_SRC_webdav_url:-${webdav_url:-}}"
#認證用戶名
webdav_remote_user="${_CONF_SRC_webdav_remote_user:-${webdav_remote_user:-}}"
#認證密碼
webdav_remote_pass=\""${_CONF_SRC_webdav_remote_pass:-$webdav_remote_pass}"\"

#流式上傳 (邊壓邊傳, 不佔本機空間)
#1 開啟流式: 數據直接壓縮→管道傳到遠端, 本機不留 tar (省空間, 全量上傳, 不做本機校驗/增量)
#0 關閉(預設): 先壓到本機→校驗→再上傳 (保留本機檔案, 支援增量)
#支援 smb / webdav 兩種 remote_type
remote_stream="${_CONF_SRC_remote_stream:-${remote_stream:-0}}"

#診斷模式 (1=保留較多遠端/流程診斷資料 0=一般使用)
#一般使用保持 0；需要把 speed_debug 給開發者排查時再設 1。
diagnostic_mode="${diagnostic_mode:-0}"

#遠程備份完成後是否保留本地檔案
#1保留本地檔案(上傳後不刪除) 0上傳成功後刪除本地檔案
remote_keep_local="${_CONF_SRC_remote_keep_local:-${remote_keep_local:-0}}"

#邊備份邊上傳 (每備份完一個應用立即上傳，然後刪除本機檔案再備份下一個，以節省本機空間)
#1 開啟 0 關閉
#開啟後：每個應用備份完成 → 立即上傳遠端 → 上傳成功後刪除本機檔案 → 繼續備份下一個
#關閉後：先備份所有應用 → 全部備份完再統一上傳
remote_upload_per_app="${_CONF_SRC_remote_upload_per_app:-${remote_upload_per_app:-0}}"

#log 目錄大小上限 (單位 MB), 達到上限會在啟動時自動清空 log/
#留空或設 0 = 關閉自動清理
log_max_size_mb="${log_max_size_mb:-}"

" | sed '
	/^Custom_path/ s/ /\n/g;
	/^blacklist/ s/ /\n/g;
	/^whitelist/ s/ /\n/g;
	/^system/ s/ /\n/g;
	/^am_start/ s/ /\n/g;
	s/true/1/g;
	s/false/0/g'
}
# 產生 restore_settings.conf 的內容模板 (寫到 stdout)
# 備份完成時呼叫此函數寫入備份目錄,讓恢復端有獨立的設定檔
update_Restore_settings_conf() {
	echo "#低電量提示 (電量≤15%且未充電時的行為)
#1低電量強制拒絕操作  2無需提示繼續執行  留空音量鍵選擇 (音量上=無視風險繼續操作, 音量下=退出)
low_battery_mode="${low_battery_mode:-}"

#輸入方式 (1=改用鍵盤輸入確認  留空/其他=音量鍵選擇)
keyboard_input="${keyboard_input:-}"

#後台執行腳本
#0不能關閉當前終端，有壓縮速率
#1終端有可能完全無顯示，但是log會持續刷新，可直接完全關閉終端
background_execution="${background_execution:-0}"

#通知欄顯示與進度條
#1開啟 0關閉
#獨立於後台執行與偽裝亮屏
notification_enable="${notification_enable:-1}"

#恢復開始後偽裝亮屏
#1開啟 0關閉
setDisplayPowerMode="${setDisplayPowerMode:-0}"

#腳本語言設置 為空自動針對當前系統語言環境自動翻譯
#1簡體中文 0繁體中文
Shell_LANG="$Shell_LANG"

#自動更新腳本(留空強制選擇)
update="${update:-1}"

#自動更新的cdn節點，針對國內用戶使用，無牆或是使用VPN請設置0
#0 直鏈下載
#1 https://ghfast.top
#2 https://shrill-pond-3e81.hunsh.workers.dev
cdn=${cdn:-1}

#恢復模式(1恢復未安裝應用 0全恢復)
recovery_mode="${recovery_mode:-0}"

#恢復資料夾
media_recovery="${media_recovery:-0}"

#存在進程忽略恢復(1忽略0恢復)
Background_apps_ignore="${Background_apps_ignore:-0}"

#使用者(如0 999等用戶，留空如存在多個用戶強制音量鍵選擇，無多用戶則默認0不詢問)
user="$user"

#log 目錄大小上限 (單位 MB), 達到上限會在啟動時自動清空 log/
#留空或設 0 = 關閉自動清理
log_max_size_mb="${log_max_size_mb:-}"

#診斷模式 (1=保留較多流程診斷資料 0=一般使用)
#一般使用保持 0；需要把 speed_debug 給開發者排查時再設 1。
diagnostic_mode="${diagnostic_mode:-0}"

#色彩設定 (256 色 ANSI 編號)
#常用值: 39藍 51青 82綠 196紅 208橘 213粉 220黃 165紫
#主色 (一般資訊, 預設亮黃)
rgb_a="${rgb_a:-220}"
#輔色1 (提示/進度, 預設亮青)
rgb_b="${rgb_b:-51}"
#輔色2 (強調/變數值, 預設粉紅)
rgb_c="${rgb_c:-213}"" | sed 's/true/1/g ; s/false/0/g'
}

if [[ ! -d $tools_path ]]; then
	tools_path="${MODDIR%/*}/tools"
	[[ ! -d $tools_path ]] && echo "$tools_path二進制目錄遺失" && EXIT="true"
fi
# 根據當前 conf_path 判斷類型,觸發對應模板重新寫入
# 用於腳本版本升級時自動補齊新增的設定欄位
_update_conf() {
	case $conf_path in
	*backup_settings.conf)  update_backup_settings_conf>"$conf_path" ;;
	*restore_settings.conf) update_Restore_settings_conf>"$conf_path" ;;
	*) echo "$conf_path配置遺失" && exit 1 ;;
	esac
}
_conf_patch_log() {
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d ${SPEED_DEBUG_RUN_DIR:-} ]] || return 0
	printf '%s\n' "$*" >> "$SPEED_DEBUG_RUN_DIR/conf_patch.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}
_conf_has_key() {
	grep -Eq "^[[:space:]]*$1=" "$conf_path" 2>/dev/null
}
_conf_append_key() {
	local _key="$1" _line="$2"
	_conf_has_key "$_key" && return 0
	printf '\n%s\n' "$_line" >> "$conf_path" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	_conf_patch_log "APPEND key=$_key line=$_line"
}
_conf_insert_after_key() {
	local _anchor="$1" _key="$2" _line="$3" _tmp
	[[ -n $_key && -n $_line ]] || return 0
	_conf_has_key "$_key" && return 0
	_tmp="${conf_path}.tmp.$$"
	awk -v a="$_anchor" -v l="$_line" '
		BEGIN { done=0 }
		{ print }
		!done && $0 ~ "^[[:space:]]*" a "=" { print l; done=1 }
		END { if (!done) { print ""; print l } }
	' "$conf_path" > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && {
		cat "$_tmp" > "$conf_path"
		_conf_patch_log "INSERT key=$_key after=$_anchor line=$_line"
	}
	rm -f "$_tmp" 2>/dev/null
}
_conf_remove_exact_conf_lines() {
	local _tmp
	_tmp="${conf_path}.tmp.$$"
	awk '
		/^[[:space:]]*hybrid_urls="\$\{hybrid_urls:-\}"[[:space:]]*$/ {changed=1; next}
		/^[[:space:]]*hybrid_get_mode="\$\{hybrid_get_mode:-assist\}"[[:space:]]*$/ {changed=1; next}
		/^[[:space:]]*hybrid_get_lead_chunks="\$\{hybrid_get_lead_chunks:-32\}"[[:space:]]*$/ {changed=1; next}
		/^[[:space:]]*hybrid_get_assist_stride="\$\{hybrid_get_assist_stride:-5\}"[[:space:]]*$/ {changed=1; next}
		{ print }
		END { if (changed) exit 0; exit 1 }
	' "$conf_path" > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && {
		cat "$_tmp" > "$conf_path"
		_conf_patch_log "REMOVE abandoned_hxfer_conf_fallback_lines"
	}
	rm -f "$_tmp" 2>/dev/null
}
_conf_remove_key() {
	local _key="$1" _tmp
	[[ -n $_key ]] || return 0
	_conf_has_key "$_key" || return 0
	_tmp="${conf_path}.tmp.$$"
	awk -v k="$_key" '
		$0 ~ "^[[:space:]]*" k "=" { changed=1; next }
		{ print }
		END { if (changed) exit 0; exit 1 }
	' "$conf_path" > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && {
		cat "$_tmp" > "$conf_path"
		_conf_patch_log "REMOVE obsolete_key=$_key"
	}
	rm -f "$_tmp" 2>/dev/null
}
_conf_remove_internal_remote_function() {
	# 7.66-158 曾誤把內部 _remote_is_enabled() 函數寫進 backup_settings.conf；這裡只精準移除該污染區塊，不重排使用者 conf。
	grep -q '^_remote_is_enabled()[[:space:]]*{' "$conf_path" 2>/dev/null || return 0
	local _tmp="${conf_path}.tmp.$$"
	awk '
		/^_remote_is_enabled\(\)[[:space:]]*\{/ {skip=1; changed=1; next}
		skip && /^}/ {skip=0; next}
		!skip {print}
		END { if (changed) exit 0; exit 1 }
	' "$conf_path" > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && {
		if [[ -s "$_tmp" ]]; then
			cat "$_tmp" > "$conf_path"
			_conf_patch_log "REMOVE internal_function=_remote_is_enabled"
		else
			_conf_patch_log "SKIP remove: stripped result empty, conf left untouched"
		fi
	}
	rm -f "$_tmp" 2>/dev/null
}
_patch_conf_missing_fields() {
	# 只補缺失項，不整份重寫，不刪註解，不重排使用者設定。
	case $conf_path in
	*backup_settings.conf)
		# 清除已移交獨立模組/已放棄支線造成的舊污染；不重寫或重排其他使用者設定。
		local _obsolete_module_key="sm""bd_share_path"
		_conf_remove_key "$_obsolete_module_key"
		_conf_remove_internal_remote_function
		_conf_remove_exact_conf_lines
		# 只補缺失項，補固定值，不再把 ${var:-default} fallback 寫入使用者 conf。
		_conf_insert_after_key background_execution notification_enable 'notification_enable=1'
		_conf_insert_after_key Compression_method rgb_a 'rgb_a=220'
		_conf_insert_after_key rgb_a rgb_b 'rgb_b=51'
		_conf_insert_after_key rgb_b rgb_c 'rgb_c=213'
		_conf_insert_after_key rgb_c remote_type 'remote_type='
		_conf_insert_after_key remote_type smb_url 'smb_url='
		_conf_insert_after_key smb_url smb_remote_user 'smb_remote_user='
		_conf_insert_after_key smb_remote_user smb_remote_pass 'smb_remote_pass=""'
		_conf_insert_after_key smb_remote_pass webdav_url 'webdav_url='
		_conf_insert_after_key webdav_url webdav_remote_user 'webdav_remote_user='
		_conf_insert_after_key webdav_remote_user webdav_remote_pass 'webdav_remote_pass=""'
		_conf_insert_after_key webdav_remote_pass remote_stream 'remote_stream=0'
		_conf_insert_after_key remote_stream diagnostic_mode 'diagnostic_mode=0'
		_conf_insert_after_key diagnostic_mode remote_keep_local 'remote_keep_local=0'
		_conf_insert_after_key remote_keep_local remote_upload_per_app 'remote_upload_per_app=0'
		_conf_insert_after_key remote_upload_per_app log_max_size_mb 'log_max_size_mb=1'
		;;
	*restore_settings.conf)
		_conf_remove_exact_conf_lines
		_conf_insert_after_key background_execution notification_enable 'notification_enable=1'
		_conf_insert_after_key notification_enable diagnostic_mode 'diagnostic_mode=0'
		_conf_insert_after_key diagnostic_mode log_max_size_mb 'log_max_size_mb=1'
		_conf_insert_after_key Compression_method rgb_a 'rgb_a=220'
		_conf_insert_after_key rgb_a rgb_b 'rgb_b=51'
		_conf_insert_after_key rgb_b rgb_c 'rgb_c=213'
		;;
	esac
}
if [[ ! -f $conf_path ]]; then
	_update_conf
	echo "因腳本找不到\n$conf_path\n故重新生成默認列表\n請重新配置後重新執行腳本" && exit 0
fi
. "$conf_path" &>/dev/null
# 保存使用者 conf 原值；後續遠端預檢可能會暫時清空/關閉 runtime 變量，不能反寫污染 backup_settings.conf。
_CONF_SRC_remote_type="$remote_type"
_CONF_SRC_smb_url="$smb_url"
_CONF_SRC_smb_remote_user="$smb_remote_user"
_CONF_SRC_smb_remote_pass="$smb_remote_pass"
_CONF_SRC_webdav_url="$webdav_url"
_CONF_SRC_webdav_remote_user="$webdav_remote_user"
_CONF_SRC_webdav_remote_pass="$webdav_remote_pass"
_CONF_SRC_remote_stream="$remote_stream"
_CONF_SRC_remote_keep_local="$remote_keep_local"
_CONF_SRC_remote_upload_per_app="$remote_upload_per_app"
_patch_conf_missing_fields
# 補缺失項後重新載入一次，但不重寫、不重排使用者 conf。
. "$conf_path" &>/dev/null
# 使用者只看到一個診斷開關；細項除錯/測試策略在內部統一派生，不寫回 conf。
_speedbackup_apply_internal_policy
_remote_type_orig="${remote_type:-}"
# 依 remote_type 取對應遠端位址/帳密 (smb_*/webdav_* 由 conf 設定)
case $remote_type in
smb) remote_url="$smb_url"; remote_user="$smb_remote_user"; remote_pass="$smb_remote_pass" ;;
webdav) remote_url="$webdav_url"; remote_user="$webdav_remote_user"; remote_pass="$webdav_remote_pass" ;;
*) remote_url=""; remote_user=""; remote_pass="" ;;
esac

# SMB 憑證改走檔案傳遞；WebDAV 已改由 dex WebDavUtil 傳參，不再生成外部 HTTP 工具專用參數。
_SMB_AUTHFILE=""
# trim 前後空白: 設定檔裡的欄位若殘留空格/CR, "-n" 判斷會誤判為已填帳號,
# 導致產生只含空白的憑證檔路徑, 舊外部 HTTP 工具收到錯誤參數直接報錯。
_remote_user_trimmed="${remote_user# }"; _remote_user_trimmed="${_remote_user_trimmed% }"
if [[ $remote_type = smb && -n $_remote_user_trimmed ]]; then
	_SMB_AUTHFILE="${TMPDIR:-/data/local/tmp}/.smb_authfile_$$"
	{
		printf 'username = %s\n' "$remote_user"
		printf 'password = %s\n' "$remote_pass"
	} > "$_SMB_AUTHFILE" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	chmod 0600 "$_SMB_AUTHFILE" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
fi
unset _remote_user_trimmed

# ===== WebDAV daemon（優先 AF_UNIX，TCP loopback 相容回退）=====
# Dex daemon 的六行控制協定保持不變；native unixsock v2 只負責二進位安全的
# stdin/stdout relay、stdin EOF half-close，以及把兩行回應 header 寫入小型 sidecar。
# getstdoutrel 的 body 直接串到 stdout，不建立 archive-sized response 暫存檔。
_WEBDAV_DAEMON_PORT="${_WEBDAV_DAEMON_PORT:-8971}"
_WEBDAV_DAEMON_SOCKET="${_WEBDAV_DAEMON_SOCKET:-$TMPDIR/.webdav_daemon.sock}"
_WEBDAV_DAEMON_PID_FILE=""
_WEBDAV_DAEMON_STATE_FILE=""
_WEBDAV_DAEMON_START_LOCK="${_WEBDAV_DAEMON_START_LOCK:-$TMPDIR/.webdav_daemon.start.lock}"
_WEBDAV_DAEMON_READY=0
_WEBDAV_DAEMON_MODE=""
_WEBDAV_DAEMON_TARGET=""
_WEBDAV_UNIXSOCK_READY_CACHE=""
# command substitution 會在子 shell 執行；_WEBDAV_HTTP_CODE 這類變數不會回到父 shell。
# 因此 daemon 解析到的 HTTP 狀態同時寫入 sidecar，供 OPTIONS/list/stat 等捕獲 stdout 的路徑讀回。
_WEBDAV_LAST_STATUS_FILE="${_WEBDAV_LAST_STATUS_FILE:-$TMPDIR/.webdav_last_status_${SPEEDBACKUP_MAIN_PID:-$$}}"

_webdav_status_sidecar_reset() {
	[[ -n ${_WEBDAV_LAST_STATUS_FILE:-} ]] && rm -f "$_WEBDAV_LAST_STATUS_FILE" 2>/dev/null
}

_webdav_status_sidecar_store() {
	[[ -n ${_WEBDAV_LAST_STATUS_FILE:-} ]] || return 0
	{
		printf '%s\n' "${_WEBDAV_HTTP_CODE:-0}"
		printf '%s\n' "${_WEBDAV_BODY_LENGTH:-0}"
	} > "$_WEBDAV_LAST_STATUS_FILE" 2>/dev/null || true
}

_webdav_status_sidecar_load() {
	local _code _len
	[[ -s ${_WEBDAV_LAST_STATUS_FILE:-} ]] || return 1
	_code="$(sed -n '1p' "$_WEBDAV_LAST_STATUS_FILE" 2>/dev/null)"
	_len="$(sed -n '2p' "$_WEBDAV_LAST_STATUS_FILE" 2>/dev/null)"
	case $_code in ''|*[!0-9]*) return 1 ;; esac
	case $_len in -1|-2|*[!0-9]*|'') _len=0 ;; esac
	_WEBDAV_HTTP_CODE="$_code"
	_WEBDAV_BODY_LENGTH="$_len"
	rm -f "$_WEBDAV_LAST_STATUS_FILE" 2>/dev/null
	return 0
}

_webdav_tmp_path() {
	local _prefix="${1:-webdav_tmp}" _f
	_f="$(mktemp "$TMPDIR/.${_prefix}_XXXXXX" 2>/dev/null)" && { echo "$_f"; return 0; }
	printf '%s/.%s_%s_%s_%s\n' "$TMPDIR" "$_prefix" "$$" "$RANDOM" "$(date +%s 2>/dev/null)"
}

_webdav_unixsock_relay_ready() {
	local _ver
	case ${_WEBDAV_UNIXSOCK_READY_CACHE:-} in
	1) return 0 ;;
	0) return 1 ;;
	esac
	[[ -x ${EVENT_UNIXSOCK_BIN:-} ]] || { _WEBDAV_UNIXSOCK_READY_CACHE=0; return 1; }
	# 外層 subshell 一併吞掉「Segmentation fault」等 shell 診斷；結果只快取一次，
	# 避免損壞的 unixsock 在同一輪被重複執行。
	_ver="$( ( "$EVENT_UNIXSOCK_BIN" --version ) 2>/dev/null | head -n 1)"
	case "$_ver" in
	*stream-relay*|*stream-framed*) _WEBDAV_UNIXSOCK_READY_CACHE=1; return 0 ;;
	*) _WEBDAV_UNIXSOCK_READY_CACHE=0; return 1 ;;
	esac
}

_webdav_proc_cmdline() {
	local _pid="$1"
	[[ -r /proc/$_pid/cmdline ]] || return 1
	tr '\000' ' ' < "/proc/$_pid/cmdline" 2>/dev/null
}

_webdav_proc_starttime() {
	local _pid="$1"
	[[ -r /proc/$_pid/stat ]] || return 1
	sed 's/^[^)]*) //' "/proc/$_pid/stat" 2>/dev/null | awk '{print $20; exit}'
}

_webdav_daemon_write_state() {
	local _pid="$1" _mode="$2" _target="$3" _start _tmp
	_start="$(_webdav_proc_starttime "$_pid")"
	case $_pid in ''|*[!0-9]*) return 1 ;; esac
	case $_start in ''|*[!0-9]*) return 1 ;; esac
	_tmp="${_WEBDAV_DAEMON_STATE_FILE}.tmp.$$.$RANDOM"
	printf '%s|%s|%s|%s|%s\n' "$_mode" "$_target" "$SPEEDBACKUP_MAIN_PID" "$_pid" "$_start" > "$_tmp" 2>/dev/null || return 1
	chmod 0600 "$_tmp" 2>/dev/null
	mv -f "$_tmp" "$_WEBDAV_DAEMON_STATE_FILE" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
	printf '%s\n' "$_pid" > "${_WEBDAV_DAEMON_PID_FILE}.tmp.$$" 2>/dev/null || return 1
	chmod 0600 "${_WEBDAV_DAEMON_PID_FILE}.tmp.$$" 2>/dev/null
	mv -f "${_WEBDAV_DAEMON_PID_FILE}.tmp.$$" "$_WEBDAV_DAEMON_PID_FILE" 2>/dev/null
}

_webdav_daemon_load_state() {
	local _line _mode _target _owner _pid _start _current
	[[ -s $_WEBDAV_DAEMON_STATE_FILE && -s $_WEBDAV_DAEMON_PID_FILE ]] || return 1
	_line="$(sed -n '1p' "$_WEBDAV_DAEMON_STATE_FILE" 2>/dev/null)"
	_mode="${_line%%|*}"; _line="${_line#*|}"
	_target="${_line%%|*}"; _line="${_line#*|}"
	_owner="${_line%%|*}"; _line="${_line#*|}"
	_pid="${_line%%|*}"; _start="${_line#*|}"
	case $_pid in ''|*[!0-9]*) return 1 ;; esac
	case $_start in ''|*[!0-9]*) return 1 ;; esac
	[[ $_owner = "$SPEEDBACKUP_MAIN_PID" ]] || return 1
	[[ "$(cat "$_WEBDAV_DAEMON_PID_FILE" 2>/dev/null)" = "$_pid" ]] || return 1
	kill -0 "$_pid" 2>/dev/null || return 1
	_current="$(_webdav_proc_starttime "$_pid")"
	[[ $_current = "$_start" ]] || return 1
	# 不在 daemon fork 後立即用 /proc/<pid>/cmdline 驗證 Java 參數：
	# child 在 exec app_process 前存在極短競態窗口，會暫時仍顯示父 shell/nohup cmdline，
	# 導致正常 daemon 被誤判並立刻 TERM。PID + /proc starttime + owner + target 已足以防 PID reuse。
	case $_mode in
	unix) [[ $_target = "$_WEBDAV_DAEMON_SOCKET" ]] || return 1 ;;
	tcp) [[ $_target = "$_WEBDAV_DAEMON_PORT" ]] || return 1 ;;
	*) return 1 ;;
	esac
	_WEBDAV_DAEMON_MODE="$_mode"
	_WEBDAV_DAEMON_TARGET="$_target"
	return 0
}

_webdav_daemon_transport_probe() {
	# 不只看 pid/state；直接對現存 transport 發一個純本地 encodepath request。
	# 這能跨 mksh command substitution/subshell 驗證真正可用的 daemon endpoint，
	# 避免 shell identity 或 state validator 假陰性造成每次 WebDAV 操作都重啟 JVM。
	local _status _rc _code_line
	_webdav_unixsock_relay_ready || return 1
	_status="$(_webdav_tmp_path webdav_daemon_probe_status)"
	rm -f "$_status" 2>/dev/null
	case $_WEBDAV_DAEMON_MODE in
	unix)
		[[ -S $_WEBDAV_DAEMON_SOCKET ]] || { rm -f "$_status" 2>/dev/null; return 1; }
		printf 'encodepath\n\n\nprobe\n\n0\n' | "$EVENT_UNIXSOCK_BIN" relay-unix "$_WEBDAV_DAEMON_SOCKET" --header-file "$_status" >/dev/null 2>/dev/null
		_rc=$?
		;;
	tcp)
		printf 'encodepath\n\n\nprobe\n\n0\n' | "$EVENT_UNIXSOCK_BIN" relay-tcp 127.0.0.1 "$_WEBDAV_DAEMON_PORT" --header-file "$_status" >/dev/null 2>/dev/null
		_rc=$?
		;;
	*)
		rm -f "$_status" 2>/dev/null
		return 1
		;;
	esac
	_code_line="$(sed -n '1p' "$_status" 2>/dev/null)"
	rm -f "$_status" 2>/dev/null
	[[ $_rc = 0 && $_code_line = "HTTP 200" ]]
}

_webdav_daemon_transport_alive() {
	# Reuse 以「實際 endpoint 可連線」為最終依據，而不是只依賴 shell state/PID。
	# state/PID 仍保留給 stop 的安全身分驗證與 TCP mode 還原。
	local _pid _line _mode _target
	[[ -n $_WEBDAV_DAEMON_PID_FILE ]] || _WEBDAV_DAEMON_PID_FILE="$TMPDIR/.webdav_daemon.pid"
	[[ -n $_WEBDAV_DAEMON_STATE_FILE ]] || _WEBDAV_DAEMON_STATE_FILE="$TMPDIR/.webdav_daemon.state"

	# AF_UNIX endpoint 存在時優先直接 probe；即使 state owner/starttime 因 shell identity
	# 驗證失敗，只要 socket 真能完成 daemon protocol，就視為可 reuse。
	if [[ -S $_WEBDAV_DAEMON_SOCKET ]]; then
		_WEBDAV_DAEMON_MODE=unix
		_WEBDAV_DAEMON_TARGET="$_WEBDAV_DAEMON_SOCKET"
		_webdav_daemon_transport_probe && return 0
	fi

	# 沒有可用 Unix endpoint 時，從 state 還原 TCP mode 再做實際 probe。
	if [[ -s $_WEBDAV_DAEMON_STATE_FILE ]]; then
		_line="$(sed -n '1p' "$_WEBDAV_DAEMON_STATE_FILE" 2>/dev/null)"
		_mode="${_line%%|*}"
		_line="${_line#*|}"
		_target="${_line%%|*}"
		case $_mode in
		tcp)
			[[ $_target = "$_WEBDAV_DAEMON_PORT" ]] || return 1
			_WEBDAV_DAEMON_MODE=tcp
			_WEBDAV_DAEMON_TARGET="$_target"
			_webdav_daemon_transport_probe && return 0
			;;
		esac
	fi

	# probe 不可用/失敗時只作保守失敗，不把未知 PID 當成可重用 daemon。
	return 1
}

_webdav_daemon_ready_line_ok() {
	local _out="$1"
	case $_WEBDAV_DAEMON_MODE in
	unix) grep -Fqx "DAEMON_READY_UNIX $_WEBDAV_DAEMON_SOCKET" "$_out" 2>/dev/null && [[ -S $_WEBDAV_DAEMON_SOCKET ]] ;;
	tcp) grep -Fqx "DAEMON_READY $_WEBDAV_DAEMON_PORT" "$_out" 2>/dev/null ;;
	*) return 1 ;;
	esac
}

# WebDAV daemon readiness：優先 filewatch 阻塞等待；事件遺失或 ROM inotify
# 行為異常時，才回退 0.1 秒有限輪詢。
_webdav_daemon_wait_ready() {
	local _out="$1" _diag="$2" _pid="$3" _fw_pid="" _guard_pid="" _fw_rc=0 _i=0
	case $_pid in ''|*[!0-9]*) return 1 ;; esac
	# 啟動等待只檢查這次剛 fork 出來的明確 PID。
	# 不在 ready 前重新走 state/owner/target 驗證：command substitution / mksh subshell
	# 的 shell identity 可能讓完整 validator 暫時失敗，造成 daemon 還活著卻同秒被判死。
	_webdav_daemon_ready_line_ok "$_out" && kill -0 "$_pid" 2>/dev/null && return 0
	kill -0 "$_pid" 2>/dev/null || return 1

	_event_filewatch_once "$_out" 5 webdav_ready "$_diag"
	_fw_rc=$?
	_webdav_daemon_ready_line_ok "$_out" && kill -0 "$_pid" 2>/dev/null && {
		echo "$(date '+%H:%M:%S') ready_wait=filewatch rc=$_fw_rc mode=$_WEBDAV_DAEMON_MODE pid=$_pid" >> "$_diag" 2>/dev/null
		return 0
	}
	kill -0 "$_pid" 2>/dev/null || return 1
	[[ $_fw_rc != 125 ]] && echo "$(date '+%H:%M:%S') filewatch no ready line rc=$_fw_rc mode=$_WEBDAV_DAEMON_MODE pid=$_pid, fallback bounded poll" >> "$_diag" 2>/dev/null

	_i=0
	while [[ $_i -lt 30 ]]; do
		_webdav_daemon_ready_line_ok "$_out" && kill -0 "$_pid" 2>/dev/null && {
			echo "$(date '+%H:%M:%S') ready_wait=fallback_poll iterations=$_i mode=$_WEBDAV_DAEMON_MODE pid=$_pid" >> "$_diag" 2>/dev/null
			return 0
		}
		kill -0 "$_pid" 2>/dev/null || return 1
		sleep 0.1
		_i=$((_i + 1))
	done
	return 1
}

_webdav_daemon_stop() {
	_dex_watchdog_stop webdav
	local _pid="" _i=0 _can_kill=0 _cmdline=""
	[[ -n $_WEBDAV_DAEMON_PID_FILE ]] || _WEBDAV_DAEMON_PID_FILE="$TMPDIR/.webdav_daemon.pid"
	[[ -n $_WEBDAV_DAEMON_STATE_FILE ]] || _WEBDAV_DAEMON_STATE_FILE="$TMPDIR/.webdav_daemon.state"

	# 優先使用嚴格 state 驗證，避免 stale pid file 遇到 PID reuse 時誤殺其他程序。
	if _webdav_daemon_load_state; then
		_pid="$(cat "$_WEBDAV_DAEMON_PID_FILE" 2>/dev/null)"
		_can_kill=1
	else
		# 若 state 因 shell identity/owner 驗證失敗，但 pid 指向的 cmdline 明確仍是本工具的
		# WebDavUtil daemon，也允許安全收尾，避免留下只能等 idle timeout 的孤兒 JVM。
		_pid="$(cat "$_WEBDAV_DAEMON_PID_FILE" 2>/dev/null)"
		case $_pid in ''|*[!0-9]*) _pid="" ;; esac
		if [[ -n $_pid ]] && kill -0 "$_pid" 2>/dev/null; then
			_cmdline="$(_webdav_proc_cmdline "$_pid")"
			case "$_cmdline" in
			*"com.xayah.dex.WebDavUtil daemonunix $_WEBDAV_DAEMON_SOCKET"*|*"com.xayah.dex.WebDavUtil daemon $_WEBDAV_DAEMON_PORT"*) _can_kill=1 ;;
			esac
		fi
	fi

	if [[ $_can_kill = 1 && -n $_pid ]] && kill -0 "$_pid" 2>/dev/null; then
		_event_terminate_pid "$_pid" webdav_daemon_stop
	fi
	rm -f "$_WEBDAV_DAEMON_PID_FILE" "$_WEBDAV_DAEMON_STATE_FILE" "$TMPDIR/.webdav_daemon_out" "$_WEBDAV_DAEMON_SOCKET" 2>/dev/null
	# start lock 是 mkdir 建立的空目錄；正常/異常 stop 都保底移除，避免下輪等待 stale starter。
	rmdir "$_WEBDAV_DAEMON_START_LOCK" 2>/dev/null || true
	_WEBDAV_DAEMON_READY=0
	_WEBDAV_DAEMON_MODE=""
	_WEBDAV_DAEMON_TARGET=""
}

_webdav_daemon_start_mode() {
	local _mode="$1" _diag="$2" _out="$TMPDIR/.webdav_daemon_out" _pid _daemon_err
	_daemon_err="$(_speed_debug_log_path webdav_daemon_stderr.log)"
	_WEBDAV_DAEMON_MODE="$_mode"
	case $_mode in
	unix)
		_WEBDAV_DAEMON_TARGET="$_WEBDAV_DAEMON_SOCKET"
		rm -f "$_WEBDAV_DAEMON_SOCKET" 2>/dev/null
		;;
	tcp) _WEBDAV_DAEMON_TARGET="$_WEBDAV_DAEMON_PORT" ;;
	*) return 1 ;;
	esac
	: > "$_out" 2>/dev/null || return 1
	_dex_export_classpath
	case $_mode in
	unix)
		nohup "$DEX_APP_PROCESS_BIN" "$DEX_APP_PROCESS_BASE" com.xayah.dex.WebDavUtil \
			daemonunix "$_WEBDAV_DAEMON_SOCKET" 1800 "$SPEEDBACKUP_MAIN_PID" > "$_out" 2>>"$_daemon_err" &
		;;
	tcp)
		nohup "$DEX_APP_PROCESS_BIN" "$DEX_APP_PROCESS_BASE" com.xayah.dex.WebDavUtil \
			daemon "$_WEBDAV_DAEMON_PORT" 1800 "$SPEEDBACKUP_MAIN_PID" > "$_out" 2>>"$_daemon_err" &
		;;
	esac
	_pid=$!
	disown "$_pid" 2>/dev/null
	_speedbackup_protect_pid "$_pid" webdav_daemon
	if ! _webdav_daemon_write_state "$_pid" "$_mode" "$_WEBDAV_DAEMON_TARGET"; then
		kill "$_pid" 2>/dev/null
		return 1
	fi
	if _webdav_daemon_wait_ready "$_out" "$_diag" "$_pid"; then
		_WEBDAV_DAEMON_READY=1
		echo "$(date '+%H:%M:%S') OK started pid=$_pid owner=$SPEEDBACKUP_MAIN_PID mode=$_mode target=$_WEBDAV_DAEMON_TARGET" >> "$_diag" 2>/dev/null
		case $_mode in
		unix) _dex_watchdog_start webdav "$_WEBDAV_DAEMON_PID_FILE" "$_WEBDAV_DAEMON_SOCKET" com.xayah.dex.WebDavUtil daemonunix "$_WEBDAV_DAEMON_SOCKET" 1800 "$SPEEDBACKUP_MAIN_PID" ;;
		tcp) _dex_watchdog_start webdav "$_WEBDAV_DAEMON_PID_FILE" - com.xayah.dex.WebDavUtil daemon "$_WEBDAV_DAEMON_PORT" 1800 "$SPEEDBACKUP_MAIN_PID" ;;
		esac
		return 0
	fi
	{
		echo "$(date '+%H:%M:%S') FAIL daemon did not become ready mode=$_mode target=$_WEBDAV_DAEMON_TARGET out=$_out"
		echo "state=$(cat "$_WEBDAV_DAEMON_STATE_FILE" 2>/dev/null)"
		echo "pid=$_pid alive=$(kill -0 "$_pid" 2>/dev/null && echo 1 || echo 0) starttime=$(_webdav_proc_starttime "$_pid") shell_pid=$$"
		if _webdav_daemon_load_state; then echo "state_valid=1 mode=$_WEBDAV_DAEMON_MODE target=$_WEBDAV_DAEMON_TARGET"; else echo "state_valid=0"; fi
		echo "cmdline=$(_webdav_proc_cmdline "$_pid")"
		echo "----- daemon stdout -----"
		cat "$_out" 2>/dev/null
	} >> "$_diag" 2>/dev/null
	_webdav_daemon_stop
	return 1
}

_webdav_daemon_wait_for_starter() {
	local _i=0
	while [[ $_i -lt 80 ]]; do
		if _webdav_daemon_transport_alive; then
			_WEBDAV_DAEMON_READY=1
			return 0
		fi
		[[ -d $_WEBDAV_DAEMON_START_LOCK ]] || return 1
		sleep 0.1
		_i=$((_i + 1))
	done
	return 1
}

_webdav_daemon_ensure() {
	_WEBDAV_DAEMON_PID_FILE="$TMPDIR/.webdav_daemon.pid"
	_WEBDAV_DAEMON_STATE_FILE="$TMPDIR/.webdav_daemon.state"
	_WEBDAV_DAEMON_START_LOCK="${_WEBDAV_DAEMON_START_LOCK:-$TMPDIR/.webdav_daemon.start.lock}"
	if [[ $_WEBDAV_DAEMON_READY = 1 ]] && _webdav_daemon_transport_alive; then
		return 0
	fi
	_WEBDAV_DAEMON_READY=0
	local _diag="${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/webdav_daemon_ensure.log" _have_lock=0

	if _webdav_daemon_transport_alive; then
		_WEBDAV_DAEMON_READY=1
		echo "$(date '+%H:%M:%S') reuse pid=$(cat "$_WEBDAV_DAEMON_PID_FILE" 2>/dev/null) owner=$SPEEDBACKUP_MAIN_PID mode=$_WEBDAV_DAEMON_MODE target=$_WEBDAV_DAEMON_TARGET" >> "$_diag" 2>/dev/null
		return 0
	fi

	# 多個 command substitution / 並行遠端預掃可能同時第一次呼叫 _webdav_dex。
	# 用 mkdir 原子鎖只允許一個 starter，其餘等待 state/socket 出現後直接 reuse。
	if mkdir "$_WEBDAV_DAEMON_START_LOCK" 2>/dev/null; then
		_have_lock=1
	else
		if _webdav_daemon_wait_for_starter; then
			echo "$(date '+%H:%M:%S') reuse_after_wait pid=$(cat "$_WEBDAV_DAEMON_PID_FILE" 2>/dev/null) mode=$_WEBDAV_DAEMON_MODE target=$_WEBDAV_DAEMON_TARGET" >> "$_diag" 2>/dev/null
			return 0
		fi
		# starter 超時或異常退出，清理 stale lock 後只重試一次。
		rmdir "$_WEBDAV_DAEMON_START_LOCK" 2>/dev/null
		mkdir "$_WEBDAV_DAEMON_START_LOCK" 2>/dev/null && _have_lock=1
	fi
	[[ $_have_lock = 1 ]] || {
		echo "$(date '+%H:%M:%S') FAIL cannot acquire daemon start lock" >> "$_diag" 2>/dev/null
		return 1
	}

	# 拿到鎖後再次確認，避免上一個 starter 已經在鎖交接前完成。
	if _webdav_daemon_transport_alive; then
		_WEBDAV_DAEMON_READY=1
		rmdir "$_WEBDAV_DAEMON_START_LOCK" 2>/dev/null
		echo "$(date '+%H:%M:%S') reuse_after_lock pid=$(cat "$_WEBDAV_DAEMON_PID_FILE" 2>/dev/null) mode=$_WEBDAV_DAEMON_MODE target=$_WEBDAV_DAEMON_TARGET" >> "$_diag" 2>/dev/null
		return 0
	fi

	_webdav_daemon_stop

	# 只有 unixsock v2 stream relay 可用時才嘗試 AF_UNIX；舊單行 unixsock 不相容。
	if _webdav_unixsock_relay_ready; then
		if _webdav_daemon_start_mode unix "$_diag"; then
			rmdir "$_WEBDAV_DAEMON_START_LOCK" 2>/dev/null
			return 0
		fi
		echo "$(date '+%H:%M:%S') WARN unix daemon unavailable, fallback tcp" >> "$_diag" 2>/dev/null
	fi

	if _webdav_unixsock_relay_ready; then
		if _webdav_daemon_start_mode tcp "$_diag"; then
			rmdir "$_WEBDAV_DAEMON_START_LOCK" 2>/dev/null
			return 0
		fi
	fi
	rmdir "$_WEBDAV_DAEMON_START_LOCK" 2>/dev/null
	echo "$(date '+%H:%M:%S') FAIL no usable unixsock v2 stream relay" >> "$_diag" 2>/dev/null
	return 1
}

_webdav_parse_daemon_status() {
	local _status="$1" _code_line _len_line
	[[ -s $_status ]] || return 1
	_code_line="$(sed -n '1p' "$_status" 2>/dev/null)"
	_len_line="$(sed -n '2p' "$_status" 2>/dev/null)"
	_WEBDAV_HTTP_CODE="${_code_line#HTTP }"
	case $_WEBDAV_HTTP_CODE in *[!0-9]*|'') _WEBDAV_HTTP_CODE=0 ;; esac
	case $_len_line in
	-1|-2) _WEBDAV_BODY_LENGTH="$_len_line" ;;
	*[!0-9]*|'') _WEBDAV_BODY_LENGTH=0 ;;
	*) _WEBDAV_BODY_LENGTH="$_len_line" ;;
	esac
	[[ $_code_line = "HTTP $_WEBDAV_HTTP_CODE" ]] || return 1
	_webdav_status_sidecar_store
}

_webdav_transport_relay() {
	local _status="$1"
	_webdav_unixsock_relay_ready || return 125
	case $_WEBDAV_DAEMON_MODE in
	unix) "$EVENT_UNIXSOCK_BIN" relay-unix "$_WEBDAV_DAEMON_SOCKET" --header-file "$_status" ;;
	tcp) "$EVENT_UNIXSOCK_BIN" relay-tcp 127.0.0.1 "$_WEBDAV_DAEMON_PORT" --header-file "$_status" ;;
	*) return 125 ;;
	esac
}

# $1=command $2=user $3=pass $4=url $5=extra(可省)；stdin 為 PUT body。
# unixsock v2 路徑的 response body 全程直通 stdout，只暫存兩行 response header。
_webdav_daemon_call() {
	local _cmd="$1" _user="$2" _pass="$3" _url="$4" _extra=""
	shift 4 2>/dev/null || true
	if [[ $# -gt 0 ]]; then _extra="$1"; shift; fi
	while [[ $# -gt 0 ]]; do _extra="${_extra}	$1"; shift; done

	# WEB-R4/334: 只允許 unixsock v2 framed relay；不再回退 nc-only 舊 framing。
	if ! _webdav_unixsock_relay_ready; then
		_WEBDAV_HTTP_CODE=0
		_WEBDAV_ERROR_ZH="WebDAV daemon relay 不可用：需要 unixsock v2 framed relay；不再回退 nc-only 舊 framing"
		return 125
	fi

	case $_cmd in
	putstdinmanagedrel|putmanagedrel|managedproberel|compatProbeRel|putstdinchunkedrel|putbatchrel|getstdoutrel|mkdirsrel|moverel|copyrel|statrel|listrel|deleterel|putrel|getrel|mkdirrel|propfindrel|optionsrel) ;;
	*)
		_WEBDAV_HTTP_CODE=0
		_WEBDAV_ERROR_ZH="WebDAV rel-only 模式拒絕舊命令：$_cmd"
		return 125
		;;
	esac

	local _body_len=0 _status _relay_rc _try=0 _max_try=2 _diag
	_webdav_status_sidecar_reset
	case $_cmd in putstdinmanagedrel|putstdinchunkedrel|putbatchrel) _body_len=-1 ;; esac
	case $_cmd in putstdinmanagedrel|putstdinchunkedrel|putbatchrel|getstdoutrel) _max_try=1 ;; esac
	_diag="${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/webdav_daemon_call.log"

	while [[ $_try -lt $_max_try ]]; do
		_status="$(_webdav_tmp_path webdav_daemon_status)"
		rm -f "$_status" 2>/dev/null
		{
			printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$_cmd" "$_user" "$_pass" "$_url" "$_extra" "$_body_len"
			if [[ $_body_len = -1 ]]; then cat; fi
		} | _webdav_transport_relay "$_status" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_relay_rc=$?
		if [[ $_relay_rc = 0 ]] && _webdav_parse_daemon_status "$_status"; then
			_webdav_set_error_zh "$_WEBDAV_HTTP_CODE" ""
			echo "$(date '+%H:%M:%S') cmd=$_cmd mode=$_WEBDAV_DAEMON_MODE relay_rc=$_relay_rc http=$_WEBDAV_HTTP_CODE body_len=${_WEBDAV_BODY_LENGTH:-0} try=$_try" >> "$_diag" 2>/dev/null
			rm -f "$_status" 2>/dev/null
			case $_WEBDAV_HTTP_CODE in 2[0-9][0-9]) return 0 ;; *) return 1 ;; esac
		fi
		echo "$(date '+%H:%M:%S') FAIL cmd=$_cmd mode=$_WEBDAV_DAEMON_MODE relay_rc=$_relay_rc status_size=$(_local_file_size_debug "$_status") try=$_try" >> "$_diag" 2>/dev/null
		rm -f "$_status" 2>/dev/null
		_WEBDAV_DAEMON_READY=0
		_webdav_daemon_stop
		_try=$((_try + 1))
		[[ $_try -lt $_max_try ]] && _webdav_daemon_ensure || break
	done
	_WEBDAV_HTTP_CODE=0
	_WEBDAV_ERROR_ZH="WebDAV daemon 沒有有效回應：AF_UNIX/TCP framed relay 中斷、daemon 已退出或本次傳輸被下游提前關閉"
	return 1
}
# 統一透過 dex WebDavUtil daemon 呼叫。daemon/relay 不可用時直接失敗，不再回退單次 app_process。
# 大型 getstdoutrel 只走 daemon stream relay，不使用 command substitution。
_webdav_dex() {
	_WEBDAV_HTTP_CODE=0
	_WEBDAV_BODY_LENGTH=0
	_WEBDAV_ERROR_ZH=""
	if ! _webdav_daemon_ensure; then
		_WEBDAV_HTTP_CODE=0
		_WEBDAV_ERROR_ZH="WebDAV daemon 不可用：daemon 啟動失敗、unixsock v2 framed relay 不可用或 endpoint 無回應；熱路徑不再回退單次 app_process"
		_speed_debug_log "WEBDAV_DAEMON_REQUIRED_NO_SPAWN command=$1"
		return 1
	fi
	_webdav_daemon_call "$@"
	local _daemon_rc=$?
	if [[ $_daemon_rc = 125 ]]; then
		_WEBDAV_HTTP_CODE=0
		_WEBDAV_ERROR_ZH="WebDAV daemon relay 不可用：本功能需要 daemon stream relay；不再回退單次 app_process"
		_speed_debug_log "WEBDAV_DAEMON_RELAY_REQUIRED_NO_SPAWN command=$1 mode=$_WEBDAV_DAEMON_MODE"
		return 1
	fi
	return "$_daemon_rc"
}

# 本輪 WebDAV 目錄建立快取：避免同一輪反覆對同一路徑 MKCOL/EXISTS。
# 311: cache 必須是本輪私有；舊版固定 $TMPDIR/.webdav_mkcol_cache 會跨 run 殘留，
# 遠端被清空後仍誤判 MKCOL_CACHE_HIT，導致新備份目錄未建立。
_WEBDAV_MKCOL_CACHE_FILE="${_WEBDAV_MKCOL_CACHE_FILE:-$TMPDIR/.webdav_mkcol_cache_$$}"
_webdav_mkcol_cache_prune_stale() {
	local _f
	# 312: 清掉舊版固定 cache 與前次異常中斷留下的 per-run cache；本輪 cache 只做優化，刪舊檔不影響正確性。
	for _f in "$TMPDIR/.webdav_mkcol_cache" "$TMPDIR"/.webdav_mkcol_cache_[0-9]*; do
		[[ -e $_f ]] || continue
		[[ $_f = "$_WEBDAV_MKCOL_CACHE_FILE" ]] && continue
		rm -f "$_f" 2>/dev/null
	done
}
_webdav_mkcol_cache_prune_stale
_webdav_mkcol_cache_clear_current() {
	# 320: 本輪 MKCOL cache 只用於同一輪去重，正常/異常退出後都不應殘留在 TMPDIR。
	[[ -n ${_WEBDAV_MKCOL_CACHE_FILE:-} ]] && rm -f "$_WEBDAV_MKCOL_CACHE_FILE" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}
_webdav_mkcol_cache_has() {
	local _key="$1	$2"
	[[ -s $_WEBDAV_MKCOL_CACHE_FILE ]] && grep -Fqx "$_key" "$_WEBDAV_MKCOL_CACHE_FILE" 2>/dev/null
}
_webdav_mkcol_cache_add() {
	local _key="$1	$2"
	mkdir -p "${_WEBDAV_MKCOL_CACHE_FILE%/*}" 2>/dev/null || true
	printf '%s
' "$_key" >> "$_WEBDAV_MKCOL_CACHE_FILE" 2>/dev/null
}
_webdav_mkdirrel_chain() {
	# 339: mkdirsrel 在部分 rclone/WebDAV 組合上可能回 http=0，且新 app 目錄 stat=404。
	# 這裡以 rel-only mkdirrel 逐層建立 parent chain，避免目錄不存在時仍把大檔串進 PUT
	# 導致 daemon/unixsock broken pipe。既有層用 statrel/cache 跳過，新層用 mkdirrel 建立。
	local _user="$1" _pass="$2" _base="$3" _rel="$4" _err="$5"
	local _oldifs _seg _cur="" _rc=1 _http=0 _stat_rc _stat_http
	[[ -n $_base && -n $_rel ]] || return 1
	_oldifs="$IFS"
	IFS='/'
	set -- $_rel
	IFS="$_oldifs"
	for _seg; do
		[[ -z $_seg ]] && continue
		if [[ -z $_cur ]]; then _cur="$_seg"; else _cur="$_cur/$_seg"; fi
		if _webdav_mkcol_cache_has "$_base" "$_cur"; then
			continue
		fi
		if [[ -n $_err ]]; then
			_webdav_dex statrel "$_user" "$_pass" "$_base" "$_cur" > /dev/null 2>>"$_err"
		else
			_webdav_dex statrel "$_user" "$_pass" "$_base" "$_cur" > /dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		fi
		_stat_rc=$?; _stat_http="${_WEBDAV_HTTP_CODE:-0}"
		case $_stat_http in
		2*)
			_webdav_mkcol_cache_add "$_base" "$_cur"
			_speed_debug_log "WEBDAV_MKDIR_CHAIN_EXISTING rel=$_cur stat_rc=$_stat_rc stat_http=$_stat_http"
			continue
			;;
		esac
		if [[ -n $_err ]]; then
			_webdav_dex mkdirrel "$_user" "$_pass" "$_base" "$_cur" > /dev/null 2>>"$_err"
		else
			_webdav_dex mkdirrel "$_user" "$_pass" "$_base" "$_cur" > /dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		fi
		_rc=$?; _http="${_WEBDAV_HTTP_CODE:-0}"
		case $_http in
		2*)
			_webdav_mkcol_cache_add "$_base" "$_cur"
			_speed_debug_log "WEBDAV_MKDIR_CHAIN_CREATED rel=$_cur mkdir_rc=$_rc mkdir_http=$_http"
			continue
			;;
		esac
		# race/idempotent：mkdirrel 非 2xx 時再 stat 一次，若已存在仍視為成功。
		if [[ -n $_err ]]; then
			_webdav_dex statrel "$_user" "$_pass" "$_base" "$_cur" > /dev/null 2>>"$_err"
		else
			_webdav_dex statrel "$_user" "$_pass" "$_base" "$_cur" > /dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		fi
		_stat_rc=$?; _stat_http="${_WEBDAV_HTTP_CODE:-0}"
		case $_stat_http in
		2*)
			_webdav_mkcol_cache_add "$_base" "$_cur"
			_speed_debug_log "WEBDAV_MKDIR_CHAIN_RACE_EXISTING rel=$_cur mkdir_rc=$_rc mkdir_http=$_http stat_rc=$_stat_rc stat_http=$_stat_http"
			continue
			;;
		esac
		_WEBDAV_HTTP_CODE="$_http"
		_speed_debug_log "WEBDAV_MKDIR_CHAIN_FAIL rel=$_cur mkdir_rc=$_rc mkdir_http=$_http stat_rc=$_stat_rc stat_http=$_stat_http"
		return "$_rc"
	done
	_WEBDAV_HTTP_CODE=200
	return 0
}

_webdav_mkdirrel_cached() {
	local _user="$1" _pass="$2" _base="$3" _rel="$4" _err="$5"
	local _chain_rc _chain_http
	[[ -n $_base && -n $_rel ]] || return 1
	if _webdav_mkcol_cache_has "$_base" "$_rel"; then
		_WEBDAV_HTTP_CODE=200
		_speed_debug_log "WEBDAV_MKDIR_CHAIN_CACHE_HIT rel=$_rel"
		return 0
	fi
	# 340: 停用 Dex mkdirsrel 熱路徑。實測 rclone WebDAV 會讓 mkdirsrel 回 http=0，
	# 但 rel-only statrel + mkdirrel 逐層建立穩定通過；因此正式流程直接走 chain，
	# 不再先呼叫 mkdirsrel，避免 main/daemon log 出現非阻斷 http=0 噪音。
	_webdav_mkdirrel_chain "$_user" "$_pass" "$_base" "$_rel" "$_err"
	_chain_rc=$?; _chain_http="${_WEBDAV_HTTP_CODE:-0}"
	if [[ $_chain_rc = 0 ]]; then
		_webdav_mkcol_cache_add "$_base" "$_rel"
		_WEBDAV_HTTP_CODE="$_chain_http"
		_speed_debug_log "WEBDAV_MKDIR_CHAIN_ONLY_OK rel=$_rel chain_http=$_chain_http"
		return 0
	fi
	_speed_debug_log "WEBDAV_MKDIR_CHAIN_ONLY_FAIL rel=$_rel chain_rc=$_chain_rc chain_http=$_chain_http"
	return "$_chain_rc"
}

_webdav_allow_has_method() {
	local _allow="$1" _method="$2"
	[[ -n $_method ]] || return 1
	printf '%s
' "$_allow" | tr ',' '
' | awk -v m="$_method" '
		{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); if (toupper($0)==toupper(m)) {found=1; exit}}
		END{exit found?0:1}'
}

_webdav_options_preflight() {
	local _base="$1" _rel="${2:-}" _mode="${3:-control}" _err _out _rc _http _allow _dav _need _missing=""
	[[ -n $_base ]] || return 1
	_err="$TMPDIR/.webdav_options_err_$$"
	_webdav_status_sidecar_reset
	if [[ -n $_rel ]]; then
		_out="$(_webdav_dex optionsrel "$remote_user" "$remote_pass" "$_base" "$_rel" 2>"$_err")"
	else
		_out="$(_webdav_dex optionsrel "$remote_user" "$remote_pass" "$_base" "." 2>"$_err")"
	fi
	_rc=$?
	_webdav_status_sidecar_load || true
	_http="${_WEBDAV_HTTP_CODE:-0}"
	remote_raw_log "remote_webdav_preflight.log" "OPTIONS mode=$_mode rc=$_rc http=$_http base=$_base rel=$_rel"
	[[ -n $_out ]] && printf '%s
' "$_out" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_webdav_preflight.log" 2>/dev/null
	remote_raw_cat "remote_webdav_preflight.log" "$_err" "[WEBDAV_OPTIONS stderr mode=$_mode rel=$_rel]"
	rm -f "$_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	case $_http in 2*) ;; *) return 1 ;; esac
	_allow="$(printf '%s
' "$_out" | awk -F= 'tolower($1)=="allow"{print substr($0,index($0,"=")+1); exit}')"
	_dav="$(printf '%s
' "$_out" | awk -F= 'tolower($1)=="dav"{print substr($0,index($0,"=")+1); exit}')"
	[[ -z $_dav ]] && _speed_debug_log "WEBDAV_OPTIONS_NO_DAV_HEADER mode=$_mode base=$_base rel=$_rel"
	# 某些 WebDAV server 的 Allow header 不完整；有提供 Allow 時才作嚴格方法檢查。
	if [[ -n $_allow ]]; then
		case $_mode in
		stream|atomic) _need="OPTIONS PROPFIND PUT GET DELETE MOVE" ;;
		upload) _need="OPTIONS PROPFIND PUT GET DELETE MOVE" ;;
		restore) _need="OPTIONS PROPFIND GET" ;;
		*) _need="OPTIONS PROPFIND PUT GET DELETE" ;;
		esac
		for _m in $_need; do
			if ! _webdav_allow_has_method "$_allow" "$_m"; then _missing="$_missing $_m"; fi
		done
		if [[ -n $_missing ]]; then
			# Some WebDAV servers (notably rclone WebDAV) return an incomplete Allow header
			# on collection OPTIONS even though PUT/GET work. Treat Allow as advisory
			# and let the real stream/atomic probe decide capability.
			_speed_debug_log "WEBDAV_OPTIONS_ALLOW_MISSING_ADVISORY mode=$_mode missing=$_missing allow=$_allow"
		fi
	fi
	return 0
}

_webdav_statrel_quiet() {
	local _base="$1" _rel="$2" _err _out _rc _http
	[[ -n $_base && -n $_rel ]] || return 1
	_err="$TMPDIR/.webdav_stat_err_$$"
	_webdav_status_sidecar_reset
	_out="$(_webdav_dex statrel "$remote_user" "$remote_pass" "$_base" "$_rel" 2>"$_err")"
	_rc=$?
	_webdav_status_sidecar_load || true
	_http="${_WEBDAV_HTTP_CODE:-0}"
	remote_raw_log "remote_webdav_stat_raw.log" "STAT rel=$_rel rc=$_rc http=$_http base=$_base"
	[[ -n $_out ]] && printf '%s
' "$_out" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_webdav_stat_raw.log" 2>/dev/null
	remote_raw_cat "remote_webdav_stat_raw.log" "$_err" "[WEBDAV_STAT stderr rel=$_rel]"
	rm -f "$_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	case $_http in 2*) printf '%s
' "$_out"; return 0 ;; *) return 1 ;; esac
}

_webdav_delete_quiet() {
	local _base="$1" _rel="$2"
	[[ -n $_base && -n $_rel ]] || return 0
	_webdav_dex deleterel "$remote_user" "$remote_pass" "$_base" "$_rel" >/dev/null 2>&1 || true
}

_webdav_putrel_atomic_file() {
	local _base="$1" _rel="$2" _file="$3" _tag="${4:-webdav_put}" _out="$5"
	local _err _rc _http
	[[ -n $_base && -n $_rel && -f $_file ]] || return 1
	_err="$TMPDIR/.webdav_put_managed_${_tag}_$$"
	_webdav_dex putmanagedrel "$remote_user" "$remote_pass" "$_base" "$_rel" "$_file" auto > "$_err" 2>&1
	_rc=$?
	_http="${_WEBDAV_HTTP_CODE:-0}"
	remote_raw_log "remote_webdav_upload_raw.log" "PUT_MANAGED tag=$_tag rc=$_rc http=$_http rel=$_rel file=$_file"
	remote_raw_cat "remote_webdav_upload_${_tag}.log" "$_err" "===== WEBDAV_PUT_MANAGED $_tag rel=$_rel rc=$_rc http=$_http ====="
	[[ -n $_out ]] && cat "$_err" > "$_out" 2>/dev/null
	rm -f "$_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	return "$_rc"
}

_webdav_atomic_capability_probe() {
	local _base="$1" _err _rc _http
	[[ -n $_base ]] || return 1
	_err="$TMPDIR/.webdav_managed_probe_err_$$"
	_webdav_dex managedproberel "$remote_user" "$remote_pass" "$_base" "" > /dev/null 2>"$_err"
	_rc=$?
	_http="${_WEBDAV_HTTP_CODE:-0}"
	remote_raw_log "remote_webdav_stream_probe_raw.log" "MANAGED_PROBE rc=$_rc http=$_http base=$_base"
	remote_raw_cat "remote_webdav_stream_probe_raw.log" "$_err" "[managed probe stderr http=$_http]"
	rm -f "$_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	return "$_rc"
}

# WebDAV 小檔 batch PUT：manifest 每行 rel<TAB>localFile，由 Dex daemon 同一 request 順序 PUT。
_webdav_putbatchrel() {
	local _base="$1" _base_rel="$2" _manifest="$3" _out="$4"
	[[ -s $_manifest ]] || return 1
	_webdav_dex putbatchrel "$remote_user" "$remote_pass" "$_base" "$_base_rel" < "$_manifest" > "$_out"
}
# ============================================================
# SpeedBackup single-file section: sb_10_remote_local_helpers.sh
# ============================================================
remote_type_valid() {
	case "${remote_type:-}" in webdav|smb) return 0 ;; *) return 1 ;; esac
}
remote_enabled() {
	remote_type_valid && [[ -n ${remote_url:-} ]]
}
stream_enabled() {
	remote_enabled && [[ ${remote_stream:-0} = 1 ]]
}
remote_ui_allowed() {
	remote_enabled
}
case $Shell_LANG in
1) SCRIPT_LANG="CN" ;;
0) SCRIPT_LANG="TW" ;;
*)
	_l="$(settings get system system_locales 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | head -1)"
	[[ -z $_l || $_l = null ]] && _l="$(getprop persist.sys.locale)"
	case $_l in
	zh-Hant*|zh_Hant*|zh-TW*|zh-HK*|zh-MO*) SCRIPT_LANG="TW" ;;
	zh-Hans*|zh_Hans*|zh-CN*|zh-SG*|zh*)    SCRIPT_LANG="CN" ;;
	esac
	;;
esac
# ======================================================
# 基礎工具函數
# ======================================================
# 帶色彩輸出, 用法: echoRgb "訊息" [色碼]
# 色碼:
#   0 = 紅色 (197)    - 錯誤/警告
#   1 = 亮綠 (121)    - 成功
#   2 = rgb_c (213)   - 強調/變數值 (粉紅, 預設)
#   3 = rgb_b (51)    - 提示/進度 (亮青, 預設)
#   其他/省略 = rgb_a (220) - 一般資訊 (亮黃, 預設)
# rgb_a/b/c 可在 conf 自訂, 全部都是 256 色 ANSI 編號
echoRgb() {
	local color
	case $2 in
	0) color=197 ;;
	1) color=121 ;;
	2) color=$rgb_c ;;
	3) color=$rgb_b ;;
	*) color=$rgb_a ;;
	esac
	echo -e "\e[38;5;${color}m -$1\e[0m"
	_speed_debug_log "MSG: $1"
}
[[ $remote_type = webdav ]] && echoRgb "WebDAV: dex WebDavUtil 原生/atomic模式" "3"

# ======================================================
# SMB client 網路 helper
# ======================================================
_get_local_ipv4() {
	local ipaddr

	ipaddr="$(ip route get 1.1.1.1 2>/dev/null | awk '{
		for (i = 1; i <= NF; i++) {
			if ($i == "src") {
				print $(i + 1)
				exit
			}
		}
	}')"

	if [[ -n "$ipaddr" ]]; then
		echo "$ipaddr"
		return 0
	fi

	ip -4 addr show wlan0 2>/dev/null | awk '/inet /{
		sub(/\/.*/, "", $2)
		print $2
		exit
	}'
}

# Android 上 smbclient 可能無法自行枚舉網卡；統一產生 client 端 smb.conf。
# client 端不綁死介面，避免遠端連線走錯網卡。
_smb_client_conf() {
	local run_dir conf_file ifaces ipaddr
	run_dir="/data/backup_tools/smbclient_runtime"
	conf_file="$run_dir/smb.conf"
	mkdir -p "$run_dir" 2>/dev/null || { echo /dev/null; return 1; }

	ifaces="$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
	if [[ -z "$ifaces" ]]; then
		ipaddr="$(_get_local_ipv4)"
		[[ -n "$ipaddr" ]] && ifaces="$ipaddr/24"
	fi
	if [[ -z "$ifaces" ]]; then
		ifaces="127.0.0.1/8"
	else
		ifaces="127.0.0.1/8 $ifaces"
	fi

	cat > "$conf_file" <<EOF
[global]
client min protocol = SMB2_02
client max protocol = SMB3
interfaces = $ifaces
bind interfaces only = no
disable netbios = yes
name resolve order = host
EOF
	chmod 600 "$conf_file" 2>/dev/null
	echo "$conf_file"
}

# JSON 覆寫 helper：用 cat 寫回而不是 mv/rename。
# 目的：避開部分 FUSE/sdcard/WebDAV/SMB 掛載層對 rename/chown/setfilecon 的限制。
# 僅用於 JSON 最終覆寫；壓縮檔搬移/檔名 rename 不走這裡。
_json_cat_replace() {
	local _src="$1" _dst="$2" _bak _had_old=0
	[[ -s $_src ]] || return 1
	jq -e . "$_src" >/dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	_bak="${TMPDIR:-/data/local/tmp}/.json_cat_replace_bak_${$}_$RANDOM"
	if [[ -f $_dst ]]; then
		_had_old=1
		cat "$_dst" > "$_bak" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || rm -f "$_bak" 2>/dev/null
	fi
	if cat "$_src" > "$_dst" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && jq -e . "$_dst" >/dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
		rm -f "$_bak" 2>/dev/null
		return 0
	fi
	if [[ $_had_old = 1 && -f $_bak ]]; then
		cat "$_bak" > "$_dst" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	fi
	rm -f "$_bak" 2>/dev/null
	return 1
}

# JSON 原地更新 helper
# 用法: jq_inplace <檔案> <jq 表達式> [額外參數...]
# 例: jq_inplace "$app_details" --arg k "key" '.[$k] = "value"'
jq_inplace() {
	local file="$1"; shift
	local tmp="$TMPDIR/.jq_$$" rc
	# jq_inplace 目前只用於 app_details.json；輸出使用 pretty JSON，避免本地寫入後被重新壓成單行。
	if jq "$@" "$file" > "$tmp"; then
		_json_cat_replace "$tmp" "$file"
		rc=$?
		rm -f "$tmp" 2>/dev/null
		return $rc
	else
		rm -f "$tmp" 2>/dev/null
		return 1
	fi
}

# 計算目錄總大小 (bytes), 純文件字節和 (對應電腦端「大小」)
# 用法: calc_dir_size <目錄路徑>
# 依功能類型顯示相關 conf 設定
# 遠端狀態片段 (供備份類附加顯示); 有啟用才顯示細節
remote_conf_line() {
	# 純本機模式不顯示任何遠端/流式字樣，避免一般用戶看到未啟用提示。
	remote_ui_allowed || return 0
	if stream_enabled; then
		echo "\n -遠端上傳:$remote_type ($remote_url)\n -流式上傳:開啟 (不佔本機)"
	else
		echo "\n -遠端上傳:$remote_type ($remote_url)\n -保留本地檔:$remote_keep_local"
	fi
}
show_conf() {
	case $1 in
	backup)
		echoRgb "配置詳細:\n -壓縮方式:$Compression_method\n -更新:$update\n -備份模式:$Backup_Mode\n -備份外部數據:$Backup_obb_data\n -備份user數據:$Backup_user_data\n -黑名單模式:$blacklist_mode\n -黑名單:$(printf "%s\n" "$blacklist" | awk '!/[#＃]/ && NF' | grep -c . 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})個\n -白名單:$(printf "%s\n" "$whitelist" | awk '!/[#＃]/ && NF' | grep -c . 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})個\n -自定義目錄備份:$backup_media\n -存在進程忽略備份:$Background_apps_ignore\n -關閉螢幕:$setDisplayPowerMode\n -通知欄:$notification_enable$(remote_conf_line)" ;;
	media)
		echoRgb "配置詳細:\n -壓縮方式:$Compression_method\n -自定義路徑:$Custom_path\n -關閉螢幕:$setDisplayPowerMode\n -通知欄:$notification_enable$(remote_conf_line)" ;;
	wifi)
		echoRgb "配置詳細:\n -關閉螢幕:$setDisplayPowerMode\n -通知欄:$notification_enable$(remote_conf_line)" ;;
	remote)
		echoRgb "配置詳細:\n -遠端類型:${remote_type:-未設定}\n -遠端位址:${remote_url:-未設定}\n -保留本地檔:$remote_keep_local" ;;
	restore)
		echoRgb "配置詳細:\n -壓縮方式:$Compression_method\n -關閉螢幕:$setDisplayPowerMode\n -通知欄:$notification_enable" ;;
	esac
}
calc_dir_size() {
	# 純文件字節總和 (對應電腦端「大小」, 不含目錄項佔用); 單一 find 進程。
	# FUSE/應用私有子目錄可能正常回 Permission denied；這類掃描噪音只進專用 debug，不污染 stderr.log。
	local _scan_err="/dev/null"
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d ${SPEED_DEBUG_RUN_DIR:-} ]] && _scan_err="$SPEED_DEBUG_RUN_DIR/dir_size_scan.log"
	find "$1" -type f -printf '%s\n' 2>>"$_scan_err" | awk '{s+=$1}END{print s+0}'
}

# 查預掃的目錄大小表 (.dir_sizes, 由 prepare_dir_size_map 並行算好)
# 用法: _dir_size <pkg> <type> <目錄路徑>  — 表中有則秒回, 無則現算(兜底)
_dir_size() {
	local _p="$1" _t="$2" _path="$3" _vn
	_DIR_SIZE_RET=""
	# 零 fork 組變量名 (內建展開轉義)
	_vn="_sz_${_p//[!a-zA-Z0-9]/_}_${_t//[!a-zA-Z0-9]/_}"
	# 防呆: 變量名只含合法字元才 eval (避免殘留 . 等造成 bad substitution); 否則現算
	case $_vn in
		*[!a-zA-Z0-9_]*) ;;  # 含非法字元 → 跳過查表, 走 fallback
		*) eval "_DIR_SIZE_RET=\${$_vn:-}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} ;;
	esac
	[[ -n $_DIR_SIZE_RET ]] && return
	_DIR_SIZE_RET="$(calc_dir_size "$_path")"
}
# 把 .dir_sizes 一次載入成動態變量 _sz_<pkg轉義>_<type>=size (取代每次 fork awk, 手機 fork 成本高)
load_dir_size_map() {
	[[ ! -f $TMPDIR/.dir_sizes ]] && return
	local _pk _ty _sz _vn
	while IFS=$'\t' read -r _pk _ty _sz; do
		[[ -z $_pk ]] && continue
		_vn="_sz_${_pk//[!a-zA-Z0-9]/_}_$_ty"
		eval "$_vn=\$_sz"
	done < "$TMPDIR/.dir_sizes"
}
# 將 $name1 寫入 .changed_apps (去重, 避免重複記錄)
_mark_changed() {
	awk -v n="$name1" 'BEGIN{f=0} $0==n{f=1;exit} END{if(!f)print n}' \
		"$TMPDIR/.changed_apps" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} >> "$TMPDIR/.changed_apps"
	# app_details metadata 變更也必須視為本輪有變更，否則遠端非流式增量會只上傳依賴文件，漏傳更新後的 app_details.json。
	backup_has_changes=1
}
# 通用: 把 pkg<TAB>value 表載入成動態變量 <prefix>_<pkg轉義>=value (零 fork 查詢)
# 用法: load_kv_map <檔案> <變量前綴>
load_kv_map() {
	[[ ! -f $1 ]] && return
	local _pk _val _vn _pfx="$2"
	while IFS=$'\t' read -r _pk _val; do
		[[ -z $_pk ]] && continue
		_vn="${_pfx}_${_pk//[!a-zA-Z0-9]/_}"
		eval "$_vn=\$_val"
	done < "$1"
}
# 通用查詢: _kv_get <變量前綴> <pkg>  → 印出值 (零 fork)
_kv_get() {
	local _vn="$1_${2//[!a-zA-Z0-9]/_}" _v
	eval "_v=\${$_vn}"
	echo "$_v"
}

# 通用查詢: pkg<TAB>value map 直接查詢；檔案不存在時保底建空檔，避免 awk No such file。
# 用法: _kv_file_get <map_file> <pkg>
_kv_file_get() {
	local _file="$1" _pkg="$2"
	[[ -z $_file || -z $_pkg ]] && return 0
	[[ -f $_file ]] || : > "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	awk -v pkg="$_pkg" -F'	' '$1 == pkg {print $2; exit}' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

# 依本次實際壓縮方式 chmod 輸出檔
# 注意: 應用 data 通常走全域 Compression_method=zstd；Media/自訂資料夾會用 _comp_override=tar。
# 因此不能只看全域 Compression_method，必須看傳入的有效 _comp。
_chmod_compressed_output() {
	local _base="$1" _comp="$2"
	case $_comp in
	tar|Tar|TAR)
		[[ -f "$_base.tar" ]] && chmod 0600 "$_base.tar" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		;;
	zstd|Zstd|ZSTD)
		[[ -f "$_base.tar.zst" ]] && chmod 0600 "$_base.tar.zst" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		;;
	*)
		[[ -f "$_base.tar" ]] && chmod 0600 "$_base.tar" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		[[ -f "$_base.tar.zst" ]] && chmod 0600 "$_base.tar.zst" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		;;
	esac
}

# v24.20.14-7.8 stream stderr clean: 流式 SMB 噪音只進 raw log，不污染 stderr.log。
# v24.20.14-7 local archive raw debug: 本地備份/壓縮/校驗/解壓 raw/meta/stderr log。
# 注意：tar/zstd 資料流 stdout 不可落檔；只記 meta、stderr、rc、耗時、路徑與大小。
_local_raw_debug_next_log() {
	# v24.20.14-7.66-191：raw debug 不再為每次操作建立 extract_001/compress_001/checksum_001。
	# 同一 kind 全部 append 到單一檔案，批量恢復時 speed_debug 包不會爆出大量分片日誌。
	local _kind="$1"
	printf '%s/%s.log\n' "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}" "$_kind"
}
_local_raw_debug_summary() {
	local _kind="$1"; shift
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d ${SPEED_DEBUG_RUN_DIR:-} ]] || return 0
	printf '%s\n' "$*" >> "$SPEED_DEBUG_RUN_DIR/${_kind}_raw.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}
_local_raw_debug_begin() {
	local _kind="$1"; shift
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d ${SPEED_DEBUG_RUN_DIR:-} ]] || { echo /dev/null; return 0; }
	local _log _now
	_log="$(_local_raw_debug_next_log "$_kind")"
	_now="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
	{
		echo "BEGIN kind=$_kind time=$_now"
		echo "$*"
	} >> "$_log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_local_raw_debug_summary "$_kind" "BEGIN log=${_log##*/} $*"
	echo "$_log"
}
_local_raw_debug_end() {
	local _kind="$1" _log="$2" _rc="$3" _start_ms="$4"; shift 4
	[[ -n $_log ]] || _log=/dev/null
	local _end_ms _elapsed _now
	_end_ms="$(date +%s%3N 2>/dev/null)"
	case $_end_ms in ''|*[!0-9]*) _end_ms="$(date +%s 2>/dev/null)000" ;; esac
	case $_start_ms in ''|*[!0-9]*) _elapsed=unknown ;; *) _elapsed=$((_end_ms - _start_ms)) ;; esac
	_now="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
	{
		echo "$*"
		echo "END kind=$_kind rc=$_rc elapsedMs=$_elapsed time=$_now"
	} >> "$_log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_local_raw_debug_summary "$_kind" "END log=${_log##*/} rc=$_rc elapsedMs=$_elapsed $*"
}
_local_file_size_debug() {
	local _f="$1" _s
	[ -f "$_f" ] || { echo 0; return; }
	# 不能用 `wc -c < file` 取壓縮檔大小；大檔會完整讀一遍，導致終端在「備份data數據成功」後長時間無輸出。
	# stat 只讀 metadata，8GB+ data.tar.zst 也能立即取得大小。
	_s="$(stat -c %s "$_f" 2>/dev/null)"
	case $_s in
	''|*[!0-9]*)
		# toybox/stat 不支援 -c 時退回 ls metadata；不要使用 wc -c，避免大檔完整讀取。
		_s="$(ls -ln "$_f" 2>/dev/null | awk '{print $5; exit}')"
		case $_s in ''|*[!0-9]*) _s=0 ;; esac
		;;
	esac
	echo "$_s"
}

_speed_now_ms() {
	local _ms
	_ms="$(date +%s%3N 2>/dev/null)"
	case $_ms in ''|*[!0-9]*) _ms="$(date +%s 2>/dev/null)000" ;; esac
	case $_ms in ''|*[!0-9]*) _ms=0 ;; esac
	printf '%s\n' "$_ms"
}
_webdav_speed_mib_s() {
	local _bytes="$1" _ms="$2"
	case $_bytes in ''|*[!0-9]*) _bytes=0 ;; esac
	case $_ms in ''|*[!0-9]*|0) _ms=1 ;; esac
	awk -v b="$_bytes" -v ms="$_ms" 'BEGIN{printf "%.2f", (b/1048576.0)/(ms/1000.0)}'
}
_webdav_size_mib_text() {
	local _bytes="$1"
	case $_bytes in ''|*[!0-9]*) _bytes=0 ;; esac
	awk -v b="$_bytes" 'BEGIN{printf "%.2fMiB", b/1048576.0}'
}

_archive_output_path() {
	local _base="$1" _comp="${2:-$Compression_method}"
	case $_comp in
	tar|Tar|TAR) printf '%s.tar\n' "$_base" ;;
	*) printf '%s.tar.zst\n' "$_base" ;;
	esac
}
_archive_print_ratio() {
	local _base="$1" _origin_size="$2" _comp="${3:-$Compression_method}" _out _out_size _rate
	case $_origin_size in ''|*[!0-9]*|0) return 0 ;; esac
	_out="$(_archive_output_path "$_base" "$_comp")"
	_out_size="$(_local_file_size_debug "$_out")"
	case $_out_size in ''|*[!0-9]*) _out_size=0 ;; esac
	_rate="$(awk -v s="$_out_size" -v f="$_origin_size" 'BEGIN{ if (f>0) printf "%.2f", (1-(s/f))*100; else printf "0.00" }')"
	echoRgb "壓縮率${_rate}% 大小$(size "$_out_size")"
}

# 單檔 stage helper 第一刀：集中 archive 檔名、清理、存在判斷、校驗與壓縮率輸出。
# 目標是先收斂 Backup_apk / Backup_data 裡重複的 .tar/.tar.zst 分支，不改檔名、不改恢復格式。
_archive_exists() {
	local _base="$1" _f
	for _f in "$_base".tar "$_base".tar.zst; do
		[[ -e $_f ]] && return 0
	done
	return 1
}
_archive_cleanup() {
	local _base="$1"
	rm -rf "$_base".tar "$_base".tar.zst "$_base".tar.* 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}
_backup_mark_done_pkg() {
	[[ -n $TMPDIR && -n $name2 && -n $Backup_folder ]] || return 0
	if ! awk -v p="$name2" '$2==p{f=1} END{exit !f}' "$TMPDIR/.backup_done" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
		echo "${Backup_folder##*/} $name2" >> "$TMPDIR/.backup_done"
	fi
}
_backup_stage_validate_and_ratio() {
	local _entry="$1" _base="$2" _origin_size="$3"
	if stream_enabled; then
		result=0
		echoRgb "${_entry}數據已流式上傳遠端 (大小 $(size "$_origin_size"))" "1"
		return 0
	fi
	Validation_file "$_base.tar"*
	case $result in ''|*[!0-9]*) result=1 ;; esac
	[[ $result = 0 ]] || return "$result"
	case $_origin_size in
	''|0|*[!0-9]*) ;;
	*) _archive_print_ratio "$_base" "$_origin_size" "${_comp_override:-$Compression_method}" ;;
	esac
	case $result in ''|*[!0-9]*) result=1 ;; esac
	return "$result"
}
_backup_data_archive_stage() {
	local _entry="$1" _data_path="$2" _out_base="$3" _dp_name _out_file
	_dp_name="${_data_path##*/}"
	case $_entry in
	hma)
		tar_compress_dir "$_out_base" "${_data_path%/*}" "$_dp_name"
		result=$?
		[[ $result = 0 ]] && echo_log "備份HMA-OSS配置" || { Set_back_1; echo_log "備份HMA-OSS配置"; }
		;;
	user|user_de)
		tar_compress_dir "$_out_base" "${_data_path%/*}" "$_dp_name" 			--exclude="$_dp_name/.ota" 			--exclude="$_dp_name/cache" 			--exclude="$_dp_name/lib" 			--exclude="$_dp_name/code_cache" 			--exclude="$_dp_name/no_backup" 			2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		result=$?
		[[ $result = 0 ]] && echo_log "備份${_entry}數據" || { Set_back_1; echo_log "備份${_entry}數據"; }
		;;
	*)
		tar_compress_dir "$_out_base" "${_data_path%/*}" "$_dp_name" 			--exclude="Backup_*" 			--exclude="$_dp_name/cache" 			--exclude="$_dp_name/QQ" 			--exclude="$_dp_name/Telegram" 			--exclude="$_dp_name/.*"
		result=$?
		_out_file="$(_archive_output_path "$_out_base" "${_comp_override:-$Compression_method}")"
		# Media / Download / Custom_path 這類外部目錄常有檔案邊備份邊變動；tar rc=1 但已產生非 0 備份檔時降級為警告。
		# 164 起同時支援 .tar 與 .tar.zst 輸出判斷，避免 zstd 模式誤把可用輸出當失敗。
		if [[ $result = 1 && -s "$_out_file" ]]; then
			echoRgb "備份${_entry}數據完成，但部分檔案可能在備份期間變動，已降級為警告" "0"
			_speed_debug_log "WARN: 備份${_entry}數據 tar rc=1 but output exists: $_out_file"
			result=0
			Set_back_0
		else
			[[ $result = 0 ]] && echo_log "備份${_entry}數據" || { Set_back_1; echo_log "備份${_entry}數據"; }
		fi
		;;
	esac
	case $result in ''|*[!0-9]*) result=1 ;; esac
	return "$result"
}

# stage runner final：集中 app_details stage 寫入與成功標記。
# 不改 JSON 格式，只把 Backup_data / Backup_apk 內重複 jq 片段收斂到固定入口。
_app_details_update_data_stage() {
	local _entry="$1" _path_value="$2" _size_value="$3" _date_value
	_date_value="$(date "+%Y.%m.%d %H:%M:%S")"
	if [[ -n $zsize ]]; then
		jq_inplace "$app_details" --arg e "$_entry" --arg p "$_path_value" --arg s "$_size_value" --arg d "$_date_value" '.[$e].path = $p | .[$e].Size = $s | .["Backup time"].date = $d'
	else
		jq_inplace "$app_details" --arg e "$_entry" --arg s "$_size_value" --arg d "$_date_value" '.[$e].Size = $s | .["Backup time"].date = $d'
	fi
}
_backup_data_stage_record_success() {
	local _entry="$1" _src_path="$2" _size_value="$3"
	[[ ${Backup_folder##*/} = Media ]] && [[ $(sed -e '/^$/d' "$mediatxt" | grep -w "${REPLY##*/}.tar$" | head -1) = "" ]] && echo "$FILE_NAME" >> "$mediatxt"
	_app_details_update_data_stage "$_entry" "$_src_path" "$_size_value"
	backup_has_changes=1
	case $_entry in user|data|obb|user_de|media|thanox|hma) _mark_changed ;; esac
}
_app_details_update_apk_stage() {
	local _old_version="$1" _new_version="$2"
	if [[ -n $_old_version ]]; then
		echoRgb "覆蓋app_details"
		jq_inplace "$app_details" --arg apk_version "$_new_version" --arg software "$name1" --arg pkg "$name2" '.[$software].apk_version = $apk_version | .[$software].PackageName = $pkg'
	else
		echoRgb "新增app_details"
		jq_inplace "$app_details" --arg software "$name1" --arg pkg "$name2" --arg apk_version "$_new_version" '.[$software].PackageName = $pkg | .[$software].apk_version = $apk_version'
	fi
}
_backup_apk_archive_stage() {
	tar_compress_glob "$Backup_folder/apk" "$apk_path2" "*.apk"
	result=$?
	echo_log "備份$apk_number個Apk"
	if [[ $result = 0 && $remote_stream != 1 ]]; then
		Validation_file "$Backup_folder/apk.tar"*
	fi
	case $result in ''|*[!0-9]*) result=1 ;; esac
	return "$result"
}
_backup_apk_stage_record_success() {
	local _old_version="$1" _new_version="$2"
	_backup_mark_done_pkg
	_app_details_update_apk_stage "$_old_version" "$_new_version"
	backup_has_changes=1
	_mark_changed
	[[ $name2 = com.android.chrome ]] && cleanup_chrome_legacy
}

# 壓縮 helper (取代散落各處的 tar/zstd case 分支)
# 用法 1 (目錄打包): tar_compress_dir <輸出檔基礎名> <切到目錄> <要打包名> [tar 額外參數...]
#   例: tar_compress_dir "$folder/user" "${dp%/*}" "${dp##*/}" --exclude=cache
# 用法 2 (glob 打包): tar_compress_glob <輸出檔基礎名> <切到目錄> <glob 模式>
#   例: tar_compress_glob "$folder/apk" "$apk_path2" "*.apk"
# 自動依 $Compression_method 決定輸出 .tar 還是 .tar.zst
# 若呼叫前設了局部變數 _comp_override, 優先使用它 (取代暫時修改全域 Compression_method 再復原的舊做法)
tar_compress_dir() {
	local out_base="$1" cd_to="$2" pack_name="$3"
	shift 3
	local _comp="${_comp_override:-$Compression_method}"
	# 流式模式 (remote_stream=1): 直接管道到遠端, 不寫本機 (省空間)
	# _STREAM_DEST 由呼叫端設為遠端目標目錄 (相對遠端根)
	if stream_enabled && [[ -n $_STREAM_DEST ]]; then
		{
			echoRgb "流式傳輸中 (邊壓邊傳, 不佔本機)..." "3" >/dev/tty 2>/dev/null ||
				_speed_debug_log "STREAM_TRANSFER_NOTICE out_base=$out_base comp=$_comp dest=$_STREAM_DEST"
		}
		local _rb="$_STREAM_DEST/${out_base##*/}"
		[[ ! -d ${out_base%/*} ]] && mkdir -p "${out_base%/*}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		case $_comp in
		tar|Tar|TAR)
			tar --checkpoint-action="ttyout=%T\r" --warning=no-file-changed \
				"$@" -cpf - -C "$cd_to" "$pack_name" | _stream_upload "$_rb.tar"
			;;
		zstd|Zstd|ZSTD)
			tar --checkpoint-action="ttyout=%T\r" --warning=no-file-changed \
				"$@" -cpf - -C "$cd_to" "$pack_name" | \
				zstd --ultra -3 -T0 -q --priority=rt | _stream_upload "$_rb.tar.zst"
			;;
		esac
		result=$?
		if [[ $result != 0 ]]; then
			echoRgb "流式上傳失敗 ($_rb) 遠端可能未寫入完整, 建議重試" "0" >&2
			echo "${_rb%%/*}" >> "$TMPDIR/.stream_failed"
			echo "${_rb%%/*}: ${_rb#*/}" >> "$TMPDIR/.stream_failed_detail"
			_speed_debug_log "STREAM_PAYLOAD_FAILED app=${_rb%%/*} item=${_rb#*/} pipeline_rc=$result"
		else
			_manifest_add "$_rb"
		fi
		return $result
	fi
	local _raw_log _raw_start _out_file _out_size
	_raw_start="$(date +%s%3N 2>/dev/null)"; case $_raw_start in ''|*[!0-9]*) _raw_start="$(date +%s 2>/dev/null)000" ;; esac
	_raw_log="$(_local_raw_debug_begin compress "mode=dir comp=$_comp out_base=$out_base cd_to=$cd_to pack=$pack_name extra=$*")"
	case $_comp in
	tar|Tar|TAR)
		tar --checkpoint-action="ttyout=%T\r" --warning=no-file-changed \
			"$@" -cpf "$out_base.tar" -C "$cd_to" "$pack_name" 2>>"$_raw_log"
		;;
	zstd|Zstd|ZSTD)
		( set -o pipefail 2>/dev/null; tar --checkpoint-action="ttyout=%T\r" --warning=no-file-changed \
			"$@" -cpf - -C "$cd_to" "$pack_name" 2>>"$_raw_log" | \
			zstd --ultra -3 -T0 -q --priority=rt 2>>"$_raw_log" > "$out_base.tar.zst" )
		;;
	esac
	result=$?
	_chmod_compressed_output "$out_base" "$_comp"
	case $_comp in tar|Tar|TAR) _out_file="$out_base.tar" ;; *) _out_file="$out_base.tar.zst" ;; esac
	_out_size="$(_local_file_size_debug "$_out_file")"
	_local_raw_debug_end compress "$_raw_log" "$result" "$_raw_start" "out_file=$_out_file out_size=$_out_size"
	[[ $result = 0 ]] && _manifest_add "${out_base#$Backup/}"
	return $result
}
# 記錄本次成功備份的檔案 (相對路徑不含副檔名, 例 1DM+/apk), 供結尾計數核驗
_manifest_add() {
	[[ -z $1 ]] && return
	# 第一次加入 manifest 時檔案可能尚未存在；不能直接 awk 讀不存在檔，否則 stderr.log 會出現
	# awk: /data/local/tmp/.backup_manifest: No such file or directory
	if [[ ! -f "$TMPDIR/.backup_manifest" ]]; then
		echo "$1" > "$TMPDIR/.backup_manifest"
		return 0
	fi
	if ! awk -v p="$1" '$0==p{f=1} END{exit !f}' "$TMPDIR/.backup_manifest" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
		echo "$1" >> "$TMPDIR/.backup_manifest"
	fi
}

# app_details.json 健全度檢查。
# 新格式以每個 App entry 的 app_state（schemaVersion=2）為唯一 App 狀態來源。
# 舊備份僅記弱提示；恢復時由單一 legacy→schema2 轉換器讀入，不再走舊 Dex/token 協定。
_json_health_check() {
	local _file="$1" _name="$2" _pkg _ver _state_count _legacy_count _has_ssaid _issues="" _hints=""
	[[ ! -s $_file ]] && { echo "$_name: app_details.json 不存在或為空" >> "$TMPDIR/.json_health_issues"; return; }
	if ! jq -e . "$_file" >/dev/null 2>&1; then
		echo "$_name: json 格式損壞 (無法解析)" >> "$TMPDIR/.json_health_issues"
		return
	fi
	_pkg="$(jq -r 'try (([.[] | objects | select(.PackageName != null).PackageName] | .[0]) // "") catch ""' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	_ver="$(jq -r 'try (([.[] | objects | select(.apk_version != null).apk_version] | .[0]) // "") catch ""' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	_state_count="$(jq -r 'try ([.[] | objects | select(.app_state != null)] | length) catch 0' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	_legacy_count="$(jq -r 'try ([.[] | objects | select(.permissions != null or .special_access != null or .battery_settings != null or .Ssaid != null)] | length) catch 0' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	_has_ssaid="$(jq -r 'try ([.[] | objects | select(.app_state.ssaid != null)] | length) catch 0' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	case $_state_count in ''|*[!0-9]*) _state_count=0 ;; esac
	case $_legacy_count in ''|*[!0-9]*) _legacy_count=0 ;; esac
	case $_has_ssaid in ''|*[!0-9]*) _has_ssaid=0 ;; esac
	[[ -z $_pkg ]] && _issues="$_issues 缺PackageName"
	[[ -z $_ver ]] && _issues="$_issues 缺apk_version"
	if [[ $_state_count -gt 0 ]]; then
		if ! jq -e '
			try all(.[] | objects | select(.app_state != null);
				(.app_state | type) == "object" and
				(.app_state.schemaVersion == 2) and
				(.app_state.recordType == "snapshot") and
				((.app_state.packageName // "") | type) == "string" and
				(.app_state.permissions | type) == "array" and
				(.app_state.specialAccess | type) == "object" and
				(.app_state.otherAppOps | type) == "array" and
				(.app_state.batterySettings | type) == "object") catch false
		' "$_file" >/dev/null 2>&1; then
			_issues="$_issues app_state schema/型態異常"
		fi
		if ! jq -e '
			try all(.[] | objects | select(.app_state != null);
				all(.app_state.permissions[]?;
					(.name|type)=="string" and (.granted|type)=="boolean" and
					(.flags|type)=="number") and
				all(.app_state.otherAppOps[]?;
					(.op|type)=="number" and (.mode|type)=="number")) catch false
		' "$_file" >/dev/null 2>&1; then
			_issues="$_issues app_state項目型態異常"
		fi
	else
		if [[ $_legacy_count -gt 0 ]]; then
			_hints="$_hints 舊版AppState格式（恢復時單次轉schema2）"
		else
			# 舊版/精簡 app_details 可能只有 APK/data 基本資訊，沒有權限狀態快照。
			# 只要 PackageName/apk_version 仍完整，就不視為損壞；恢復時只是不會有 AppState 可還原。
			if [[ -n $_issues ]]; then
				_issues="$_issues 缺app_state"
			else
				_hints="$_hints 精簡app_details未記錄AppState（非阻斷；重備後可補全權限狀態）"
			fi
		fi
	fi
	[[ -n $_issues ]] && echo "$_name:$_issues" >> "$TMPDIR/.json_health_issues"
	[[ $_state_count -gt 0 && $_has_ssaid -eq 0 ]] && _hints="$_hints SSAID無備份值"
	[[ -n $_hints ]] && echo "$_name:$_hints" >> "$TMPDIR/.json_health_hints"
}
# 彙整顯示流式備份失敗清單。
# 注意: 這裡的失敗不一定是 WebDAV PUT 失敗，也可能是 tar/zstd 在封包期間回傳非 0；
# 此時遠端可能已收到一個檔案，但 app_details 不會更新，下次會重備該 app，避免把不完整資料標記為有效。
_stream_failed_report() {
	[[ ! -s $TMPDIR/.stream_failed_detail ]] && return 0
	local _cnt
	_cnt="$(sort -u "$TMPDIR/.stream_failed_detail" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -vc '^$' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	case $_cnt in ''|*[!0-9]*) _cnt=0 ;; esac
	[[ $_cnt -le 0 ]] && return 0
	echoRgb "⚠️ 本輪有 $_cnt 筆流式備份資料失敗，以下應用下次會重新備份:" "0"
	sort -u "$TMPDIR/.stream_failed_detail" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _line; do
		[[ -n $_line ]] && echoRgb "$_line" "0"
	done
	echoRgb "上述項目未更新遠端 app_details.json，避免不完整資料被視為有效備份" "2"
}

# 彙整顯示 json 健全度檢查結果 (呼叫端在所有 _json_health_check 跑完後呼叫一次)
_json_health_report() {
	local _has_hints=0 _invalid_count _missing_count _checked_count
	[[ -s $TMPDIR/.json_health_hints ]] && _has_hints=1
	_invalid_count="${JSON_HEALTH_INVALID_COUNT:-0}"
	_missing_count="${JSON_HEALTH_MISSING_COUNT:-0}"
	_checked_count="${JSON_HEALTH_CHECKED_COUNT:-}"
	case $_invalid_count in ''|*[!0-9]*) _invalid_count=0 ;; esac
	case $_missing_count in ''|*[!0-9]*) _missing_count=0 ;; esac
	if [[ -s $TMPDIR/.json_health_issues || $_has_hints = 1 || ${JSON_HEALTH_REPORT_ALWAYS:-0} = 1 || $_invalid_count -gt 0 || $_missing_count -gt 0 ]]; then
		echoRgb "—————— JSON健全度檢查 ——————" "3"
	fi
	if [[ ! -s $TMPDIR/.json_health_issues && $_has_hints != 1 ]]; then
		if [[ $_invalid_count -gt 0 || $_missing_count -gt 0 ]]; then
			echoRgb "⚠️ 遠端app_details無效/下載不完整 $((_invalid_count + _missing_count)) 個，已略過，不納入損壞回報" "2"
			if [[ -s $TMPDIR/.json_health_remote_drops ]]; then
				echoRgb "遠端app_details異常清單:" "2"
				sort -u "$TMPDIR/.json_health_remote_drops" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _drop; do
					[[ -n $_drop ]] && echoRgb "$_drop" "2"
				done
				rm -f "$TMPDIR/.json_health_remote_drops" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			fi
		else
			if [[ ${JSON_HEALTH_REPORT_ALWAYS:-0} = 1 ]]; then
				if [[ -n $_checked_count ]]; then
					echoRgb "✅ JSON健全度檢查通過 $_checked_count/$_checked_count" "1"
				else
					echoRgb "✅ JSON健全度檢查通過" "1"
				fi
			fi
		fi
		unset JSON_HEALTH_REPORT_ALWAYS JSON_HEALTH_CHECKED_COUNT JSON_HEALTH_INVALID_COUNT JSON_HEALTH_MISSING_COUNT
		return
	fi
	if [[ -s $TMPDIR/.json_health_issues ]]; then
		local _cnt
		_cnt="$(grep -vc '^$' "$TMPDIR/.json_health_issues" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		echoRgb "⚠️ 發現 $_cnt 個app的app_details.json缺少必要欄位:" "0"
		while read -r _line; do
			[[ -n $_line ]] && echoRgb "$_line" "0"
		done < "$TMPDIR/.json_health_issues"
		echoRgb "上述app建議重新執行一次備份以補全資訊" "0"
		rm -f "$TMPDIR/.json_health_issues"
	fi
	if [[ $_has_hints = 1 ]]; then
		local _hcnt _limit=20
		_hcnt="$(grep -vc '^$' "$TMPDIR/.json_health_hints" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		case $_hcnt in ''|*[!0-9]*) _hcnt=0 ;; esac
		# 大量舊版備份會產生很多弱提示；完整清單留在 debug，終端只顯示摘要與前幾筆，避免誤會成失敗。
		if [[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d ${SPEED_DEBUG_RUN_DIR:-} ]]; then
			cp -f "$TMPDIR/.json_health_hints" "$SPEED_DEBUG_RUN_DIR/json_health_hints.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || true
		fi
		if [[ $_hcnt -gt $_limit ]]; then
			echoRgb "$_hcnt 個app為舊版/精簡 app_details 或缺少次要欄位（非阻斷；完整清單已寫入 debug）" "2"
			awk -v limit="$_limit" 'NF && NR<=limit {print}' "$TMPDIR/.json_health_hints" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _hline; do
				[[ -n $_hline ]] && echoRgb "$_hline" "2"
			done
			echoRgb "其餘 $((_hcnt - _limit)) 筆已省略，非阻斷" "2"
		else
			echoRgb "$_hcnt 個app有部分次要欄位未紀錄 (可能該app本來就沒有, 非異常):" "2"
			while read -r _hline; do
				[[ -n $_hline ]] && echoRgb "$_hline" "2"
			done < "$TMPDIR/.json_health_hints"
		fi
		rm -f "$TMPDIR/.json_health_hints"
	fi
	if [[ $_invalid_count -gt 0 || $_missing_count -gt 0 ]]; then
		echoRgb "⚠️ 遠端app_details無效/下載不完整 $((_invalid_count + _missing_count)) 個，已略過，不納入損壞回報" "2"
		if [[ -s $TMPDIR/.json_health_remote_drops ]]; then
			echoRgb "遠端app_details異常清單:" "2"
			sort -u "$TMPDIR/.json_health_remote_drops" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _drop; do
				[[ -n $_drop ]] && echoRgb "$_drop" "2"
			done
			rm -f "$TMPDIR/.json_health_remote_drops" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		fi
	fi
	unset JSON_HEALTH_REPORT_ALWAYS JSON_HEALTH_CHECKED_COUNT JSON_HEALTH_INVALID_COUNT JSON_HEALTH_MISSING_COUNT
}

# 最終檔案計數核驗: 本次備份的檔案逐一確認存在 (本地 [[ -f ]] / 遠端流式下載驗證), 顯示數量

# 遠端 app_details JSON 完整性判斷。
# 用於 WebDAV/SMB 遠端健康檢查與快取防線：必須是完整 JSON object，且至少含 PackageName + apk_version。
_remote_appdetails_json_ok() {
	local _f="$1"
	[[ -s $_f ]] || return 1
	jq -e 'type=="object" and ([.[] | objects | select(.PackageName != null and .apk_version != null)] | length > 0)' "$_f" >/dev/null 2>&1
}

verify_backup_manifest() {
	[[ ! -s $TMPDIR/.backup_manifest ]] && return
	local _mf="$TMPDIR/.backup_manifest" _ext _expect _found=0 _miss=""
	case $Compression_method in
	zstd|Zstd|ZSTD) _ext=".tar.zst" ;;
	*) _ext=".tar" ;;
	esac
	_expect="$(grep -vc '^$' "$_mf")"
	echoRgb "—————— 最終檔案計數核驗 ——————" "3"
	local _remote_chk=0
	if [[ $remote_stream = 1 ]]; then
		_remote_chk=1
	fi
	if [[ $_remote_chk = 1 ]]; then
		# 遠端核驗: 重抓一次遠端列表 (單連線), 逐項比對存在性
		echoRgb "核驗遠端檔案 (單次列表)..." "3"
		local _vlist="$TMPDIR/.verify_files"
		remote_list_files "$(get_backup_dirname)" > "$_vlist" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		local _rel _head
		while read -r _rel; do
			[[ -z $_rel ]] && continue
			if ! awk -v a="$_rel$_ext" -v b="$_rel.tar" '$0==a||$0==b{f=1;exit} END{exit !f}' "$_vlist" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
				# 列表沒找到: 單檔下載開頭再確認一次 (smbclient 列表對中文名轉碼毀名, 避免誤報)
				_head="$(_stream_download "$(get_backup_dirname)/$_rel$_ext" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | head -c 60)"
				case $_head in
				""|*NT_STATUS*) _miss="$_miss$_rel$_ext\n" ;;
				esac
			fi
		done <<EOF3
$(cat "$_mf")
EOF3
		_miss="$(echo -e "$_miss" | grep -v '^$')"
		rm -f "$_vlist"
	else
		# 本地核驗
		local _rel
		while read -r _rel; do
			[[ -z $_rel ]] && continue
			if [[ ! -f $Backup/$_rel.tar.zst && ! -f $Backup/$_rel.tar ]]; then
				_miss="$_miss$_rel$_ext\n"
			fi
		done <<EOF3
$(cat "$_mf")
EOF3
		_miss="$(echo -e "$_miss" | grep -v '^$')"
	fi
	local _misscnt
	_misscnt="$(echo "$_miss" | grep -vc '^$')"
	_found=$((_expect - _misscnt))
	if [[ $_misscnt -eq 0 ]]; then
		echoRgb "✅ 應有 $_expect 個檔案, 實際存在 $_expect 個" "1"
	else
		echoRgb "⚠️ 應有 $_expect 個檔案, 實際存在 $_found 個, 缺失 $_misscnt 個:" "0"
		echo "$_miss" | while read -r _m; do [[ -n $_m ]] && echoRgb "$_m" "0"; done
	fi
	rm -f "$_mf"
}

tar_compress_glob() {
	local out_base="$1" cd_to="$2" pattern="$3"
	# 第4參數可選: 覆寫本次使用的壓縮方式 (不傳則用全域 Compression_method)
	# 讓呼叫端可以針對單次打包指定方式, 不需要暫時修改全域變數再復原
	local _comp="${4:-$Compression_method}"
	# 流式模式
	if stream_enabled && [[ -n $_STREAM_DEST ]]; then
		{
			echoRgb "流式傳輸中 (邊壓邊傳, 不佔本機)..." "3" >/dev/tty 2>/dev/null ||
				_speed_debug_log "STREAM_TRANSFER_NOTICE out_base=$out_base comp=$_comp dest=$_STREAM_DEST"
		}
		local _rb="$_STREAM_DEST/${out_base##*/}"
		[[ ! -d ${out_base%/*} ]] && mkdir -p "${out_base%/*}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		(
			cd "$cd_to" || return 1
			case $_comp in
			tar|Tar|TAR)
				tar --checkpoint-action="ttyout=%T\r" -cf - $pattern | _stream_upload "$_rb.tar"
				;;
			zstd|Zstd|ZSTD)
				tar --checkpoint-action="ttyout=%T\r" -cf - $pattern | \
					zstd --ultra -3 -T0 -q --priority=rt | _stream_upload "$_rb.tar.zst"
				;;
			esac
		)
		result=$?
		if [[ $result != 0 ]]; then
			echoRgb "流式上傳失敗 ($_rb) 遠端可能未寫入完整, 建議重試" "0" >&2
			echo "${_rb%%/*}" >> "$TMPDIR/.stream_failed"
			echo "${_rb%%/*}: ${_rb#*/}" >> "$TMPDIR/.stream_failed_detail"
			_speed_debug_log "STREAM_PAYLOAD_FAILED app=${_rb%%/*} item=${_rb#*/} pipeline_rc=$result"
		else
			_manifest_add "$_rb"
		fi
		return $result
	fi
	local _raw_log _raw_start _out_file _out_size
	_raw_start="$(date +%s%3N 2>/dev/null)"; case $_raw_start in ''|*[!0-9]*) _raw_start="$(date +%s 2>/dev/null)000" ;; esac
	_raw_log="$(_local_raw_debug_begin compress "mode=glob comp=$_comp out_base=$out_base cd_to=$cd_to pattern=$pattern")"
	(
		cd "$cd_to" || return 1
		case $_comp in
		tar|Tar|TAR)
			tar --checkpoint-action="ttyout=%T\r" -cf "$out_base.tar" $pattern 2>>"$_raw_log"
			;;
		zstd|Zstd|ZSTD)
			( set -o pipefail 2>/dev/null; tar --checkpoint-action="ttyout=%T\r" -cf - $pattern 2>>"$_raw_log" | \
				zstd --ultra -3 -T0 -q --priority=rt 2>>"$_raw_log" > "$out_base.tar.zst" )
			;;
		esac
	)
	result=$?
	_chmod_compressed_output "$out_base" "$_comp"
	case $_comp in tar|Tar|TAR) _out_file="$out_base.tar" ;; *) _out_file="$out_base.tar.zst" ;; esac
	_out_size="$(_local_file_size_debug "$_out_file")"
	_local_raw_debug_end compress "$_raw_log" "$result" "$_raw_start" "out_file=$_out_file out_size=$_out_size"
	[[ $result = 0 ]] && _manifest_add "${out_base#$Backup/}"
	return $result
}

rgb_a="${rgb_a:=220}"
abi="$(getprop ro.product.cpu.abi)"
sdk="$(getprop ro.build.version.sdk)"
release="$(getprop ro.build.version.release)"
case $abi in
arm64*)
	if [[ $sdk -lt 24 ]]; then
		echoRgb "設備Android ${release}版本過低 請升級至Android 8+" "0"
		exit 1
	else
		case $sdk in
		26|27|28)
			echoRgb "設備Android ${release}版本偏低，無法確定腳本能正確的使用" "0"
			;;
		esac
	fi
	;;
*)
	echoRgb "未知的架構: $abi" "0"
	exit 1
	;;
esac
get_mv="$(which mv)"
PATH="/system/bin:/system/xbin:/data/adb/ksu/bin:/sbin/.magisk/busybox:/sbin/.magisk:/sbin:/system_ext/bin:/vendor/bin:/vendor/xbin:/data/data/com.omarea.vtools/files/toolkit:/data/user/0/com.termux/files/usr/bin"
# 先查 magisk 二進制是否存在, 避免直接呼叫導致 libc 雜訊 (小米系統 vendor 屬性權限警告)
if command -v magisk >/dev/null 2>&1; then
	_magisk_path="$(magisk --path 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	if [[ -d $_magisk_path ]]; then
		PATH="$_magisk_path/.magisk/busybox:$PATH"
	fi
elif ! command -v ksud >/dev/null 2>&1; then
	echo "Magisk busybox Path does not exist"
fi
export PATH="$PATH"
filepath="/data/backup_tools"
busybox="$filepath/busybox"
busybox2="$tools_path/busybox"
#排除自身
exclude="
update
soc.json
classes.dex
Device_List"
if [[ ! -d $filepath ]]; then
	mkdir -p "$filepath"
	[[ $? = 0 ]] && echoRgb "設置busybox環境中"
fi
#刪除無效軟連結
find -L "$filepath" -maxdepth 1 -type l -exec rm -rf {} \;
if [[ -f $busybox && -f $busybox2 ]]; then
	filesha256="$(sha256sum "$busybox" | cut -d" " -f1)"
	filesha256_1="$(sha256sum "$busybox2" | cut -d" " -f1)"
	if [[ $filesha256 != $filesha256_1 ]]; then
		echoRgb "busybox sha256不一致 重新創立環境中"
		rm -rf "$filepath"/*
	fi
fi
find "$tools_path" -maxdepth 1 ! -path "$tools_path/tools.sh" -type f | grep -Ev "$(echo $exclude | sed 's/ /\|/g')" | while read -r; do
	File_name="${REPLY##*/}"
	# 發行目錄若殘留 tools.sh.bak / tools_v*.sh / *.orig / *.tmp，不應安裝到 /data/backup_tools，也不納入啟動工具環境。
	case "$File_name" in
	tools.sh.bak|tools.sh.bak_*|tools_v*.sh|*.bak|*.bak_*|*.orig|*.tmp|.*.tmp|SHA256SUMS*)
		_speed_debug_log "TOOLS_INSTALL_SKIP_RELEASE_ARTIFACT file=$File_name"
		continue
		;;
	esac
	if [[ ! -f $filepath/$File_name ]]; then
		cp -r "$REPLY" "$filepath"
		chmod 0755 "$filepath/$File_name"
		echoRgb "$File_name > $filepath/$File_name"
	else
		filesha256="$(sha256sum "$filepath/$File_name" | cut -d" " -f1)"
		filesha256_1="$(sha256sum "$tools_path/$File_name" | cut -d" " -f1)"
		if [[ $filesha256 != $filesha256_1 ]]; then
			echoRgb "$File_name sha256不一致 重新創建"
			cp -r "$REPLY" "$filepath"
			chmod 0755 "$filepath/$File_name"
			echoRgb "$File_name > $filepath/$File_name"
		fi
	fi
done
if [[ -f $busybox ]]; then
	"$busybox" --list | while read -r; do
		if [[ $REPLY != tar && $REPLY != bc && ! -f $filepath/$REPLY ]]; then
			ln -fs "$busybox" "$filepath/$REPLY"
		fi
	done
fi
[[ ! -f $filepath/zstd ]] && echoRgb "$filepath缺少zstd" && exit 2
export PATH="$filepath:$PATH"
export TZ=Asia/Taipei

# ===== Native event tools（內部自動偵測，不新增 conf 開關）=====
_event_resolve_bin() {
	local _name="$1" _cmd="" _fallback=""
	[[ -n $_name ]] || return 1
	_cmd="$(command -v "$_name" 2>/dev/null)"
	if [[ -n $_cmd && -x $_cmd ]]; then
		printf '%s\n' "$_cmd"
		return 0
	fi
	_fallback="$filepath/$_name"
	if [[ -x $_fallback ]]; then
		printf '%s\n' "$_fallback"
		return 0
	fi
	printf '%s\n' "$_name"
	return 1
}
EVENT_FILEWATCH_BIN="$(_event_resolve_bin filewatch)"
EVENT_PROCWAIT_BIN="$(_event_resolve_bin procwait)"
EVENT_UNIXSOCK_BIN="$(_event_resolve_bin unixsock)"
EVENT_NETWATCH_BIN="$(_event_resolve_bin netwatch)"

_event_filewatch_once() {
	local _path="$1" _timeout="${2:-5}" _tag="${3:-filewatch}" _diag="${4:-}" _fw_pid="" _guard_pid="" _rc=125
	[[ -x ${EVENT_FILEWATCH_BIN:-} && -n $_path ]] || return 125
	case $_timeout in ''|*[!0-9]*) _timeout=5 ;; esac
	if command -v timeout >/dev/null 2>&1; then
		timeout "$_timeout" "$EVENT_FILEWATCH_BIN" --once "$_path" >/dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_rc=$?
	else
		"$EVENT_FILEWATCH_BIN" --once "$_path" >/dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} &
		_fw_pid=$!
		( trap - EXIT; sleep "$_timeout"; kill "$_fw_pid" 2>/dev/null ) &
		_guard_pid=$!
		wait "$_fw_pid" 2>/dev/null
		_rc=$?
		kill "$_guard_pid" 2>/dev/null
		wait "$_guard_pid" 2>/dev/null
	fi
	_speed_debug_log "FILEWATCH_ONCE tag=$_tag path=$_path timeout=$_timeout rc=$_rc"
	[[ -n $_diag ]] && echo "$(date '+%H:%M:%S') filewatch_once tag=$_tag path=$_path timeout=$_timeout rc=$_rc" >> "$_diag" 2>/dev/null
	return $_rc
}

# 等待指定 PID 清單，避免 wait 參數為空時退化成 bare wait、誤等長駐 daemon。
_event_wait_pid_list() {
	local _list="$1" _tag="${2:-pid_list}" _pid _rc=0 _one_rc=0 _count=0
	[[ -z $_list ]] && { _speed_debug_log "WAIT_PID_LIST_EMPTY tag=$_tag"; return 0; }
	for _pid in $_list; do
		[[ -z $_pid ]] && continue
		let _count++
		wait "$_pid" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_one_rc=$?
		[[ $_one_rc = 0 ]] || _rc=$_one_rc
	done
	_speed_debug_log "WAIT_PID_LIST_DONE tag=$_tag count=$_count rc=$_rc"
	return $_rc
}

_event_wait_pid_exit_procwait() {
	local _pid="$1" _timeout="${2:-1}" _tag="${3:-pid_exit}" _rc _state
	[[ -x ${EVENT_PROCWAIT_BIN:-} ]] || return 125
	command -v timeout >/dev/null 2>&1 || return 125
	case $_pid in ''|*[!0-9]*) return 125 ;; esac
	case $_timeout in ''|*[!0-9]*) _timeout=1 ;; esac
	timeout "$_timeout" "$EVENT_PROCWAIT_BIN" pid "$_pid" >/dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_rc=$?
	case $_rc in
	0)
		_speed_debug_log "PROCWAIT_EXIT tag=$_tag pid=$_pid timeout=$_timeout rc=$_rc"
		return 0
		;;
	3)
		_speed_debug_log "PROCWAIT_FALLBACK tag=$_tag pid=$_pid rc=$_rc reason=pidfd_unsupported"
		return 125
		;;
	124|137|143)
		_speed_debug_log "PROCWAIT_EXIT_TIMEOUT tag=$_tag pid=$_pid timeout=$_timeout rc=$_rc"
		return 124
		;;
	*)
		_state="$(awk '/^State:/{print $2; exit}' /proc/"$_pid"/status 2>/dev/null)"
		if ! kill -0 "$_pid" 2>/dev/null || [[ $_state = Z ]]; then
			_speed_debug_log "PROCWAIT_EXIT tag=$_tag pid=$_pid rc=$_rc state=${_state:-gone}"
			return 0
		fi
		_speed_debug_log "PROCWAIT_FALLBACK tag=$_tag pid=$_pid rc=$_rc state=$_state"
		return 125
		;;
	esac
}

_event_terminate_pid() {
	local _pid="$1" _tag="${2:-terminate}" _i=0
	case $_pid in ''|*[!0-9]*) return 1 ;; esac
	kill -0 "$_pid" 2>/dev/null || return 0
	kill "$_pid" 2>/dev/null
	if _event_wait_pid_exit_procwait "$_pid" 1 "$_tag.term"; then
		return 0
	fi
	while [[ $_i -lt 10 ]] && kill -0 "$_pid" 2>/dev/null; do
		sleep 0.1
		_i=$((_i + 1))
	done
	if kill -0 "$_pid" 2>/dev/null; then
		kill -KILL "$_pid" 2>/dev/null
		_event_wait_pid_exit_procwait "$_pid" 1 "$_tag.kill" >/dev/null 2>&1 || true
	fi
	return 0
}

# 只在遠端目標為私有 IPv4 且路由走可信 LAN 介面時啟用。
# 監看器不輪詢、不持有 WakeLock；只在 NETLINK_ROUTE 事件發生時重新檢查到遠端的路由。
_remote_private_ipv4() {
	case "$1" in
	10.*|192.168.*) return 0 ;;
	172.*)
		local _o2="${1#172.}"; _o2="${_o2%%.*}"
		case $_o2 in ''|*[!0-9]*) return 1 ;; esac
		[[ $_o2 -ge 16 && $_o2 -le 31 ]]
		return
		;;
	esac
	return 1
}

_remote_lan_iface_ok() {
	local _if="$1"
	case "$_if" in
	''|lo|rmnet*|r_rmnet*|ccmni*|pdp*|wwan*|cell*|tun*|tap*|wg*|wireguard*|tailscale*|zt*|clat*|v4-*|dummy*|ifb*|ip6tnl*|sit*|gre*|gretap*|wifi-aware*|aware*|p2p*) return 1 ;;
	wlan*|wifi*|mlan*|eth*|en*|ap*|swlan*|softap*|rndis*|usb*|bnep*|bt-pan*|br*|bond*) return 0 ;;
	esac
	[[ -d /sys/class/net/"$_if"/wireless ]]
}

_remote_route_key() {
	local _host="$1"
	ip route get "$_host" 2>/dev/null | awk '{
		dev=""; src="";
		for (i=1; i<=NF; i++) {
			if ($i=="dev" && i<NF) dev=$(i+1)
			if ($i=="src" && i<NF) src=$(i+1)
		}
		if (dev!="" && src!="") { print dev "|" src; exit }
	}'
}

REMOTE_NETWATCH_BIN_PID=""
REMOTE_NETWATCH_READER_PID=""
REMOTE_NETWATCH_FIFO=""
REMOTE_NETWATCH_FLAG=""
REMOTE_NETWATCH_KEY=""
REMOTE_NETWATCH_HOST=""
REMOTE_NETWATCH_REPORTED=0

_remote_netwatch_start() {
	_remote_netwatch_stop
	REMOTE_NETWATCH_REPORTED=0
	[[ -x ${EVENT_NETWATCH_BIN:-} ]] || { _speed_debug_log "REMOTE_NETWATCH_SKIP reason=missing"; return 0; }
	[[ -n ${REMOTE_HOST:-} ]] || { _speed_debug_log "REMOTE_NETWATCH_SKIP reason=no_host"; return 0; }
	_remote_private_ipv4 "$REMOTE_HOST" || { _speed_debug_log "REMOTE_NETWATCH_SKIP reason=non_private_ipv4 host=$REMOTE_HOST"; return 0; }

	local _key _iface _fifo _flag _log
	_key="$(_remote_route_key "$REMOTE_HOST")"
	[[ -n $_key ]] || { _speed_debug_log "REMOTE_NETWATCH_SKIP reason=no_route host=$REMOTE_HOST"; return 0; }
	_iface="${_key%%|*}"
	_remote_lan_iface_ok "$_iface" || { _speed_debug_log "REMOTE_NETWATCH_SKIP reason=untrusted_iface iface=$_iface key=$_key"; return 0; }

	_fifo="$TMPDIR/.remote_netwatch_fifo_$$"
	_flag="$TMPDIR/.remote_netwatch_event_$$"
	_log="$(_speed_debug_log_path remote_netwatch.log)"
	rm -f "$_fifo" "$_flag" 2>/dev/null
	mkfifo "$_fifo" 2>/dev/null || { _speed_debug_log "REMOTE_NETWATCH_SKIP reason=mkfifo_failed fifo=$_fifo"; return 0; }

	"$EVENT_NETWATCH_BIN" >"$_fifo" 2>>"$_log" &
	REMOTE_NETWATCH_BIN_PID=$!
	(
		# 背景 reader 是內部 worker，不得執行主腳本 EXIT trap。
		trap - EXIT
		while IFS= read -r _event; do
			_event_if=""
			_new_key=""
			case "$_event" in
			LINK_NEW*|LINK_DEL*|ADDR_NEW*|ADDR_DEL*) ;;
			*) continue ;;
			esac
			_event_if="${_event#*ifname=}"
			_event_if="${_event_if%% *}"
			[[ $_event_if = "$_iface" ]] || continue
			_new_key="$(_remote_route_key "$REMOTE_HOST")"
			if [[ $_new_key != "$_key" ]]; then
				{
					echo "time=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
					echo "host=$REMOTE_HOST"
					echo "before=$_key"
					echo "after=$_new_key"
					echo "event=$_event"
				} > "$_flag" 2>/dev/null
				break
			fi
		done < "$_fifo"
	) &
	REMOTE_NETWATCH_READER_PID=$!
	REMOTE_NETWATCH_FIFO="$_fifo"
	REMOTE_NETWATCH_FLAG="$_flag"
	REMOTE_NETWATCH_KEY="$_key"
	REMOTE_NETWATCH_HOST="$REMOTE_HOST"
	_speed_debug_log "REMOTE_NETWATCH_START host=$REMOTE_HOST key=$_key bin_pid=$REMOTE_NETWATCH_BIN_PID reader_pid=$REMOTE_NETWATCH_READER_PID"
}

_remote_netwatch_report() {
	[[ -n ${REMOTE_NETWATCH_FLAG:-} && -s ${REMOTE_NETWATCH_FLAG:-} ]] || return 0
	if [[ ${REMOTE_NETWATCH_REPORTED:-0} != 1 ]]; then
		REMOTE_NETWATCH_REPORTED=1
		echoRgb "遠端操作期間偵測到 LAN 路由／位址變更；本次傳輸結果請以協議返回值與校驗為準" "0"
		_speed_debug_append_cat "$(_speed_debug_log_path remote_netwatch.log)" "$REMOTE_NETWATCH_FLAG" "===== REMOTE LAN CHANGE ====="
	fi
	return 0
}

_remote_netwatch_stop() {
	local _pid
	for _pid in "${REMOTE_NETWATCH_READER_PID:-}" "${REMOTE_NETWATCH_BIN_PID:-}"; do
		case "$_pid" in ''|*[!0-9]*) continue ;; esac
		kill "$_pid" 2>/dev/null
	done
	for _pid in "${REMOTE_NETWATCH_READER_PID:-}" "${REMOTE_NETWATCH_BIN_PID:-}"; do
		case "$_pid" in ''|*[!0-9]*) continue ;; esac
		wait "$_pid" 2>/dev/null
	done
	[[ -n ${REMOTE_NETWATCH_FIFO:-} ]] && rm -f "$REMOTE_NETWATCH_FIFO" 2>/dev/null
	REMOTE_NETWATCH_BIN_PID=""
	REMOTE_NETWATCH_READER_PID=""
	REMOTE_NETWATCH_FIFO=""
}

ln -fs "$tools_path/classes.dex" "$filepath/classes.dex"
export CLASSPATH="$filepath/classes.dex"
# ===== dex app_process 統一入口 =====
# 所有 Java/Dex 類呼叫統一經由這幾個 helper。
# 一般一次性呼叫用 _dex / _dex_raw；需要保留原始 stdout 或背景 daemon 時用 _dex_exec_unfiltered。
DEX_APP_PROCESS_BIN="${DEX_APP_PROCESS_BIN:-app_process}"
DEX_APP_PROCESS_BASE="${DEX_APP_PROCESS_BASE:-/system/bin}"

_dex_classes_path() {
	if [[ -f ${filepath:-}/classes.dex ]]; then
		printf '%s\n' "$filepath/classes.dex"
	elif [[ -f ${tools_path:-}/classes.dex ]]; then
		printf '%s\n' "$tools_path/classes.dex"
	elif [[ -n ${CLASSPATH:-} ]]; then
		printf '%s\n' "$CLASSPATH"
	else
		printf '%s\n' "/data/backup_tools/classes.dex"
	fi
}

_dex_export_classpath() {
	local _cp
	_cp="$(_dex_classes_path)"
	[[ -n $_cp ]] && export CLASSPATH="$_cp"
}

_dex_app_process_abs() {
	local _ap
	_ap="$(command -v "$DEX_APP_PROCESS_BIN" 2>/dev/null)"
	[[ -n $_ap ]] && { printf '%s\n' "$_ap"; return 0; }
	printf '%s\n' "/system/bin/app_process"
}


# 393: 低記憶體/ROM 背景清理下，daemon 或主 shell 可能被 LMK/SIGKILL。
# root 可寫時降低 oom_score_adj；失敗只記 log，不阻塞流程。
_speedbackup_protect_pid() {
	local _pid="$1" _tag="${2:-process}"
	case $_pid in ''|*[!0-9]*) return 1 ;; esac
	kill -0 "$_pid" 2>/dev/null || return 1
	if [[ -w "/proc/$_pid/oom_score_adj" ]]; then
		echo -900 > "/proc/$_pid/oom_score_adj" 2>/dev/null && _speed_debug_log "OOM_PROTECT tag=$_tag pid=$_pid score=-900"
	fi
	renice -n -5 -p "$_pid" >/dev/null 2>&1 || true
	return 0
}

_daemon_retry_sleep() {
	local _try="$1" _tag="${2:-daemon}" _sleep="0.3"
	case $_try in
	0) _sleep="0.3" ;;
	1) _sleep="0.8" ;;
	*) _sleep="1.5" ;;
	esac
	_speed_debug_log "DAEMON_RETRY_SLEEP tag=$_tag try=$_try sleep=$_sleep"
	sleep "$_sleep" 2>/dev/null || sleep 1
}


# 394: 可選 Dex 外部 watchdog。它不取代 tools 端 retry，只在 daemon 被 SIGKILL 後、owner tools.sh 仍活著時
# 嘗試重啟 root-side daemon，降低下一次 relay 遇到 stale socket 的概率。
_DEX_WATCHDOG_DIR="${_DEX_WATCHDOG_DIR:-$TMPDIR/.speedbackup_dex_watchdog}"
_dex_watchdog_stop() {
	local _tag="$1" _pidfile _pid
	[[ -n $_tag ]] || return 0
	_pidfile="$_DEX_WATCHDOG_DIR/${_tag}.pid"
	_pid="$(cat "$_pidfile" 2>/dev/null)"
	case $_pid in ''|*[!0-9]*) _pid="" ;; esac
	[[ -n $_pid ]] && kill "$_pid" 2>/dev/null || true
	rm -f "$_pidfile" 2>/dev/null
}

_dex_watchdog_start() {
	local _tag="$1" _pid_file="$2" _socket="$3" _class="$4" _cmd="$5" _arg1="$6" _idle="$7" _owner="$8"
	local _wd_pid_file _wd_pid _wd_out _wd_err _app_process
	[[ -n $_tag && -n $_pid_file && -n $_class && -n $_cmd ]] || return 0
	[[ ${SPEEDBACKUP_MAIN_PID:-} = *[!0-9]* || -z ${SPEEDBACKUP_MAIN_PID:-} ]] && return 0
	mkdir -p "$_DEX_WATCHDOG_DIR" 2>/dev/null || return 0
	_wd_pid_file="$_DEX_WATCHDOG_DIR/${_tag}.pid"
	_wd_pid="$(cat "$_wd_pid_file" 2>/dev/null)"
	case $_wd_pid in ''|*[!0-9]*) _wd_pid="" ;; esac
	if [[ -n $_wd_pid ]] && kill -0 "$_wd_pid" 2>/dev/null; then
		return 0
	fi
	_socket="${_socket:--}"
	_idle="${_idle:-1800}"
	_owner="${_owner:-$SPEEDBACKUP_MAIN_PID}"
	_wd_out="$_DEX_WATCHDOG_DIR/${_tag}.out"
	_wd_err="$_DEX_WATCHDOG_DIR/${_tag}.err"
	_app_process="$(_dex_app_process_abs)"
	_dex_export_classpath
	case $_cmd in
	daemonunix)
		nohup "$_app_process" "$DEX_APP_PROCESS_BASE" com.xayah.dex.DaemonSupervisorUtil supervise "$_tag" "$_pid_file" "$_socket" "$_owner" 1500 -- "$_app_process" "$DEX_APP_PROCESS_BASE" "$_class" daemonunix "$_arg1" "$_idle" "$_owner" > "$_wd_out" 2>>"$_wd_err" &
		;;
	daemon)
		nohup "$_app_process" "$DEX_APP_PROCESS_BASE" com.xayah.dex.DaemonSupervisorUtil supervise "$_tag" "$_pid_file" - "$_owner" 1500 -- "$_app_process" "$DEX_APP_PROCESS_BASE" "$_class" daemon "$_arg1" "$_idle" "$_owner" > "$_wd_out" 2>>"$_wd_err" &
		;;
	*) return 0 ;;
	esac
	_wd_pid=$!
	disown "$_wd_pid" 2>/dev/null
	printf '%s\n' "$_wd_pid" > "$_wd_pid_file" 2>/dev/null
	_speedbackup_protect_pid "$_wd_pid" "${_tag}_watchdog"
	_speed_debug_log "DEX_WATCHDOG_START tag=$_tag pid=$_wd_pid class=$_class cmd=$_cmd socket=$_socket"
	return 0
}

_speedbackup_protect_pid "$SPEEDBACKUP_MAIN_PID" main_shell

_dex_exec_unfiltered() {
	_dex_export_classpath
	if [[ "$1" = "/system/bin" || "$1" = "${DEX_APP_PROCESS_BASE:-/system/bin}" ]]; then
		shift
	fi
	command "$DEX_APP_PROCESS_BIN" "$DEX_APP_PROCESS_BASE" "$@"
}

dex_hiddenapi_raw() {
	case "$1" in
	getPackageUid|getInstallSourceInfo)
		# 熱路徑必須走 HiddenApi daemon；daemon/relay 不可用時直接失敗，不再回退單次 app_process。
		_hiddenapi_daemon_call_args "$@"
		local _rc=$?
		if [[ $_rc = 125 ]]; then
			_speed_debug_log "HIDDENAPI_DAEMON_REQUIRED_NO_SPAWN command=$1"
			return 125
		fi
		return $_rc
		;;
	esac
	_dex_raw com.xayah.dex.HiddenApiUtil "$@"
}

dex_hiddenapi() {
	case "$1" in
	getPackageUid|getInstallSourceInfo)
		local _dex_out _dex_rc _dex_ctx
		_dex_ctx="$(_dex_context_from_args com.xayah.dex.HiddenApiUtil "$@")"
		_dex_out="${TMPDIR:-/data/local/tmp}/.dex_stdout_${$}_$RANDOM"
		dex_hiddenapi_raw "$@" > "$_dex_out"
		_dex_rc=$?
		_dex_translate_file "$_dex_out" "$_dex_ctx"
		_dex_filter_human_stdout < "$_dex_out"
		rm -f "$_dex_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return $_dex_rc
		;;
	esac
	_dex com.xayah.dex.HiddenApiUtil "$@"
}

dex_webdav_raw() {
	_dex_exec_unfiltered com.xayah.dex.WebDavUtil "$@"
}

dex_smbscan_raw() {
	_dex_exec_unfiltered com.xayah.dex.SmbScanUtil "$@"
}

dex_notify_raw() {
	_dex_raw com.xayah.dex.NotificationUtil "$@"
}

quit=0
while read -r file expected_hash; do
	if [[ -f $tools_path/$file ]]; then
		computed_hash="$(sha256sum "$tools_path/$file" | awk '{print $1}')"
		if [[ $computed_hash = $expected_hash ]]; then
			echoRgb "✅ $file: 驗證通過"
		else
			# 遠端可選工具在純本機模式不刷提示；只有對應遠端啟用時才顯示。
			case $file in
			smbclient)
				if [[ $remote_type = smb ]]; then
					echoRgb "⚠️ $tools_path/$file: SHA-256 不一致，僅影響 SMB 遠端備份
 -\"$computed_hash\"" "0"
				else
					_speed_debug_log "OPTIONAL_REMOTE_TOOL_HASH_MISMATCH file=$file remote_type=${remote_type:-none}"
				fi
				;;
			classes.dex)
				echoRgb "⚠️ classes.dex SHA-256 與內建值不同，允許繼續；本版以 dex --version 作為有效性驗證" "3"
				;;
			*)
				echoRgb "❌ $tools_path/$file: SHA-256 不一致
 -\"$computed_hash\""
				quit=2; break ;;
			esac
		fi
	else
		# smbclient 是遠端可選工具；純本機模式不顯示遠端相關提示。
		case $file in
		smbclient)
			if [[ $remote_type = smb ]]; then
				echoRgb "⚠️ 檔案 $tools_path/$file 不存在 (僅影響 SMB 遠端備份)" "0"
			else
				_speed_debug_log "OPTIONAL_REMOTE_TOOL_MISSING file=$file remote_type=${remote_type:-none}"
			fi
			;;
		*)
			echoRgb "⚠️ 檔案 $tools_path/$file 不存在"
			quit=1
			break
			;;
		esac
	fi
done <<EOF
busybox 4d60ab3f5a59ebb2ca863f2f514e6924401b581e9b64f602665c008177626651
classes.dex b17fcad3838024075bf930485cb3f451b75354dafefc1101698c802691bf6479
cmd 08da8ac23b6e99788fd3ce6c19c7b5a083b2ad48be35963a48d01d6ee7f3bb6d
dex_check.sh 007a71744094e68920d44554a2de9ce2d1fc7fee5330645d73bd3d3859d54d9d
filewatch 3489418b8805d3cce7c5193f503d1304632cd9ae5274de28280a2b4040441e97
find 7fa812e58aafa29679cf8b50fc617ecf9fec2cfb2e06ea491e0a2d6bf79b903b
jq 6bc62f25981328edd3cfcfe6fe51b073f2d7e7710d7ef7fcdac28d4e384fc3d4
keycheck 50645ee0e0d2a7d64fb4a1286446df7a4445f3d11aefd49eeeb88515b314c363
procwait 853ab29efa4cf4b6faab88724ef416d6b23a61fd24d94e7e2f67861289eb5021
smbclient 1866c6199998dbccfa7e7a3727e51f274cafaa8cd18752d345c62e38f28031e8
tar 882639ac310a7eb4052c68c21cea02633307700f9cc8c7c469c2dd18d734a112
uidexec d9464bee4d1fa732e926d59e75995b28240899d5c588e31c9bc4f61dc5d52469
unixsock 8578bd6e9f6f48cc9b420b67e263904d71eceac85c71cccde7e86a12e15d60b6
zstd 9ef4b54148699c9874cfd45aaf38e5cc950e5d168afdcf2edf58a2463f5561ed
EOF

# v24.20.14-7.66-199：工具 SHA 驗證資訊允許短暫顯示；全部完成後只清屏一次。
# 後續設備資訊、使用者狀態、後台應用提示與主選單照常顯示，不再被主選單前清掉。
clear 2>/dev/null

# dex 啟動期版本驗證延後：選單前不再啟動 app_process/JVM，只保留 classes.dex 存在性檢查。
# 完整 HiddenApiUtil --version 仍會在實際功能使用 / speed_debug final tools_version.log 階段取得。
if [[ ! -f $tools_path/classes.dex ]]; then
	echoRgb "⚠️ 檔案 $tools_path/classes.dex 不存在" "0"
	quit=1
else
	_speed_debug_log "DEX_PRECHECK_DEFERRED stage=startup reason=no_startup_jvm"
fi

# log 目錄超過上限就清空 (避免長期累積佔空間)
# 上限由 conf 的 log_max_size_mb 控制 (預設 2MB, 0=關閉)
# 清理範圍:
#   - ${logfile%/*}/                                 (主腳本一般 log_yyyy-mm-dd_hh-mm.txt)
#   - $MODDIR/Backup_*/log/                        (備份模式一般 log)
#   - $MODDIR/Backup_*/*/log/                      (子目錄一般 log)
#   - ${logfile%/*}/ (恢復模式一般 log)
# 除錯類 log 已集中到 /data/speed_debug/run_xxx，不再寫入腳本 log 目錄。
cleanup_log_if_oversize() {
	# conf 沒設置 (空值) 也不清, 只有明確設正整數才啟用
	local max="$log_max_size_mb"
	[[ -z $max || $max = 0 ]] && return 0
	case $max in
	*[!0-9]*) return 0 ;;  # 非純數字直接跳過
	esac
	local max_kb=$((max * 1024))
	local d size_kb
	for d in "$MODDIR/log" "$MODDIR"/Backup_*/log "$MODDIR"/Backup_*/*/log; do
		[[ ! -d $d ]] && continue
		[[ -z $(ls -A "$d" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) ]] && continue
		size_kb=$(du -sk "$d" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{print $1}')
		if [[ ${size_kb:-0} -ge $max_kb ]]; then
			rm -rf "$d"/*
			echoRgb "log 目錄 $d 超過 ${max}MB, 已清空" "3"
		fi
	done
}

# 打印 tools 目錄內所有二進制版本到 speed_debug/tools_version.log
# 啟動時跑一次, 方便除錯時知道用戶用什麼版本工具；不寫入腳本 log 目錄。
print_tools_version() {
	local _ver_log="${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/tools_version.log" _dex_ver_line="" _evt
	# print_tools_version 只記錄已知資訊，不啟動 app_process/JVM 讀 dex --version。
	# 若本輪已有顯式查過版本，使用快取；否則只記 sha256，避免 speed_debug final 打包階段拖慢/喚醒 dex。
	_dex_ver_line="${SPEED_DEBUG_LAST_DEX_VERSION:-未查詢（print_tools_version 不啟動 dex）}"
	mkdir -p "${_ver_log%/*}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	{
		echo "===== Tools version on $(date '+%Y-%m-%d %H:%M:%S') ====="
		echo "abi=$abi sdk=$sdk release=$release"
		echo ""
		# zstd
		which zstd >/dev/null 2>&1 && {
			echo "[zstd]"
			zstd --version 2>&1 | head -2
			echo ""
		}
		# tar
		which tar >/dev/null 2>&1 && {
			echo "[tar]"
			tar --version 2>&1 | head -2
			echo ""
		}
		# busybox
		which busybox >/dev/null 2>&1 && {
			echo "[busybox]"
			busybox 2>&1 | head -1
			echo ""
		}
		# jq
		which jq >/dev/null 2>&1 && {
			echo "[jq]"
			jq --version 2>&1
			echo ""
		}
		# find
		which find >/dev/null 2>&1 && {
			echo "[find]"
			find --version 2>&1 | head -1
			echo ""
		}
		# smbclient
		which smbclient >/dev/null 2>&1 && {
			echo "[smbclient]"
			smbclient --version 2>&1 | head -1
			echo ""
		}
		# Native event tools：優先記錄 PATH 解析到的工具，若未進 PATH 則 fallback 到 tools 目錄。
		for _evt in filewatch procwait unixsock netwatch; do
			_evt_bin="$(command -v "$_evt" 2>/dev/null)"
			[[ -z $_evt_bin && -x $filepath/$_evt ]] && _evt_bin="$filepath/$_evt"
			if [[ -n $_evt_bin && -x $_evt_bin ]]; then
				echo "[$_evt]"
				"$_evt_bin" --version 2>&1 | head -1
				echo "path: $_evt_bin"
				echo "sha256: $(sha256sum "$_evt_bin" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{print $1}')"
				echo ""
			fi
		done
		unset _evt_bin
		# keycheck (沒 --version, 記 sha256)
		which keycheck >/dev/null 2>&1 && {
			echo "[keycheck]"
			echo "sha256: $(sha256sum "$(which keycheck)" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{print $1}')"
			echo ""
		}
		# classes.dex
		[[ -f $tools_path/classes.dex ]] && {
			echo "[classes.dex]"
			echo "sha256: $(sha256sum "$tools_path/classes.dex" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{print $1}')"
			echo ""
			echo "[HiddenApiUtil]"
			echo "${_dex_ver_line:-無法取得}"
			echo ""
		}
		# script 自己版本
		echo "[backup_script]"
		echo "backup_version=$backup_version"
	} > "$_ver_log" 2>&1
	[[ ${SPEED_DEBUG_TOOLS_VERSION_SILENT:-0} = 1 ]] || echoRgb "工具版本已寫入 speed_debug 包內: tools_version.log" "2"
}

get_dex_version_line() {
	# 只在使用者/流程明確需要顯示 dex 版本時呼叫；print_tools_version 不會再透過此函式啟動 JVM。
	# 結果寫入 SPEED_DEBUG_LAST_DEX_VERSION 供 show_dex_version / 後續 debug 使用。
	if [[ -n ${SPEED_DEBUG_LAST_DEX_VERSION:-} ]]; then
		echo "$SPEED_DEBUG_LAST_DEX_VERSION"
		return 0
	fi
	[[ ! -f $tools_path/classes.dex ]] && { SPEED_DEBUG_LAST_DEX_VERSION="未找到classes.dex"; echo "$SPEED_DEBUG_LAST_DEX_VERSION"; return 0; }
	local _dex_raw _dex_line
	_dex_raw="$(_dex_exec_unfiltered com.xayah.dex.HiddenApiUtil --version 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	# 新版 dex 直接輸出: v13.1 build=20260621
	# 單次 awk 解析 v / build 並組好輸出行 (原 2 次 awk + shell if/elif → 1 次)
	_dex_line="$(echo "$_dex_raw" | awk '{
		v=""; b="";
		for(i=1;i<=NF;i++){
			if(v=="" && $i ~ /^v[0-9]/) v=$i;
			if(b=="" && $i ~ /^build=/){ b=$i; sub(/^build=/,"",b) }
		}
		if(v!="" && b!="") print v" build="b;
		else if(v!="") print v;
		else print "無法取得";
	}')"
	SPEED_DEBUG_LAST_DEX_VERSION="$_dex_line"
	echo "$SPEED_DEBUG_LAST_DEX_VERSION"
}

show_dex_version() {
	[[ ! -f $tools_path/classes.dex ]] && return 0
	local _dex_ver
	_dex_ver="${SPEED_DEBUG_LAST_DEX_VERSION:-}"
	[[ -z $_dex_ver ]] && _dex_ver="$(get_dex_version_line)"
	if [[ -n $_dex_ver && $_dex_ver != "無法取得" ]]; then
		echoRgb "dex版本: $_dex_ver" "3"
	else
		echoRgb "dex版本: 無法取得，可能 classes.dex 尚未包含 --version" "0"
	fi
}

# 通知欄獨立開關：1=開啟, 0=關閉
# v24.20.14-7.66-190：verify-noise-fix；宣告型 FGS 權限不做 runtime 硬錯，AppOps 驗證補用 scope detail。
# v24.20.14-7.66-191：debug-log-merge；speed_debug 不再產生 *_001/*_002 分片日誌，改寫入單一 aggregate log。
# v24.20.14-7.66-192：debug-semantic-decl-skip；FOREGROUND_SERVICE* 宣告型權限在 semantic debug 內標記略過 runtime 判定。
# v24.20.14-7.66-194：json-compact-fast-menu；permission_policy_v2 改成 compact/derived，tools_version 延後到打包前，縮短進入選單時間。
# v24.20.14-7.66-197：no-logo-no-startup-dex-version；以 7.66-194 為基底，只移除啟動第一屏與選單前 dex 版本/JVM 啟動。
# 主通知固定 TAG/ID，避免不同階段堆出多張 SpeedBackup 進度通知。
notification_enable="${notification_enable:-1}"
SPEEDBACKUP_NOTIFY_THROTTLE_MS="${SPEEDBACKUP_NOTIFY_THROTTLE_MS:-500}"
SPEEDBACKUP_NOTIFY_MAIN_TAG="${SPEEDBACKUP_NOTIFY_MAIN_TAG:-speedbackup_main}"
SPEEDBACKUP_NOTIFY_MAIN_ID="${SPEEDBACKUP_NOTIFY_MAIN_ID:-2020}"
SPEEDBACKUP_NOTIFY_ERROR_TAG="${SPEEDBACKUP_NOTIFY_ERROR_TAG:-speedbackup_error}"
SPEEDBACKUP_NOTIFY_ERROR_ID="${SPEEDBACKUP_NOTIFY_ERROR_ID:-2021}"
if [[ $notification_enable = 1 ]]; then
	_notification_notify_batch_send() {
		local _event="$1" _channel="$2" _tag="$3" _max="$4" _progress="$5" _indeterminate="$6" _ongoing="$7" _auto_cancel="$8" _only_alert_once="$9"
		shift 9
		local _text="$*" _tmp _pkg _android_tag _android_id _event_up _channel_lc
		[[ -z $_tag ]] && _tag="speedbackup"
		[[ -z $_event ]] && _event="INFO"
		[[ -z $_channel ]] && _channel="result"
		[[ -z $_max ]] && _max=0
		[[ -z $_progress ]] && _progress=0
		[[ -z $_indeterminate ]] && _indeterminate=0
		[[ -z $_ongoing ]] && _ongoing=0
		[[ -z $_auto_cancel ]] && _auto_cancel=1
		[[ -z $_only_alert_once ]] && _only_alert_once=1
		_event_up="$(echo "$_event" | tr '[:lower:]' '[:upper:]')"
		_channel_lc="$(echo "$_channel" | tr '[:upper:]' '[:lower:]')"
		if [[ $_event_up == *ERROR* || $_event_up == *WARN* || $_event_up == *FAIL* || $_channel_lc = error ]]; then
			_android_tag="$SPEEDBACKUP_NOTIFY_ERROR_TAG"
			_android_id="$SPEEDBACKUP_NOTIFY_ERROR_ID"
		else
			_android_tag="$SPEEDBACKUP_NOTIFY_MAIN_TAG"
			_android_id="$SPEEDBACKUP_NOTIFY_MAIN_ID"
		fi
		_pkg="${SPEEDBACKUP_NOTIFY_PACKAGE:-}"
		_tmp="${TMPDIR:-/data/local/tmp}/.speedbackup_notify_batch_$$"
		{
			printf 'EVENT|%s\n' "$_event"
			printf 'TAG|%s\n' "$_android_tag"
			printf 'ID|%s\n' "$_android_id"
			printf 'CHANNEL|%s\n' "$_channel"
			printf 'TITLE|SpeedBackup\n'
			printf 'TEXT|%s\n' "$_text"
			printf 'BIGTEXT|%s\n' "$_text"
			[[ -n $_pkg ]] && printf 'PACKAGE|%s\n' "$_pkg"
			[[ -n ${SPEED_DEBUG_MAIN_LOG:-} ]] && printf 'LOG_PATH|%s\n' "$SPEED_DEBUG_MAIN_LOG"
			[[ -n ${SPEED_DEBUG_RUN_DIR:-} ]] && printf 'DIR_PATH|%s\n' "$SPEED_DEBUG_RUN_DIR"
			printf 'INBOX|1\n'
			printf 'ERROR_AGGREGATE|1\n'
			printf 'NO_ACTIONS|1\n'
			printf 'SINGLE_MAIN|1\n'
			printf 'THROTTLE_MS|%s\n' "$SPEEDBACKUP_NOTIFY_THROTTLE_MS"
			if [[ $_max -gt 0 || $_indeterminate = 1 ]]; then
				printf 'PROGRESS|%s|%s|%s\n' "$_max" "$_progress" "$_indeterminate"
				[[ $_max -gt 0 ]] && printf 'ITEMS|%s|%s\n' "$_progress" "$_max"
			fi
			printf 'ONGOING|%s\n' "$_ongoing"
			printf 'AUTO_CANCEL|%s\n' "$_auto_cancel"
			printf 'ONLY_ALERT_ONCE|%s\n' "$_only_alert_once"
			printf 'END\n'
		} > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		local _nout _rc
		_nout="$(_webdav_tmp_path notify_daemon_out)"
		_notify_daemon_call_file notifyBatch "$_tmp" "$_nout" >/dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_rc=$?
		if [[ $_rc = 125 ]]; then
			# 通知是非核心功能；daemon 不可用時跳過通知，避免每次通知退回 app_process。
			_speed_debug_log "NOTIFY_DAEMON_REQUIRED_SKIP_NO_SPAWN tag=$_android_tag id=$_android_id event=$_event"
			_rc=0
		fi
		rm -f "$_tmp" "$_nout" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return $_rc
	}
	notification() {
		local _tag="$1"
		shift
		_notification_notify_batch_send INFO result "$_tag" 0 0 0 0 1 1 "$@"
	}
	# 主流程固定使用同一個 TAG/ID 更新主通知；dex 端負責 500ms 節流、ETA、Inbox。
	# 用法: notification_progress <tag> <max> <progress> <content>
	notification_progress() {
		local _tag="$1" _max="$2" _progress="$3" _ongoing=1 _auto_cancel=0
		shift 3
		[[ -z $_max || $_max -le 0 ]] && _max=100
		[[ -z $_progress || $_progress -lt 0 ]] && _progress=0
		[[ $_progress -gt $_max ]] && _progress="$_max"
		if [[ $_max -gt 0 && $_progress -ge $_max ]]; then
			_ongoing=0
			_auto_cancel=1
		fi
		_notification_notify_batch_send PROGRESS progress "$_tag" "$_max" "$_progress" 0 "$_ongoing" "$_auto_cancel" 1 "$@"
	}
	# 不確定總進度時使用跑馬條
	# 用法: notification_indeterminate <tag> <content>
	notification_indeterminate() {
		local _tag="$1"
		shift
		_notification_notify_batch_send PROGRESS progress "$_tag" 0 0 1 1 0 1 "$@"
	}
else
	notification() { :; }
	notification_progress() { :; }
	notification_indeterminate() { :; }
fi
if [[ $quit -ne 0 ]]; then
exit "$quit"
fi
cleanup_log_if_oversize
# tools_version.log 改為延後到 speed_debug 打包前產生，避免啟動進選單變慢。
# 啟動第一屏已移除：不再顯示 Logo / RESTORE // SYNC / sleep / clear，直接進入後續流程。
TMPDIR="/data/local/tmp"
# 安全清理 TMPDIR：只清本腳本自有暫存，避免誤刪 /data/local/tmp 其他工具檔案
cleanup_tmpdir_contents() {
	case "$TMPDIR" in
	"/data/local/tmp") ;;
	*)
		echoRgb "TMPDIR異常，拒絕清理: $TMPDIR" "0" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 1
		;;
	esac
	[[ -d $TMPDIR ]] || return 0
	local f

	# 固定名暫存檔：同時覆蓋舊版與新版命名
	for f in \
		add_apks applist_cnt applist_err apps_list apps_sorted apps_sorted_keep \
		backup_done backup_manifest batch_appstate_ndjson \
		changed_apps chk_folders chk_listed dchk_folders \
		dchk_listed decoded_listing dex_call_log dir_sizes dirs_count dirsize_work \
		dl_diff_items dl_items dns_cache getlist_allpkg getlist_apkinfo getlist_append \
		getlist_class getlist_filtered getlist_pkgset install_diag \
		installed_pkgs json_fetch json_health_hints json_health_issues json_health_remote_drops listver_changed \
		local_apps local_sorted media_custom_paths pkg_appstate appstate_snapshot_errors \
		pkg_uid pkg_ver install_method_log \
		post_json_apps precheck_list raw_wdav_listing rcollect remote_files remote_scripts \
		remote_stats_apps remote_stats_files remote_sub_listing remote_filelist_ok remote_webdav_last_list_ok \
		rfail rlist rok screen_timeout_orig sfail slist \
		smb_batch smb_groups smb_mkdir smb_scan_results sok stream_err \
		stream_failed stream_failed_detail stream_json_check_apps stream_restore_list \
		remote_stream_fatal remote_stream_fatal_notice update_apks \
		verify_files wdav_all_files wdav_out wdav_root \
		appstate_restore_issues appstate_verify_issues pkg_ver.tmp; do
		case "$f" in
		dirsize_work)
			# .dirsize_work 是目錄；中斷後可能殘留，不能用 rm -f 清。
			rm -rf "$TMPDIR/.$f" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			continue
			;;
		batch_*)
			# 批量恢復時 restore_appstate() 只把每個 app 的 canonical AppState 累積到 .batch_appstate_ndjson，
			# 迴圈結束後才由同一 daemon restore + verify。Release_data() 每解壓一包會呼叫
			# cleanup_tmpdir_contents()，因此恢復主迴圈期間絕對不能清掉 .batch_*，否則最後只剩最後一個 app。
			if [[ ${_RESTORE_PRESERVE_BATCH_QUEUE:-0} = 1 || ${_batch_appstate_mode:-0} = 1 ]]; then
				_speed_debug_log "RESTORE_BATCH_QUEUE_KEEP preserve=$TMPDIR/.$f"
				continue
			fi
			;;
		installed_pkgs|pkg_uid|pkg_ver)
			# 恢復主迴圈會多次呼叫 cleanup_tmpdir_contents()（例如 Release_data 後），
			# 這三個預掃 map 必須保留到整輪恢復結束，否則第 2 個 app 起會誤判未安裝/版本 0。
			if [[ ${_RESTORE_KEEP_SESSION_MAPS:-0} = 1 ]]; then
				_speed_debug_log "RESTORE_SESSION_MAP_KEEP preserve=$TMPDIR/.$f"
				continue
			fi
			;;
		esac
		rm -f "$TMPDIR/.$f" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	done


	# WebDAV daemon runtime (.webdav_daemon.pid/.state/.sock/.start.lock/.webdav_daemon_out)
	# 不能放進通用 cleanup glob。cleanup_tmpdir_contents() 會在備份/恢復流程中被多次呼叫；
	# 若用 webdav_daemon* 廣域刪除，會把仍在使用的 socket/state unlink，導致每次 WebDAV 操作
	# 都重新啟動一個 daemon，舊 daemon 只能等 owner/idle watchdog 才退出。runtime 只由
	# _webdav_daemon_stop() 統一清理；這裡只清每次 request 的 body/resp/status 暫存。
	# PID/mktemp 後綴：只清本腳本專屬前綴，絕不清裸 .*
	for f in \
		app_details_read_ appstate_maps_ appstate_cap_in_ appstate_cap_out_ appstate_snapshot_pkgs_ appstate_snapshot_out_ battery_raw_ compress_progress_ find_ssaid_ install_compare_ install_diag_one_ jq_ \
		merge_remote_ merged_app_details_ perm_ rel_jq_ remote_app_details_ remote_app_details_merge_ \
		remote_check_ remote_health_check_ smb_dbg_ smb_dl_ ssaid_list_ ssaid_only_ ssaid_record_ ts_ \
		update_check_ wdav_scan_ json_fetch_ verify_files_ dex_stdin_ \
		play_install_session_ play_install_session_write_stderr_ play_install_precheck_ play_install_source_ install_source_installer_ \
		dex_stderr_ dex_stdout_ dex_xargs_ zstd_test_ \
		webdav_progress_ webdav_last_status_ stream_download_err_ stream_mkcol_err_ wdav_get_err_ webdav_ad_err_ webdav_mkcol_err_ webdav_source_precheck_ \
		notify_fastskip_ smb_ls_ smb_ls_err_ smb_ls_out_ smb_size_ smb_size_err_ smb_size_out_ \
		speedbackup_notify_batch_ notify_daemon_out hiddenapi_args hiddenapi_out hiddenapi_status hiddenapi_probe_status hiddenapi_probe_body hiddenapi_force_stop_ speedbackup_hiddenapi_force_stop_ notify_status notify_probe_status notify_probe_body install_args install_out install_status install_probe_status install_probe_body \
		ssaid_expected_ ssaid_readback_ ssaid_details_list apk_scan_list \
		wdav_err_ wdav_propfind_ wdav_propfind_list_out_ wdav_propfind_size_out_ webdav_chunk_test_err_ webdav_chunk_test_in_ \
		dex_probe_ appstate_filter_ appstate_chunk_ appstate_diff_ appstate_record_ appstate_restore_ appstate_verify_ verify_appstate_chunk_ \
		hybrid_play_pm_ hybrid_play_pm_stderr_ hybrid_installer_pm_ hybrid_installer_pm_stderr_ sparse_dedupe_ play_uid_pm_probe_ play_uid_pm_probe_ok_ remote_debug_seq_ local_raw_ \
		smb_authfile_ webdav_daemon_body webdav_daemon_resp webdav_daemon_status webdav_daemon_probe_status webdav_test_err webdav_dex_err_ smb_scan_dex_out_ smb_scan_dex_err_ smb_stream_batch_ smb_stream_batch_groups_ smb_stream_batch_mkdir_ stream_infra_smb_files_ stream_infra_webdav_files_ webdav_local_batch_manifest_ webdav_local_batch_out_ webdav_local_batch_failed_ appstate_prescan_raw_ appstate_prescan_err_ appstate_prescan_requested_ appstate_prescan_returned_ appstate_probe_status appstate_probe_body appstate_status appstate_snapshot_pkgs_ appstate_snapshot_out_ remote_stats_json_bad \
		stream_err_ wdav_propfind_list_err_ wdav_propfind_size_err_ wdav_root_err_ pkg_installer_legacy_ appops_scope_ appops_scope_dex_ appops_scope_expect_ appops_scope_pkg_ appops_scope_uid_ \
		speedbackup_wifi_save_ procwait_timeout_ remote_netwatch_fifo_ remote_netwatch_event_; do
		rm -rf "$TMPDIR/.$f"* 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	done

	# 本腳本建立的暫存目錄
	rm -rf "$TMPDIR/.remote_json" "$TMPDIR/.health_check_dl" "$TMPDIR/.remote_stats_dl" "$TMPDIR/.stream_stage" \
		"$TMPDIR/.speedbackup_play_session" "$TMPDIR/.speedbackup_apk_stage" "$TMPDIR/.speedbackup_apk_work" \
		"$TMPDIR/speedbackup_notify_state" "$TMPDIR/.speedbackup_notify_state" "$TMPDIR/.speedbackup_notify_state_"* 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# 294: 恢復主迴圈中 cleanup_tmpdir_contents() 會被 Release_data 多次呼叫；若 Install daemon
	# 正在服務批量 !AppName，不能刪 AF_UNIX runtime socket，否則下一個 App 會被迫重啟 daemon。
	if type _install_daemon_probe >/dev/null 2>&1 && _install_daemon_probe; then
		_speed_debug_log "INSTALL_DAEMON_RUNTIME_KEEP cleanup=tmpdir socket=${_INSTALL_DAEMON_SOCKET:-}"
	else
		rm -rf "$TMPDIR/.speedbackup_install_daemon_u"* 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	fi
	# Play UID install daemon 工作區放在集中二進制目錄；只清本腳本專用前綴。
	# 296: 294/295 已保留 Install daemon socket/runtime，但 cleanup_tmpdir_contents() 仍會刪
	# $filepath/.speedbackup_play_session，導致批量 !AppName 每個 App 都重新 PLAY_DEX_COPY。
	# 若 Install daemon 仍可 probe，必須保留 art/classes.dex；等 daemon 不活時才清理。
	if [[ -n ${filepath:-} && -d "$filepath" ]]; then
		if type _install_daemon_probe >/dev/null 2>&1 && _install_daemon_probe; then
			_speed_debug_log "PLAY_SESSION_RUNTIME_KEEP cleanup=tmpdir path=$filepath/.speedbackup_play_session socket=${_INSTALL_DAEMON_SOCKET:-}"
		else
			rm -rf "$filepath/.speedbackup_play_session" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		fi
	fi
}
TMPDIR="/data/local/tmp"
cleanup_tmpdir_contents || exit 1
[[ ! -d $TMPDIR ]] && mkdir "$TMPDIR"
chmod 771 "$TMPDIR"
chown '2000:2000' "$TMPDIR"

# WebDAV 已全面改由 dex WebDavUtil；不再覆蓋/包裝外部 HTTP 工具，也不再依賴外部 DNS fallback。

if [[ $(which busybox) = "" ]]; then
	echoRgb "環境變量中沒有找到busybox 請在tools內添加一個\narm64可用的busybox\n或是安裝搞機助手 scene或是Magisk busybox模塊...." "0"
	exit 1
fi
if [[ $(which toybox | grep -Eo "system") != system ]]; then
	echoRgb "系統變量中沒有找到toybox" "0"
	exit 1
fi
#下列為自定義函數
# 原始資料輸出型 dex 指令不可走 _dex 翻譯包裝層。
# down 可能下載 JSON / zip 等 payload；ts 也輸出原始文字，因此走 _dex_raw，避免 grep/翻譯層污染或卡住。
down() {
	_dex_raw com.xayah.dex.HttpUtil get "$@"
}
ts() {
	case $SCRIPT_LANG in
	*CN* | *cn*) _dex_raw com.xayah.dex.CCUtil t2s "$@" ;;
	*) _dex_raw com.xayah.dex.CCUtil s2t "$@" ;;
	esac
}
alias LS="toybox ls -Zd"
alias mv="$get_mv"
# 給 trap / 流程控制用的 return 函數
# Set_back_0 永遠回 0 (成功), Set_back_1 永遠回 1 (失敗)
Set_back_0() {
	return 0
}
Set_back_1() {
	return 1
}
# 計算並輸出某段流程的耗時
# 用法: endtime <計時編號> <名稱>
# 計時編號: 1=讀 starttime1, 2=讀 starttime2 (需先在外面 set 變數)
# 輸出格式: " -<名稱>用時:X天X時X分X秒"
endtime() {
	case $1 in
	1) starttime="$starttime1" ;;
	2) starttime="$starttime2" ;;
	esac
	endtime="$(date -u "+%s")"
	duration="$(echo $((endtime - starttime)) | awk '{t=split("60 秒 60 分 24 時 999 天",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')"
	[[ $duration != "" ]] && echo " -$2用時:$duration" || echo " -$2用時:0秒"
}
# 安全百分比，避免 total=0 時除以 0
# 用法: safe_percent <current> <total>
safe_percent() {
	local cur="$1" total="$2"
	case $cur in ""|*[!0-9]*) cur=0 ;; esac
	case $total in ""|*[!0-9]*) total=0 ;; esac
	[[ $total -le 0 ]] && { echo 0; return 0; }
	[[ $cur -lt 0 ]] && cur=0
	[[ $cur -gt $total ]] && cur="$total"
	echo $((cur * 100 / total))
}

nskg=1
# 從 GitHub Release API 取得腳本最新版本號
# 透過 CDN (ghfast / cloudflare worker) 加速避免被牆
get_version() {
	# keyboard_input=1 時改用鍵盤輸入 (輸入1=$1, 0=$2), 否則維持音量鍵
	if [[ $keyboard_input = 1 ]]; then
		echoRgb "請輸入選項: 1=$1  0=$2" "2"
		unset _kv_option
		while true; do
			if [[ -n $_kv_option ]]; then
				case $_kv_option in
				1)
					[[ $Select_user = true ]] && branch="$1" || branch=true
					echoRgb "$1" "1"
					break ;;
				0)
					[[ $Select_user = true ]] && branch="$2" || branch=false
					echoRgb "$2" "0"
					break ;;
				*)
					echoRgb "$_kv_option參數錯誤 只能是0或1" "0"
					unset _kv_option ;;
				esac
			else
				read _kv_option
			fi
		done
		return
	fi
	while :; do
		keycheck
		case $? in
		42)
			[[ $Select_user = true ]] && branch="$1" || branch=true
			echoRgb "$1" "1"
			;;
		41)
			[[ $Select_user = true ]] && branch="$2" || branch=false
			echoRgb "$2" "0"
			;;
		*)
			echoRgb "keycheck錯誤" "0"
			continue
			;;
		esac
		sleep 0.3
		break
	done
}
# AppState / Permission / AppOps 顯示本地化已搬到 Dex。
# tools.sh 只保留薄 wrapper：raw 欄位仍用於恢復/驗證，cn 欄位只用於終端顯示。
_appstate_dex_localize() {
	local _type="$1" _key="$2" _in _out _val
	[[ -n $_type && -n $_key ]] || return 1
	_in="$TMPDIR/.appstate_localize_in_${$}_$RANDOM"
	_out="$TMPDIR/.appstate_localize_out_${$}_$RANDOM"
	printf '%s\t%s\n' "$_type" "$_key" > "$_in" 2>/dev/null || return 1
	if _appstate_daemon_call localize "$_in" "$_out"; then
		_val="$(awk -F'\t' 'NF>=3 {print $3; exit}' "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		rm -f "$_in" "$_out" 2>/dev/null
		[[ -n $_val ]] && { printf '%s\n' "$_val"; return 0; }
	else
		_speed_debug_log "APPSTATE_LOCALIZE_FAIL type=$_type key=$_key"
	fi
	rm -f "$_in" "$_out" 2>/dev/null
	return 1
}

_appops_localization_builtin() {
	_appstate_dex_localize lookup "$1"
}

_appops_localization_lookup_one() {
	local _key="$1" _file _val
	[[ -z $_key ]] && return 1
	for _file in "$tools_path/appops-localization.tsv" "$filepath/appops-localization.tsv"; do
		[[ -s $_file ]] || continue
		_val="$(awk -F'\t' -v k="$_key" '$1==k && $2!="" {print $2; exit}' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		[[ -n $_val ]] && { echo "$_val"; return 0; }
	done
	_appstate_dex_localize lookup "$_key"
}

_appops_localization_lookup() {
	_appops_localization_lookup_one "$1"
}

# 權限全名 → 中文名稱對照：Dex 解析；查不到回 raw。
_perm_cn() {
	_appstate_dex_localize perm "$1" || echo "$1"
}

# canonical AppState 的 mode/特殊存取顯示：Dex 解析；查不到保留 raw。
_appstate_mode_cn() {
	_appstate_dex_localize mode "$1" || echo "模式$1"
}
_appstate_bool_cn() {
	case "$1" in
	true|1) echo "是" ;;
	false|0) echo "否" ;;
	null|'') echo "未設定" ;;
	missing) echo "已移除" ;;
	*) echo "$1" ;;
	esac
}
_appstate_special_cn() {
	_appstate_dex_localize special "$1" || _perm_cn "$1"
}
_battery_cn() {
	case "$1" in
	RUN_IN_BACKGROUND|BATTERY:RUN_IN_BACKGROUND) echo "背景執行" ;;
	RUN_ANY_IN_BACKGROUND|BATTERY:RUN_ANY_IN_BACKGROUND) echo "任意背景執行" ;;
	deviceidleWhitelist|BATTERY:deviceidle_whitelist) echo "Doze白名單" ;;
	*) echo "$1" ;;
	esac
}

# 顯示兩份 schema v2 canonical AppState 的實際差異。
# 只負責 UI 翻譯，不參與備份、恢復或驗證判斷。
_appstate_show_backup_diff() {
	local _old="$1" _new="$2" _diff="$TMPDIR/.appstate_diff_${$}_$RANDOM"
	local _kind _key _a _b _c _d _e _f _label _msg _count=0 _flags_a _flags_b
	printf '%s\n' "$_old" | jq -e 'type=="object" and .schemaVersion==2' >/dev/null 2>&1 || return 0
	printf '%s\n' "$_new" | jq -e 'type=="object" and .schemaVersion==2' >/dev/null 2>&1 || return 0
	jq -nr --argjson old "$_old" --argjson new "$_new" '
		def idx($a;$k): reduce ($a[]? | select(type=="object")) as $x ({}; .[($x[$k]|tostring)]=$x);
		def sv($x): if $x == null then "null" else ($x|tostring) end;
		($old.permissions // [] | idx(.;"name")) as $op |
		($new.permissions // [] | idx(.;"name")) as $np |
		(
			($np|to_entries[] | .key as $k | .value as $n | ($op[$k] // null) as $o |
				if $o == null then empty
				elif (($o.granted//null)!=($n.granted//null) or ($o.appOpMode//null)!=($n.appOpMode//null) or ($o.flags//0)!=($n.flags//0)) then
					["PERMISSION",$k,sv($o.granted),sv($n.granted),sv($o.appOpMode),sv($n.appOpMode),sv($o.flags//0),sv($n.flags//0)]|@tsv
				else empty end),
			($op|to_entries[] | select($np[.key] == null) |
				["PERMISSION",.key,sv(.value.granted),"missing",sv(.value.appOpMode),"missing",sv(.value.flags//0),"missing"]|@tsv)
		),
		($old.specialAccess // {}) as $os |
		($new.specialAccess // {}) as $ns |
		($ns|to_entries[] | .key as $k | .value as $n | ($os[$k] // null) as $o |
			if $o != null and (($o.mode//null)!=($n.mode//null) or ($o.allowed//null)!=($n.allowed//null))
			then ["SPECIAL",$k,sv($o.mode),sv($n.mode),sv($o.allowed),sv($n.allowed),"",""]|@tsv else empty end),
		($old.otherAppOps // [] | idx(.;"publicName")) as $oo |
		($new.otherAppOps // [] | idx(.;"publicName")) as $no |
		($no|to_entries[] | .key as $k | .value as $n | ($oo[$k]//null) as $o |
			if $o != null and (($o.mode//null)!=($n.mode//null) or ($o.packageMode//null)!=($n.packageMode//null) or ($o.uidMode//null)!=($n.uidMode//null))
			then ["APPOP",$k,sv($o.mode),sv($n.mode),"","","",""]|@tsv else empty end),
		(["RUN_IN_BACKGROUND","RUN_ANY_IN_BACKGROUND"][] as $k |
			(($old.batterySettings[$k]//null) as $o | ($new.batterySettings[$k]//null) as $n |
			if $o != null and $n != null and (($o.mode//null)!=($n.mode//null))
			then ["BATTERY",$k,sv($o.mode),sv($n.mode),"","","",""]|@tsv else empty end)),
		(if (($old.batterySettings.deviceidleWhitelist//null)!=($new.batterySettings.deviceidleWhitelist//null))
			then ["BATTERY","deviceidleWhitelist",sv($old.batterySettings.deviceidleWhitelist),sv($new.batterySettings.deviceidleWhitelist),"","","",""]|@tsv else empty end),
		(if (($old.ssaid//null)!=($new.ssaid//null)) then ["SSAID","value","changed","changed","","","",""]|@tsv else empty end)
	' > "$_diff" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || { rm -f "$_diff" 2>/dev/null; return 0; }
	[[ -s $_diff ]] || { rm -f "$_diff" 2>/dev/null; return 0; }
	_count="$(awk 'NF{n++} END{print n+0}' "$_diff" 2>/dev/null)"
	echoRgb "AppState狀態變更 $_count 項" "2"
	while IFS="$(printf '\t')" read -r _kind _key _a _b _c _d _e _f; do
		case $_kind in
		PERMISSION)
			_label="$(_perm_cn "$_key")"; _msg=""
			[[ $_a != $_b ]] && _msg="授予:$(_appstate_bool_cn "$_a")→$(_appstate_bool_cn "$_b")"
			[[ $_c != $_d ]] && _msg="${_msg:+$_msg  }AppOps:$(_appstate_mode_cn "$_c")→$(_appstate_mode_cn "$_d")"
			if [[ $_e != $_f ]]; then
				_flags_a="$_e"; _flags_b="$_f"
				[[ $_flags_a = missing ]] && _flags_a="已移除"
				[[ $_flags_b = missing ]] && _flags_b="已移除"
				[[ $_flags_a = null ]] && _flags_a="未設定"
				[[ $_flags_b = null ]] && _flags_b="未設定"
				_msg="${_msg:+$_msg  }flags:${_flags_a}→${_flags_b}"
			fi
			echoRgb "$_label: $_msg"
			;;
		SPECIAL)
			_label="$(_appstate_special_cn "$_key")"
			echoRgb "$_label: AppOps $(_appstate_mode_cn "$_a")→$(_appstate_mode_cn "$_b")"
			;;
		APPOP)
			_label="$(_perm_cn "$_key")"
			echoRgb "$_label: $(_appstate_mode_cn "$_a")→$(_appstate_mode_cn "$_b")"
			;;
		BATTERY)
			_label="$(_battery_cn "$_key")"
			case $_key in
			deviceidleWhitelist) echoRgb "$_label: $(_appstate_bool_cn "$_a")→$(_appstate_bool_cn "$_b")" ;;
			*) echoRgb "$_label: $(_appstate_mode_cn "$_a")→$(_appstate_mode_cn "$_b")" ;;
			esac
			;;
		SSAID) echoRgb "SSAID已變更" "2" ;;
		esac
	done < "$_diff"
	[[ -n ${SPEED_DEBUG_DEX_HUMAN_LOG:-} ]] && cat "$_diff" >> "$SPEED_DEBUG_DEX_HUMAN_LOG" 2>/dev/null
	rm -f "$_diff" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

# 規範化布林值,將 1/true/yes 等變成 true,其他變成 false
# 用於 conf 讀進來的開關項統一格式
isBoolean() {
	nsx="$1"
	case $1 in
	1|true|True|TRUE)
		nsx=true ;;
	0|false|False|FALSE)
		nsx=false ;;
	*)
		echoRgb "$conf_path $2=$1填寫錯誤，正確值1or0" "0"
		exit 2 ;;
	esac
}
# 根據上一條命令的退出碼輸出成功/失敗訊息
# 用法: echo_log "操作名稱" [skip_success_msg]
# 第二個參數非空時, 成功不輸出訊息 (只設變數)
echo_log() {
	if [[ $? = 0 ]]; then
		[[ $2 = "" ]] && echoRgb "$1成功" "1"
		_speed_debug_log "OK: $1"
		result=0
		Set_back_0
	else
		echoRgb "$1失敗，過世了" "0"
		_speed_debug_log "FAIL: $1"
		notification "$RANDOM" "$name1: $1失敗，過世"
		result=1
		Set_back_1
	fi
}
# lock 清理保底：不要依賴 kill_Serve() 內的 local LOCK_DIR，避免 EXIT trap 執行時 local 已失效導致 /data/.backup_lock 殘留。
SPEEDBACKUP_LOCK_DIR="${SPEEDBACKUP_LOCK_DIR:-/data/.backup_lock}"
SPEEDBACKUP_LOCK_OWNER_PID="${SPEEDBACKUP_LOCK_OWNER_PID:-$$}"
_speedbackup_lock_cleanup() {
	local _lock="${SPEEDBACKUP_LOCK_DIR:-/data/.backup_lock}" _pid="" _owner="${SPEEDBACKUP_LOCK_OWNER_PID:-$$}"
	[[ -n $_lock && $_lock = /data/.backup_lock ]] || { _speed_debug_log "LOCK_CLEAN_SKIP invalid_lock=$_lock"; return 0; }
	[[ -d $_lock ]] || return 0
	if [[ -f $_lock/pid ]]; then
		_pid="$(cat "$_lock/pid" 2>/dev/null)"
		# 只清自己本輪建立的 lock；如果 pid 不是本輪 shell，避免誤刪另一個正在跑的腳本 lock。
		if [[ $_pid = "$_owner" || $_pid = "$$" ]]; then
			rm -rf "$_lock" 2>/dev/null && _speed_debug_log "LOCK_CLEANED pid=$_pid lock=$_lock"
		else
			_speed_debug_log "LOCK_CLEAN_SKIP owner_mismatch lock_pid=$_pid owner=$_owner self=$$"
		fi
	else
		# 沒 pid 的 lock 只會來自建立中斷或舊版殘留；若目前不是另一輪已知 lock，安全清掉。
		rm -rf "$_lock" 2>/dev/null && _speed_debug_log "LOCK_CLEANED empty_pid lock=$_lock"
	fi
}
# 殺死先前殘留的腳本進程,並設置 lock 防止重複執行
# trap EXIT 會清 lock 並觸發 remote_cleanup (若有遠端設定)
kill_Serve() {
	SPEEDBACKUP_LOCK_DIR="/data/.backup_lock"
	SPEEDBACKUP_LOCK_OWNER_PID="$$"
	local LOCK_DIR="$SPEEDBACKUP_LOCK_DIR"
	local MY_PID="$SPEEDBACKUP_LOCK_OWNER_PID"
	# 使用 mkdir 作為原子鎖操作，避免 TOCTOU 競態條件
	if ! mkdir "$LOCK_DIR" 2>/dev/null; then
		if [[ -f $LOCK_DIR/pid ]]; then
			OLD_PID="$(cat "$LOCK_DIR/pid")"
			if kill -0 "$OLD_PID" 2>/dev/null; then
				echo "發現先前的備份程序 (PID=$OLD_PID)，將其終止"
				# 單次 ps 快照 + awk 一次算出待殺清單: 舊程序整棵子孫樹 + 殘留 start.sh/tools.sh (排除自己祖先鏈)
				local _kp _psbin="/system/bin/ps"
				[[ -x $_psbin ]] || _psbin="ps"
				# self 整條祖先鏈 + 自己的子孫樹 一律保護 (避免殺到自己 / 自己起的 ps 子進程)
				for _kp in $($_psbin -e -o pid=,ppid=,args= 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk -v root="$OLD_PID" -v self="$$" -v me="$MY_PID" '
					{ ppid[$1]=$2; cmd[$1]=$0 }
					END {
						# 保護: self 與 MY_PID 的祖先鏈
						for (start_pid in ppid) {}
						split(self" "me, seeds, " ")
						for (k in seeds) { p=seeds[k]; while (p>1 && (p in ppid)) { safe[p]=1; p=ppid[p] } safe[seeds[k]]=1 }
						# 保護: self/me 的子孫樹
						sm[self]=1; sm[me]=1; ch=1
						while (ch) { ch=0; for (x in ppid) if (!(x in sm) && (ppid[x] in sm)) { sm[x]=1; ch=1 } }
						for (x in sm) safe[x]=1
						# 待殺: 舊程序子孫樹 + 殘留 start.sh/tools.sh, 扣除保護集
						mark[root]=1; ch=1
						while (ch) { ch=0; for (x in ppid) if (!(x in mark) && (ppid[x] in mark)) { mark[x]=1; ch=1 } }
						for (x in cmd) if (cmd[x] ~ /start\.sh|tools\.sh/) mark[x]=1
						for (x in mark) if (!(x in safe)) print x
					}'); do
					kill -0 "$_kp" 2>/dev/null && kill -KILL "$_kp" 2>/dev/null
				done
				# 舊程序已被終止，清掉舊 lock，避免下次啟動再看到 stale lock。
				rm -rf "$LOCK_DIR" 2>/dev/null
				_speed_debug_log "LOCK_CLEANED killed_old_pid=$OLD_PID lock=$LOCK_DIR"
				echo "結束自身，避免重複執行"
				exit 1
			else
				_speed_debug_log "STALE_LOCK_CLEARED pid=$OLD_PID lock=$LOCK_DIR"
				rm -rf "$LOCK_DIR"
				mkdir "$LOCK_DIR" 2>/dev/null || exit 1
			fi
		else
			rm -rf "$LOCK_DIR"
			mkdir "$LOCK_DIR" 2>/dev/null || exit 1
		fi
	fi
	echo "$MY_PID" > "$LOCK_DIR/pid"
    # 安全清理暫存檔：避免 TMPDIR 異常時誤刪
    _speedbackup_kill_dirsize_workers() {
    	local _pid
    	for _pid in ${SPEEDBACKUP_DIRSIZE_PIDS:-}; do
    		kill -0 "$_pid" 2>/dev/null && kill -TERM "$_pid" 2>/dev/null
    	done
    	for _pid in ${SPEEDBACKUP_DIRSIZE_PIDS:-}; do
    		kill -0 "$_pid" 2>/dev/null && kill -KILL "$_pid" 2>/dev/null
    	done
    	unset SPEEDBACKUP_DIRSIZE_PIDS
    }
    _cleanup_tmp_files() {
    	# EXIT 收尾必須做完整清理，不保留恢復主迴圈的 session maps / batch queue。
    	_RESTORE_KEEP_SESSION_MAPS=0
    	_RESTORE_PRESERVE_BATCH_QUEUE=0
    	_speedbackup_kill_dirsize_workers
    	_remote_netwatch_report
    	_remote_netwatch_stop
    	_webdav_daemon_stop
	_webdav_mkcol_cache_clear_current
	_appstate_daemon_stop
	_hiddenapi_daemon_stop
	_notify_daemon_stop
	_install_daemon_stop
	# .restore_stage 不能放進通用 cleanup（恢復中途會多次呼叫）；只在 EXIT 明確收尾。
	rm -rf "$TMPDIR/.restore_stage" 2>/dev/null
    	cleanup_tmpdir_contents
    }
    _speedbackup_exit_trap() {
    	local _ec="$?" _trap_err
    	_speed_debug_disarm_if_run_gone
    	_trap_err="$(_speed_debug_stderr_target)"
    	if [[ "${SPEEDBACKUP_ENTRY_QUIET_TRAP:-0}" = 1 ]]; then _speed_debug_log "trap信號成功接受EXIT，退出腳本(exit=$_ec)"; else echoRgb "trap信號成功接受EXIT，退出腳本(exit=$_ec)" "3"; fi
    	# 預設不在 EXIT 裡做 snapshot，避免同一次退出打包兩次。
    	# 只有 SPEED_DEBUG_SNAPSHOT_ON_EXIT=1 時才先留安全快照。
    	if [[ "${SPEED_DEBUG_SNAPSHOT_ON_EXIT:-0}" = 1 ]]; then
    		if [[ "${SPEED_DEBUG_SNAPSHOT_DONE:-0}" = 1 ]]; then
    			if [[ "${SPEEDBACKUP_ENTRY_QUIET_TRAP:-0}" = 1 ]]; then _speed_debug_log "trap略過speed_debug快照，先前已建立"; else echoRgb "trap略過speed_debug快照，先前已建立" "3"; fi
    		else
    			if [[ "${SPEEDBACKUP_ENTRY_QUIET_TRAP:-0}" = 1 ]]; then _speed_debug_log "trap開始建立speed_debug快照"; else echoRgb "trap開始建立speed_debug快照" "3"; fi
    			_speed_debug_snapshot_pack "$_ec"
    		fi
    	fi
    	# 收尾清理。這些步驟不應阻止最後打包。
    	_speed_debug_disarm_if_run_gone
    	_trap_err="$(_speed_debug_stderr_target)"
    	_speedbackup_lock_cleanup
    	remote_cleanup
    	_speed_debug_disarm_if_run_gone
    	_cleanup_tmp_files
    	# 最終打包成功後才刪 run_xxx 目錄；失敗則保留 run_xxx。
    	if [[ "${SPEEDBACKUP_ENTRY_QUIET_TRAP:-0}" = 1 ]]; then _speed_debug_log "trap開始建立speed_debug最終包"; else echoRgb "trap開始建立speed_debug最終包" "3"; fi
    	_speed_debug_pack "$_ec"
    	if [[ "${SPEEDBACKUP_ENTRY_QUIET_TRAP:-0}" = 1 ]]; then _speed_debug_log "trap收尾流程完成(exit=$_ec)"; else echoRgb "trap收尾流程完成(exit=$_ec)" "3"; fi
    	return "$_ec"
    }
    trap '_speedbackup_exit_trap' EXIT
}
kill_Serve
# ======================================================
# 遠端功能函數 (upload / download / smb / webdav)
# ======================================================
# TCP port 探測：Android/toybox nc 常沒有 -z，不能只依賴 nc -z。
# 成功 return 0；失敗 return 1。用途：remote_precheck / SMB 區網掃描 fallback。
_tcp_port_open() {
	local host="$1" port="$2" timeout_s="${3:-2}" dbg="$4"
	local _nc_help _nc_has_z
	[[ -z $host || -z $port ]] && return 1
	if command -v nc >/dev/null 2>&1; then
		# 遠端未開時，timeout 包住 nc 可能讓終端直接吐出 "Terminated"。
		# 先判斷 nc 是否支援 -z：支援就只跑 -z；不支援才用空輸入 no-z。
		# 不再在 nc 已存在時疊加 bash /dev/tcp fallback，避免離線遠端多等與終端噪音。
		_nc_has_z=0
		_nc_help="$(nc -h 2>&1 || true)"
		case "$_nc_help" in *-z*) _nc_has_z=1 ;; esac
		if [[ $_nc_has_z = 1 ]]; then
			nc -z -w "$timeout_s" "$host" "$port" >/dev/null 2>&1 && {
				[[ -n $dbg ]] && _speed_debug_append_file "$dbg" "[OK] nc -z passed host=$host port=$port"
				return 0
			}
			[[ -n $dbg ]] && _speed_debug_append_file "$dbg" "[FAIL] nc -z failed host=$host port=$port"
			return 1
		fi
		nc -w "$timeout_s" "$host" "$port" </dev/null >/dev/null 2>&1 && {
			[[ -n $dbg ]] && _speed_debug_append_file "$dbg" "[OK] nc no-z passed host=$host port=$port"
			return 0
		}
		[[ -n $dbg ]] && _speed_debug_append_file "$dbg" "[FAIL] nc no-z failed host=$host port=$port"
		return 1
	fi
	# 只有沒有 nc 時才退到 bash /dev/tcp；保留兼容，但避免正常 Android 路徑觸發 timeout TERM 噪音。
	if command -v bash >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
		timeout "$timeout_s" bash -c ':</dev/tcp/$1/$2' _ "$host" "$port" >/dev/null 2>&1 && {
			[[ -n $dbg ]] && _speed_debug_append_file "$dbg" "[OK] bash /dev/tcp passed host=$host port=$port"
			return 0
		}
		[[ -n $dbg ]] && _speed_debug_append_file "$dbg" "[FAIL] bash /dev/tcp failed host=$host port=$port"
	fi
	return 1
}

# 預連線測試 (避免後續操作卡住)
# 用法: remote_precheck <host> <port>
# 多層 fallback: nc -z → nc 無 -z → bash /dev/tcp，失敗會寫 speed_debug/remote_precheck.log
remote_precheck() {
	local host="$1" port="$2"
	[[ -z $host ]] && { echoRgb "remote_precheck: host為空" "0"; return 1; }
	local dbg
	dbg="$(_speed_debug_log_path remote_precheck.log)"
	_speed_debug_append_file "$dbg" \
		"===== precheck $(date '+%Y-%m-%d %H:%M:%S') =====" \
		"host=$host port=$port"
	if _tcp_port_open "$host" "$port" 3 "$dbg"; then
		return 0
	fi
	# 詳細失敗原因已寫入 speed_debug 包內 remote_precheck.log；此函數本身不刷終端，交由呼叫端顯示摘要。
	return 1
}

# 流式恢復來源硬預檢：TCP port open 只代表該主機有服務監聽，不代表 SMB share/WebDAV 路徑可用。
# 這裡實際驗證「協議認證 + 遠端根 + Backup_zstd_X 子目錄」；任一失敗都必須在 Restore() 前中止。
_remote_stream_source_precheck() {
	local _subdir="$1" _dbg
	[[ -n $_subdir ]] || return 1
	_dbg="$(_speed_debug_log_path remote_source_precheck.log)"
	_speed_debug_append_file "$_dbg" \
		"===== source precheck $(date '+%Y-%m-%d %H:%M:%S') =====" \
		"type=$remote_type subdir=$_subdir url=$remote_url"

	case $remote_type in
	smb)
		local _auth _opts _target _cmd_path _out _rc
		_auth="$(_smb_auth_args_current)" || {
			_speed_debug_append_file "$_dbg" "[FAIL] SMB auth unavailable"
			echoRgb "SMB 認證資訊不可用，已中止流式恢復" "0"
			return 1
		}
		_target="$SMB_REM_PATH/$_subdir"
		_target="${_target#/}"
		_cmd_path="${_target//\//\\}"
		_opts="-t 10 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		_out="$(command smbclient "$SMB_SHARE" $_auth $_opts -c "cd \"$_cmd_path\"; pwd; exit" 2>&1)"
		_rc=$?
		_speed_debug_append_file "$_dbg" \
			"SMB share=$SMB_SHARE target=$_target rc=$_rc" \
			"$_out"
		if [[ $_rc != 0 ]] || printf '%s\n' "$_out" | grep -qiE \
			'NT_STATUS|tree connect failed|session setup failed|LOGON_FAILURE|ACCESS_DENIED|BAD_NETWORK_NAME|OBJECT_NAME_NOT_FOUND|OBJECT_PATH_NOT_FOUND|ERRbadpath|does not exist|cd .*failed|Connection refused|protocol negotiation failed|Unable to connect'; then
			echoRgb "SMB 遠端來源不可用，已中止流式恢復" "0"
			echoRgb "共享/路徑: $SMB_SHARE/${_target}" "0"
			echoRgb "請檢查共享名稱、帳密與遠端備份目錄是否存在" "3"
			return 1
		fi
		return 0
		;;
	webdav)
		local _base _err _rc _http
		_base="${remote_url%/}"
		_err="$TMPDIR/.webdav_source_precheck_$$"
		rm -f "$_err" 2>/dev/null
		_webdav_dex statrel "$remote_user" "$remote_pass" "$_base" "$_subdir" >/dev/null 2>"$_err"
		_rc=$?
		_http="${_WEBDAV_HTTP_CODE:-0}"
		_speed_debug_append_file "$_dbg" \
			"WEBDAV_STAT base=$_base target=$_subdir rc=$_rc http=$_http"
		[[ -s $_err ]] && _speed_debug_append_cat "$_dbg" "$_err" "[WEBDAV stderr]"
		rm -f "$_err" 2>/dev/null
		case "$_http" in
		2[0-9][0-9])
			[[ $_rc = 0 ]] && return 0
			;;
		esac
		echoRgb "WebDAV 遠端來源不可用，已中止流式恢復" "0"
		echoRgb "HTTP:${_http:-0} 路徑: $_subdir" "0"
		[[ -n ${_WEBDAV_ERROR_ZH:-} ]] && echoRgb "原因: $_WEBDAV_ERROR_ZH" "3"
		return 1
		;;
	esac
	return 1
}

# 寫入遠端上傳 log (帶時間戳)
# 用法: remote_log "訊息"
remote_log() {
	[[ -z $MODDIR ]] && return
	local _up_log
	_up_log="$(_speed_debug_log_path remote_upload.log)"
	_speed_debug_append_file "$_up_log" "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# v24.20.14-6 remote raw debug：遠端/流式詳細除錯 log。
# 注意：流式下載 stdout 是真實資料流，不能落檔也不能插入文字；这里只記 meta/stderr/rc/HTTP code。
remote_raw_log() {
	local _file="$1"; shift
	local _log
	_log="$(_speed_debug_log_path "$_file")"
	_speed_debug_append_file "$_log" "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

remote_raw_cat() {
	local _file="$1" _src="$2" _prefix="$3"
	[[ -s $_src ]] || return 0
	local _log
	_log="$(_speed_debug_log_path "$_file")"
	_speed_debug_append_cat "$_log" "$_src" "$_prefix"
}

_remote_debug_seq() {
	local _name="$1" _f _n
	_f="$TMPDIR/.remote_debug_seq_${_name}"
	_n=0
	[[ -f $_f ]] && _n="$(cat "$_f" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	case $_n in ''|*[!0-9]*) _n=0 ;; esac
	_n=$((_n + 1))
	echo "$_n" > "$_f" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	printf '%03d' "$_n"
}

# 上傳結束時統一輸出總結並決定是否刪本地
# 參數: $1=協議名 $2=成功清單檔 $3=失敗清單檔
upload_summary() {
	local proto="$1" ok_list="$2" fail_list="$3"
	local ok_count=0 fail_count=0
	[[ -f $ok_list ]] && ok_count="$(wc -l < "$ok_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	[[ -f $fail_list ]] && fail_count="$(wc -l < "$fail_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	ok_count=${ok_count:-0}
	fail_count=${fail_count:-0}
	# 計算總耗時
	local elapsed_str=""
	if [[ -n $UPLOAD_START_TS ]]; then
		local elapsed=$(( $(date +%s) - UPLOAD_START_TS ))
		elapsed_str=" 用時${elapsed}秒"
	fi
	echoRgb "_______________________________________" "2"
	echoRgb "$proto 上傳完成: 成功 $ok_count / 失敗 $fail_count${elapsed_str}" "3"
	remote_log "$proto 上傳結束: 成功 $ok_count / 失敗 $fail_count${elapsed_str}"
	if [[ $fail_count -gt 0 ]]; then
		echoRgb "失敗清單已寫入 speed_debug 包內: remote_upload.log" "0"
		local n=0
		while read -r line && [[ $n -lt 5 ]]; do
			echoRgb "$line" "0"
			let n++
		done < "$fail_list"
		[[ $fail_count -gt 5 ]] && echoRgb "...還有 $((fail_count - 5)) 個，請看 speed_debug 包內 remote_upload.log" "0"
	fi
	# 刪本地檔案的策略: remote_keep_local=true 或 1 永遠保留
	# 否則: 必須「全部成功」才刪除所有上傳過的檔案
	case $remote_keep_local in
	1|true|True|TRUE)
		echoRgb "remote_keep_local=$remote_keep_local 本地檔案保留" "3"
		;;
	*)
		if [[ $fail_count -eq 0 && $ok_count -gt 0 ]]; then
			echoRgb "全部上傳成功,清除本地已上傳檔案與空應用資料夾 (保留 tools/ 跟入口腳本)" "1"
			while read -r f; do
				[[ -z $f ]] && continue
				# 保留: tools/ 目錄下檔案 / 備份根目錄入口檔
				case $f in
				*/tools/*) continue ;;
				esac
				_f_dir=${f%/*}
				_f_base=${f##*/}
				if [[ $_f_dir = "$Backup" ]]; then
					case $_f_base in
					start.sh|restore_settings.conf) continue ;;
					esac
				fi
				rm -f "$f"
			done < "$ok_list"
			# 刪除上傳後留下的空 log/ 與 app 目錄；保留 Backup 根目錄本身
			find "$Backup" -mindepth 1 -type d -empty -delete 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		elif [[ $fail_count -gt 0 ]]; then
			echoRgb "部分上傳失敗,本地檔案全部保留 (含已上傳的)" "0"
			remote_log "部分失敗,本地檔案全部保留"
		fi
		;;
	esac
	rm -f "$ok_list" "$fail_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	unset UPLOAD_START_TS
	[[ $fail_count -eq 0 ]]
}

# 計算速度顯示字串
# 用法: speed_calc <總bytes> <用時秒數>
# 輸出: "1.23 GB/s" 或 "8.5 MB/s" 或 "512 KB/s" 或 "" (時間=0時)
speed_calc() {
	local bytes="$1" secs="$2"
	[[ -z $bytes || -z $secs ]] && return
	[[ $secs -le 0 ]] && return
	# 依速率(bytes/secs)分級, awk 一次處理 (無 32-bit 溢位, 四捨五入)
	awk -v b="$bytes" -v s="$secs" 'BEGIN{
		r=b/s
		if(r>=1073741824) printf "%.2f GB/s", r/1073741824
		else if(r>=1048576) printf "%.2f MB/s", r/1048576
		else if(r>=1024) printf "%.1f KB/s", r/1024
		else if(r>0) printf "%d B/s", r
	}'
}

# 計算清單檔案總大小 (bytes)
list_total_size() {
	local list="$1"
	[[ ! -f $list ]] && { echo 0; return; }
	# 一次批量 stat (xargs 分批) 取代逐行 fork, 大量檔案時快很多; 精確位元組
	tr '\n' '\0' < "$list" | xargs -0 -r stat -c%s 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{s+=$1} END{print s+0}'
}

# 收集本次需要上傳的清單 (而非整個Backup)
# 結果寫入 $1 指定的list_file
# 範圍由以下變數控制 (在各備份入口設定,只反映「本次執行」):
#   REMOTE_APPLIST    : 字串,本次備份的 app 清單 (跟 $txt 同格式)
#   REMOTE_UPLOAD_MEDIA=1 : 本次有跑 Media 備份, 要上傳 $Backup/Media
#   REMOTE_UPLOAD_WIFI=1  : 本次有跑 wifi 備份, 要上傳 $Backup/wifi
# app 上傳條件:
#   1. 該行未被 #/＃/! 註解
#   2. $Backup/$name1 目錄存在
#   3. 目錄內至少有一個有效檔案
remote_collect_targets() {
	local list_file="$1"
	local tmp_collect="$TMPDIR/.rcollect"
	: > "$list_file"
	# 全目錄模式: 上傳整個 Backup 下所有檔案 (排除 log/), 不依清單
	if [[ $REMOTE_FULL_DIR = 1 ]]; then
		[[ $REMOTE_QUIET != 1 ]] && echoRgb "全目錄模式: 收集整個備份目錄" "2"
		find "$Backup" -type f -not -path "$Backup/log/*" >> "$list_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		rm -f "$tmp_collect" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 0
	fi
	# 如果設置了 REMOTE_SKIP_APPDATA，跳過應用數據上傳
	if [[ $REMOTE_SKIP_APPDATA != 1 && -n $REMOTE_APPLIST ]]; then
		[[ $REMOTE_QUIET != 1 ]] && echoRgb "讀取本次備份名單" "2"
		echo "$REMOTE_APPLIST" | grep -Ev '^[[:space:]]*[#＃!]|^[[:space:]]*$' | while read -r line; do
			local name1="${line%% *}"
			[[ -z $name1 ]] && continue
			local full="$Backup/$name1"
			[[ -d $full ]] || continue
			if [[ $REMOTE_APPDETAILS_SKIP = 1 ]]; then
				find "$full" -type f ! -name "app_details.json" > "$tmp_collect" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			else
				find "$full" -type f  > "$tmp_collect" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			fi
			[[ -s $tmp_collect ]] && cat "$tmp_collect" >> "$list_file"
		done
	fi
	if [[ $REMOTE_UPLOAD_MEDIA = 1 && -d $Backup/Media ]]; then
		find "$Backup/Media" -type f  > "$tmp_collect" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		[[ -s $tmp_collect ]] && cat "$tmp_collect" >> "$list_file"
	fi
	if [[ $REMOTE_UPLOAD_WIFI = 1 && -d $Backup/wifi ]]; then
		find "$Backup/wifi" -type f  > "$tmp_collect" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		[[ -s $tmp_collect ]] && cat "$tmp_collect" >> "$list_file"
	fi
	# 固定附加: tools/ 資料夾、start.sh、restore_settings.conf、appList.txt、mediaList.txt
	# 只要 list_file 已經有內容(代表本次有東西要上傳)就一併帶上,讓遠端目錄能獨立還原
	# REMOTE_SKIP_FIXED=1 時跳過 (逐應用上傳模式，避免重複上傳)
	# REMOTE_SKIP_APPDATA=1 時也需要上傳依賴文件
	if [[ $REMOTE_SKIP_FIXED != 1 && $REMOTE_SKIP_APPDATA = 1 ]] || [[ $REMOTE_SKIP_FIXED != 1 && -s $list_file ]]; then
		[[ -d $Backup/tools ]] && find "$Backup/tools" -type f >> "$list_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		[[ -f $Backup/start.sh ]] && echo "$Backup/start.sh" >> "$list_file"
		[[ -f $Backup/restore_settings.conf ]] && echo "$Backup/restore_settings.conf" >> "$list_file"
		[[ -f $Backup/appList.txt ]] && echo "$Backup/appList.txt" >> "$list_file"
		[[ -f $Backup/mediaList.txt ]] && echo "$Backup/mediaList.txt" >> "$list_file"
		[[ -f "$Backup/MT管理器.apk" ]] && echo "$Backup/MT管理器.apk" >> "$list_file"
	fi
	rm -f "$tmp_collect" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}
# 掃描核心: 找出區網內所有開放 445 的主機, 寫入 $TMPDIR/.smb_scan_results (一行一 IP, 已排序)
# 成功(有結果) return 0; 無結果或無法掃描 return 1. 供 scan_smb / smb_autodetect_url 複用
_smb_scan_hosts() {
	local my_ip
	my_ip="$(ip route get 1 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{print $7; exit}')"
	[[ -z $my_ip ]] && my_ip="$(ifconfig 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -m1 'inet addr:192' | awk '{print $2}' | cut -d: -f2)"
	[[ -n $my_ip ]] && SMB_SCAN_SUBNET="${my_ip%.*}" || SMB_SCAN_SUBNET="auto"
	local _scan_label
	[[ $SMB_SCAN_SUBNET = auto ]] && _scan_label="自動偵測網段" || _scan_label="$SMB_SCAN_SUBNET.0/24"
	echoRgb "本機 IP: ${my_ip:-自動偵測}" "2"
	echoRgb "掃描 $_scan_label 上的 SMB 主機 (445 port)..." "3"
	local results="$TMPDIR/.smb_scan_results"; : > "$results"

	# 優先用 dex 併發 socket 預掃，避免 shell/nc 對 254 個 IP 反覆 fork。
	# SMB 傳輸仍交給 smbclient；這裡只找 445 open 的候選主機。
	local _dex_scan_out="$TMPDIR/.smb_scan_dex_out_$$" _dex_scan_err="$TMPDIR/.smb_scan_dex_err_$$" _dex_scan_rc=1
	if [[ -f "$tools_path/classes.dex" ]] && command -v "$DEX_APP_PROCESS_BIN" >/dev/null 2>&1; then
		dex_smbscan_raw scanSmb "$SMB_SCAN_SUBNET" 800 192 0 445,139 >"$_dex_scan_out" 2>"$_dex_scan_err"
		_dex_scan_rc=$?
		[[ -n ${SPEED_DEBUG_RUN_DIR:-} ]] && {
			{
				echo "===== SMB_SCAN_DEX rc=$_dex_scan_rc subnet=$SMB_SCAN_SUBNET ====="
				cat "$_dex_scan_out" 2>/dev/null
				cat "$_dex_scan_err" 2>/dev/null
			} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_smb_scan_raw.log" 2>/dev/null
		}
		if [[ $_dex_scan_rc = 0 && -s $_dex_scan_out ]]; then
			awk -F '\t' '$3=="open" && ($2==445 || $2==139) {print $1}' "$_dex_scan_out" | sort -t. -k4 -n -u > "$results"
			rm -f "$_dex_scan_out" "$_dex_scan_err" 2>/dev/null
			if [[ -s $results ]]; then
				printf '\r -掃描 254/254 %s\n' "$(progress_bar 100)" >&2
				return 0
			fi
		fi
	fi
	rm -f "$_dex_scan_out" "$_dex_scan_err" 2>/dev/null

	# dex 不可用或未找到主機時，回退 shell TCP 掃描。
	# Android/toybox nc 常沒有 -z，因此不能硬依賴 nc -z。
	if ! command -v nc >/dev/null 2>&1 && ! command -v bash >/dev/null 2>&1; then
		echoRgb "未找到 nc/bash，無法 fallback 掃描" "0"; return 1
	fi
	if [[ $SMB_SCAN_SUBNET = auto ]]; then
		echoRgb "無法取得本機 IP" "0"; return 1
	fi
	local i pids=""
	for i in $(seq 1 254); do
		( _tcp_port_open "$SMB_SCAN_SUBNET.$i" 445 1 "" && echo "$SMB_SCAN_SUBNET.$i" >> "$results" ) &
		pids="$pids $!"
		if [[ $((i % 20)) -eq 0 ]]; then
			_event_wait_pid_list "$pids" smb_scan_batch 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; pids=""
			printf '\r -掃描 %d/254 %s' "$i" "$(progress_bar $((i * 100 / 254)))" >&2
		fi
	done
	_event_wait_pid_list "$pids" smb_scan_final 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	printf '\r -掃描 254/254 %s\n' "$(progress_bar 100)" >&2
	[[ ! -s $results ]] && return 1
	sort -t. -k4 -n "$results" -o "$results"
	return 0
}

# 自動偵測區網 SMB 並設定 remote_url (取第一台有可用共享的主機)
# 不論 remote_stream/remote_user/remote_pass 是否填寫都會探測
smb_autodetect_url() {
	_smb_scan_hosts || return 1
	local _auth
	_auth="$(_smb_auth_args_current)" || { echoRgb "SMB 認證資訊不可用，已停止操作" "0"; return 1; }
	local target share
	while read -r target; do
		echoRgb "發現 SMB: $target" "1"
		share="$(command smbclient -g -L "//$target" $_auth -t 5 -s $(_smb_client_conf) -m SMB3 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} \
			| _smb_parse_share_grepable)"
		if [[ -n $share ]]; then
			remote_url="smb://$target/$share"
			rm -f "$TMPDIR/.smb_scan_results"
			return 0
		fi
		echoRgb "$target 無可用共享 (或需認證)" "2"
	done < "$TMPDIR/.smb_scan_results"
	rm -f "$TMPDIR/.smb_scan_results"
	return 1
}

# 掃描區網內所有開放 SMB (445 port) 的主機 (菜單功能: 顯示所有主機與共享)
scan_smb() {
	if ! _smb_scan_hosts; then
		echoRgb "未發現 SMB 主機" "0"
		rm -f "$TMPDIR/.smb_scan_results"
		return 1
	fi
	echoRgb "------- 掃描完成 -------" "3"
	local _auth
	_auth="$(_smb_auth_args_current)" || { echoRgb "SMB 認證資訊不可用，已停止操作" "0"; return 1; }
	while read -r target; do
		echoRgb "發現 SMB: $target" "1"
		# 查主機名 (有 nmblookup 才查)
		if command -v nmblookup >/dev/null 2>&1; then
			local hn
			hn="$(nmblookup -A "$target" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk 'NR==2{print $1}' | tr -d '<>\t ')"
			[[ -n $hn ]] && echoRgb "主機名: $hn" "2"
		fi
		# 列 share — smbclient 的 CP850/charset 噪音只進 raw log，不污染 stderr.log。
		local _scan_raw
		_scan_raw="$(_speed_debug_log_path remote_smb_scan_raw.log)"
		command smbclient -g -L "//$target" $_auth -t 3 -s $(_smb_client_conf) -m SMB3 2>>"$_scan_raw" \
			| awk -F'|' '
				function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s}
				$1=="Disk" {n=trim($2); if (n!="" && n !~ /\$$/) print "  共享: " n}
			' \
			| while read -r line; do echoRgb "$line" "2"; done
	done < "$TMPDIR/.smb_scan_results"
	rm -f "$TMPDIR/.smb_scan_results"
}
# SMB 上傳實作 (使用 smbclient)
# 流程: 解析 URL → 預檢 → 收集檔案 → 按目錄分組 → 每組一次 smbclient 批次傳輸
# 跟 upload_remote 的差別: SMB 用獨立的 smbclient 二進制, 不走外部 HTTP 工具
upload_smb() {
	[[ -z $remote_url ]] && { echoRgb "remote_url未設置" "0"; return 1; }
	UPLOAD_START_TS=$(date +%s)
	[[ $REMOTE_QUIET != 1 ]] && echoRgb "使用: $filepath/smbclient" "2"
	# 解析 smb://server/share/remotepath
	remote_parse_smb_url
	local share="$SMB_SHARE"
	local rem_path="$SMB_REM_PATH"
	# 自動加上備份目錄前綴 (跟本地結構一致)
	local backup_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	rem_path="${rem_path}/${backup_subdir}"
	# 拆出 host 和 port (從 share 反推)
	local _hp="${share#//}"; _hp="${_hp%%/*}"
	local host="${_hp%%:*}"
	local port="${_hp#*:}"
	[[ $port = $_hp ]] && port=445
	echoRgb "SMB: $share (路徑: ${rem_path:-/})" "2"
	# 連線預檢
	if ! remote_precheck "$host" "$port"; then
		echoRgb "SMB伺服器無法連線: $host:$port (請檢查WiFi/位址/伺服器狀態)" "0"
		echoRgb "本地檔案已保留" "0"
		return 1
	fi
	local list_file="$TMPDIR/.slist"
	local ok_list="$TMPDIR/.sok"
	local fail_list="$TMPDIR/.sfail"
	: > "$ok_list"; : > "$fail_list"
	remote_collect_targets "$list_file"
	_remote_filter_tools_targets_by_signature "$list_file" "$Backup/tools"
	if [[ ! -s $list_file ]]; then
		echoRgb "無檔案需上傳" "3"
		rm -f "$list_file" "$ok_list" "$fail_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 0
	fi
	local total
	total="$(wc -l < "$list_file")"
	[[ $REMOTE_QUIET != 1 ]] && echoRgb "準備上傳 $total 個檔案" "3"
	if [[ $REMOTE_QUIET != 1 ]]; then
		local _up_bytes
		_up_bytes="$(list_total_size "$list_file")"
		echoRgb "本次上傳總大小: $(size "$_up_bytes") (位元組:$_up_bytes)" "3"
	fi
	remote_log "SMB 開始: $share, 共 $total 檔"
	remote_raw_log "remote_smb_upload_raw.log" "BEGIN share=$share rem_path=$rem_path total=$total backup_subdir=$backup_subdir host=$host port=$port"
	# smbclient 共用參數:
	#   -t 10           : 命令 timeout 秒數
	#   -s $(_smb_client_conf)    : 跳過讀取 smb.conf (避免手動編譯版找不到 conf 噴警告)
	#   -p <port>       : 指定 SMB 端口 (預設 445, 由 remote_parse_endpoint 設定)
	#   -m SMB3         : client max protocol = SMB3, 表示最高用到 SMB3.1.1
	#                     min 維持 smbclient 預設 (SMB2_02), 故拒絕 SMB1 但允許協商到 SMB2.x ~ SMB3.x
	local SMB_OPTS="-t 10 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
	local _smb_auth_args
	_smb_auth_args="$(_smb_auth_args_current)" || {
		echoRgb "SMB 認證資訊不可用，已停止上傳" "0"
		echo "SMB auth unavailable: user=${remote_user:+set} authfile=${_SMB_AUTHFILE:-empty}" >> "$fail_list"
		rm -f "$list_file" "$ok_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 1
	}
	# 收集所有需要建立的目錄
	local mkdir_script="$TMPDIR/.smb_mkdir"
	: > "$mkdir_script"
	{
		while read -r f; do
			local d="${f#$Backup/}"
			d="${d%/*}"
			[[ -n $d && $d != "${f#$Backup/}" ]] && echo "${rem_path:+$rem_path/}$d"
		done < "$list_file"
	} | sort -u | while read -r d; do
		# 對每層路徑都產生 mkdir 命令
		# 注意: smbclient 內部命令不認 shell 引號, 不能加 '' 或 ""
		local cur=""
		local OLDIFS="$IFS"
		IFS='/'
		set -- $d
		IFS="$OLDIFS"
		for seg; do
			[[ -z $seg ]] && continue
			cur="$cur/$seg"
			echo "mkdir $cur" >> "$mkdir_script"
		done
	done
	# 一次連線執行所有 mkdir (比每個目錄重新連快很多)
	if [[ -s $mkdir_script ]]; then
		echo "exit" >> "$mkdir_script"
		local _mkdir_out _mkdir_rc
		_mkdir_out="$(smbclient "$share" $_smb_auth_args $SMB_OPTS < "$mkdir_script" 2>&1)"
		_mkdir_rc=$?
		remote_raw_log "remote_smb_upload_raw.log" "MKDIR rc=$_mkdir_rc script=$mkdir_script"
		printf '%s\n' "$_mkdir_out" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_smb_upload_raw.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		printf '%s\n' "$_mkdir_out" | grep -Ev '^Domain=|^OS=|NT_STATUS_OBJECT_NAME_COLLISION|^Try "help"|^dos charset|^Can.t load' >&2
		if [[ $_mkdir_rc != 0 ]] || _smb_output_has_error "$_mkdir_out"; then
			echoRgb "SMB 建立遠端目錄失敗，已停止上傳" "0"
			rm -f "$mkdir_script" "$list_file" "$ok_list" "$fail_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			return 1
		fi
	fi
	rm -f "$mkdir_script" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# 按目錄分組上傳 (同一目錄的所有檔案,一次連線傳完)
	# 先依遠端目錄分組
	local group_dir="$TMPDIR/.smb_groups"
	mkdir -p "$group_dir" && rm -f "$group_dir"/*
	while read -r f; do
		[[ -z $f ]] && continue
		local rel="${f#$Backup/}"
		local file_dir="$(dirname "$rel")"
		local rem_dir="$rem_path"
		[[ $file_dir != . ]] && rem_dir="${rem_dir:+$rem_dir/}$file_dir"
		[[ -z $rem_dir ]] && rem_dir="/"
		# 用 base64 或 hash 當分組 key,避免路徑裡的 / 影響檔名
		local key="$(echo "$rem_dir|$(dirname "$f")" | md5sum 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | cut -c1-12)"
		[[ -z $key ]] && key="$(echo "$rem_dir|$(dirname "$f")" | cksum | cut -d' ' -f1)"
		local gf="$group_dir/$key"
		[[ ! -f $gf ]] && {
			echo "$rem_dir" > "$gf.meta"
			echo "$(dirname "$f")" >> "$gf.meta"
		}
		echo "$f" >> "$gf"
	done < "$list_file"
	# 對每個分組執行批次上傳
	local idx=0
	# 算總目錄數 (用於進度計算; 不含 wifi, wifi 不參與百分比)
	local total_dirs done_dirs=0
	for gf in "$group_dir"/*; do
		[[ -f $gf && $gf != *.meta ]] || continue
		local rem_dir_check
		rem_dir_check="$(sed -n 1p "$gf.meta")"
		# wifi 目錄不算進總數
		[[ $rem_dir_check = */wifi || $rem_dir_check = wifi || $rem_dir_check = */wifi/* ]] && continue
		let total_dirs++
	done
	for gf in "$group_dir"/*; do
		[[ -f $gf && $gf != *.meta ]] || continue
		local meta="$gf.meta"
		local rem_dir local_dir
		rem_dir="$(sed -n 1p "$meta")"
		local_dir="$(sed -n 2p "$meta")"
		local file_count
		file_count="$(wc -l < "$gf")"
		# 判斷是否為 wifi (不計入進度)
		local is_wifi=0
		[[ $rem_dir = */wifi || $rem_dir = wifi || $rem_dir = */wifi/* ]] && is_wifi=1
		echoRgb "上傳目錄 $rem_dir ($file_count 檔)" "3"
		local dir_start
		dir_start=$(date +%s)
		# 建立 smbclient batch script
		local batch="$TMPDIR/.smb_batch"
		echo "cd $rem_dir" > "$batch"
		echo "lcd $local_dir" >> "$batch"
		while read -r f; do
			local fname="$(basename "$f")"
			echo "put $fname" >> "$batch"
		done < "$gf"
		echo "exit" >> "$batch"
		# 跑 batch, 解析每個 put 的結果
		local smb_out _smb_batch_rc _raw_tag
		_raw_tag="$(_remote_debug_seq smb_upload)"
		smb_out="$(smbclient "$share" $_smb_auth_args $SMB_OPTS < "$batch" 2>&1)"
		_smb_batch_rc=$?
		remote_raw_log "remote_smb_upload_raw.log" "BATCH tag=$_raw_tag rc=$_smb_batch_rc rem_dir=$rem_dir local_dir=$local_dir file_count=$file_count batch=$batch"
		{
			echo "===== SMB_UPLOAD_BATCH $_raw_tag rem_dir=$rem_dir rc=$_smb_batch_rc ====="
			printf '%s\n' "$smb_out"
		} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_smb_upload_${_raw_tag}.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		printf '%s\n' "$smb_out" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_smb_upload_raw.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		# 對應每個檔案的成功/失敗
		# 優化: smb_out 對全部檔案是同一份, 迴圈前一次抽出含錯誤標記的行,
		# 迴圈內改用參數展開 + case 零 fork 比對 (原本每檔 basename+echo+2grep ~4 fork)
		local _smb_err_lines _smb_global_fail=0
		_smb_err_lines="$(printf '%s\n' "$smb_out" | grep -E 'NT_STATUS|does not exist|ERR|Unable to|Failed to|failed|denied|Connection refused|tree connect|session setup' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		# smbclient 的 rc/錯誤有時不含檔名；這種全域錯誤必須整組判失敗，避免假成功後刪除本地檔案。
		if [[ $_smb_batch_rc != 0 ]] || printf '%s\n' "$smb_out" | grep -qiE 'Unable to open credentials file|Failed to set parse authentication file|session setup failed|tree connect failed|NT_STATUS_LOGON_FAILURE|NT_STATUS_ACCESS_DENIED|NT_STATUS_BAD_NETWORK_NAME|Connection refused|protocol negotiation failed'; then
			_smb_global_fail=1
		fi
		while read -r f; do
			let idx++
			local rel="${f#$Backup/}"
			local fname="${f##*/}"
			if [[ $_smb_global_fail = 1 ]]; then
				echo "$rel" >> "$fail_list"
				echoRgb "[$idx/$total] ✗ $rel" "0"
				remote_log "FAIL SMB $rel batch_rc=$_smb_batch_rc"
			else
				# 用檔名比對錯誤行時必須要求邊界字元，否則像 user.tar 會被
				# user.tar.zst 的錯誤行「假陽性」命中 (純子字串比對的舊 bug)，
				# 導致明明上傳成功的檔案被誤判失敗。
				case "$_smb_err_lines" in
					"$fname" | "$fname"[!A-Za-z0-9_.-]* | *[!A-Za-z0-9_.-]"$fname" | *[!A-Za-z0-9_.-]"$fname"[!A-Za-z0-9_.-]*)
						echo "$rel" >> "$fail_list"
						echoRgb "[$idx/$total] ✗ $rel" "0"
						remote_log "FAIL SMB $rel"
						;;
					*)
						echo "$f" >> "$ok_list"
						echoRgb "[$idx/$total] ✓ $rel" "1"
						;;
				esac
			fi
		done < "$gf"
		rm -f "$batch"
		# 此目錄完成,印整體進度 (wifi 不算)
		if [[ $is_wifi = 0 && $total_dirs -gt 0 ]]; then
			let done_dirs++
			local dir_speed=""
			local dir_bytes
			dir_bytes=$(list_total_size "$gf")
			local dir_elapsed=$(( $(date +%s) - dir_start ))
			local sp
			sp=$(speed_calc "$dir_bytes" "$dir_elapsed")
			[[ -n $sp ]] && dir_speed=" ($sp)"
			echoRgb "完成$((done_dirs * 100 / total_dirs))% $(progress_bar $((done_dirs * 100 / total_dirs)))${dir_speed}" "3"
		fi
	done
	# REMOTE_APPDETAILS_FILE: 主體上傳完成後，若無失敗則上傳 app_details.json
	if [[ -n $REMOTE_APPDETAILS_FILE && -f $REMOTE_APPDETAILS_FILE ]]; then
		# 非流式遠端最後上傳 app_details 前再收斂，避免本地後續 jq_inplace/merge 遺留格式漂移。
		_app_details_normalize_restore_profile_file "$REMOTE_APPDETAILS_FILE" || _speed_debug_log "APPDETAILS_REMOTE_FINAL_PRETTY_FAIL file=$REMOTE_APPDETAILS_FILE proto=SMB"
		if [[ ! -s $fail_list ]]; then
			let idx++
			local _ad_rel="${REMOTE_APPDETAILS_FILE#$Backup/}"
			local _ad_dir="$(dirname "$REMOTE_APPDETAILS_FILE")"
			local _ad_fname="$(basename "$REMOTE_APPDETAILS_FILE")"
			local _ad_smb_out _ad_smb_rc _ad_tag
			_ad_tag="$(_remote_debug_seq smb_upload)"
			if ! _smb_safe_component "$_ad_dir" || ! _smb_safe_component "$_ad_fname"; then
				echoRgb "偵測到不安全的路徑字元, 拒絕上傳 app_details: $_ad_rel" "0" >&2
				return 1
			fi
			_ad_smb_out="$(smbclient "$share" $_smb_auth_args -t 10 -s $(_smb_client_conf) \
				-D "${rem_path:+$rem_path/}$(dirname "$_ad_rel")" \
				-c "lcd $_ad_dir; put $_ad_fname; exit" 2>&1)"
			_ad_smb_rc=$?
			remote_raw_log "remote_smb_upload_raw.log" "APP_DETAILS tag=$_ad_tag rc=$_ad_smb_rc rel=$_ad_rel dir=$_ad_dir"
			{
				echo "===== SMB_UPLOAD_APP_DETAILS $_ad_tag rel=$_ad_rel rc=$_ad_smb_rc ====="
				printf '%s\n' "$_ad_smb_out"
			} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_smb_upload_${_ad_tag}.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			if [[ $_ad_smb_rc != 0 ]] || echo "$_ad_smb_out" | grep -qE 'NT_STATUS|does not exist|ERR|Unable to|Failed to|failed|denied|session setup|tree connect'; then
				echo "$_ad_rel" >> "$fail_list"
				echoRgb "[$idx/$idx] ✗ $_ad_rel" "0"
				remote_log "FAIL SMB $_ad_rel"
			else
				echo "$REMOTE_APPDETAILS_FILE" >> "$ok_list"
				echoRgb "[$idx/$idx] ✓ $_ad_rel" "1"
			fi
		else
			echoRgb "其他文件上傳失敗,跳過 app_details.json" "0"
		fi
	fi
	rm -rf "$group_dir" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	rm -f "$list_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	upload_summary "SMB" "$ok_list" "$fail_list"
}

# 遠端上傳分派器 + WebDAV 實作
# $1=協議名 (webdav/smb), smb 會轉派給 upload_smb
# WebDAV: 用 dex WebDavUtil 逐檔 PUT，預先 MKCOL 建好目錄結構
upload_remote() {
	local proto="$1"
	[[ $proto = smb ]] && { upload_smb; return $?; }
	[[ -z $remote_url ]] && { echoRgb "remote_url未設置" "0"; return 1; }
	echoRgb "WebDAV上傳: dex WebDavUtil 原生/atomic模式" "3"
	UPLOAD_START_TS=$(date +%s)
	local base_root base_url
	case $proto in
	webdav)
		base_root="${remote_url%/}"
		base_url="$base_root"
		[[ $base_url != http://* && $base_url != https://* ]] && { echoRgb "WebDAV地址格式錯誤: $remote_url" "0"; return 1; }
		;;
	*) echoRgb "未支援的協議: $proto" "0"; return 1 ;;
	esac
	# 自動加上備份目錄前綴 (跟本地結構一致)
	local backup_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	base_url="$base_root/$backup_subdir"
	# 連線預檢: 從 base_url 解出 host:port
	local _hp="${base_url#*://}"
	_hp="${_hp%%/*}"
	local _host="${_hp%%:*}"
	local _port="${_hp#*:}"
	if [[ $_port = $_hp ]]; then
		[[ $base_url = https://* ]] && _port=443 || _port=80
	fi
	if ! remote_precheck "$_host" "$_port"; then
		echoRgb "$proto伺服器無法連線: $_host:$_port (請檢查WiFi/位址/伺服器狀態)" "0"
		echoRgb "本地檔案已保留" "0"
		return 1
	fi
	[[ $REMOTE_QUIET != 1 ]] && echoRgb "使用: classes.dex WebDavUtil" "2"
	local list_file="$TMPDIR/.rlist"
	local ok_list="$TMPDIR/.rok"
	local fail_list="$TMPDIR/.rfail"
	: > "$ok_list"; : > "$fail_list"
	[[ -z $Backup ]] && { echoRgb "Backup路徑為空" "0"; return 1; }
	remote_collect_targets "$list_file"
	_remote_filter_tools_targets_by_signature "$list_file" "$Backup/tools"
	if [[ ! -s $list_file ]]; then
		echoRgb "無檔案需上傳" "3"
		rm -f "$list_file" "$ok_list" "$fail_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 0
	fi
	local total
	total="$(wc -l < "$list_file")"
	[[ $REMOTE_QUIET != 1 ]] && echoRgb "準備上傳 $total 個檔案" "3"
	if [[ $REMOTE_QUIET != 1 ]]; then
		local _up_bytes
		_up_bytes="$(list_total_size "$list_file")"
		echoRgb "本次上傳總大小: $(size "$_up_bytes") (位元組:$_up_bytes)" "3"
	fi
	remote_log "$proto 開始: $base_url, 共 $total 檔"
	remote_raw_log "remote_webdav_upload_raw.log" "BEGIN base_url=$base_url total=$total host=$_host port=$_port backup_subdir=$backup_subdir"
	# WEB-R3: 非流式 WebDAV 也先走 OPTIONS 能力預檢；atomic 上傳需要 MOVE。
	if ! _webdav_options_preflight "$base_root" "$backup_subdir" upload; then
		echoRgb "WebDAV 能力預檢失敗：伺服器不支援必要方法或遠端路徑不可用" "0"
		[[ -n ${_WEBDAV_ERROR_ZH:-} ]] && echoRgb "原因: $_WEBDAV_ERROR_ZH" "0"
		return 1
	fi
	# WebDAV: 先建初始目錄 (Backup_zstd_X 自己)
	local _mkcol_http _mkcol_rc _mkcol_err="$TMPDIR/.webdav_mkcol_err_$$"
	_webdav_mkdirrel_cached "$remote_user" "$remote_pass" "$base_root" "$backup_subdir" "$_mkcol_err"
	_mkcol_rc=$?
	_mkcol_http="$_WEBDAV_HTTP_CODE"
	remote_raw_log "remote_webdav_upload_raw.log" "MKCOL root rc=$_mkcol_rc http=$_mkcol_http url=$base_url"
	remote_raw_cat "remote_webdav_upload_raw.log" "$_mkcol_err" "[MKCOL root stderr]"
	rm -f "$_mkcol_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# WebDAV: 創建遠程子目錄。340 起正式流程停用 mkdirsrel，改用 statrel + mkdirrel 逐層建立。
	while read -r f; do
		local d="${f#$Backup/}"
		d="${d%/*}"
		[[ -n $d && $d != "${f#$Backup/}" ]] && echo "$backup_subdir/$d"
	done < "$list_file" | sort -u | while read -r cur_rel; do
		local _sub_mk_err="$TMPDIR/.webdav_mkdirs_err_$$" _sub_mk_http _sub_mk_rc
		_webdav_mkdirrel_cached "$remote_user" "$remote_pass" "$base_root" "$cur_rel" "$_sub_mk_err"
		_sub_mk_rc=$?
		_sub_mk_http="$_WEBDAV_HTTP_CODE"
		remote_raw_log "remote_webdav_upload_raw.log" "MKDIRS dir rc=$_sub_mk_rc http=$_sub_mk_http rel=$cur_rel"
		remote_raw_cat "remote_webdav_upload_raw.log" "$_sub_mk_err" "[MKDIRS dir stderr]"
		rm -f "$_sub_mk_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	done
	# 預掃總目錄數 (排除 wifi, 不計入百分比)
	local total_dirs done_dirs=0 last_dir="" cur_top_dir=""
	local dir_start=0 dir_bytes_accum=0
	while read -r f; do
		local top="${f#$Backup/}"
		top="${top%%/*}"
		[[ $top = wifi ]] && continue
		echo "$top"
	done < "$list_file" | sort -u | while read -r d; do echo "$d"; done > "$TMPDIR/.dirs_count"
	total_dirs="$(wc -l < "$TMPDIR/.dirs_count" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	rm -f "$TMPDIR/.dirs_count"
	# 上傳檔案
	local idx=0
	while read -r f; do
		[[ -z $f ]] && continue
		let idx++
		local rel="${f#$Backup/}"
		local cur_top="${rel%%/*}"
		# 判斷是「目錄內檔案」還是「根目錄檔案」
		# rel 含 / → 目錄內檔案, cur_top 是目錄名
		# rel 不含 / → 根目錄檔案, cur_top 是檔案名本身
		local is_root_file=0
		[[ $rel = "$cur_top" ]] && is_root_file=1
		# 目錄切換時印上一個目錄的進度
		if [[ -n $last_dir && $cur_top != "$last_dir" ]]; then
			if [[ $last_dir != wifi && $total_dirs -gt 0 ]]; then
				let done_dirs++
				local dir_speed=""
				local dir_elapsed=$(( $(date +%s) - dir_start ))
				local sp
				sp=$(speed_calc "$dir_bytes_accum" "$dir_elapsed")
				[[ -n $sp ]] && dir_speed=" ($sp)"
				echoRgb "完成$((done_dirs * 100 / total_dirs))% $(progress_bar $((done_dirs * 100 / total_dirs)))${dir_speed}" "3"
			fi
			if [[ $is_root_file = 1 ]]; then
				echoRgb "上傳檔案 $cur_top" "3"
			else
				echoRgb "上傳目錄 $cur_top" "3"
			fi
			dir_start=$(date +%s)
			dir_bytes_accum=0
		elif [[ -z $last_dir ]]; then
			if [[ $is_root_file = 1 ]]; then
				echoRgb "上傳檔案 $cur_top" "3"
			else
				echoRgb "上傳目錄 $cur_top" "3"
			fi
			dir_start=$(date +%s)
			dir_bytes_accum=0
		fi
		last_dir="$cur_top"
		# 累計這個目錄已上傳的 bytes
		local _sz
		_sz=$(stat -c%s "$f" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})
		dir_bytes_accum=$(( dir_bytes_accum + ${_sz:-0} ))
		local target_url
		if [[ $proto = webdav ]]; then
			target_url="$backup_subdir/$rel"
		else
			target_url="$base_url/$rel"
		fi
		local http_code webdav_exit
		local _sz_human
		_sz_human=$(awk "BEGIN{s=${_sz:-0};if(s>=1073741824)printf\"%.2fGB\",s/1073741824;else if(s>=1048576)printf\"%.1fMB\",s/1048576;else if(s>=1024)printf\"%.0fKB\",s/1024;else printf\"%dB\",s}")
		local _webdav_progress="$TMPDIR/.webdav_progress_$$" _webdav_tag
		_webdav_tag="$(_remote_debug_seq webdav_upload)"
		echoRgb "\r[$idx/$total] $rel ($_sz_human) 上傳中..." "3" > /dev/tty
		_webdav_putrel_atomic_file "$base_root" "$target_url" "$f" "$_webdav_tag" "$_webdav_progress"
		webdav_exit=$?
		http_code="$_WEBDAV_HTTP_CODE"
		remote_raw_log "remote_webdav_upload_raw.log" "PUT_ATOMIC tag=$_webdav_tag rc=$webdav_exit http=$http_code bytes=${_sz:-0} rel=$rel url=$target_url"
		remote_raw_cat "remote_webdav_upload_${_webdav_tag}.log" "$_webdav_progress" "===== WEBDAV_PUT $_webdav_tag rel=$rel rc=$webdav_exit http=$http_code ====="
		cat "$_webdav_progress" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_webdav_upload_raw.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		rm -f "$_webdav_progress" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		printf "\r\033[K" > /dev/tty
		# http_code 2xx 視為成功
		case $http_code in
		2*)
			echo "$f" >> "$ok_list"
			echoRgb "[$idx/$total] ✓ $rel" "1"
			;;
		*)
			echo "$rel  (HTTP $http_code)" >> "$fail_list"
			echoRgb "[$idx/$total] ✗ $rel (HTTP $http_code)" "0"
			[[ -n ${_WEBDAV_ERROR_ZH:-} ]] && echoRgb "原因: $_WEBDAV_ERROR_ZH" "0"
			remote_log "FAIL $proto $rel HTTP=$http_code webdav_exit=$webdav_exit"
			;;
		esac
	done < "$list_file"
	# 最後一個目錄(非wifi)的進度
	if [[ -n $last_dir && $last_dir != wifi && $total_dirs -gt 0 ]]; then
		let done_dirs++
		local dir_speed=""
		local dir_elapsed=$(( $(date +%s) - dir_start ))
		local sp
		sp=$(speed_calc "$dir_bytes_accum" "$dir_elapsed")
		[[ -n $sp ]] && dir_speed=" ($sp)"
		echoRgb "完成$((done_dirs * 100 / total_dirs))% $(progress_bar $((done_dirs * 100 / total_dirs)))${dir_speed}" "3"
	fi
	# REMOTE_APPDETAILS_FILE: 主體上傳完成後，若無失敗則上傳 app_details.json
	if [[ -n $REMOTE_APPDETAILS_FILE && -f $REMOTE_APPDETAILS_FILE ]]; then
		# 非流式遠端最後上傳 app_details 前再收斂，避免本地後續 jq_inplace/merge 遺留格式漂移。
		_app_details_normalize_restore_profile_file "$REMOTE_APPDETAILS_FILE" || _speed_debug_log "APPDETAILS_REMOTE_FINAL_PRETTY_FAIL file=$REMOTE_APPDETAILS_FILE proto=WebDAV"
		if [[ ! -s $fail_list ]]; then
			let idx++
			local _ad_rel="${REMOTE_APPDETAILS_FILE#$Backup/}"
			local _ad_url="$backup_subdir/$_ad_rel"
			local _ad_http _ad_webdav_rc _ad_webdav_err="$TMPDIR/.webdav_ad_err_$$" _ad_tag
			_ad_tag="$(_remote_debug_seq webdav_upload)"
			_webdav_putrel_atomic_file "$base_root" "$_ad_url" "$REMOTE_APPDETAILS_FILE" "$_ad_tag" "$_ad_webdav_err"
			_ad_webdav_rc=$?
			_ad_http="$_WEBDAV_HTTP_CODE"
			remote_raw_log "remote_webdav_upload_raw.log" "APP_DETAILS_ATOMIC tag=$_ad_tag rc=$_ad_webdav_rc http=$_ad_http rel=$_ad_rel url=$_ad_url"
			remote_raw_cat "remote_webdav_upload_${_ad_tag}.log" "$_ad_webdav_err" "===== WEBDAV_APP_DETAILS $_ad_tag rel=$_ad_rel rc=$_ad_webdav_rc http=$_ad_http ====="
			rm -f "$_ad_webdav_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			case $_ad_http in
			2*)
				echo "$REMOTE_APPDETAILS_FILE" >> "$ok_list"
				echoRgb "[$idx/$idx] ✓ $_ad_rel" "1"
				;;
			*)
				echo "$_ad_rel  (HTTP $_ad_http)" >> "$fail_list"
				echoRgb "[$idx/$idx] ✗ $_ad_rel (HTTP $_ad_http)" "0"
				remote_log "FAIL $proto $_ad_rel HTTP=$_ad_http"
				;;
			esac
		else
			echoRgb "其他文件上傳失敗,跳過 app_details.json" "0"
		fi
	fi
	rm -f "$list_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	upload_summary "$proto" "$ok_list" "$fail_list"
}

# 從 remote_url 解析出 host 和 port (依 remote_type)
# 結果寫到全域變數 REMOTE_HOST 和 REMOTE_PORT
remote_parse_endpoint() {
	REMOTE_HOST=""; REMOTE_PORT=""
	case $remote_type in
	smb)
		local u="${remote_url#smb://}"; u="${u%%/*}"
		REMOTE_HOST="${u%%:*}"; REMOTE_PORT="${u#*:}"; [[ $REMOTE_PORT = $u ]] && REMOTE_PORT=445
		;;
	webdav)
		local u="${remote_url#*://}"; u="${u%%/*}"
		REMOTE_HOST="${u%%:*}"; REMOTE_PORT="${u#*:}"
		if [[ $REMOTE_PORT = $u ]]; then [[ $remote_url = https://* ]] && REMOTE_PORT=443 || REMOTE_PORT=80; fi
		;;
	esac
}
# 計算遠端某路徑 (相對遠端根) 下所有檔案總大小 (bytes), 對齊本地 calc_dir_size 的純檔案字節統計
# 用法: remote_dir_size "Backup_zstd_0/iQIYI"  或  "Backup_zstd_0"
# 依 remote_type 分發 smbclient(recurse ls) / dex WebDavUtil(PROPFIND)
# 一次列出遠端 $1 (相對 share/url 的子目錄) 下所有檔案的相對路徑 (相對 $1), 一行一個
# SMB 用 recurse ls 單連線; WebDAV 用 PROPFIND Depth:infinity 解析 href
remote_list_files() {
	local _path="$1"
	case $remote_type in
	smb)
		# v24.20.14-7.66-6: 非流式 SMB 也必須先解析 share/path。
		# 先前只有流式在 remote_setup() 解析，導致 remote_list_files/remote_dir_size
		# 於非流式備份前快照/增量預掃時 SMB_SHARE 為空，smbclient 只印 Usage，
		# 進而讓增量列表為空並誤判需要全量上傳。
		remote_parse_smb_url
		local _auth
		_auth="$(_smb_auth_args_current)" || { echoRgb "SMB 認證資訊不可用，已停止操作" "0"; return 1; }
		local SMB_OPTS="-t 300 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _pref="$SMB_REM_PATH/$_path"; _pref="${_pref#/}"
		local _p="$_pref"; _p="${_p//\//\\}"
		# recurse ls: stderr 只進 raw log；CP850/橫幅噪音不寫入 stderr.log。
		local _smb_ls_out="$TMPDIR/.smb_ls_out_$$" _smb_ls_err="$TMPDIR/.smb_ls_err_$$"
		command smbclient -g "$SMB_SHARE" $_auth $SMB_OPTS \
			-c "recurse ON; prompt OFF; cd \"$_p\"; ls" >"$_smb_ls_out" 2>"$_smb_ls_err"
		remote_raw_cat "remote_smb_list_raw.log" "$_smb_ls_err" "[SMB_LIST stderr path=$_path]"
		# stderr 已完整寫入 remote_smb_list_raw.log；列表/大小探測屬於非致命診斷，不污染 stderr.log。
		# v24.20.14-7.10：cd 目標不存在時，smbclient 會停在 share 根目錄；若繼續解析 ls，會誤把根目錄內容當成目標目錄。
		# 這會讓冷流式備份的「備份前遠端大小」變成接近舊資料大小，造成「本次備份增加 1KB」之類錯誤顯示。
		if grep -qiE 'NT_STATUS_OBJECT_NAME_NOT_FOUND|NT_STATUS_OBJECT_PATH_NOT_FOUND|ERRbadpath|does not exist|cd .*failed|cd .*NT_STATUS' "$_smb_ls_out" "$_smb_ls_err" 2>/dev/null; then
			_speed_debug_log "REMOTE_SMB_LIST_MISSING path=$_path pref=$_pref"
			rm -f "$_smb_ls_out" "$_smb_ls_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			return 0
		fi
		remote_raw_cat "remote_smb_list_raw.log" "$_smb_ls_out" "[SMB_LIST stdout-g path=$_path]"
		_smb_parse_ls_entries "$_pref" < "$_smb_ls_out" | awk -F'\t' 'index($1,"D")==0 {print $3}' 
		rm -f "$_smb_ls_out" "$_smb_ls_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		;;
	webdav)
		local _wd_list _wd_err="$TMPDIR/.wdav_propfind_list_err_$$" _wd_rc
		local _wurl="${remote_url%/}"
		rm -f "$TMPDIR/.remote_webdav_last_list_ok" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		# v24.20.14-7.12：PROPFIND 404/空目錄屬於可預期情境，不污染 stderr.log；完整 stderr 進 raw log。
		_webdav_status_sidecar_reset
		_wd_list="$(_webdav_dex listrel "$remote_user" "$remote_pass" "$_wurl" "$_path" -1 2>"$_wd_err")"
		_wd_rc=$?
		_webdav_status_sidecar_load || true
		remote_raw_log "remote_webdav_propfind_raw.log" "LIST path=$_path rc=$_wd_rc base=$_wurl"
		remote_raw_cat "remote_webdav_propfind_raw.log" "$_wd_err" "[WEBDAV_LIST stderr path=$_path]"
		if [[ -n $_wd_list ]]; then
			local _wd_out="$TMPDIR/.wdav_propfind_list_out_$$"
			printf '%s\n' "$_wd_list" > "$_wd_out"
			remote_raw_cat "remote_webdav_propfind_raw.log" "$_wd_out" "[WEBDAV_LIST stdout path=$_path]"
			rm -f "$_wd_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		fi
		rm -f "$_wd_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		if [[ $_wd_rc != 0 ]]; then
			_speed_debug_log "REMOTE_WEBDAV_LIST_MISSING_OR_FAIL path=$_path rc=$_wd_rc"
			return 0
		fi
		: > "$TMPDIR/.remote_webdav_last_list_ok"
		# dex list 已輸出 URL 解碼後的絕對路徑 (href.path); 這裡只需切掉 base 前綴、過濾目錄(以 / 結尾)。
		printf '%s\n' "$_wd_list" | awk -v base="$_path" -F'\t' '
			{
				h=$1
				if (h ~ /\/$/) next
				idx=index(h, base"/")
				if (idx==0) next
				print substr(h, idx+length(base)+1)
			}'
		;;
	esac
}
remote_dir_size() {
	local _path="$1"
	case $remote_type in
	smb)
		# v24.20.14-7.66-6: 非流式 SMB 也必須先解析 share/path。
		# 先前只有流式在 remote_setup() 解析，導致 remote_list_files/remote_dir_size
		# 於非流式備份前快照/增量預掃時 SMB_SHARE 為空，smbclient 只印 Usage，
		# 進而讓增量列表為空並誤判需要全量上傳。
		remote_parse_smb_url
		local _auth
		_auth="$(_smb_auth_args_current)" || { echoRgb "SMB 認證資訊不可用，已停止操作" "0"; return 1; }
		local SMB_OPTS="-t 300 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _pref="$SMB_REM_PATH/$_path"; _pref="${_pref#/}"
		local _p="$_pref"; _p="${_p//\//\\}"
		# recurse ls 累加檔案大小；stderr 只進 raw log，避免 CP850 噪音污染 stderr.log。
		local _smb_size_out="$TMPDIR/.smb_size_out_$$" _smb_size_err="$TMPDIR/.smb_size_err_$$"
		command smbclient -g "$SMB_SHARE" $_auth $SMB_OPTS \
			-c "recurse ON; prompt OFF; cd \"$_p\"; ls" >"$_smb_size_out" 2>"$_smb_size_err"
		remote_raw_cat "remote_smb_list_raw.log" "$_smb_size_err" "[SMB_SIZE stderr path=$_path]"
		# stderr 已完整寫入 remote_smb_list_raw.log；列表/大小探測屬於非致命診斷，不污染 stderr.log。
		# v24.20.14-7.10：遠端目標目錄不存在時必須回 0，不能解析 share 根目錄的 ls 輸出。
		if grep -qiE 'NT_STATUS_OBJECT_NAME_NOT_FOUND|NT_STATUS_OBJECT_PATH_NOT_FOUND|ERRbadpath|does not exist|cd .*failed|cd .*NT_STATUS' "$_smb_size_out" "$_smb_size_err" 2>/dev/null; then
			_speed_debug_log "REMOTE_SMB_SIZE_MISSING path=$_path pref=$_pref before=0"
			echo 0
			rm -f "$_smb_size_out" "$_smb_size_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			return 0
		fi
		remote_raw_cat "remote_smb_list_raw.log" "$_smb_size_out" "[SMB_SIZE stdout-g path=$_path]"
		_smb_parse_ls_entries "$_pref" < "$_smb_size_out" | awk -F'\t' 'index($1,"D")==0 {s+=$2} END{print s+0}' 
		rm -f "$_smb_size_out" "$_smb_size_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		;;
	webdav)
		local _wd_list _wd_err="$TMPDIR/.wdav_propfind_size_err_$$" _wd_rc
		local _wurl="${remote_url%/}"
		# v24.20.14-7.12：PROPFIND 404/空目錄回 0，stderr 只進 raw log。
		_webdav_status_sidecar_reset
		_wd_list="$(_webdav_dex listrel "$remote_user" "$remote_pass" "$_wurl" "$_path" -1 2>"$_wd_err")"
		_wd_rc=$?
		_webdav_status_sidecar_load || true
		remote_raw_log "remote_webdav_propfind_raw.log" "SIZE path=$_path rc=$_wd_rc base=$_wurl"
		remote_raw_cat "remote_webdav_propfind_raw.log" "$_wd_err" "[WEBDAV_SIZE stderr path=$_path]"
		if [[ -n $_wd_list ]]; then
			local _wd_out="$TMPDIR/.wdav_propfind_size_out_$$"
			printf '%s\n' "$_wd_list" > "$_wd_out"
			remote_raw_cat "remote_webdav_propfind_raw.log" "$_wd_out" "[WEBDAV_SIZE stdout path=$_path]"
			rm -f "$_wd_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		fi
		rm -f "$_wd_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		if [[ $_wd_rc != 0 ]]; then
			_speed_debug_log "REMOTE_WEBDAV_SIZE_MISSING_OR_FAIL path=$_path rc=$_wd_rc before=0"
			echo 0
			return 0
		fi
		# dex list 每行 "href\tlength"; 累加 length 欄位即目錄總大小。
		printf '%s\n' "$_wd_list" | awk -F'\t' '{s+=$2} END{print s+0}'
		;;
	*)
		echo 0
		;;
	esac
}
# 流式模式: 上傳恢復必要的基礎設施到遠端 (tools/ 目錄、start.sh、restore_settings.conf)
# 294: SMB 真流式流程中的「已落地小檔」批量上傳。
# 大型 tar/zstd 仍走 _stream_upload 的 stdin 真流式；這裡只處理 start.sh/conf/appList/tools 這類本地檔案，
# 目標是把多個小檔從「每檔一次 smbclient」收斂為「每個目錄一個 smbclient batch」。
_stream_upload_smb_local_files_batch() {
	local _list="$1" _label="${2:-local_files}" _subdir _auth SMB_OPTS _base _mkdir_script _groups _line _rel _file
	[[ $remote_type = smb && -s $_list ]] || return 1
	_auth="$(_smb_auth_args_current)" || { echoRgb "SMB 認證資訊不可用，已停止批量上傳" "0"; return 1; }
	SMB_OPTS="-t 300 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
	_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	_base="$SMB_REM_PATH/$_subdir"; _base="${_base#/}"
	_mkdir_script="$TMPDIR/.smb_stream_batch_mkdir_$$"
	_groups="$TMPDIR/.smb_stream_batch_groups_$$"
	rm -rf "$_groups" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	mkdir -p "$_groups" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	: > "$_mkdir_script"
	while IFS='	' read -r _rel _file; do
		[[ -n $_rel && -f $_file ]] || continue
		case $_rel in /*|*../*|../*) _speed_debug_log "SMB_STREAM_BATCH_SKIP_UNSAFE rel=$_rel"; continue ;; esac
		if printf '%s\n' "$_rel" | grep -q '[;"$]' 2>/dev/null; then _speed_debug_log "SMB_STREAM_BATCH_SKIP_UNSAFE rel=$_rel"; continue; fi
		local _remote="${_base:+$_base/}$_rel" _rdir _cur="" _seg _OLDIFS
		_rdir="${_remote%/*}"
		[[ $_rdir = $_remote ]] && _rdir=""
		_OLDIFS="$IFS"; IFS='/'; set -- $_rdir; IFS="$_OLDIFS"
		for _seg; do
			[[ -z $_seg ]] && continue
			if [[ -z $_cur ]]; then _cur="$_seg"; else _cur="$_cur\\$_seg"; fi
			printf 'mkdir "%s"\n' "$_cur" >> "$_mkdir_script"
		done
		local _ldir="${_file%/*}" _fname="${_file##*/}" _rfname="${_rel##*/}" _rdir_bslash="${_rdir//\//\\}"
		[[ -z $_rdir_bslash ]] && _rdir_bslash="\\"
		local _key
		_key="$(printf '%s' "$_rdir_bslash|$_ldir" | md5sum 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{print $1}' | cut -c1-12)"
		[[ -z $_key ]] && _key="$(printf '%s' "$_rdir_bslash|$_ldir" | cksum 2>/dev/null | awk '{print $1}')"
		[[ -n $_key ]] || _key="group"
		if [[ ! -f $_groups/$_key.meta ]]; then
			printf '%s\n%s\n' "$_rdir_bslash" "$_ldir" > "$_groups/$_key.meta"
		fi
		printf '%s\t%s\t%s\n' "$_fname" "$_rfname" "$_rel" >> "$_groups/$_key"
	done < "$_list"
	if [[ -s $_mkdir_script ]]; then
		printf 'exit\n' >> "$_mkdir_script"
		local _mk_out _mk_rc
		_mk_out="$(command smbclient "$SMB_SHARE" $_auth $SMB_OPTS < "$_mkdir_script" 2>&1)"
		_mk_rc=$?
		remote_raw_log "stream_upload.log" "SMB_LOCAL_BATCH_MKDIR label=$_label rc=$_mk_rc list=$_list"
		printf '%s\n' "$_mk_out" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/stream_upload_detail.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		if [[ $_mk_rc != 0 ]] || _smb_output_has_error "$_mk_out"; then
			_speed_debug_log "SMB_LOCAL_BATCH_MKDIR_FAIL label=$_label rc=$_mk_rc"
			rm -rf "$_groups" "$_mkdir_script" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			return 1
		fi
	fi
	local _gf _ok=0 _fail=0 _total=0
	for _gf in "$_groups"/*; do
		[[ -f $_gf && $_gf != *.meta ]] || continue
		local _meta="$_gf.meta" _rdir _ldir _batch _out _rc _tag
		_rdir="$(sed -n 1p "$_meta" 2>/dev/null)"
		_ldir="$(sed -n 2p "$_meta" 2>/dev/null)"
		_batch="$TMPDIR/.smb_stream_batch_$$"
		{
			printf 'cd "%s"\n' "$_rdir"
			printf 'lcd "%s"\n' "$_ldir"
			while IFS='	' read -r _fname _rfname _rel; do
				[[ -n $_fname && -n $_rfname ]] || continue
				printf 'put "%s" "%s"\n' "$_fname" "$_rfname"
			done < "$_gf"
			printf 'exit\n'
		} > "$_batch"
		_tag="$(_remote_debug_seq stream_smb_batch)"
		_out="$(command smbclient "$SMB_SHARE" $_auth $SMB_OPTS < "$_batch" 2>&1)"
		_rc=$?
		local _count
		_count="$(wc -l < "$_gf" 2>/dev/null | tr -d ' ')"
		case $_count in ''|*[!0-9]*) _count=0 ;; esac
		_total=$((_total + _count))
		remote_raw_log "stream_upload.log" "SMB_LOCAL_BATCH tag=$_tag label=$_label rc=$_rc dir=$_rdir local=$_ldir count=$_count"
		{
			echo "===== STREAM_UPLOAD_SMB_LOCAL_BATCH $_tag label=$_label rc=$_rc dir=$_rdir count=$_count ====="
			printf '%s\n' "$_out"
		} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/stream_upload_detail.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		if [[ $_rc != 0 ]] || _smb_output_has_error "$_out"; then
			_fail=$((_fail + _count))
		else
			_ok=$((_ok + _count))
		fi
		rm -f "$_batch" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	done
	rm -rf "$_groups" "$_mkdir_script" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_speed_debug_log "SMB_LOCAL_BATCH_SUMMARY label=$_label total=$_total ok=$_ok fail=$_fail"
	[[ $_total -gt 0 && $_fail -eq 0 ]]
}


_remote_stream_fatal_file() {
	printf '%s\n' "$TMPDIR/.remote_stream_fatal"
}

_remote_stream_fatal_active() {
	[[ -s "$(_remote_stream_fatal_file)" ]]
}

_remote_stream_fatal_reset() {
	local _why="${1:-manual}" _f
	_f="$(_remote_stream_fatal_file)"
	if [[ -e $_f || -e $TMPDIR/.remote_stream_fatal_notice ]]; then
		rm -f "$_f" "$TMPDIR/.remote_stream_fatal_notice" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_speed_debug_log "REMOTE_STREAM_FATAL_RESET reason=$_why"
	fi
}

_remote_stream_mark_fatal() {
	local _rel="${1:-unknown}" _rc="${2:-1}" _http="${3:-0}" _reason="${4:-}" _f
	_f="$(_remote_stream_fatal_file)"
	[[ -s $_f ]] && return 0
	{
		printf 'rel=%s\n' "$_rel"
		printf 'rc=%s\n' "$_rc"
		printf 'http=%s\n' "$_http"
		printf 'reason=%s\n' "$_reason"
		printf 'time=%s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
	} > "$_f" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_speed_debug_log "REMOTE_STREAM_FATAL rel=$_rel rc=$_rc http=$_http reason=$_reason"
	[[ ${remote_type:-} = webdav ]] && _webdav_daemon_stop >/dev/null 2>&1 || true
}

_remote_stream_fatal_summary() {
	local _f
	_f="$(_remote_stream_fatal_file)"
	[[ -s $_f ]] || return 1
	tr '\n' ' ' < "$_f" 2>/dev/null
	return 0
}

_wait_pid_timeout_basic() {
	local _pid="$1" _timeout="${2:-30}" _tag="${3:-child}" _i=0 _rc
	case $_pid in ''|*[!0-9]*) return 125 ;; esac
	case $_timeout in ''|*[!0-9]*) _timeout=30 ;; esac
	while kill -0 "$_pid" 2>/dev/null; do
		if [[ $_i -ge $_timeout ]]; then
			kill -TERM "$_pid" 2>/dev/null
			sleep 1
			kill -0 "$_pid" 2>/dev/null && kill -KILL "$_pid" 2>/dev/null
			wait "$_pid" 2>/dev/null
			_speed_debug_log "WAIT_PID_TIMEOUT_BASIC tag=$_tag pid=$_pid timeout=$_timeout"
			return 124
		fi
		sleep 1
		_i=$((_i + 1))
	done
	wait "$_pid" 2>/dev/null
	_rc=$?
	_speed_debug_log "WAIT_PID_DONE_BASIC tag=$_tag pid=$_pid rc=$_rc elapsed=${_i}s"
	return $_rc
}

_wait_child_timeout_remote() {
	local _pid="$1" _timeout="${2:-30}" _tag="${3:-remote_child}" _rc
	_wait_child_timeout_procwait "$_pid" "$_timeout" "$_tag"
	_rc=$?
	[[ $_rc != 125 ]] && return $_rc
	_wait_pid_timeout_basic "$_pid" "$_timeout" "$_tag"
	return $?
}



_tools_sha_manifest_extract() {
	# 從 tools.sh 內嵌啟動 SHA 表抽出「工具包簽名」。
	# 簽名包含 tools.sh 版本號 + backup_version + tools/ 下工具 SHA 表；tools.sh 自身 hash 不納入，避免自我循環。
	local _file="$1"
	[[ -f $_file ]] || return 1
	awk '
		BEGIN { seen=0; cap=0 }
		/^speedbackup_patch_build=/ {
			v=$0; sub(/^[^=]*=/, "", v); gsub(/"/, "", v); print "__tools_patch_build__ " v
		}
		/^backup_version=/ {
			v=$0; sub(/^[^=]*=/, "", v); gsub(/"/, "", v); print "__backup_version__ " v
		}
		/while read -r file expected_hash; do/ { seen=1 }
		seen && /^done <<EOF[[:space:]]*$/ { cap=1; next }
		cap && /^EOF[[:space:]]*$/ { exit }
		cap && NF==2 {
			h=$2
			if (length(h)==64 && h !~ /[^0-9a-fA-F]/) print $1 " " tolower(h)
		}
	' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sort
}

_remote_tools_signature_matches() {
	# 回傳 0=遠端 tools/ 與本地工具包簽名一致，可跳過；1=遠端缺失/版本不同/無法判定，應上傳本地 tools/。
	local _src_tools_dir="$1" _subdir _remote_rel _local_sig _remote_file _remote_sig _lsha _rsha _dl_rc
	[[ -d $_src_tools_dir && -f $_src_tools_dir/tools.sh ]] || return 1
	_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	[[ -n $_subdir ]] || return 1
	_remote_rel="$_subdir/tools/tools.sh"
	_local_sig="${TMPDIR:-/data/local/tmp}/.tools_sig_local_${$}_$RANDOM"
	_remote_file="${TMPDIR:-/data/local/tmp}/.tools_remote_tools_${$}_$RANDOM.sh"
	_remote_sig="${TMPDIR:-/data/local/tmp}/.tools_sig_remote_${$}_$RANDOM"
	_tools_sha_manifest_extract "$_src_tools_dir/tools.sh" > "$_local_sig"
	if [[ ! -s $_local_sig ]]; then
		_speed_debug_log "REMOTE_TOOLS_SIG_LOCAL_EMPTY dir=$_src_tools_dir"
		rm -f "$_local_sig" "$_remote_file" "$_remote_sig" 2>/dev/null
		return 1
	fi
	_stream_download "$_remote_rel" > "$_remote_file"
	_dl_rc=$?
	if [[ $_dl_rc != 0 || ! -s $_remote_file ]]; then
		_speed_debug_log "REMOTE_TOOLS_SIG_REMOTE_MISSING rel=$_remote_rel rc=$_dl_rc"
		rm -f "$_local_sig" "$_remote_file" "$_remote_sig" 2>/dev/null
		return 1
	fi
	_tools_sha_manifest_extract "$_remote_file" > "$_remote_sig"
	if [[ ! -s $_remote_sig ]]; then
		_speed_debug_log "REMOTE_TOOLS_SIG_REMOTE_EMPTY rel=$_remote_rel"
		rm -f "$_local_sig" "$_remote_file" "$_remote_sig" 2>/dev/null
		return 1
	fi
	_lsha="$(sha256sum "$_local_sig" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{print $1}')"
	_rsha="$(sha256sum "$_remote_sig" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{print $1}')"
	rm -f "$_local_sig" "$_remote_file" "$_remote_sig" 2>/dev/null
	[[ -n $_lsha && $_lsha = "$_rsha" ]]
}

_remote_filter_tools_targets_by_signature() {
	# 非流式上傳清單已包含 Backup/tools/* 時，先比較遠端 tools 簽名：
	# 一致則從清單移除 tools/，不同則保留整包上傳本地版本。
	local _list_file="$1" _src_tools_dir="$2" _prefix _tmp
	[[ -s $_list_file && -d $_src_tools_dir ]] || return 0
	_prefix="$Backup/tools/"
	awk -v p="$_prefix" 'index($0,p)==1 {found=1; exit} END{exit found?0:1}' "$_list_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 0
	if _remote_tools_signature_matches "$_src_tools_dir"; then
		echoRgb "遠端 tools/ 工具包版本一致 (跳過, 省流量)" "2"
		_tmp="${_list_file}.notools.$$"
		awk -v p="$_prefix" 'index($0,p)!=1 {print}' "$_list_file" > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && cat "$_tmp" > "$_list_file"
		rm -f "$_tmp" 2>/dev/null
		_speed_debug_log "REMOTE_TOOLS_SKIP reason=signature_match src=$_src_tools_dir"
	else
		echoRgb "遠端 tools/ 工具包版本不同或無法驗證，將上傳本地 tools/" "3"
		_speed_debug_log "REMOTE_TOOLS_UPLOAD reason=signature_mismatch_or_missing src=$_src_tools_dir"
	fi
}

_stream_upload_webdav_local_files_batch() {
	local _list="$1" _label="${2:-local_files}" _subdir _base _manifest _out _failed_manifest _rc _ok _fail _total _line _rel _file
	[[ $remote_type = webdav && -s $_list ]] || return 1
	_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	_base="${remote_url%/}"
	_manifest="$TMPDIR/.webdav_local_batch_manifest_$$"
	_out="$TMPDIR/.webdav_local_batch_out_$$"
	_failed_manifest="$TMPDIR/.webdav_local_batch_failed_${_label}_$$"
	rm -f "$_failed_manifest" 2>/dev/null
	: > "$_manifest" || return 1
	while IFS='	' read -r _rel _file; do
		[[ -n $_rel && -f $_file ]] || continue
		case $_rel in /*|*../*|../*) _speed_debug_log "WEBDAV_LOCAL_BATCH_SKIP_UNSAFE rel=$_rel"; continue ;; esac
		printf '%s	%s
' "$_rel" "$_file" >> "$_manifest"
	done < "$_list"
	[[ -s $_manifest ]] || { rm -f "$_manifest" "$_out" 2>/dev/null; return 1; }
	_webdav_daemon_ensure || { rm -f "$_manifest" "$_out" 2>/dev/null; return 1; }
	local _batch_pid _batch_timeout
	case $_label in
	wifi) _batch_timeout=20 ;;
	infra) _batch_timeout=90 ;;
	*) _batch_timeout=60 ;;
	esac
	(
		_webdav_putbatchrel "$_base" "$_subdir" "$_manifest" "$_out"
	) &
	_batch_pid=$!
	_wait_child_timeout_remote "$_batch_pid" "$_batch_timeout" "webdav_local_batch_${_label}"
	_rc=$?
	if [[ $_rc = 124 ]]; then
		remote_raw_log "stream_upload.log" "WEBDAV_LOCAL_BATCH_TIMEOUT label=$_label timeout=$_batch_timeout base=$_base subdir=$_subdir"
		_remote_stream_mark_fatal "local_batch/$_label" 124 0 "WebDAV local batch timeout ${_batch_timeout}s"
		_webdav_daemon_stop >/dev/null 2>&1 || true
	fi
	_total="$(awk 'BEGIN{n=0} $1!="SUMMARY"{n++} END{print n+0}' "$_out" 2>/dev/null)"
	_ok="$(awk -F'	' '$4=="OK"{n++} END{print n+0}' "$_out" 2>/dev/null)"
	_fail="$(awk -F'	' '$4!="OK" && $1!="SUMMARY"{n++} END{print n+0}' "$_out" 2>/dev/null)"
	remote_raw_log "stream_upload.log" "WEBDAV_LOCAL_BATCH_SUMMARY label=$_label rc=$_rc http=${_WEBDAV_HTTP_CODE:-0} total=${_total:-0} ok=${_ok:-0} fail=${_fail:-0} base=$_base subdir=$_subdir"
	remote_raw_cat "stream_upload_detail.log" "$_out" "===== STREAM_UPLOAD_WEBDAV_LOCAL_BATCH label=$_label rc=$_rc http=${_WEBDAV_HTTP_CODE:-0} ====="
	if [[ $_rc = 0 && ${_fail:-1} = 0 && ${_ok:-0} -gt 0 && -s $_out ]]; then
		awk -F'	' '$4=="OK"{print $1}' "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _line; do
			[[ -n $_line ]] && _remote_files_note_present "$_line"
		done
	else
		# 320: batch partial 時只把失敗項留給呼叫端 fallback；避免 tools/ 成功 20 個又被逐檔重傳一次，造成收尾一卡一卡與速度下降。
		if [[ -s $_out && -s $_manifest ]]; then
			awk -F'	' '$1!="SUMMARY" && $4!="OK"{print $1}' "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _line; do
				[[ -n $_line ]] || continue
				awk -F'	' -v r="$_line" '$1==r{print; exit}' "$_manifest" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} >> "$_failed_manifest"
			done
		fi
		_speed_debug_log "WEBDAV_LOCAL_BATCH_PARTIAL_NO_REMOTE_FILELIST_NOTE label=$_label rc=$_rc ok=${_ok:-0} fail=${_fail:-0} failed_manifest=$_failed_manifest"
	fi
	rm -f "$_manifest" "$_out" 2>/dev/null
	[[ $_rc = 0 && ${_fail:-1} = 0 && ${_ok:-0} -gt 0 ]]
}

_stream_upload_infra_smb_batch() {
	stream_enabled || return 1
	[[ $remote_type = smb ]] || return 1
	local _stage="$TMPDIR/.stream_stage/.infra" _list="$TMPDIR/.stream_infra_smb_files_$$" _stream_app_list _tf _rel
	mkdir -p "$_stage" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	: > "$_list"
	touch_shell "2" "$_stage/start.sh"
	printf '%s\t%s\n' "start.sh" "$_stage/start.sh" >> "$_list"
	update_Restore_settings_conf > "$_stage/restore_settings.conf"
	printf '%s\t%s\n' "restore_settings.conf" "$_stage/restore_settings.conf" >> "$_list"
	_stream_app_list="${STREAM_APPLIST_PATH:-$MODDIR/appList.txt}"
	[[ -f $_stream_app_list ]] && printf '%s\t%s\n' "appList.txt" "$_stream_app_list" >> "$_list"
	[[ -f $Backup/MT管理器.apk ]] && printf '%s\t%s\n' "MT管理器.apk" "$Backup/MT管理器.apk" >> "$_list"
	if _remote_tools_signature_matches "$MODDIR/tools"; then
		echoRgb "遠端 tools/ 工具包版本一致 (跳過, 省流量)" "2"
	else
		echoRgb "遠端 tools/ 缺失或版本不同，SMB 批量上傳本地工具目錄..." "3"
		find "$MODDIR/tools" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _tf; do
			_rel="tools/${_tf#$MODDIR/tools/}"
			printf '%s\t%s\n' "$_rel" "$_tf"
		done >> "$_list"
	fi
	if _stream_upload_smb_local_files_batch "$_list" infra; then
		echoRgb "SMB 基礎恢復檔案已批量上傳" "1"
		rm -rf "$_stage" "$_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 0
	fi
	_speed_debug_log "SMB_STREAM_INFRA_BATCH_FAIL fallback=per_file"
	rm -f "$_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	return 1
}


_stream_upload_webdav_infra_file_direct() {
	local _rel="$1" _file="$2" _subdir _base _full_rel _wdir _mk_err _mk_rc _mk_http
	local _put_err _put_rc _put_http _stat_err _stat_rc _stat_http
	[[ ${remote_type:-} = webdav && -n $_rel && -f $_file ]] || return 1
	case $_rel in /*|*../*|../*) _speed_debug_log "WEBDAV_INFRA_DIRECT_SKIP_UNSAFE rel=$_rel"; return 1 ;; esac
	_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	_base="${remote_url%/}"
	_full_rel="$_subdir/$_rel"

	_wdir="${_full_rel%/*}"
	if [[ $_wdir != $_full_rel ]]; then
		_mk_err="$TMPDIR/.webdav_infra_mkdir_$$_$RANDOM"
		_webdav_mkdirrel_cached "$remote_user" "$remote_pass" "$_base" "$_wdir" "$_mk_err"
		_mk_rc=$?
		_mk_http="${_WEBDAV_HTTP_CODE:-0}"
		remote_raw_log "stream_upload.log" "WEBDAV_INFRA_DIRECT_MKDIR rel=$_wdir rc=$_mk_rc http=$_mk_http"
		remote_raw_cat "stream_upload_detail.log" "$_mk_err" "===== WEBDAV_INFRA_DIRECT_MKDIR rel=$_wdir rc=$_mk_rc http=$_mk_http ====="
		rm -f "$_mk_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		if [[ $_mk_rc != 0 ]]; then
			_speed_debug_log "WEBDAV_INFRA_DIRECT_MKDIR_FAIL rel=$_wdir rc=$_mk_rc http=$_mk_http reason=${_WEBDAV_ERROR_ZH:-}"
			return 1
		fi
	fi

	_put_err="$TMPDIR/.webdav_infra_put_$$_$RANDOM"
	_webdav_dex putrel "$remote_user" "$remote_pass" "$_base" "$_full_rel" "$_file" > "$_put_err" 2>&1
	_put_rc=$?
	_put_http="${_WEBDAV_HTTP_CODE:-0}"
	remote_raw_log "stream_upload.log" "WEBDAV_INFRA_DIRECT_PUT rel=$_full_rel rc=$_put_rc http=$_put_http file=$_file"
	remote_raw_cat "stream_upload_detail.log" "$_put_err" "===== WEBDAV_INFRA_DIRECT_PUT rel=$_full_rel rc=$_put_rc http=$_put_http ====="
	if [[ $_put_rc != 0 ]]; then
		_speed_debug_log "WEBDAV_INFRA_DIRECT_PUT_FAIL rel=$_full_rel rc=$_put_rc http=$_put_http reason=${_WEBDAV_ERROR_ZH:-}"
		rm -f "$_put_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 1
	fi
	rm -f "$_put_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}

	_stat_err="$TMPDIR/.webdav_infra_stat_$$_$RANDOM"
	_webdav_dex statrel "$remote_user" "$remote_pass" "$_base" "$_full_rel" >/dev/null 2>"$_stat_err"
	_stat_rc=$?
	_stat_http="${_WEBDAV_HTTP_CODE:-0}"
	remote_raw_log "stream_upload.log" "WEBDAV_INFRA_DIRECT_STAT rel=$_full_rel rc=$_stat_rc http=$_stat_http"
	remote_raw_cat "stream_upload_detail.log" "$_stat_err" "===== WEBDAV_INFRA_DIRECT_STAT rel=$_full_rel rc=$_stat_rc http=$_stat_http ====="
	rm -f "$_stat_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [[ $_stat_rc = 0 ]]; then
		_remote_files_note_present "$_rel"
		return 0
	fi
	return 1
}

# 讓遠端備份能獨立恢復 (功能8 檢查這些, 功能10 流式恢復需要)
# tools/ 較大(數十 MB 二進制), 遠端已有就跳過; start.sh/conf 小, 每次重傳確保最新
stream_upload_infra() {
	stream_enabled || { _speed_debug_log "STREAM_INFRA_SKIP reason=remote_disabled"; return 0; }
	if [[ $remote_type = smb ]]; then
		_stream_upload_infra_smb_batch && return 0
	fi
	if [[ $remote_type = webdav ]]; then
		local _stage_b="$TMPDIR/.stream_stage/.infra" _list_b="$TMPDIR/.stream_infra_webdav_files_$$" _stream_app_list_b _tf_b _rel_b
		mkdir -p "$_stage_b" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		: > "$_list_b" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		touch_shell "2" "$_stage_b/start.sh"
		printf '%s	%s
' "start.sh" "$_stage_b/start.sh" >> "$_list_b"
		update_Restore_settings_conf > "$_stage_b/restore_settings.conf"
		printf '%s	%s
' "restore_settings.conf" "$_stage_b/restore_settings.conf" >> "$_list_b"
		_stream_app_list_b="${STREAM_APPLIST_PATH:-$MODDIR/appList.txt}"
		[[ -f $_stream_app_list_b ]] && printf '%s	%s
' "appList.txt" "$_stream_app_list_b" >> "$_list_b"
		[[ -f $Backup/MT管理器.apk ]] && printf '%s	%s
' "MT管理器.apk" "$Backup/MT管理器.apk" >> "$_list_b"
		if _remote_tools_signature_matches "$MODDIR/tools"; then
			echoRgb "遠端 tools/ 工具包版本一致 (跳過, 省流量)" "2"
		else
			echoRgb "遠端 tools/ 缺失或版本不同，WebDAV daemon 上傳本地工具目錄..." "3"
			find "$MODDIR/tools" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _tf_b; do
				_rel_b="tools/${_tf_b#$MODDIR/tools/}"
				printf '%s	%s
' "$_rel_b" "$_tf_b"
			done >> "$_list_b"
		fi
		# 342: rclone WebDAV 對大型 infra putbatchrel 可能在 daemon stderr 留 Broken pipe。
		# 352: 123pan/openresty 對根層 infra 檔案的 atomic MOVE 可能回 HTTP 500；
		# infra/start.sh/conf/appList/tools 是收尾恢復輔助檔，不需要 atomic publish。
		# 改用 rel-only putrel 直接覆寫並 statrel 驗證，避免把主備份成功後的 infra MOVE 500 標成 fatal。
		_speed_debug_log "WEBDAV_STREAM_INFRA_BATCH_SKIP reason=avoid_large_putbatchrel_broken_pipe fallback=direct_putrel"
		local _infra_total_b=0 _infra_ok_b=0 _infra_fail_b=0 _tools_total_b=0 _tools_fail_b=0
		while IFS='	' read -r _rel_b _tf_b; do
			[[ -n $_rel_b && -f $_tf_b ]] || continue
			_infra_total_b=$((_infra_total_b + 1))
			case $_rel_b in tools/*) _tools_total_b=$((_tools_total_b + 1)) ;; esac
			if _stream_upload_webdav_infra_file_direct "$_rel_b" "$_tf_b"; then
				_infra_ok_b=$((_infra_ok_b + 1))
				case $_rel_b in
				start.sh|restore_settings.conf|appList.txt|MT管理器.apk) echoRgb "$_rel_b 已上傳遠端" "1" ;;
				esac
			else
				_infra_fail_b=$((_infra_fail_b + 1))
				case $_rel_b in tools/*) _tools_fail_b=$((_tools_fail_b + 1)) ;; esac
				case $_rel_b in
				start.sh|restore_settings.conf|appList.txt|MT管理器.apk) echoRgb "$_rel_b 上傳失敗" "0" ;;
				esac
			fi
		done < "$_list_b"
		[[ $_tools_total_b -gt 0 && $_tools_fail_b -eq 0 ]] && echoRgb "tools/ 已上傳遠端" "1"
		[[ $_tools_total_b -gt 0 && $_tools_fail_b -gt 0 ]] && echoRgb "tools/ 部分上傳失敗 ($_tools_fail_b/$_tools_total_b)" "0"
		_speed_debug_log "WEBDAV_STREAM_INFRA_DIRECT_SUMMARY total=$_infra_total_b ok=$_infra_ok_b fail=$_infra_fail_b tools_total=$_tools_total_b tools_fail=$_tools_fail_b"
		rm -rf "$_stage_b" "$_list_b" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		[[ $_infra_fail_b -eq 0 ]]
		return $?
	fi
	local _stage="$TMPDIR/.stream_stage/.infra"
	mkdir -p "$_stage" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# 1. start.sh (恢復模式入口, touch_shell "2")
	touch_shell "2" "$_stage/start.sh"
	_stream_upload "start.sh" < "$_stage/start.sh" && echoRgb "start.sh 已上傳遠端" "1" || echoRgb "start.sh 上傳失敗" "0"
	# 2. restore_settings.conf
	update_Restore_settings_conf > "$_stage/restore_settings.conf"
	_stream_upload "restore_settings.conf" < "$_stage/restore_settings.conf" && echoRgb "restore_settings.conf 已上傳遠端" "1" || echoRgb "restore_settings.conf 上傳失敗" "0"
		# 3. appList.txt (功能8/恢復需要應用清單)
		# 批量真流式時優先上傳本輪 staging 清單；若尚未產生才退回原始 MODDIR/appList.txt。
		local _stream_app_list="${STREAM_APPLIST_PATH:-$MODDIR/appList.txt}"
		if [[ -f $_stream_app_list ]]; then
			_stream_upload "appList.txt" < "$_stream_app_list" && echoRgb "appList.txt 已上傳遠端" "1" || echoRgb "appList.txt 上傳失敗" "0"
		fi
	# 3b. MT管理器.apk (恢復時安裝用, 對齊非流式上傳清單)
	if [[ -f $Backup/MT管理器.apk ]]; then
		_stream_upload "MT管理器.apk" < "$Backup/MT管理器.apk" && echoRgb "MT管理器.apk 已上傳遠端" "1" || echoRgb "MT管理器.apk 上傳失敗" "0"
	fi
	# 4. tools/ 目錄: 直接使用本輪已取得的遠端總列表判斷。
	# 不再用「_stream_download | head -c 30」探測：head 讀滿後會提早關閉 pipe，
	# Dex 仍在串流完整 tools.sh 時會得到預期性 Broken pipe，污染 daemon stderr。
	# .remote_files 在流式備份預掃時已建立，條目相對於 Backup_zstd_X 根目錄。
	if _remote_tools_signature_matches "$MODDIR/tools"; then
		echoRgb "遠端 tools/ 工具包版本一致 (跳過, 省流量)" "2"
	else
		echoRgb "遠端 tools/ 缺失或版本不同，上傳本地工具目錄..." "3"
		local _tf _rel
		find "$MODDIR/tools" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _tf; do
			_rel="tools/${_tf#$MODDIR/tools/}"
			_stream_upload "$_rel" < "$_tf"
		done
		echoRgb "tools/ 已上傳遠端" "1"
	fi
	rm -rf "$_stage" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_stream_upload_rel_is_metadata() {
	case "$1" in
	*/app_details.json|*/recover.sh|*/backup.sh|*/upload.sh|start.sh|restore_settings.conf|appList.txt|mediaList.txt|wifi/*|tools/*) return 0 ;;
	*) return 1 ;;
	esac
}

# 通用流式上傳: 從 stdin 讀資料, 上傳到遠端 (相對遠端根的) 路徑
# 依 remote_type 分發到 smbclient / dex WebDavUtil(webdav)
# 用法: <資料來源> | _stream_upload "相對路徑/file.tar.zst"
# 回傳: 0=成功
_stream_upload() {
	local _rel="$1"
	remote_enabled || { remote_log "STREAM_UPLOAD_SKIP remote_disabled rel=$_rel"; return 1; }
	if _remote_stream_fatal_active; then
		remote_raw_log "stream_upload.log" "SKIP type=${remote_type:-unknown} rel=$_rel reason=remote_stream_fatal $(_remote_stream_fatal_summary)"
		[[ -f $TMPDIR/.remote_stream_fatal_notice ]] || {
			echoRgb "本輪遠端流式已失敗，略過後續遠端上傳，避免網路中斷後卡住" "0" >&2
			: > "$TMPDIR/.remote_stream_fatal_notice" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		}
		return 1
	fi
	# 加上備份子目錄前綴 (Backup_zstd_X), 與 remote_download_single_file 路徑一致, 確保增量比對找得到
	# 用快取值 (_BACKUP_DIRNAME_CACHED, 在 backup()/backup_media() 開頭固定一次) 而非即時呼叫,
	# 因為 Backup_data() 內部對非 user/data/obb/user_de/media 類型資料 (如自訂資料夾) 會暫時
	# 把全域 Compression_method 改成 tar 再復原, 若流式上傳剛好在這段窗口期觸發, 即時呼叫
	# get_backup_dirname() 會拿到被污染的值, 導致上傳到錯誤的子資料夾 (如 Backup_tar_0 而非 Backup_zstd_0)
	local _subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	_rel="$_subdir/$_rel"
	local _stream_tag _stream_start
	_stream_tag="$(_remote_debug_seq stream_upload)"
	_stream_start=$(date +%s)
	remote_raw_log "stream_upload.log" "BEGIN tag=$_stream_tag type=$remote_type rel=$_rel"
	case $remote_type in
	smb)
		# SMB 流式: 用 cd 切目錄 (對齊既有成功的 upload_smb, -D 會吃掉路徑字元) + put - 從 stdin
		local _auth
		_auth="$(_smb_auth_args_current)" || { echoRgb "SMB 認證資訊不可用，已停止操作" "0"; return 1; }
		local SMB_OPTS="-t 300 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _smbpath="$SMB_REM_PATH/$_rel"; _smbpath="${_smbpath#/}"
		local _smbdir="${_smbpath%/*}" _file="${_smbpath##*/}"
		# 1. 先逐層建目錄 (smbclient 內部路徑用反斜線)
		if [[ $_smbdir != $_smbpath ]]; then
			local _mk="" _cur="" _seg _OLDIFS="$IFS"
			IFS='/'; set -- $_smbdir; IFS="$_OLDIFS"
			for _seg; do
				[[ -z $_seg ]] && continue
				if [[ -z $_cur ]]; then _cur="$_seg"; else _cur="$_cur\\$_seg"; fi
				# smbclient stdin 餵命令必須一行一條 (分號在 stdin 模式不是分隔符),
				# 故字串內嵌真換行 (下一行的 " 是字串收尾, 非贅字)
				_mk="${_mk}mkdir \"$_cur\"
"
			done
			local _mk_out _mk_rc
			_mk_out="$(printf '%sexit\n' "$_mk" | command smbclient "$SMB_SHARE" $_auth $SMB_OPTS 2>&1)"
			_mk_rc=$?
			remote_raw_log "stream_upload.log" "SMB_MKDIR tag=$_stream_tag rc=$_mk_rc dir=$_smbdir"
			printf '%s\n' "$_mk_out" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/stream_upload_detail.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			if [[ $_mk_rc != 0 ]] || _smb_output_has_error "$_mk_out"; then
				local _elapsed_mk=$(( $(date +%s) - _stream_start ))
				remote_raw_log "stream_upload.log" "END tag=$_stream_tag type=smb rc=1 cmd_rc=$_mk_rc elapsed=${_elapsed_mk}s rel=$_rel dir=$_smbdir file=${_rel##*/} stage=mkdir"
				echoRgb "[SMB流式失敗] 建立遠端目錄失敗 dir=$_smbdir" "0" >&2
				printf '%s\n' "$_mk_out" | sed -E 's#://[^/@[:space:]]+:[^/@[:space:]]+@#://[REDACTED]@#g; s/(password[[:space:]]*=[[:space:]]*).*/\1[REDACTED]/I; s/^/  /' >&2
				return 1
			fi
		fi
		# 2. 流式 put -: 用 -c 傳命令 (不佔 stdin!), stdin 留給 put - 讀管道資料
		#    (之前用 printf|smbclient 喂命令會佔住 stdin, 導致 put - 讀不到資料寫出 0KB)
		local _cddir="${_smbdir//\//\\}"
		local _out _cmd_rc
		if ! _smb_safe_component "$_cddir" || ! _smb_safe_component "$_file"; then
			echoRgb "偵測到不安全的路徑字元, 拒絕流式上傳: $_file" "0" >&2
			return 1
		fi
		_out="$(command smbclient "$SMB_SHARE" $_auth $SMB_OPTS \
			-c "cd \"$_cddir\"; put - \"$_file\"" 2>&1)"
		_cmd_rc=$?
		# smbclient 退出碼不可靠, 改看輸出有無錯誤關鍵字
		local _rc=0
		_smb_output_has_error "$_out" && _rc=1
		local _elapsed=$(( $(date +%s) - _stream_start ))
		remote_raw_log "stream_upload.log" "END tag=$_stream_tag type=smb rc=$_rc cmd_rc=$_cmd_rc elapsed=${_elapsed}s rel=$_rel dir=$_cddir file=$_file"
		{
			echo "===== STREAM_UPLOAD_SMB $_stream_tag rel=$_rel rc=$_rc cmd_rc=$_cmd_rc elapsed=${_elapsed}s ====="
			printf '%s\n' "$_out"
		} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/stream_upload_detail.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		if [[ $_rc != 0 ]]; then
			echoRgb "[SMB流式失敗] dir=$_cddir file=$_file" "0" >&2
			echo "$_out" | sed -E 's#://[^/@[:space:]]+:[^/@[:space:]]+@#://[REDACTED]@#g; s/(password[[:space:]]*=[[:space:]]*).*/\1[REDACTED]/I; s/^/  /' >&2
		fi
		return $_rc
		;;
	webdav)
		# WebDAV: tools 只傳 baseUrl + raw relPath；URL 編碼與 raw UTF-8 fallback 由 dex HttpCore 統一處理。
		local _wbase="${remote_url%/}"
		# 340: 目錄建立直接走 statrel + mkdirrel 逐層建立，不再先呼叫 Dex mkdirsrel。
		local _wdir="${_rel%/*}"
		if [[ $_wdir != $_rel ]]; then
			local _su_mk_err="$TMPDIR/.stream_mkdirs_err_${_stream_tag}_$$" _su_mk_http _su_mk_rc
			_webdav_mkdirrel_cached "$remote_user" "$remote_pass" "$_wbase" "$_wdir" "$_su_mk_err"
			_su_mk_rc=$?
			_su_mk_http="$_WEBDAV_HTTP_CODE"
			remote_raw_log "stream_upload.log" "WEBDAV_MKDIRS tag=$_stream_tag rc=$_su_mk_rc http=$_su_mk_http rel=$_wdir"
			remote_raw_cat "stream_upload_detail.log" "$_su_mk_err" "[STREAM_UPLOAD_WEBDAV_MKDIRS stderr]"
			if [[ $_su_mk_rc != 0 ]]; then
				local _elapsed_mkdir=$(( $(date +%s) - _stream_start ))
				remote_raw_log "stream_upload.log" "END tag=$_stream_tag type=webdav rc=1 http=$_su_mk_http elapsed=${_elapsed_mkdir}s rel=$_rel stage=mkdir dir=$_wdir"
				_remote_stream_mark_fatal "$_rel" "$_su_mk_rc" "$_su_mk_http" "${_WEBDAV_ERROR_ZH:-WebDAV 建立遠端目錄失敗：statrel/mkdirrel 均未確認 collection 存在}"
				echoRgb "[WebDAV建立遠端目錄失敗 rc=$_su_mk_rc http=$_su_mk_http] rel=$_wdir" "0" >&2
				[[ -n ${_WEBDAV_ERROR_ZH:-} ]] && echoRgb "原因: $_WEBDAV_ERROR_ZH" "0" >&2
				rm -f "$_su_mk_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				return 1
			fi
			rm -f "$_su_mk_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		fi
		local _httpcode _stream_err="$TMPDIR/.stream_err_${_stream_tag}_$$" _put_cmd _rc
		_put_cmd="${WEBDAV_STREAM_UPLOAD_CMD:-putstdinmanagedrel}"
		if [[ $_put_cmd != putstdinmanagedrel ]]; then
			echoRgb "WebDAV 流式拒絕非 Dex managed 真流式上傳命令: $_put_cmd" "0" >&2
			remote_raw_log "stream_upload.log" "ABORT tag=$_stream_tag type=webdav reason=non_managed_stream cmd=$_put_cmd rel=$_rel"
			return 1
		fi

		# 379: WebDAV direct/atomic 決策搬進 Dex WebDavUtil。
		# shell 不再判斷 rclone，不再自行產生 .part/moverel；只把 stdin 與 rel 交給 putstdinmanagedrel。
		_webdav_dex putstdinmanagedrel "$remote_user" "$remote_pass" "$_wbase" "$_rel" auto 2>"$_stream_err"
		_rc=$?
		_httpcode="$_WEBDAV_HTTP_CODE"
		local _elapsed=$(( $(date +%s) - _stream_start ))
		remote_raw_log "stream_upload.log" "END tag=$_stream_tag type=webdav cmd=$_put_cmd managed=1 rc=$_rc http=$_httpcode elapsed=${_elapsed}s rel=$_rel base=$_wbase"
		if [[ $_rc = 0 ]]; then
			_remote_files_note_present "${_rel#$_subdir/}"
		fi
		remote_raw_cat "stream_upload_detail.log" "$_stream_err" "===== STREAM_UPLOAD_WEBDAV_MANAGED $_stream_tag rel=$_rel rc=$_rc http=$_httpcode elapsed=${_elapsed}s ====="
		if [[ $_rc != 0 ]]; then
			if _stream_upload_rel_is_metadata "${_rel#$_subdir/}"; then
				_speed_debug_log "REMOTE_STREAM_METADATA_FAIL_NONFATAL rel=$_rel rc=$_rc http=$_httpcode reason=${_WEBDAV_ERROR_ZH:-WebDAV managed metadata upload failed}"
			else
				_remote_stream_mark_fatal "$_rel" "$_rc" "$_httpcode" "${_WEBDAV_ERROR_ZH:-WebDAV managed stream upload failed}"
			fi
			echoRgb "[WebDAV managed流式失敗 rc=$_rc http=$_httpcode] rel=$_rel" "0" >&2
			[[ -n ${_WEBDAV_ERROR_ZH:-} ]] && echoRgb "原因: $_WEBDAV_ERROR_ZH" "0" >&2
			sed -E 's#://[^/@[:space:]]+:[^/@[:space:]]+@#://[REDACTED]@#g; s/(password[[:space:]]*=[[:space:]]*).*/[REDACTED]/I; s/^/  /' "$_stream_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} >&2
		fi
		rm -f "$_stream_err"
		return $_rc
		;;
	*)
		return 1
		;;
	esac
}

# 通用流式下載: 把遠端 (相對遠端根的) 路徑檔案輸出到 stdout
# 依 remote_type 分發 smbclient(get -) / dex WebDavUtil. 配合管道解壓: _stream_download "路徑" | zstd -d | tar -x
_stream_download() {
	local _rel="$1"
	local _stream_tag _stream_start
	_stream_tag="$(_remote_debug_seq stream_download)"
	_stream_start=$(date +%s)
	remote_raw_log "stream_download.log" "BEGIN tag=$_stream_tag type=$remote_type rel=$_rel"
	case $remote_type in
	smb)
		local _auth
		_auth="$(_smb_auth_args_current)" || { echoRgb "SMB 認證資訊不可用，已停止操作" "0"; return 1; }
		local SMB_OPTS="-t 300 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _smbpath="$SMB_REM_PATH/$_rel"; _smbpath="${_smbpath#/}"
		local _smbdir="${_smbpath%/*}" _file="${_smbpath##*/}"
		local _cddir="${_smbdir//\//\\}"
		# get "檔" - : 輸出到 stdout；stderr 另存 raw log 後再轉回 stderr，避免污染資料流。
		local _sd_err="$TMPDIR/.stream_download_err_$$" _sd_rc _sd_elapsed
		if ! _smb_safe_component "$_cddir" || ! _smb_safe_component "$_file"; then
			echoRgb "偵測到不安全的路徑字元, 拒絕流式下載: $_file" "0" >&2
			return 1
		fi
		command smbclient "$SMB_SHARE" $_auth $SMB_OPTS \
			-c "cd \"$_cddir\"; get \"$_file\" -" 2>"$_sd_err"
		_sd_rc=$?
		_sd_elapsed=$(( $(date +%s) - _stream_start ))
		remote_raw_log "stream_download.log" "END tag=$_stream_tag type=smb rc=$_sd_rc elapsed=${_sd_elapsed}s rel=$_rel dir=$_cddir file=$_file"
		remote_raw_cat "stream_download_detail.log" "$_sd_err" "===== STREAM_DOWNLOAD_SMB $_stream_tag rel=$_rel rc=$_sd_rc elapsed=${_sd_elapsed}s ====="
		grep -Ev '^dos charset|^Can.t load|^Domain=|^OS=|^Try "help"|^getting file |^putting file |^$' "$_sd_err" >&2 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		rm -f "$_sd_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return $_sd_rc
		;;
	webdav)
		local _wd_err="$TMPDIR/.stream_download_err_${_stream_tag}_$$" _wd_rc _wd_elapsed _wd_http _wd_base
		# AF_UNIX daemon + unixsock v2 會把兩行 protocol header 寫到 sidecar，body 直接串到 stdout；
		# 若 daemon/relay 不可用，_webdav_dex 會直接失敗，避免熱路徑回退單次 app_process。
		_wd_base="${remote_url%/}"
		_webdav_dex getstdoutrel "$remote_user" "$remote_pass" "$_wd_base" "$_rel" 2>"$_wd_err"
		_wd_rc=$?
		_wd_http="${_WEBDAV_HTTP_CODE:-0}"
		_wd_elapsed=$(( $(date +%s) - _stream_start ))
		remote_raw_log "stream_download.log" "END tag=$_stream_tag type=webdav rc=$_wd_rc http=${_wd_http:-0} elapsed=${_wd_elapsed}s rel=$_rel base=$_wd_base"
		remote_raw_cat "stream_download_detail.log" "$_wd_err" "===== STREAM_DOWNLOAD_WEBDAV $_stream_tag rel=$_rel rc=$_wd_rc http=${_wd_http:-0} elapsed=${_wd_elapsed}s ====="
		# app_details / tools 探測 404、以及 head 提前關管線，都屬於預期非致命；只寫 raw log，不污染 stderr.log。
		if [[ $_wd_rc != 0 ]]; then
			case "$_wd_http:$_rel:$_wd_rc" in
			404:*app_details.json:*|404:*/tools/tools.sh:*|*:*/tools/tools.sh:18|*:*/tools/tools.sh:22|*:*/tools/tools.sh:23|*:*:18|*:*:22|*:*:23)
				_speed_debug_log "WEBDAV_STREAM_DOWNLOAD_EXPECTED_NONFATAL rel=$_rel rc=$_wd_rc http=${_wd_http:-0}"
				;;
			*)
				cat "$_wd_err" >&2 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				;;
			esac
		fi
		rm -f "$_wd_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return $_wd_rc
		;;
	*)
		return 1
		;;
	esac
}

# 解析 SMB URL 並設定 SMB_SHARE / SMB_REM_PATH 全域變數
# SMB_SHARE     = //server/share_name (smbclient -L 用)
# SMB_REM_PATH  = /sub/path (空字串代表 share 根目錄, 不含結尾斜線)
# 重複的 SMB URL 解析邏輯抽出 (原本有 4 個地方各自解析)
remote_parse_smb_url() {
	local url="${remote_url#smb://}"; url="${url%/}"
	local server="${url%%/*}"
	local after_server="${url#$server/}"
	local share_name="${after_server%%/*}"
	# after_server 去掉 share_name 後可能是 "" 或 "/path/..."
	# 直接用結果, 不再前綴 "/", 否則 "/path" 會變 "//path"
	local rem_path="${after_server#$share_name}"
	rem_path="${rem_path%/}"
	[[ $rem_path = / ]] && rem_path=""
	SMB_SHARE="//$server/$share_name"
	SMB_REM_PATH="$rem_path"
}


_smb_trim_value() {
	# mksh 相容：去掉常見設定檔殘留空白/CR/TAB，避免把空白誤判成帳號。
	printf '%s' "${1:-}" | tr -d '
' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

_smb_ensure_authfile() {
	# SMB 有帳號時一律用臨時 credentials file，即使密碼為空字串也要建立。
	# 這避免 remote_user 已設定但 _SMB_AUTHFILE 因初始化時機/TMPDIR 清理而不存在時，誤報「認證檔不存在」。
	local _u _auth_dir
	_u="$(_smb_trim_value "${remote_user:-}")"
	[[ -n $_u ]] || return 1
	if [[ -n ${_SMB_AUTHFILE:-} && -f "$_SMB_AUTHFILE" ]]; then
		return 0
	fi
	_auth_dir="${TMPDIR:-/data/local/tmp}"
	mkdir -p "$_auth_dir" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_SMB_AUTHFILE="$_auth_dir/.smb_authfile_$$"
	{
		printf 'username = %s\n' "$_u"
		printf 'password = %s\n' "${remote_pass:-}"
	} > "$_SMB_AUTHFILE" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	chmod 0600 "$_SMB_AUTHFILE" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	return 0
}

_smb_auth_args_current() {
	# 無帳號：匿名/Guest；有帳號：惰性建立 credentials file。
	# 不再把「密碼未設」等同於「不能測試」；空密碼帳號會寫入 password = 空字串。
	if [[ -n "$(_smb_trim_value "${remote_user:-}")" ]]; then
		if _smb_ensure_authfile; then
			printf '%s\n' "-A $_SMB_AUTHFILE"
			return 0
		fi
		return 1
	fi
	printf '%s\n' "-N"
	return 0
}

_smb_protocol_from_debug() {
	local _dbg="$1" _proto=""
	[[ -s $_dbg ]] || return 1
	_proto="$(grep -aioE 'selected protocol[^A-Za-z0-9_]*(SMB[0-9](_[0-9]{2})?|SMB[0-9]_[0-9]{2}|NT1)|negotiated dialect[^A-Za-z0-9_]*(SMB[0-9](_[0-9]{2})?|SMB[0-9]_[0-9]{2}|NT1)|protocol[^\n\r]*(SMB[0-9]_[0-9]{2}|SMB[0-9]|NT1)[^\n\r]*(selected|negotiated)' "$_dbg" 2>/dev/null | grep -aioE 'SMB[0-9]_[0-9]{2}|SMB[0-9]|NT1' | tail -1)"
	[[ -n $_proto ]] || _proto="$(grep -aioE 'SMB3_11|SMB3_02|SMB3_00|SMB2_10|SMB2_02|SMB3|SMB2|NT1' "$_dbg" 2>/dev/null | tail -1)"
	[[ -n $_proto ]] || return 1
	printf '%s\n' "$_proto"
	return 0
}

_smb_probe_one_dialect() {
	local _share="$1" _auth="$2" _dialect="$3" _rem_path="${4:-}" _dbg="$5" _out _rc _cmd
	_cmd="cd ${_rem_path:-/}; exit"
	_out="$(command smbclient "$_share" $_auth -t 5 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} \
		--option="client min protocol=$_dialect" --option="client max protocol=$_dialect" \
		-c "$_cmd" 2>&1)"
	_rc=$?
	{
		echo "===== SMB_FORCE_DIALECT $_dialect rc=$_rc ====="
		printf '%s\n' "$_out"
	} >> "$_dbg" 2>/dev/null
	[[ $_rc = 0 ]] || return 1
	printf '%s\n' "$_out" | grep -qiE 'protocol negotiation failed|NT_STATUS_INVALID_NETWORK_RESPONSE|NT_STATUS_NOT_SUPPORTED|NT_STATUS_CONNECTION_DISCONNECTED|NT_STATUS_LOGON_FAILURE|NT_STATUS_ACCESS_DENIED' && return 1
	return 0
}

_smb_detect_protocol_version() {
	local _share="$1" _auth="$2" _rem_path="${3:-}" _dbg
	_dbg="$(_speed_debug_log_path smb_protocol_debug.log)"
	: > "$_dbg" 2>/dev/null
	{
		echo "===== SMB_PROTOCOL_DETECT $(date '+%Y-%m-%d %H:%M:%S') ====="
		echo "share=$_share rem_path=${_rem_path:-/} port=${REMOTE_PORT:-default}"
		echo "method=debug-parse"
	} >> "$_dbg" 2>/dev/null
	command smbclient "$_share" $_auth -t 5 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3 -d 10 \
		-c 'exit' >>"$_dbg" 2>&1
	local _proto
	_proto="$(_smb_protocol_from_debug "$_dbg")"
	if [[ -n $_proto ]]; then
		echoRgb "協議版本: $_proto" "1"
		return 0
	fi
	{
		echo ""
		echo "method=forced-dialect-probe"
	} >> "$_dbg" 2>/dev/null
	local _d
	for _d in SMB3_11 SMB3_02 SMB3_00 SMB2_10 SMB2_02 NT1; do
		if _smb_probe_one_dialect "$_share" "$_auth" "$_d" "$_rem_path" "$_dbg"; then
			echoRgb "協議版本: $_d (最高可用)" "1"
			return 0
		fi
	done
	echoRgb "無法解析協議版本，debug 已寫入 speed_debug: smb_protocol_debug.log" "2"
	return 1
}

_webdav_http_reason() {
	case "${1:-0}" in
	0|000) echo "未收到 HTTP 回應：可能是 DNS/路由/防火牆、TLS 握手失敗、daemon 無回應或連線被中斷" ;;
	200|201|204|207) echo "請求成功" ;;
	301|302|303|307|308) echo "伺服器要求重定向：remote_url 可能不是 WebDAV 真實端點" ;;
	400) echo "請求格式錯誤：URL 或 WebDAV path 可能含不合法字元" ;;
	401) echo "認證失敗：帳號或密碼錯誤" ;;
	403) echo "權限不足：帳號可登入但沒有此路徑讀寫權限" ;;
	404) echo "路徑不存在：remote_url/base path 或備份目錄不存在" ;;
	405) echo "方法不允許：此 URL 可能不是 WebDAV 端點，或伺服器不允許 PROPFIND/PUT" ;;
	408) echo "請求逾時：伺服器忙碌或網路延遲過高" ;;
	409) echo "父目錄不存在：需要先建立上層 WebDAV 目錄" ;;
	413) echo "檔案過大：伺服器限制單檔大小或反向代理限制 body size" ;;
	415) echo "伺服器不接受目前上傳格式" ;;
	423) echo "資源被鎖定：可能有其他客戶端正在寫入" ;;
	429) echo "請求過於頻繁：觸發伺服器限流" ;;
	500) echo "伺服器內部錯誤" ;;
	501) echo "伺服器不支援此 WebDAV 方法" ;;
	502) echo "閘道錯誤：反向代理或上游服務異常" ;;
	503) echo "服務不可用：伺服器維護、過載或 WebDAV 服務未啟動" ;;
	504) echo "閘道逾時：反向代理等待上游逾時" ;;
	507) echo "遠端空間不足或配額已滿" ;;
	*) echo "WebDAV/HTTP 異常：HTTP $1" ;;
	esac
}

_webdav_stderr_reason() {
	local _err="$1"
	case "$_err" in
	*UnknownHostException*|*Could\ not\ resolve\ host*|*Couldn*resolve*host*) echo "DNS 解析失敗：域名不存在、DNS 不通或代理未生效" ;;
	*ConnectException*Connection\ refused*|*Connection\ refused*) echo "連線被拒：IP 可達但端口未開，或防火牆拒絕" ;;
	*NoRouteToHostException*|*Network\ is\ unreachable*|*Host\ is\ unreachable*) echo "網路不可達：不在同網段、路由錯誤或防火牆阻擋" ;;
	*SocketTimeoutException*|*timed\ out*|*timeout*) echo "連線或讀寫逾時：伺服器太慢或網路不穩" ;;
	*SSLHandshakeException*|*certificate*|*Hostname\ verification\ failed*) echo "TLS/憑證驗證失敗：自簽、過期、域名不匹配或 http/https 寫錯" ;;
	*WRONG_VERSION_NUMBER*|*wrong\ version\ number*) echo "協議與端口不匹配：可能把 https 寫到 http 端口，或反過來" ;;
	*EOFException*empty\ HTTP\ response*|*Empty\ reply*) echo "伺服器提前關閉連線，沒有回 HTTP 回應" ;;
	*unexpected\ EOF*) echo "傳輸中斷：下載/上傳途中連線被關閉" ;;
	*HttpCore\ client\ is\ closing*) echo "WebDAV daemon 正在關閉，請重試" ;;
	*) return 1 ;;
	esac
	return 0
}

_webdav_set_error_zh() {
	local _code="${1:-0}" _err="${2:-}"
	_WEBDAV_ERROR_ZH="$(_webdav_stderr_reason "$_err" 2>/dev/null || true)"
	[[ -n $_WEBDAV_ERROR_ZH ]] || _WEBDAV_ERROR_ZH="$(_webdav_http_reason "$_code")"
	return 0
}


_remote_files_note_present() {
	local _rel="$1" _tmp
	[[ -n $_rel ]] || return 0
	case $_rel in /*|*../*|../*) return 0 ;; esac
	[[ -f $TMPDIR/.remote_files ]] || return 0
	_tmp="$TMPDIR/.remote_files.present_$$.$RANDOM"
	{
		cat "$TMPDIR/.remote_files" 2>/dev/null
		printf '%s\n' "$_rel"
	} | awk 'NF && !seen[$0]++' > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && mv "$_tmp" "$TMPDIR/.remote_files" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	rm -f "$_tmp" 2>/dev/null
	_speed_debug_log "REMOTE_FILELIST_NOTE_PRESENT rel=$_rel"
	return 0
}

_remote_webdav_known_missing() {
	local _rel="$1"
	[[ $remote_type = webdav ]] || return 1
	[[ -f $TMPDIR/.remote_files && -f $TMPDIR/.remote_webdav_last_list_ok ]] || return 1
	awk -v r="$_rel" '$0==r{f=1;exit} END{exit f?0:1}' "$TMPDIR/.remote_files" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && return 1
	return 0
}

# 從遠端下載單個文件 (用於備份前對比 app_details.json)
# 用法: remote_download_single_file <遠端相對路徑> <本地目標路徑>
# 回傳: 0=成功, 1=失敗
remote_download_single_file() {
	local remote_rel="$1" local_dest="$2"
	[[ -z $remote_type || -z $remote_url ]] && return 1
	local backup_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	case $remote_type in
	webdav)
		local base_url="${remote_url%/}"
		local target_rel="$backup_subdir/$remote_rel"
		if _remote_webdav_known_missing "$remote_rel"; then
			_speed_debug_log "WEBDAV_SINGLE_GET_SKIP_KNOWN_MISSING rel=$remote_rel source=remote_files"
			rm -f "$local_dest" 2>/dev/null
			return 1
		fi
		local _tmp="${local_dest}.part.$$.$RANDOM" _err="$TMPDIR/.wdav_get_err_$$_$RANDOM" _rc _bytes _get_start_ms _get_elapsed_ms _get_speed
		# v24.20.14-7.66-16: 暫存錯誤檔可能已被其他清理流程移除；不要讓 rm 噪音污染 stderr.log。
		rm -f "$local_dest" "$_tmp" "$_err" 2>/dev/null
		_get_start_ms="$(_speed_now_ms)"
		_webdav_dex getrel "$remote_user" "$remote_pass" "$base_url" "$target_rel" "$_tmp" 2>"$_err"
		_rc=$?
		_get_elapsed_ms=$(( $(_speed_now_ms) - _get_start_ms ))
		[[ $_get_elapsed_ms -le 0 ]] && _get_elapsed_ms=1
		_bytes="$(_local_file_size_debug "$_tmp")"
		_get_speed="$(_webdav_speed_mib_s "$_bytes" "$_get_elapsed_ms")"
		remote_raw_log "remote_download_raw.log" "WEBDAV_SINGLE_GET rc=$_rc bytes=${_bytes:-0} elapsedMs=$_get_elapsed_ms speedMiBps=$_get_speed rel=$target_rel base=$base_url"
		remote_raw_cat "remote_download_raw.log" "$_err" "[WEBDAV_SINGLE_GET stderr rel=$remote_rel rc=$_rc]"
		if [[ $_rc = 0 && -s $_tmp ]]; then
			mv "$_tmp" "$local_dest" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			rm -f "$_err" 2>/dev/null
			return 0
		fi
		_speed_debug_log "WEBDAV_SINGLE_GET_DROP rel=$remote_rel rc=$_rc bytes=${_bytes:-0}"
		rm -f "$_tmp" "$_err" "$local_dest" 2>/dev/null
		return 1
		;;
	smb)
		remote_parse_smb_url
		local share="$SMB_SHARE"
		local rem_path="$SMB_REM_PATH"
		local base="${rem_path:+$rem_path/}$backup_subdir"
		local dir_part="${remote_rel%/*}"
		local file_part="${remote_rel##*/}"
		local smb_dest="$(mktemp -d "$TMPDIR/.smb_dl_XXXXXX" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		[[ -z $smb_dest ]] && smb_dest="$TMPDIR/.smb_dl_$$_$RANDOM"
		mkdir -p "$smb_dest" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		if ! _smb_safe_component "$file_part" || ! _smb_safe_component "$smb_dest"; then
			echoRgb "偵測到不安全的檔名字元, 拒絕執行 smbclient 下載: $file_part" "0" >&2
			return 1
		fi
		local _smb_auth_args
		_smb_auth_args="$(_smb_auth_args_current)" || return 1
		smbclient "$share" $_smb_auth_args -t 10 -s $(_smb_client_conf) \
			-D "$base/$dir_part" \
			-c "lcd $smb_dest; get $file_part; exit" >/dev/null 2>&1
		if [[ -f "$smb_dest/$file_part" ]]; then
			mv "$smb_dest/$file_part" "$local_dest"
			rm -rf "$smb_dest"
			return 0
		else
			rm -rf "$smb_dest"
			return 1
		fi
		;;
	*)
		return 1
		;;
	esac
}

# 過濾 smbclient 輸出的雜訊行 (Try help / dos charset / OS= 等橫幅文字)
# 用法: smb_filter_noise <輸入字串>
smb_filter_noise() {
	echo "$1" | grep -Ev '^Try "help"|^dos charset|^Can.t load|^Domain=|^OS=|^directory_create_or_exist:|^$'
}

# 解析 smbclient -g -L 輸出，回傳第一個可用 Disk share 名稱。
# 純 -g 模式：只接受 Samba grepable share 格式 Disk|share|comment；不再解析普通 -L 表格。
_smb_parse_share_grepable() {
	awk -F'|' '
		function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s}
		$1=="Disk" {
			n=trim($2)
			if (n!="" && n !~ /\$$/) { print n; exit }
		}
	'
}

# 解析 smbclient -g ls，輸出：ATTR<TAB>SIZE<TAB>REL_PATH
# 純 -g 命令模式：所有呼叫端都必須使用 smbclient -g。
# 注意：Samba 4.24.4 的「-g ls」實測仍可能輸出表格行，而不是 pipe 行；
# 這裡只把它視為 -g ls 的實際格式，不再提供「不帶 -g 重跑 / 普通 -L」兼容路徑。
# 支援的 -g ls 實測格式：
#   name|ATTR|SIZE|...
#   ATTR|name|SIZE|...
#   name|SIZE|ATTR|...
#   name  ATTR  SIZE  Week Mon Day Time Year   （4.24.4 -g ls 實測表格）
_smb_parse_ls_entries() {
	local _pref="${1:-}"
	awk -v pref="$_pref" '
		function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s}
		function norm(s){gsub(/\\/, "/", s); gsub(/\/+/, "/", s); sub(/^\/+/, "", s); sub(/\/+$/, "", s); return s}
		function is_attr(s){return (s ~ /^[A-Za-z]+$/ && s ~ /[ADNHSR]/)}
		function emit(name, attr, sz, full, rel){
			name=trim(name); attr=trim(attr); sz=trim(sz)
			if (name=="" || name=="." || name=="..") return
			if (attr=="" || sz !~ /^[0-9]+$/) sz=0
			name=norm(name)
			if (name=="" || name=="." || name=="..") return
			if (dir!="" && index(name, dir"/")!=1) full=dir"/"name; else full=name
			full=norm(full)
			if (p!="") {
				if (full==p) return
				if (index(full,p"/")==1) rel=substr(full,length(p)+2)
				else rel=full
			} else rel=full
			rel=norm(rel)
			if (rel=="" || rel=="." || rel=="..") return
			print attr "\t" sz "\t" rel
		}
		BEGIN{p=norm(pref); dir=""}
		/^Try "help"/ || /^dos charset/ || /^Can.t load/ || /^WARNING:/ || /^Domain=/ || /^OS=/ || /^directory_create_or_exist:/ || /^$/ { next }
		/^[[:space:]]*[0-9]+[[:space:]]+blocks[[:space:]]+of[[:space:]]+size[[:space:]]+[0-9]+/ { next }
		/^\\/ { dir=norm($0); next }
		index($0,"|")>0 {
			n=split($0,a,"|"); for(i=1;i<=n;i++) a[i]=trim(a[i])
			if (a[1]=="Disk" || a[1]=="IPC" || a[1]=="Printer") next
			if (n>=3 && is_attr(a[2]) && a[3] ~ /^[0-9]+$/) { emit(a[1],a[2],a[3]); next }
			if (n>=3 && is_attr(a[1]) && a[3] ~ /^[0-9]+$/) { emit(a[2],a[1],a[3]); next }
			if (n>=3 && is_attr(a[3]) && a[2] ~ /^[0-9]+$/) { emit(a[1],a[3],a[2]); next }
			next
		}
		{
			# Samba 4.24.4 smbclient -g ls 實測仍輸出表格：檔名 ATTR SIZE 日期...
			# 檔名可含空白，因此找第一個 attr 欄位，下一欄必須是 size。
			for (i=2; i<=NF; i++) {
				if (is_attr($i) && $(i+1) ~ /^[0-9]+$/) {
					name=$1
					for (j=2; j<i; j++) name=name" "$j
					emit(name,$i,$(i+1)); break
				}
			}
		}
	'
}

# 判斷目錄是否含任何檔案 (非空)
# 用法: dir_has_files <目錄路徑>
# 回傳: 0=有檔案, 1=空目錄或不存在
dir_has_files() {
	[[ -d $1 ]] || return 1
	[[ -n $(find "$1" -type f -print -quit 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) ]]
}

# 啟動時的遠端設定初始化
# 規範化 remote_keep_local 值, 驗證 remote_type, TCP 預檢
# 失敗時清空 remote_type 停用上傳但保留本地備份
remote_setup() {
	# 若之前連線失敗清空了 remote_type, 用原始值恢復以重新檢測 (支援中途開 WiFi 後重試)
	[[ -z $remote_type && -n $_remote_type_orig ]] && remote_type="$_remote_type_orig"
	# 純本機模式：只做 runtime 關閉，不反寫 conf；使用者原 remote_stream/remote_upload_per_app 保留。
	if [[ -z $remote_type ]]; then
		remote_stream=0
		remote_upload_per_app=0
		return 0
	fi
	# 規範化 remote_keep_local 成 true/false
	case $remote_keep_local in
	1|true|True|TRUE) remote_keep_local=true ;;
	*) remote_keep_local=false ;;
	esac
	echoRgb "遠程備份: $remote_type -> $remote_url" "3"
	case $remote_type in
	webdav|smb)
		;;
	*) echoRgb "未知遠程類型: $remote_type (可選: webdav/smb)" "0"; remote_type=""; return 1 ;;
	esac
	[[ -z $remote_url ]] && { echoRgb "遠端位址未設置 (請設 smb_url 或 webdav_url)，停用遠端上傳" "0"; remote_type=""; return 1; }
	# conf 防呆: 檢查 URL 格式跟協議匹配
	case $remote_type in
	webdav)
		case $remote_url in
		http://*|https://*) ;;
		smb://*)
			echoRgb "remote_type=webdav 但 remote_url 是 smb:// 開頭" "0"
			echoRgb "請改成 http:// 或 https:// 開頭, 或把 remote_type 改成 smb" "3"
			remote_type=""; return 1 ;;
		*)
			echoRgb "remote_url 必須以 http:// 或 https:// 開頭" "0"
			echoRgb "目前: $remote_url" "0"
			remote_type=""; return 1 ;;
		esac
		;;
	smb)
		case $remote_url in
		smb://*) ;;
		http://*|https://*)
			echoRgb "remote_type=smb 但 remote_url 是 http(s):// 開頭" "0"
			echoRgb "請改成 smb:// 開頭, 或把 remote_type 改成 webdav" "3"
			remote_type=""; return 1 ;;
		"")
			# 未填地址: 自動掃描區網 SMB 並填入第一台的第一個共享
			echoRgb "remote_url 未填, 自動掃描區網 SMB..." "3"
			if smb_autodetect_url; then
				echoRgb "自動填入: $remote_url" "1"
			else
				echoRgb "自動掃描未找到可用 SMB, 請手動填 remote_url" "0"
				remote_type=""; return 1
			fi
			;;
		*)
			echoRgb "remote_url 必須以 smb:// 開頭" "0"
			echoRgb "目前: $remote_url" "0"
			remote_type=""; return 1 ;;
		esac
		;;
	esac
	# 帳密為空提醒 (非致命, 可能是匿名認證)
	[[ -z $remote_user ]] && echoRgb "remote_user 未設定 (將以匿名嘗試連線)" "0"
	# 事前連線測試: 從各協議解出 host:port 做快速 TCP 探測
	remote_parse_endpoint
	# 流式模式需要 SMB_SHARE/SMB_REM_PATH (平時在 upload 函數才解析, 流式不走那裡, 故這裡先解析)
	[[ $remote_stream = 1 && $remote_type = smb ]] && remote_parse_smb_url
	# 端口跟協議不一致警告 (常見錯誤: https 配 80 或 http 配 443)
	if [[ $remote_type = webdav ]]; then
		case "$remote_url:$REMOTE_PORT" in
		https://*:80)
			echoRgb "警告: HTTPS 通常用 443, 你設 80 (可能應改用 http://)" "0" ;;
		http://*:443)
			echoRgb "警告: HTTP 通常用 80, 你設 443 (可能應改用 https://)" "0" ;;
		esac
	fi
	if remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線測試通過 ($REMOTE_HOST:$REMOTE_PORT)" "1"
		if [[ $remote_type = webdav ]]; then
			if _webdav_options_preflight "${remote_url%/}" "" control; then
				echoRgb "WebDAV OPTIONS 能力預檢通過" "1"
			else
				echoRgb "WebDAV OPTIONS 能力預檢失敗，已停用遠端上傳" "0"
				[[ -n ${_WEBDAV_ERROR_ZH:-} ]] && echoRgb "原因: $_WEBDAV_ERROR_ZH" "0"
				if [[ $remote_stream = 1 ]]; then
					_speed_debug_normal_finish_pack 1
					exit 1
				fi
				remote_type=""
				return 1
			fi
		fi
		_remote_netwatch_start
		if [[ $remote_stream = 1 ]]; then
			echoRgb "流式上傳模式 (邊壓邊傳, 不佔本機空間)" "3"
			# WebDAV 流式只允許 dex putstdinchunkedrel：stdin 直接轉 HTTP chunked PUT，不在本機落地整包暫存。
			# 若伺服器不支援 chunked PUT，直接退出；remote_stream=1 的語意就是「真流式」。
			if [[ $remote_type = webdav ]]; then
				WEBDAV_STREAM_UPLOAD_CMD=putstdinmanagedrel
				if _webdav_options_preflight "${remote_url%/}" "" stream && _webdav_atomic_capability_probe "${remote_url%/}"; then
					echoRgb "WebDAV Dex managed 真流式可用 (direct/atomic 由 Dex 決策，不佔本機整包暫存)" "1"
				else
					_probe_http="${_WEBDAV_HTTP_CODE:-0}"
					if [[ ${_probe_http:-0} = 0 ]]; then
						echoRgb "WebDAV Dex/daemon 原子真流式探測失敗：未取得有效 HTTP 回應" "0"
						echoRgb "請先檢查 classes.dex、WebDavUtil daemon、unixsock relay 與 WebDAV 伺服器" "3"
					else
						echoRgb "WebDAV Dex managed 真流式探測失敗 (HTTP $_probe_http)，已停止；remote_stream=1 不允許回退到本機暫存上傳" "0"
						echoRgb "需要伺服器支援 PUT 與必要的 MOVE/STAT；可改用 SMB 流式或設 remote_stream=0" "3"
					fi
					_speed_debug_normal_finish_pack 1
					exit 1
				fi
			fi
		elif [[ $remote_keep_local = true ]]; then
			echoRgb "備份完成後將自動上傳到遠端 (保留本地檔案)" "3"
		else
			echoRgb "備份完成後將自動上傳到遠端 (上傳成功後刪除本地檔案)" "3"
		fi
	else
		if [[ $remote_stream = 1 ]]; then
			echoRgb "真流式上傳不可用：遠端不可連線 ($REMOTE_HOST:$REMOTE_PORT)，已終止" "0"
			echoRgb "remote_stream=1 不允許回退成本地備份；請開啟遠端伺服器、修正網路，或設 remote_stream=0" "3"
			echoRgb "詳情已寫入 speed_debug 包內: remote_precheck.log" "3"
			_speed_debug_normal_finish_pack 1
			exit 1
		fi
		echoRgb "遠端不可連線，已停用遠端上傳並保留本地備份 ($REMOTE_HOST:$REMOTE_PORT)" "2"
		echoRgb "詳情已寫入 speed_debug 包內: remote_precheck.log" "3"
		remote_type=""
	fi
}

# 獨立的測試遠端入口 (給選單用)
# 1. 顯示 conf 設定
# 2. TCP 預檢
# 3. 嘗試認證 + list 遠端目錄
# 不會實際上傳任何東西
# 單獨上傳某個 app 的備份 (給子目錄 upload.sh 用)
# 假設呼叫時 Backup 是備份根目錄 (Backup_zstd_X)
# $1 = app 名 (子目錄名)
single_upload() {
	local app_name="$1"
	[[ -z $app_name ]] && { echoRgb "single_upload: 缺少 app 名" "0"; return 1; }
	[[ -z $Backup ]] && Backup="$MODDIR"
	local target="$Backup/$app_name"
	[[ ! -d $target ]] && { echoRgb "找不到目錄: $target" "0"; return 1; }
	dir_has_files "$target" || { echoRgb "$app_name 目錄為空,沒有東西可上傳" "0"; return 1; }
	# 重置範圍 flag, 只標記這一個
	unset REMOTE_APPLIST REMOTE_UPLOAD_MEDIA REMOTE_UPLOAD_WIFI
	case $app_name in
	Media) REMOTE_UPLOAD_MEDIA=1 ;;
	wifi) REMOTE_UPLOAD_WIFI=1 ;;
	*) REMOTE_APPLIST="$app_name" ;;
	esac
	REMOTE_TRIGGER=1
	# 啟動時 remote_setup 已跑過, 這裡只檢查狀態
	[[ -z $remote_type ]] && { echoRgb "遠端未設定或預檢失敗,終止" "0"; return 1; }
	echoRgb "—————— 單獨上傳: $app_name ——————" "3"
	case $remote_type in
	smb) upload_smb ;;
	webdav) upload_remote "webdav" ;;
	esac
	# 已主動上傳, 清旗標避免 trap EXIT 再跑一次
	unset REMOTE_TRIGGER
}

# 邊備份邊上傳：每備份完一個應用後立即上傳並刪除本機檔案
# $1 = 應用名 (目錄名)
# 依賴 global: remote_type, remote_keep_local, Backup
per_app_upload_and_cleanup() {
	local app_name="$1"
	[[ -z $app_name ]] && return 1
	[[ -z $Backup ]] && return 1
	local target="$Backup/$app_name"
	[[ ! -d $target ]] && return 0
	dir_has_files "$target" || return 0
	[[ -z $remote_type ]] && return 1
	# 合併遠端 app_details.json 到本地，避免丢失遠端已有的字段
	local local_app_details="$target/app_details.json"
	local remote_app_details="$TMPDIR/.remote_app_details_merge_$$"
	local remote_rel="${app_name}/app_details.json"
	if [[ -f $local_app_details ]] && remote_download_single_file "$remote_rel" "$remote_app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
		[[ -s $remote_app_details ]] && {
			# 合併遠端數據到本地（本地數據優先，但保留遠端已有的字段）
			local merged="$TMPDIR/.merged_app_details_$$"
			if jq -s '.[0] * .[1]' "$remote_app_details" "$local_app_details" > "$merged" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && [[ -s $merged ]]; then
				cat "$merged" > "$local_app_details"
			fi
			rm -f "$merged"
		}
	fi
	rm -f "$remote_app_details"
	# 設定上傳範圍：只上傳這一個 app, 跳過 tools/ 等固定項避免重複上傳
	# REMOTE_APPDETAILS_FILE: 主體上傳完成後，若無失敗則由上傳函數自動處理
	unset REMOTE_APPLIST REMOTE_UPLOAD_MEDIA REMOTE_UPLOAD_WIFI
	REMOTE_APPLIST="$app_name"
	REMOTE_SKIP_FIXED=1
	REMOTE_APPDETAILS_SKIP=1
	REMOTE_QUIET=1
	REMOTE_TRIGGER=1
	REMOTE_APPDETAILS_FILE="$Backup/$app_name/app_details.json"
	local _upload_rc=0
	case $remote_type in
	smb) upload_smb; _upload_rc=$? ;;
	webdav) upload_remote "webdav"; _upload_rc=$? ;;
	esac
	# 清除標記
	unset REMOTE_TRIGGER REMOTE_SKIP_FIXED REMOTE_APPLIST REMOTE_APPDETAILS_SKIP REMOTE_QUIET REMOTE_APPDETAILS_FILE
	return $_upload_rc
}

# 主選單觸發: 讀 appList.txt + Custom_path, 直接上傳對應目錄
# 不互動,等同於跑完整備份後的自動上傳,但不重新備份
upload_current_backup() {
	backup_path
	[[ ! -d $Backup ]] && { echoRgb "本地備份目錄不存在: $Backup" "0"; return 1; }
	echoRgb "本地備份: $Backup" "2"
	show_conf remote
	# remote_setup 連線失敗或未設定時會清空 remote_type → 直接終止, 不再詢問
	# 用 remote_url 區分: 有設 URL 但 type 被清空 = 連線失敗; 沒設 URL = 未設定
	if [[ -z $remote_type ]]; then
		if [[ -n $remote_url ]]; then
			echoRgb "遠端連線失敗 (請檢查 WiFi/伺服器), 無法上傳" "0"
		else
			echoRgb "未設定遠端, 無法上傳" "0"
		fi
		return 1
	fi
	# 選擇上傳模式: 1=按清單(appList) 2=整個目錄
	unset REMOTE_FULL_DIR
	unset _up_mode
	if ! ask_yn "上傳模式" "按清單上傳" "上傳整個Backup目錄"; then
		REMOTE_FULL_DIR=1
	fi
	if [[ $REMOTE_FULL_DIR = 1 ]]; then
		echoRgb "已選擇: 上傳整個 Backup 目錄 (排除 log)" "2"
	else
		# 讀 appList.txt (跟備份用同一個解析邏輯)
		local applist=""
		if [[ -n $list_location ]]; then
			if [[ ${list_location:0:1} = / ]]; then
				[[ -f $list_location ]] && applist="$list_location"
			else
				[[ -f $MODDIR/$list_location ]] && applist="$MODDIR/$list_location"
			fi
		fi
		[[ -z $applist && -f $MODDIR/appList.txt ]] && applist="$MODDIR/appList.txt"
		# 組裝 REMOTE_APPLIST (跟 backup() 用同一個變數,讓 collect_targets 認得)
		unset REMOTE_APPLIST REMOTE_UPLOAD_MEDIA REMOTE_UPLOAD_WIFI
		if [[ -n $applist ]]; then
			REMOTE_APPLIST="$(cat "$applist")"
			local app_count
			app_count=$(echo "$REMOTE_APPLIST" | grep -cEv '^[[:space:]]*[#＃!]|^[[:space:]]*$')
			echoRgb "讀取 $applist (有效 $app_count 個 app)" "2"
		else
			echoRgb "找不到 appList.txt" "0"
		fi
		# 讀 Custom_path: 有設就帶上 Media
		if [[ -n $Custom_path ]]; then
			if dir_has_files "$Backup/Media"; then
				REMOTE_UPLOAD_MEDIA=1
				echoRgb "Custom_path 已設, 將上傳 Media" "2"
			fi
		fi
		# wifi 目錄存在就一併上傳
		if dir_has_files "$Backup/wifi"; then
			REMOTE_UPLOAD_WIFI=1
			echoRgb "wifi 目錄存在, 將上傳 wifi" "2"
		fi
		if [[ -z $REMOTE_APPLIST && $REMOTE_UPLOAD_MEDIA != 1 && $REMOTE_UPLOAD_WIFI != 1 ]]; then
			echoRgb "沒有可上傳項目 (appList 為空, Custom_path 未設, 無 wifi)" "0"
			return 1
		fi
	fi
	# 上傳前統計大小並確認
	local _pre_list="$TMPDIR/.precheck_list" _pre_bytes
	remote_collect_targets "$_pre_list"
	if [[ ! -s $_pre_list ]]; then
		echoRgb "沒有可上傳的檔案" "0"; rm -f "$_pre_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; return 1
	fi
	local _pre_count="$(wc -l < "$_pre_list")"
	if [[ $REMOTE_FULL_DIR = 1 ]]; then
		# 全目錄模式: 用 du 算整個目錄 (跟備份時 Calculate_size 同源), 減去 log
		local _all _log
		# 純文件字節, 排除根目錄 log (整體 - log, 兩者同算法相減精確)
		local _all _log
		_all="$(calc_dir_size "$Backup")"
		_log="$(calc_dir_size "$Backup/log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		_pre_bytes=$(awk -v a="${_all:-0}" -v l="${_log:-0}" 'BEGIN{print a-l}')
	else
		_pre_bytes="$(list_total_size "$_pre_list")"
	fi
	echoRgb "本次上傳: $_pre_count 個檔案, 總大小 $(size "$_pre_bytes") (位元組:$_pre_bytes)" "3"
	rm -f "$_pre_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if ! ask_yn "確認上傳?" "確認上傳" "取消"; then
		echoRgb "已取消上傳" "1"; return 0
	fi
	REMOTE_TRIGGER=1
	# 啟動時 remote_setup 已跑過, 這裡只檢查狀態
	[[ -z $remote_type ]] && { echoRgb "遠端未設定或預檢失敗,終止" "0"; return 1; }
	case $remote_type in
	smb) upload_smb ;;
	webdav) upload_remote "webdav" ;;
	esac
	# 已主動上傳, 清旗標避免 trap EXIT 再跑一次
	unset REMOTE_TRIGGER
}

# 測試遠端連線完整性 (主選單第 6 項)
# 三層測試: TCP 預檢 → 認證 → 路徑訪問
# 每層失敗都有具體錯誤訊息 (帳密錯/路徑不存在/分享不存在等)
remote_test() {
	echoRgb "============== 遠端連線測試 ==============" "3"
	show_conf remote
	if [[ -z $remote_type ]]; then
		echoRgb "remote_type 未設定" "0"
		echoRgb "請編輯 $conf_path 設定 remote_type/remote_url/remote_user/remote_pass" "3"
		return 1
	fi
	echoRgb "類型: $remote_type" "2"
	echoRgb "位址: $remote_url" "2"
	echoRgb "帳號: ${remote_user:-(未設)}" "2"
	[[ -n $remote_pass ]] && echoRgb "密碼: ********" "2" || echoRgb "密碼: (未設)" "2"
	echoRgb "保留本地: ${remote_keep_local:-0}" "2"
	case $remote_type in
	webdav|smb) ;;
	*) echoRgb "未知 remote_type: $remote_type (可選: webdav/smb)" "0"; return 1 ;;
	esac
	[[ -z $remote_url ]] && { echoRgb "remote_url 未設置" "0"; return 1; }
	# 協議與 URL 一致性檢查
	case $remote_type in
	webdav)
		case $remote_url in
		http://*|https://*) ;;
		smb://*)
			echoRgb "remote_type=webdav 但 remote_url 是 smb:// 開頭" "0"
			echoRgb "請改 remote_type=smb, 或把 remote_url 改成 http(s)://" "3"
			return 1 ;;
		*://*)
			echoRgb "remote_url 協議 (${remote_url%%://*}://) 不被 webdav 支援" "0"
			echoRgb "WebDAV 只支援 http:// 或 https://" "3"
			return 1 ;;
		*)
			echoRgb "remote_url 必須以 http:// 或 https:// 開頭" "0"
			echoRgb "目前: $remote_url" "0"
			return 1 ;;
		esac ;;
	smb)
		case $remote_url in
		smb://*) ;;
		http://*|https://*)
			echoRgb "remote_type=smb 但 remote_url 是 http(s):// 開頭" "0"
			echoRgb "請改 remote_type=webdav, 或把 remote_url 改成 smb://" "3"
			return 1 ;;
		*://*)
			echoRgb "remote_url 協議 (${remote_url%%://*}://) 不被 smb 支援" "0"
			echoRgb "SMB 只支援 smb://" "3"
			return 1 ;;
		*)
			echoRgb "remote_url 必須以 smb:// 開頭" "0"
			echoRgb "目前: $remote_url" "0"
			return 1 ;;
		esac ;;
	esac
	# 遠端連線測試只測目前設定的 remote_url，不做整個區網 SMB 掃描。
	# SMB 掃描保留在「掃描 SMB」功能與 remote_type=smb 且 remote_url 空白的自動偵測流程。
	# 避免 WebDAV 測試也被 445/139 掃描拖慢。
	# 第一關: TCP 預檢
	remote_parse_endpoint
	echoRgb "—————— TCP 連線測試 ——————" "3"
	echoRgb "目標: $REMOTE_HOST:$REMOTE_PORT" "2"
	if remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "TCP 連線通過" "1"
	else
		echoRgb "TCP 連線失敗" "0"
		echoRgb "可能原因:" "0"
		echoRgb "WiFi 未開啟或不在同網段" "0"
		echoRgb "伺服器 IP / port 寫錯" "0"
		echoRgb "伺服器未啟動 / 防火牆阻擋" "0"
		return 1
	fi
	# 第二關: 認證 + 列目錄
	echoRgb "—————— 認證與列目錄測試 ——————" "3"
	case $remote_type in
	smb)
		remote_parse_smb_url
		local share="$SMB_SHARE"
		local rem_path="$SMB_REM_PATH"
		local out _smb_auth_args
		_smb_auth_args="$(_smb_auth_args_current)" || { echoRgb "SMB 認證資訊不可用，無法測試" "0"; return 1; }
		out="$(smbclient -g "$share" $_smb_auth_args -t 10 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3 \
			-c "cd ${rem_path:-/}; ls; exit" 2>&1)"
		out="$(smb_filter_noise "$out")"
		if echo "$out" | grep -qE 'NT_STATUS_LOGON_FAILURE'; then
			echoRgb "認證失敗 (帳號或密碼錯誤)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_ACCESS_DENIED'; then
			echoRgb "存取被拒 (帳號權限不足)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_BAD_NETWORK_NAME'; then
			echoRgb "share 名稱錯誤: $share (請檢查伺服器是否有此分享)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_OBJECT_(PATH|NAME)_NOT_FOUND'; then
			echoRgb "遠端路徑不存在: $rem_path (將在首次上傳時建立)" "3"
		elif echo "$out" | grep -qE 'NT_STATUS_(CONNECTION_REFUSED|IO_TIMEOUT|HOST_UNREACHABLE)'; then
			echoRgb "網路不通 (伺服器無回應)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_UNSUCCESSFUL'; then
			echoRgb "SMB 連線失敗 (NT_STATUS_UNSUCCESSFUL)" "0"
			echoRgb "常見原因: 端口錯誤 / SMB 協議版本不相容 / 伺服器拒絕" "3"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS|ERRSRV'; then
			echoRgb "SMB 錯誤:" "0"
			echo "$out" | head -5
			return 1
		else
			echoRgb "認證通過, share 可存取" "1"
			echoRgb "遠端路徑 $remote_url 可存取" "1"
			# 抓 SMB 協議版本：先解析 smbclient debug；解析不到時以 min=max 逐一強制 dialect，找最高可用版本。
			_smb_detect_protocol_version "$share" "$_smb_auth_args" "$rem_path" || true
		fi
		;;
	webdav)
		local base_url="${remote_url%/}"
		local code webdav_err _test_out
		# WEB-R3: 測試入口改走 OPTIONS + statrel/listrel，對齊新 WebDavUtil 能力層。
		_webdav_options_preflight "$base_url" "" control >/dev/null 2>"$TMPDIR/.webdav_test_err"
		code="$_WEBDAV_HTTP_CODE"
		if [[ $code = 2* ]]; then
			_webdav_status_sidecar_reset
			_test_out="$(_webdav_dex listrel "$remote_user" "$remote_pass" "$base_url" "." 0 2>>"$TMPDIR/.webdav_test_err")"
			_webdav_status_sidecar_load || true
			code="$_WEBDAV_HTTP_CODE"
		fi
		webdav_err="$(cat "$TMPDIR/.webdav_test_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		rm -f "$TMPDIR/.webdav_test_err"
		case $code in
		2*|207) echoRgb "WebDAV 認證通過 (HTTP $code)" "1" ;;
		401) echoRgb "認證失敗 (HTTP 401, 帳號或密碼錯誤)" "0"; return 1 ;;
		403) echoRgb "權限不足 (HTTP 403)" "0"; return 1 ;;
		404) echoRgb "路徑不存在 (HTTP 404)" "0"; return 1 ;;
		405) echoRgb "方法不允許 (HTTP 405, 此 URL 可能不是 WebDAV 端點)" "0"; return 1 ;;
		408) echoRgb "請求逾時 (HTTP 408, 伺服器繁忙)" "0"; return 1 ;;
		423) echoRgb "資源被鎖定 (HTTP 423, 有其他客戶端正在寫入)" "0"; return 1 ;;
		429) echoRgb "請求過於頻繁 (HTTP 429, 觸發伺服器限流)" "0"; return 1 ;;
		500) echoRgb "伺服器內部錯誤 (HTTP 500)" "0"; return 1 ;;
		502) echoRgb "閘道錯誤 (HTTP 502, 反向代理 / 上游服務有問題)" "0"; return 1 ;;
		503) echoRgb "服務不可用 (HTTP 503, 伺服器維護或過載)" "0"; return 1 ;;
		504) echoRgb "閘道逾時 (HTTP 504)" "0"; return 1 ;;
		3*) echoRgb "未處理的重定向 (HTTP $code，可能跳到非 WebDAV 端點)" "0"; return 1 ;;
		000)
			echoRgb "dex WebDavUtil 無法完成請求" "0"
			[[ -n ${_WEBDAV_ERROR_ZH:-} ]] && echoRgb "原因: $_WEBDAV_ERROR_ZH" "0"
			[[ -n $webdav_err ]] && echoRgb "詳細: $webdav_err" "0"
			return 1 ;;
		*)   echoRgb "WebDAV 異常 (HTTP $code)" "0"
			[[ -n ${_WEBDAV_ERROR_ZH:-} ]] && echoRgb "原因: $_WEBDAV_ERROR_ZH" "0"
			[[ -n $webdav_err ]] && echoRgb "詳細: $webdav_err" "0"
			return 1 ;;
		esac
		;;
	esac
	echoRgb "========================================" "3"
	echoRgb "全部測試通過, 可以開始備份" "1"
	return 0
}

# 功能 6 入口：保留原本「測試目前遠端連線」，並把區網 SMB 併發掃描接回來。
# 掃描使用既有 scan_smb() / _smb_scan_hosts()：優先 dex 併發 socket，fallback nc 並發。
remote_test_menu() {
	local _old_remote_type="$remote_type" _old_remote_url="$remote_url" _old_remote_user="$remote_user" _old_remote_pass="$remote_pass"
	local _old_smb_url="${smb_url:-}" _choice
	while true; do
		echoRgb "============== 遠端連線 / SMB 掃描 ==============" "3"
		echo " -1) 測試目前遠端連線"
		echo " -2) 掃描區網全部 SMB 主機"
		echo " -3) 掃描 SMB 並臨時套用第一個可用共享後測試"
		echo " -0) 返回"
		echo -n " -請輸入選項編號: "
		if ! read _choice; then
			# 若主選單因 background_execution=1 用 subshell/背景執行，stdin 可能在子選單變成 EOF；
			# 這裡嘗試從實際終端讀取，避免直接跳回「測試目前遠端連線」。
			if [[ -r /dev/tty ]]; then
				IFS= read -r _choice < /dev/tty || _choice=""
			fi
			if [[ -z $_choice ]]; then
				echoRgb "無互動 stdin，改為測試目前遠端連線" "0"
				remote_test
				return $?
			fi
		fi
		case $_choice in
		1)
			remote_test
			return $?
			;;
		2)
			# 掃描 SMB 時使用 SMB 專用帳密；若未設帳密則走 guest/匿名。
			remote_user="${smb_remote_user:-}"
			remote_pass="${smb_remote_pass:-}"
			scan_smb
			_rc=$?
			remote_type="$_old_remote_type"; remote_url="$_old_remote_url"; remote_user="$_old_remote_user"; remote_pass="$_old_remote_pass"
			return $_rc
			;;
		3)
			remote_type="smb"
			remote_user="${smb_remote_user:-}"
			remote_pass="${smb_remote_pass:-}"
			remote_url="${smb_url:-}"
			if smb_autodetect_url; then
				smb_url="$remote_url"
				echoRgb "臨時套用 SMB 位址: $remote_url" "1"
				remote_test
				_rc=$?
			else
				echoRgb "未找到可用 SMB 共享" "0"
				_rc=1
			fi
			# 不自動寫入 backup_settings.conf；只是功能 6 診斷流程的臨時套用。
			remote_type="$_old_remote_type"; remote_url="$_old_remote_url"; remote_user="$_old_remote_user"; remote_pass="$_old_remote_pass"; smb_url="$_old_smb_url"
			return $_rc
			;;
		0)
			return 0
			;;
		*)
			echoRgb "輸入錯誤，請重新輸入有效的數字。" "0"
			;;
		esac
	done
}

# 列出遠端可用的備份目錄並產生 appList_network.txt
# 流程: 連遠端 → 列 Backup_*_* 目錄 → 讓使用者選 → 檢查必要檔案 → 掃 app 清單 → 輸出
remote_list_backups() {
	show_conf remote
	[[ -z $remote_type ]] && { echoRgb "remote_type 未設定" "0"; return 1; }
	case $remote_type in
	smb|webdav) ;;
	*) echoRgb "下載功能僅支援 smb / webdav (目前 remote_type=$remote_type)" "0"; return 1 ;;
	esac
	# 規範化 remote_keep_local
	case $remote_keep_local in
	1|true|True|TRUE) remote_keep_local=true ;;
	*) remote_keep_local=false ;;
	esac
	# 目標目錄 = 跟本地備份一樣的命名規則
	local target_dir="$(get_backup_dirname)"
	echoRgb "目標遠端目錄: $target_dir" "3"
	# 連線預檢
	remote_parse_endpoint
	if ! remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		return 1
	fi
	echoRgb "連線到 $remote_type://$REMOTE_HOST:$REMOTE_PORT" "1"
	# 進入目標目錄, 列出檔案/子資料夾
	local sub_listing="$TMPDIR/.remote_sub_listing"
	: > "$sub_listing"
	if [[ $remote_type = smb ]]; then
		remote_parse_smb_url
		local share="$SMB_SHARE"
		local rem_path="$SMB_REM_PATH"
		local smb_out
		local _smb_auth_args
		_smb_auth_args="$(_smb_auth_args_current)" || { echoRgb "SMB 認證資訊不可用，無法列出遠端" "0"; return 1; }
		smb_out=$(smbclient -g "$share" $_smb_auth_args -t 10 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3 \
			-c "cd ${rem_path:-/}/$target_dir; ls; exit" 2>&1)
		if echo "$smb_out" | grep -qE 'NT_STATUS_OBJECT_(PATH|NAME)_NOT_FOUND'; then
			echoRgb "遠端目錄不存在: $target_dir" "0"
			echoRgb "請確認遠端有此備份,或備份過至少一次" "3"
			rm -f "$sub_listing"
			return 1
		fi
		if echo "$smb_out" | grep -qE 'NT_STATUS|ERRSRV'; then
			echoRgb "讀取遠端失敗:" "0"
			echo "$smb_out" | grep -E 'NT_STATUS|ERR' | head -3
			rm -f "$sub_listing"
			return 1
		fi
		# 格式: "D dirname" 或 "N filename"；輸入固定來自 smbclient -g ls 的實測格式。
		{
			echo "===== SMB_LIST_BACKUPS stdout-g target=$target_dir ====="
			printf '%s\n' "$smb_out"
		} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_smb_list_raw.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		printf '%s\n' "$smb_out" | _smb_parse_ls_entries "" | awk -F'\t' '
			{
				name=$3
				# remote menu 只需要 target_dir 直下一層；遞迴項不在這裡處理。
				if (name=="" || name ~ /\//) next
				if (index($1,"D")>0) print "D " name; else print "N " name
			}' > "$sub_listing"
	elif [[ $remote_type = webdav ]]; then
		local base_url="${remote_url%/}"
		local http_code _wdav_err
		_wdav_err="$TMPDIR/.wdav_err_$$"
		: > "$TMPDIR/.wdav_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_webdav_dex listrel "$remote_user" "$remote_pass" "$base_url" "$target_dir" 1 > "$TMPDIR/.wdav_out" 2>"$_wdav_err"
		http_code="$_WEBDAV_HTTP_CODE"
		# debug: 把 list 結果(href/length)與 dex stderr 寫到 log 供除錯；不可污染 stderr.log。
		local dbg_log
		dbg_log="$(_speed_debug_log_path webdav_debug.log)"
		{
			echo "===== WebDAV list $(date '+%Y-%m-%d %H:%M:%S') ====="
			echo "Base: $base_url"
			echo "Rel: $target_dir"
			echo "HTTP code: $http_code"
			if [[ -s "$_wdav_err" ]]; then
				echo "----- dex stderr -----"
				cat "$_wdav_err" 2>/dev/null
			fi
			echo "----- href/length -----"
			[[ -f "$TMPDIR/.wdav_out" ]] && cat "$TMPDIR/.wdav_out" 2>/dev/null
			echo ""
			echo "----- End -----"
		} | while IFS= read -r _dbg_line; do _speed_debug_append_file "$dbg_log" "$_dbg_line"; done
		case $http_code in
		2*) ;;
		404)
			echoRgb "遠端目錄不存在: $target_dir (HTTP 404)" "0"
			echoRgb "請確認遠端有此備份,或備份過至少一次" "3"
			# 列根目錄看實際有什麼, 幫用戶確認路徑名
			local root_code root_xml="$TMPDIR/.wdav_root"
			local _root_err="$TMPDIR/.wdav_root_err_$$"
			_webdav_dex listrel "$remote_user" "$remote_pass" "$base_url" "." 1 > "$root_xml" 2>"$_root_err"
			root_code="$_WEBDAV_HTTP_CODE"
			{
				echo ""
				echo "----- 根目錄探測 listrel $base_url . -----"
				echo "HTTP code: $root_code"
				if [[ -s "$_root_err" ]]; then
					echo "----- root dex stderr -----"
					cat "$_root_err" 2>/dev/null
				fi
				[[ -f "$root_xml" ]] && cat "$root_xml" 2>/dev/null
				echo ""
			} | while IFS= read -r _dbg_line; do _speed_debug_append_file "$dbg_log" "$_dbg_line"; done
			case $root_code in
			2*)
				# 抓 href 列表給用戶看
				local found
				found=$(cat "$root_xml" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | tr '><' '\n' | awk '
					/^(D:)?response$/ { in_resp=1; href="" }
					/^\/(D:)?response$/ { if (in_resp && href != "") print href; in_resp=0 }
					/^(D:)?href$/ { getline href }
				' | grep -v '^/$' | grep -v "^${base_url#http*://*/}$")
				if [[ -n $found ]]; then
					echoRgb "遠端根目錄實際有以下項目:" "3"
					echo "$found" | head -20
				fi
				;;
			esac
			rm -f "$root_xml" "$_root_err"
			echoRgb "原始回應已寫入 speed_debug 包內: webdav_debug.log" "3"
			rm -f "$sub_listing" "$TMPDIR/.wdav_out" "$_wdav_err"; return 1 ;;
		*) echoRgb "讀取遠端失敗 (HTTP $http_code)" "0"
			echoRgb "原始回應已寫入 speed_debug 包內: webdav_debug.log" "3"
			rm -f "$sub_listing" "$TMPDIR/.wdav_out" "$_wdav_err"; return 1 ;;
		esac
		local propfind_out
		propfind_out=$(cat "$TMPDIR/.wdav_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})
		rm -f "$TMPDIR/.wdav_out" "$_wdav_err"
		# WebDavUtil no-ktor/daemon list 已輸出解析後的 TSV，不再是原始 XML：
		#   href<TAB>length<TAB>D/F
		# 舊 XML parser 會把已解析 TSV 全部吃空，導致遠端明明有檔案卻顯示「目錄為空」。
		# 這裡直接從 href 取 target_dir 下的一層子項，產生 remote_list_backups 後續使用的：
		#   D 資料夾名
		#   N 檔案名
		: > "$sub_listing"
		printf '%s\n' "$propfind_out" | awk -v target="$target_dir" -F'\t' '
			function trim_slash(s) { sub(/\/*$/, "", s); return s }
			NF >= 2 {
				h = $1
				kind = $3
				gsub(/\r$/, "", h)
				gsub(/\r$/, "", kind)
				if (h == "" || h ~ /^HTTP /) next
				is_dir = (kind == "D" || h ~ /\/$/)
				path = h
				sub(/\?.*$/, "", path)
				base1 = "/" target "/"
				base2 = target "/"
				idx = index(path, base1)
				if (idx > 0) {
					rel = substr(path, idx + length(base1))
				} else {
					idx = index(path, base2)
					if (idx == 0) next
					rel = substr(path, idx + length(base2))
				}
				rel = trim_slash(rel)
				if (rel == "" || rel == target) next
				# remote menu 只需要 target_dir 直下一層；遞迴項交給後續下載流程處理。
				if (rel ~ /\//) next
				print (is_dir ? "D" : "N") " " rel
			}
		' > "$sub_listing"

		# 保留舊 WebDAV 伺服器/舊 dex 若回傳 percent-encoded href 的解碼能力。
		local decoded="$TMPDIR/.decoded_listing"
		: > "$decoded"
		while read -r typ name; do
			[[ -z $name ]] && continue
			local converted real
			converted=$(echo "$name" | sed 's/%\([0-9a-fA-F][0-9a-fA-F]\)/\\x\1/g')
			real=$(printf '%b' "$converted")
			echo "$typ $real" >> "$decoded"
		done < "$sub_listing"
		mv "$decoded" "$sub_listing"
	fi
	if [[ ! -s $sub_listing ]]; then
		echoRgb "遠端目錄為空或讀取失敗" "0"
		# 列出 raw XML 跟解析後的結果到 log 方便除錯
		if [[ $remote_type = webdav && -f ${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/webdav_debug.log ]]; then
			{
				echo ""
				echo "----- Parsed listing (sub_listing) -----"
				[[ -f $sub_listing ]] && cat "$sub_listing"
				echo "(empty)"
			} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/webdav_debug.log"
			echoRgb "詳細回應已寫入 speed_debug 包內: webdav_debug.log" "3"
		fi
		rm -f "$sub_listing"
		return 1
	fi
	# 檢查必要檔案: tools/ start.sh restore_settings.conf
	local has_tools=0 has_start=0 has_conf=0
	while read -r type name; do
		case "$name" in
		tools) [[ $type = D ]] && has_tools=1 ;;
		start.sh) [[ $type != D ]] && has_start=1 ;;
		restore_settings.conf) [[ $type != D ]] && has_conf=1 ;;
		esac
	done < "$sub_listing"
	local missing=""
	[[ $has_tools = 0 ]] && missing="$missing tools/"
	[[ $has_start = 0 ]] && missing="$missing start.sh"
	[[ $has_conf = 0 ]] && missing="$missing restore_settings.conf"
	if [[ -n $missing ]]; then
		echoRgb "錯誤: 遠端 $target_dir 缺少必要檔案:$missing" "0"
		echoRgb "此備份不完整,無法用於恢復" "0"
		rm -f "$sub_listing"
		return 1
	fi
	echoRgb "必要檔案檢查通過 (tools/ start.sh restore_settings.conf)" "1"
	# 產生 appList_network.txt
	# 規則:
	#   - 排除 tools, start.sh, restore_settings.conf (固定下載項)
	#   - 是目錄: wifi/Media → 特殊項; 其他 → app
	#   - 是檔案就忽略
	local out="$MODDIR/appList_network.txt"
	# 遠端 app 清單
	local apps="$TMPDIR/.apps_list"
	: > "$apps"
	while read -r type name; do
		[[ $type = D ]] || continue
		case "$name" in
		tools|wifi|Media) continue ;;
		esac
		echo "$name" >> "$apps"
	done < "$sub_listing"
	sort "$apps" > "$TMPDIR/.apps_sorted"
	# 本地備份資料夾清單
	local local_apps="$TMPDIR/.local_apps"
	local _local_backup="$MODDIR/$(get_backup_dirname)"
	: > "$local_apps"
	for _d in "$_local_backup"/*/; do
		_d="${_d%/}"; _d="${_d##*/}"
		case "$_d" in tools|wifi|Media|log) continue ;; esac
		[[ -f "$_local_backup/$_d/app_details.json" ]] && echo "$_d" >> "$local_apps"
	done
	sort "$local_apps" > "$TMPDIR/.local_sorted"
	local only_remote only_local
	only_remote="$(comm -23 "$TMPDIR/.apps_sorted" "$TMPDIR/.local_sorted")"
	only_local="$(comm -13 "$TMPDIR/.apps_sorted" "$TMPDIR/.local_sorted")"
	{
		echo "# 遠端備份目錄: $target_dir"
		echo "# 連線: $remote_type://$REMOTE_HOST/"
		echo "# 用 # 註解掉不要下載的項目, 編輯完選 '從遠端下載備份' 即可"
		echo ""
		echo "# ---- 應用 (每行一個 app) ----"
		cat "$TMPDIR/.apps_sorted"
		echo ""
		echo "# ---- 特殊項目 (非 app, 有就會下載) ----"
		while read -r type name; do
			[[ $type = D ]] || continue
			case "$name" in
			wifi|Media) echo "$name" ;;
			esac
		done < "$sub_listing"
		echo ""
		echo "# ---- 比對結果 ----"
		if [[ -n $only_remote ]]; then
			echo "# 遠端有、本地無 (可下載):"
			echo "$only_remote" | while read -r _n; do echo "#   $_n"; done
		fi
		if [[ -n $only_local ]]; then
			echo "# 本地有、遠端無 (未上傳):"
			echo "$only_local" | while read -r _n; do echo "#   $_n"; done
		fi
		[[ -z $only_remote && -z $only_local ]] && echo "# 本地與遠端完全一致"
	} > "$out"
	cp "$TMPDIR/.apps_sorted" "$TMPDIR/.apps_sorted_keep" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	rm -f "$apps" "$TMPDIR/.apps_sorted" "$local_apps" "$TMPDIR/.local_sorted"
	rm -f "$sub_listing"
	echoRgb "已輸出清單: $out" "1"
	local _rc _lc
	[[ -n $only_remote ]] && _rc="$(echo "$only_remote" | grep -c .)"
	[[ -n $only_local ]]  && _lc="$(echo "$only_local"  | grep -c .)"
	[[ -n $only_remote ]] && echoRgb "遠端有、本地無: ${_rc}個" "3" && echo "$only_remote" | while read -r _n; do echoRgb "$_n" "3"; done
	[[ -n $only_local ]]  && echoRgb "本地有、遠端無: ${_lc}個" "0" && echo "$only_local"  | while read -r _n; do echoRgb "$_n" "0"; done
	[[ -z $only_remote && -z $only_local ]] && echoRgb "本地與遠端完全一致" "1"
	# 有差異時提供快速操作
	if [[ -n $only_local ]]; then
		if ask_yn "立即上傳本地多出的應用?" "上傳" "跳過"; then
			backup_path
			REMOTE_APPLIST="$only_local"
			REMOTE_TRIGGER=1
			case $remote_type in
			smb) upload_smb ;;
			webdav) upload_remote "webdav" ;;
			esac
			unset REMOTE_TRIGGER REMOTE_APPLIST
		fi
	fi
	if [[ -n $only_remote ]]; then
		if ask_yn "立即下載遠端多出的應用?" "下載" "跳過"; then
			local _dl_items="$TMPDIR/.dl_diff_items"
			echo "$only_remote" > "$_dl_items"
			local chosen="$(get_backup_dirname)"
			local dest="$MODDIR/$chosen"
			mkdir -p "$dest" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			remote_parse_endpoint
			if remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
				if [[ $remote_type = smb ]]; then
					_remote_download_smb "$chosen" "$dest" "$_dl_items"
				elif [[ $remote_type = webdav ]]; then
					_remote_download_webdav "$chosen" "$dest" "$_dl_items"
				fi
			else
				echoRgb "遠端連線失敗" "0"
			fi
			rm -f "$_dl_items"
		fi
	fi
	ask_yn_indep "順手檢查遠端app_details.json健全度? (會逐個下載驗證,較耗時)" "檢查" "跳過"
	if [[ $branch = true ]]; then
		local _ra _jchk_total _jchk_i=0 _running=0 _jok=0 _jinvalid=0 _jmissing=0 _jchk_pids=""
		_jchk_total="$(grep -vc '^$' "$TMPDIR/.apps_sorted_keep" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		rm -rf "$TMPDIR/.health_check_dl" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		mkdir -p "$TMPDIR/.health_check_dl" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		while read -r _ra; do
			[[ -z $_ra ]] && continue
			let _jchk_i++
			# 遠端清單行格式通常是「備份資料夾名 package.name」；
			# 真正 app_details 位於 Backup_xxx/<備份資料夾名>/app_details.json。
			# 不能把整行拿去組遠端路徑，否則會下載到 404/Not Found 內容，誤判 JSON 損壞。
			local _rk="${_ra%% *}"
			[[ -z $_rk ]] && _rk="$_ra"
			printf '\r -下載中 %d/%d' "$_jchk_i" "$_jchk_total" >&2
			( _get_remote_appdetails "$_rk" "$TMPDIR/.health_check_dl/$_rk.json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} ) &
			_jchk_pids="$_jchk_pids $!"
			let _running++
			if [[ $_running -ge 8 ]]; then _event_wait_pid_list "$_jchk_pids" remote_health_batch; _jchk_pids=""; _running=0; fi
		done < "$TMPDIR/.apps_sorted_keep"
		_event_wait_pid_list "$_jchk_pids" remote_health_final
		echo >&2
		# 下載完畢後序列跑健全檢查 (純本地讀檔, 快, 不需並發)
		_jchk_i=0
		while read -r _ra; do
			[[ -z $_ra ]] && continue
			let _jchk_i++
			local _rk="${_ra%% *}"
			[[ -z $_rk ]] && _rk="$_ra"
			echoRgb "[$_jchk_i/$_jchk_total] $_ra" "3"
			if [[ -s "$TMPDIR/.health_check_dl/$_rk.json" ]]; then
				if _remote_appdetails_json_ok "$TMPDIR/.health_check_dl/$_rk.json"; then
					let _jok++
					_json_health_check "$TMPDIR/.health_check_dl/$_rk.json" "$_ra (遠端)"
				else
					let _jinvalid++
					_speed_debug_log "REMOTE_HEALTH_APPDETAILS_INVALID_DROP app=$_ra key=$_rk file=$TMPDIR/.health_check_dl/$_rk.json"
					echo "$_ra (遠端): app_details.json 無效/下載不完整 ($_rk/app_details.json)" >> "$TMPDIR/.json_health_remote_drops"
					rm -f "$TMPDIR/.health_check_dl/$_rk.json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				fi
			else
				let _jmissing++
				_speed_debug_log "REMOTE_HEALTH_APPDETAILS_MISSING app=$_ra key=$_rk"
				echo "$_ra (遠端): app_details.json 缺失或下載失敗 ($_rk/app_details.json)" >> "$TMPDIR/.json_health_remote_drops"
			fi
		done < "$TMPDIR/.apps_sorted_keep"
		rm -rf "$TMPDIR/.health_check_dl" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		JSON_HEALTH_REPORT_ALWAYS=1
		JSON_HEALTH_CHECKED_COUNT="$_jchk_total"
		JSON_HEALTH_INVALID_COUNT="$_jinvalid"
		JSON_HEALTH_MISSING_COUNT="$_jmissing"
		_json_health_report
		echoRgb "檢查完成 $_jchk_i/$_jchk_total" "1"
	fi
	rm -f "$TMPDIR/.apps_sorted_keep" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	echoRgb "請編輯該檔案,留下你要下載的項目,然後選 '從遠端下載備份'" "3"
}

# 依 appList_network.txt 下載備份到 $MODDIR/Backup_*_$user
remote_download_backup() {
	show_conf remote
	[[ -z $remote_type ]] && { echoRgb "remote_type 未設定" "0"; return 1; }
	case $remote_type in
	smb|webdav) ;;
	*) echoRgb "下載功能僅支援 smb / webdav (目前 remote_type=$remote_type)" "0"; return 1 ;;
	esac
	local list="$MODDIR/appList_network.txt"
	if [[ ! -f $list ]]; then
		echoRgb "找不到 $list" "0"
		echoRgb "請先執行 '列出遠端備份' 產生清單" "3"
		return 1
	fi
	local dl_start
	dl_start=$(date +%s)
	# 目標目錄 = 跟本地備份一樣的命名規則
	local chosen="$(get_backup_dirname)"
	echoRgb "目標遠端目錄: $chosen" "3"
	# 連線預檢
	remote_parse_endpoint
	if ! remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		return 1
	fi
	# 解析清單 (去除註解/空行)
	local items_file="$TMPDIR/.dl_items"
	grep -Ev '^[[:space:]]*[#＃]|^[[:space:]]*$' "$list" > "$items_file"
	if [[ ! -s $items_file ]]; then
		echoRgb "清單為空,沒有東西需要下載" "0"
		rm -f "$items_file"
		return 1
	fi
	local item_count
	item_count=$(wc -l < "$items_file")
	echoRgb "將下載 $item_count 個項目 + 固定 3 項 (tools/ start.sh restore_settings.conf)" "3"
	# 下載目標: $MODDIR/$chosen (例: $MODDIR/Backup_zstd_0)
	local dest="$MODDIR/$chosen"
	mkdir -p "$dest" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	echoRgb "下載到: $dest" "2"
	# 依協議分派
	local fail=0
	if [[ $remote_type = smb ]]; then
		_remote_download_smb "$chosen" "$dest" "$items_file" || fail=1
	elif [[ $remote_type = webdav ]]; then
		_remote_download_webdav "$chosen" "$dest" "$items_file" || fail=1
	fi
	rm -f "$items_file"
	local dl_elapsed=$(( $(date +%s) - dl_start ))
	if [[ $fail -eq 0 ]]; then
		echoRgb "_______________________________________" "2"
		echoRgb "下載完成: $dest 用時${dl_elapsed}秒" "1"
		echoRgb "可直接執行 $dest/start.sh 進行恢復" "3"
		remote_log "下載完成: $dest 用時${dl_elapsed}秒"
	else
		echoRgb "下載過程有失敗,請檢查上方訊息 (用時${dl_elapsed}秒)" "0"
		remote_log "下載失敗 用時${dl_elapsed}秒"
		return 1
	fi
}

# SMB 下載實作
# 每個 item 一次 smbclient (用 -D 直接切目錄,避免 cd 路徑解析問題)
# $1=遠端 Backup_zstd_X 目錄名, $2=本地目標, $3=要下載的項目清單檔
_remote_download_smb() {
	local chosen="$1" dest="$2" items_file="$3"
	remote_parse_smb_url
	local share="$SMB_SHARE"
	local rem_path="$SMB_REM_PATH"
	local SMB_OPTS="-t 300 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
	local base="${rem_path:+$rem_path/}$chosen"
	remote_raw_log "remote_download_raw.log" "SMB_BEGIN share=$share base=$base dest=$dest items_file=$items_file"
	local total_items
	total_items=$(wc -l < "$items_file")
	local idx=0 fail_total=0
	# 下載每個項目 (用 -D 切到指定目錄, 再 mget *)
	while read -r item; do
		[[ -z $item ]] && continue
		let idx++
		echoRgb "[$idx/$total_items] $(progress_bar $((idx * 100 / total_items))) 下載 $item" "3"
		mkdir -p "$dest/$item" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		local out
		if ! _smb_safe_component "$item" || ! _smb_safe_component "$dest"; then
			echoRgb "偵測到不安全的項目名稱字元, 拒絕執行 smbclient 下載: $item" "0" >&2
			continue
		fi
		local _smb_auth_args
		_smb_auth_args="$(_smb_auth_args_current)" || { echoRgb "SMB 認證資訊不可用，停止下載 $item" "0"; fail_total=$((fail_total+1)); continue; }
		out=$(smbclient "$share" $_smb_auth_args $SMB_OPTS \
			-D "$base/$item" \
			-c "lcd $dest/$item; prompt off; recurse on; mget *; exit" 2>&1)
		out="$(smb_filter_noise "$out")"
		local _dl_tag
		_dl_tag="$(_remote_debug_seq remote_download_smb)"
		remote_raw_log "remote_download_raw.log" "SMB_ITEM tag=$_dl_tag idx=$idx total=$total_items item=$item dest=$dest/$item"
		{
			echo "===== SMB_DOWNLOAD_ITEM $_dl_tag item=$item ====="
			printf '%s\n' "$out"
		} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_download_smb_${_dl_tag}.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		printf '%s\n' "$out" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_download_raw.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		if echo "$out" | grep -qE 'NT_STATUS_[A-Z_]+' \
			|| [[ -z "$(ls -A "$dest/$item" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})" ]]; then
			if echo "$out" | grep -q 'NT_STATUS_OBJECT_NAME_NOT_FOUND'; then
				echoRgb "✗ $item（遠端不存在或已被刪除）" "0"
				rm -rf "$dest/$item" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			else
				echoRgb "✗ $item（下載失敗，詳見 speed_debug）" "0"
			fi
			let fail_total++
		else
			echoRgb "✓ $item" "1"
		fi
	done < "$items_file"
	# 固定 3 項: tools/ (獨立連線)
	echoRgb "下載固定項目: tools/ start.sh restore_settings.conf" "3"
	mkdir -p "$dest/tools" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	local tools_out
	if ! _smb_safe_component "$dest"; then
		echoRgb "偵測到不安全的目標路徑字元, 拒絕執行 smbclient 下載: $dest" "0" >&2
		return 1
	fi
	local _smb_auth_args
	_smb_auth_args="$(_smb_auth_args_current)" || { echoRgb "SMB 認證資訊不可用，停止下載 tools" "0"; return 1; }
	tools_out=$(smbclient "$share" $_smb_auth_args $SMB_OPTS \
		-D "$base/tools" \
		-c "lcd $dest/tools; prompt off; recurse on; mget *; exit" 2>&1)
	tools_out="$(smb_filter_noise "$tools_out")"
	remote_raw_log "remote_download_raw.log" "SMB_FIXED tools base=$base/tools dest=$dest/tools"
	{
		echo "===== SMB_DOWNLOAD_FIXED_TOOLS ====="
		printf '%s\n' "$tools_out"
	} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_download_smb_fixed.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# 固定 3 項: start.sh / restore_settings.conf (獨立連線)
	local fix_out
	if ! _smb_safe_component "$dest"; then
		echoRgb "偵測到不安全的目標路徑字元, 拒絕執行 smbclient 下載: $dest" "0" >&2
		return 1
	fi
	fix_out=$(smbclient "$share" $_smb_auth_args $SMB_OPTS \
		-D "$base" \
		-c "lcd $dest; prompt off; get start.sh; get restore_settings.conf; exit" 2>&1)
	fix_out="$(smb_filter_noise "$fix_out")"
	remote_raw_log "remote_download_raw.log" "SMB_FIXED start_conf base=$base dest=$dest"
	{
		echo "===== SMB_DOWNLOAD_FIXED_START_CONF ====="
		printf '%s\n' "$fix_out"
	} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_download_smb_fixed.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# 驗證
	local fix_fail=0
	[[ -z "$(ls -A "$dest/tools" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})" ]] && fix_fail=1
	[[ ! -s $dest/start.sh ]] && fix_fail=1
	[[ ! -s $dest/restore_settings.conf ]] && fix_fail=1
	if [[ $fix_fail = 1 ]]; then
		echoRgb "固定項目下載有錯誤" "0"
		echo "$tools_out
$fix_out" | grep -E 'NT_STATUS' | head -5
		[[ -z "$(ls -A "$dest/tools" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})" ]] && echoRgb "tools/ 為空" "0"
		[[ ! -s $dest/start.sh ]] && echoRgb "start.sh 缺失或空檔" "0"
		[[ ! -s $dest/restore_settings.conf ]] && echoRgb "restore_settings.conf 缺失或空檔" "0"
		let fail_total++
	else
		echoRgb "✓ 固定 3 項" "1"
	fi
	[[ -f $dest/start.sh ]] && chmod +x "$dest/start.sh" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	[[ -d $dest/tools ]] && chmod -R +x "$dest/tools" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	[[ $fail_total -eq 0 ]]
}

# WebDAV 下載實作 (先遞迴掃出所有相對路徑，再用 dex WebDavUtil 逐檔下載)
_remote_download_webdav() {
	local chosen="$1" dest="$2" items_file="$3"
	local base_url="${remote_url%/}"
	local base_rel="$chosen"
	remote_raw_log "remote_download_raw.log" "WEBDAV_BEGIN base_url=$base_url base_rel=$base_rel dest=$dest items_file=$items_file"
	local total_items
	total_items=$(wc -l < "$items_file")
	local fail_total=0
	# 遞迴掃描 WebDAV 路徑, 把所有檔案 (含子目錄內) 寫入清單檔
	# 清單格式: <遠端相對路徑>\t<本地完整路徑>
	# $1=遠端相對路徑, $2=本地目錄, $3=清單檔
	_webdav_scan_files() {
		local r_rel="$1" l_dir="$2" out_list="$3"
		mkdir -p "$l_dir" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		local out _scan_err="$TMPDIR/.wdav_scan_err_$$" _scan_rc _scan_tag
		_scan_tag="$(_remote_debug_seq webdav_scan)"
		_webdav_status_sidecar_reset
		out="$(_webdav_dex listrel "$remote_user" "$remote_pass" "$base_url" "$r_rel" 1 2>"$_scan_err")"
		_scan_rc=$?
		_webdav_status_sidecar_load || true
		remote_raw_log "remote_download_raw.log" "WEBDAV_SCAN tag=$_scan_tag rc=$_scan_rc rel=$r_rel local=$l_dir"
		remote_raw_cat "remote_download_webdav_scan_${_scan_tag}.log" "$_scan_err" "===== WEBDAV_SCAN $_scan_tag rel=$r_rel rc=$_scan_rc ====="
		rm -f "$_scan_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		# 用 mktemp 避免遞迴呼叫時不同層級共用同個檔案造成資料覆蓋
		local parsed
		parsed=$(mktemp "$TMPDIR/.wdav_scan_XXXXXX")
		# dex list 已輸出 "href	length	D|F"; 重排成 "typ	href" 供下游沿用。
		printf '%s\n' "$out" | awk -F'	' '{print $3"	"$1}' > "$parsed"
		local r_url_basename
		r_url_basename="${r_rel%/}"
		r_url_basename="${r_url_basename##*/}"
		local rc=0
		while IFS=$'	' read -r typ href; do
			[[ -z $href ]] && continue
			local name
			name="$(echo "$href" | sed 's|/$||; s|.*/||')"
			[[ -z $name ]] && continue
			[[ $name = "$r_url_basename" ]] && continue
			if [[ $typ = D ]]; then
				_webdav_scan_files "$r_rel/$name" "$l_dir/$name" "$out_list" || rc=1
			else
				# 寫入清單: 遠端相對路徑	本地路徑
				echo -e "$r_rel/$name	$l_dir/$name" >> "$out_list"
			fi
		done < "$parsed"
		rm -f "$parsed"
		return $rc
	}
	# 逐筆下載清單內的所有檔案 (改用 dex get, 不再 parallel; 正確性優先於並行速度)
	# 每行 "rel_path\tlocal_path"
	_webdav_parallel_get() {
		local list="$1"
		[[ ! -s $list ]] && return 0
		local _get_err="$TMPDIR/.wdav_get_err_$$" _get_tag
		_get_tag="$(_remote_debug_seq webdav_get)"
		local rc=0 _get_total _get_idx=0 _pct _get_start_ms _get_elapsed_ms _get_bytes _get_speed _get_size
		_get_total=$(wc -l < "$list" 2>/dev/null)
		case "$_get_total" in ''|*[!0-9]*) _get_total=0 ;; esac
		while IFS=$'	' read -r rel lpath; do
			[[ -z $rel ]] && continue
			_get_idx=$((_get_idx + 1))
			if [[ $_get_total -gt 0 ]]; then
				_pct=$((_get_idx * 100 / _get_total))
				printf '\r -下載遠端檔案 %d/%d %s %s' "$_get_idx" "$_get_total" "$(progress_bar $_pct)" "$rel" >&2
			else
				printf '\r -下載遠端檔案 %d %s' "$_get_idx" "$rel" >&2
			fi
			_get_start_ms="$(_speed_now_ms)"
			if ! _webdav_dex getrel "$remote_user" "$remote_pass" "$base_url" "$rel" "$lpath" 2>>"$_get_err"; then
				rc=1
			fi
			_get_elapsed_ms=$(( $(_speed_now_ms) - _get_start_ms ))
			[[ $_get_elapsed_ms -le 0 ]] && _get_elapsed_ms=1
			_get_bytes="$(_local_file_size_debug "$lpath")"
			_get_speed="$(_webdav_speed_mib_s "$_get_bytes" "$_get_elapsed_ms")"
			_get_size="$(_webdav_size_mib_text "$_get_bytes")"
			remote_raw_log "remote_download_raw.log" "WEBDAV_GET_FILE tag=$_get_tag idx=$_get_idx total=$_get_total rc=$rc bytes=${_get_bytes:-0} elapsedMs=$_get_elapsed_ms speedMiBps=$_get_speed rel=$rel"
			if [[ $_get_total -gt 0 ]]; then
				printf '\r -下載遠端檔案 %d/%d %s %s %sMiB/s %s\n' "$_get_idx" "$_get_total" "$(progress_bar $_pct)" "$_get_size" "$_get_speed" "$rel" >&2
			else
				printf '\r -下載遠端檔案 %d %sMiB/s %s %s\n' "$_get_idx" "$_get_speed" "$_get_size" "$rel" >&2
			fi
		done < "$list"
		remote_raw_log "remote_download_raw.log" "WEBDAV_GET tag=$_get_tag rc=$rc files=$_get_idx list=$list"
		{
			echo "===== WEBDAV_GET $_get_tag rc=$rc list=$list ====="
			echo "[list]"
			cat "$list"
			echo "[stderr]"
			cat "$_get_err" 2>/dev/null
		} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_download_webdav_get_${_get_tag}.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		# v24.20.14-7.66-17: WebDAV GET 清理暫存檔時完全靜默，避免偶發 rm 噪音污染 stderr.log。
		rm -f "$_get_err" 2>/dev/null
		return $rc
	}
	# 1. 遞迴掃描所有要下載的檔案
	local all_files="$TMPDIR/.wdav_all_files"
	: > "$all_files"
	local idx=0
	local scan_fail=0
	# 1a. items_file 內每個項目
	while read -r item; do
		[[ -z $item ]] && continue
		let idx++
		# 與本地檔案預掃一致：同一行刷新，不再產生一整組看似「第一次下載」的進度條。
		printf '\r -預掃遠端檔案 %d/%d %s' "$idx" "$total_items" "$(progress_bar $((idx * 100 / total_items)))" >&2
		if ! _webdav_scan_files "$base_rel/$item" "$dest/$item" "$all_files"; then
			printf '\n' >&2
			echoRgb "✗ 掃描失敗: $item" "0"
			scan_fail=1
			let fail_total++
		fi
	done < "$items_file"
	[[ $idx -gt 0 ]] && printf '\n' >&2
	# 1b. 固定項目 tools/
	echoRgb "掃描固定項目: tools/" "3"
	if ! _webdav_scan_files "$base_rel/tools" "$dest/tools" "$all_files"; then
		echoRgb "✗ 掃描失敗: tools/" "0"
		scan_fail=1
		let fail_total++
	fi
	# 1c. 固定檔案 start.sh / restore_settings.conf 直接加進清單。
	# _webdav_parallel_get() 使用 getrel(base_url, rel)，因此這裡必須放 base_rel 下的相對路徑；
	# 舊版誤放完整 base_url/$f，會讓固定兩檔 GET 失敗並被驗證成缺失/空檔。
	for f in start.sh restore_settings.conf; do
		printf '%s\t%s\n' "$base_rel/$f" "$dest/$f" >> "$all_files"
	done
	# 2. 逐檔下載（目前 helper 為序列 getrel，UI 不再誤報 4 路並行）
	local total_files
	total_files=$(wc -l < "$all_files")
	echoRgb "下載 $total_files 個檔案" "3"
	_webdav_parallel_get "$all_files"
	rm -f "$all_files"
	# 3. 事後驗證每個項目本地是否有檔案
	local _vi=0
	while read -r item; do
		[[ -z $item ]] && continue
		let _vi++
		if [[ -z "$(ls -A "$dest/$item" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})" ]]; then
			echoRgb "[$_vi/$total_items] $(progress_bar $((_vi * 100 / total_items))) ✗ $item (本地為空)" "0"
			let fail_total++
		else
			echoRgb "[$_vi/$total_items] $(progress_bar $((_vi * 100 / total_items))) ✓ $item" "1"
		fi
	done < "$items_file"
	# 固定項目驗證
	local fix_fail=0
	[[ -z "$(ls -A "$dest/tools" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})" ]] && fix_fail=1
	[[ ! -s $dest/start.sh ]] && fix_fail=1
	[[ ! -s $dest/restore_settings.conf ]] && fix_fail=1
	if [[ $fix_fail = 1 ]]; then
		echoRgb "固定項目下載有錯誤" "0"
		[[ -z "$(ls -A "$dest/tools" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})" ]] && echoRgb "tools/ 為空" "0"
		[[ ! -s $dest/start.sh ]] && echoRgb "start.sh 缺失或空檔" "0"
		[[ ! -s $dest/restore_settings.conf ]] && echoRgb "restore_settings.conf 缺失或空檔" "0"
		let fail_total++
	else
		echoRgb "✓ 固定 3 項" "1"
	fi
	[[ -f $dest/start.sh ]] && chmod +x "$dest/start.sh" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	[[ -d $dest/tools ]] && chmod -R +x "$dest/tools" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	[[ $fail_total -eq 0 ]]
}

# trap EXIT 觸發的遠端上傳函數
# 只在 backup/backup_media/backup_update_apk 成功完成後才觸發上傳
# 其他選項 (測試/列出/下載/退出) 不觸發, 由 REMOTE_TRIGGER 旗標控制
remote_cleanup() {
	# 只有在 backup / backup_media / backup_update_apk 跑完後才上傳。
	# 未觸發上傳時仍要停止本輪臨時 netwatch，避免回到選單後殘留。
	if [[ $REMOTE_TRIGGER != 1 ]]; then
		_remote_netwatch_report
		_remote_netwatch_stop
		return 0
	fi
	# 純本機模式：完全不進入遠端收尾，避免「已上傳/只上傳依賴文件」等提示殘留。
	if ! remote_ui_allowed; then
		_remote_netwatch_report
		_remote_netwatch_stop
		return 0
	fi
	# 防雙重觸發 (backup 內直接呼叫 + trap EXIT 都可能呼叫)
	if [[ $REMOTE_DONE = 1 ]]; then
		_remote_netwatch_report
		_remote_netwatch_stop
		return 0
	fi
	REMOTE_DONE=1
	# 流式模式: 應用數據與 json 已在備份過程中逐個流式傳走, 此處只補傳結尾的 wifi (若有)
	if [[ $remote_stream = 1 && -n $remote_type ]]; then
		local _wifidir="$TMPDIR/.stream_stage/wifi"
		if _remote_stream_fatal_active; then
			echoRgb "本輪遠端流式已失敗，略過 wifi/tools/遠端統計收尾，避免網路中斷後卡住" "0"
			_speed_debug_log "REMOTE_CLEANUP_STREAM_FATAL_SKIP $(_remote_stream_fatal_summary)"
			_remote_netwatch_report
			_remote_netwatch_stop
			return 0
		fi
		if [[ $REMOTE_UPLOAD_WIFI = 1 && -d $_wifidir ]]; then
			local _wf
			if [[ $remote_type = webdav ]]; then
				local _wifi_list="$TMPDIR/.stream_wifi_webdav_files_$$"
				: > "$_wifi_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				for _wf in "$_wifidir"/*; do
					[[ -f $_wf ]] && printf '%s	%s
' "wifi/${_wf##*/}" "$_wf" >> "$_wifi_list"
				done
				if _stream_upload_webdav_local_files_batch "$_wifi_list" wifi; then
					echoRgb "wifi 設定已上傳遠端" "1"
				else
					echoRgb "wifi 設定上傳失敗/逾時，已略過；下次會重試" "0"
				fi
				rm -f "$_wifi_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			else
				for _wf in "$_wifidir"/*; do
					[[ -f $_wf ]] && _stream_upload "wifi/${_wf##*/}" < "$_wf"
				done
				echoRgb "wifi 設定已上傳遠端" "1"
			fi
		fi
		if _remote_stream_fatal_active; then
			echoRgb "WebDAV 收尾上傳中斷，略過 tools/ 與遠端統計，避免卡住" "0"
			_speed_debug_log "REMOTE_CLEANUP_AFTER_WIFI_FATAL_SKIP $(_remote_stream_fatal_summary)"
			_remote_netwatch_report
			_remote_netwatch_stop
			return 0
		fi
		echoRgb "流式上傳完成 (數據未佔用本機空間)" "1"
		# 上傳恢復必要檔案到遠端 (tools/ start.sh restore_settings.conf), 讓遠端備份可獨立恢復 (功能8/10 需要)
		stream_upload_infra
		if _remote_stream_fatal_active; then
			echoRgb "WebDAV tools/ 上傳中斷，略過遠端統計，避免卡住" "0"
			_speed_debug_log "REMOTE_CLEANUP_AFTER_INFRA_FATAL_SKIP $(_remote_stream_fatal_summary)"
			_remote_netwatch_report
			_remote_netwatch_stop
			return 0
		fi
		# 統計遠端備份資料夾大小 (對齊本地備份的 Calculate_size 顯示)
		local _subdir="$(get_backup_dirname)"
		local _rtotal _rnew
		_rtotal="$(remote_dir_size "$_subdir")"
		if [[ -n $_rtotal && $_rtotal != 0 ]]; then
			echoRgb "遠端備份資料夾↓↓↓\n -$remote_url ($_subdir)" "2"
			echoRgb "遠端備份總體大小$(size "$_rtotal") $_rtotal" "3"
			# 本次差異: 整體資料夾大小差異 (備份前快照 vs 現在, 對齊本地 Calculate_size)
			_rnew=$(awk -v a="${_rtotal:-0}" -v b="${_RTOTAL_BEFORE:-0}" 'BEGIN{print a-b}')
			_speed_debug_log "REMOTE_TOTAL_AFTER subdir=$_subdir before=${_RTOTAL_BEFORE:-0} after=${_rtotal:-0} delta=$_rnew"
			case $_rnew in
			-*) echoRgb "本次備份減少 $(size "$(awk -v n="$_rnew" 'BEGIN{print -n}')")" "3" ;;
			0)  echoRgb "文件大小未改變" "3" ;;
			*)  echoRgb "本次備份增加 $(size "$_rnew")" "3" ;;
			esac
		fi
		# 方案A: 只清理 TMPDIR 暫存區 (絕不碰用戶既有的本地 $Backup 備份)
		rm -rf "$TMPDIR/.stream_stage" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		# 遠端json健全度檢查: 流式模式每個app上傳完就已即時上傳json, 此處對本次變更的app做收尾驗證
		if [[ -s $TMPDIR/.changed_apps ]]; then
			echoRgb "—————— 備份後 JSON 結構驗證 ——————" "3"
			local _ra _rfile _jchk_total _jchk_i=1 _jchk_sorted="$TMPDIR/.stream_json_check_apps" _jinvalid=0 _jmissing=0 _jok=0
			sort -u "$TMPDIR/.changed_apps" > "$_jchk_sorted"
			_jchk_total="$(grep -vc '^$' "$_jchk_sorted")"
			while read -r _ra; do
				[[ -z $_ra ]] && continue
				local _rk="${_ra%% *}"
				[[ -z $_rk ]] && _rk="$_ra"
				echoRgb "[$_jchk_i/$_jchk_total] $_ra" "3"
				_rfile="$TMPDIR/.remote_health_check_$$.json"
				if remote_download_single_file "$_rk/app_details.json" "$_rfile" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && [[ -s $_rfile ]]; then
					if _remote_appdetails_json_ok "$_rfile"; then
						let _jok++
						_json_health_check "$_rfile" "$_ra (遠端)"
					else
						let _jinvalid++
						_speed_debug_log "REMOTE_HEALTH_APPDETAILS_INVALID_DROP app=$_ra key=$_rk file=$_rfile"
						echo "$_ra (遠端): app_details.json 無效/下載不完整 ($_rk/app_details.json)" >> "$TMPDIR/.json_health_remote_drops"
					fi
				else
					let _jmissing++
					_speed_debug_log "REMOTE_HEALTH_APPDETAILS_MISSING app=$_ra key=$_rk"
				echo "$_ra (遠端): app_details.json 缺失或下載失敗 ($_rk/app_details.json)" >> "$TMPDIR/.json_health_remote_drops"
				fi
				rm -f "$_rfile" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				let _jchk_i++
			done < "$_jchk_sorted"
			rm -f "$_jchk_sorted"
			echoRgb "檢查完成 $((_jchk_i-1))/$_jchk_total" "1"
			JSON_HEALTH_REPORT_ALWAYS=1
			JSON_HEALTH_CHECKED_COUNT="$_jchk_total"
			JSON_HEALTH_INVALID_COUNT="$_jinvalid"
			JSON_HEALTH_MISSING_COUNT="$_jmissing"
			_json_health_report
		fi
		_remote_netwatch_report
		_remote_netwatch_stop
		return 0
	fi
	if [[ $backup_has_changes = 0 ]]; then
		if [[ $remote_upload_per_app = 1 ]]; then
			echoRgb "逐應用上傳模式：無備份變更，只上傳依賴文件" "2"
		else
			echoRgb "無備份變更，只上傳依賴文件" "2"
		fi
		# 設置標記，跳過應用數據上傳
		REMOTE_SKIP_APPDATA=1
	elif [[ $remote_upload_per_app = 0 && -s "$TMPDIR/.changed_apps" ]]; then
		# 非逐應用上傳模式，但有變更的應用，只上傳變更的應用
		local changed_apps changed_count
		changed_apps="$(sort -u "$TMPDIR/.changed_apps" | tr '\n' ' ')"
		changed_count="$(sort -u "$TMPDIR/.changed_apps" | awk 'END{print NR}')"
		[[ -n $remote_type ]] && echoRgb "僅上傳變更的應用 (共 $changed_count 個): $changed_apps" "2"
		# 設置 REMOTE_APPLIST 為變更的應用列表
		REMOTE_APPLIST="$(sort -u "$TMPDIR/.changed_apps")"
	fi
	case $remote_type in
	webdav) upload_remote "webdav" ;;
	smb) upload_remote "smb" ;;
	*)
		_remote_netwatch_report
		_remote_netwatch_stop
		return 0
		;;
	esac
	REMOTE_SKIP_APPDATA=0
	# 遠端json健全度檢查: 下載剛上傳的 app_details.json 逐一驗證 (確保傳輸/合併過程沒有損壞欄位)
	# 優先用 .changed_apps (本次實際變更上傳的app, 覆蓋面較廣); 無則 fallback REMOTE_APPLIST
	local _health_src
	if [[ -s $TMPDIR/.changed_apps ]]; then
		_health_src="$(sort -u "$TMPDIR/.changed_apps")"
	else
		_health_src="$REMOTE_APPLIST"
	fi
	if [[ -n $_health_src ]]; then
		local _ra _rfile _jchk_total _jchk_i=1
		_jchk_total="$(echo "$_health_src" | grep -vc '^$')"
		while read -r _ra; do
			[[ -z $_ra ]] && continue
			local _rk="${_ra%% *}"
			[[ -z $_rk ]] && _rk="$_ra"
			echoRgb "[$_jchk_i/$_jchk_total] $_ra" "3"
			_rfile="$TMPDIR/.remote_health_check_$$.json"
			if remote_download_single_file "$_rk/app_details.json" "$_rfile" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && [[ -s $_rfile ]]; then
				if _remote_appdetails_json_ok "$_rfile"; then
					_json_health_check "$_rfile" "$_ra (遠端)"
				else
					_speed_debug_log "REMOTE_HEALTH_APPDETAILS_INVALID_DROP app=$_ra key=$_rk file=$_rfile"
					echo "$_ra (遠端): app_details.json 無效/下載不完整 ($_rk/app_details.json)" >> "$TMPDIR/.json_health_remote_drops"
				fi
			fi
			rm -f "$_rfile" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			let _jchk_i++
		done <<EOF4
$_health_src
EOF4
		echoRgb "檢查完成 $((_jchk_i-1))/$_jchk_total" "1"
		_json_health_report
	fi
	unset REMOTE_APPLIST
	_remote_netwatch_report
	_remote_netwatch_stop
}
# 秒 -> Nx天 Ny小時 Nz分鐘 Ns秒 (省略前導 0 單位)
hms() {
	awk -v t="$1" 'BEGIN{
		t=int(t); d=int(t/86400); h=int((t%86400)/3600); m=int((t%3600)/60); s=t%60
		o=""
		if(d>0) o=o d"天 "
		if(o!="" || h>0) o=o h"小時 "
		if(o!="" || m>0) o=o m"分鐘 "
		o=o s"秒"
		printf "%s", o
	}'
}

# 運作時間 + 深度睡眠 (uptime vs CLOCK_MONOTONIC 差 = 深睡時長)
Show_boottime() {
	local BOOT MONO
	BOOT=$(awk '{print $1; exit}' /proc/uptime)
	MONO=$(awk '/now at/{print $3; exit}' /proc/timer_list 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})
	if [[ -z $MONO ]]; then
		hms "$BOOT"
		return
	fi
	awk -v b="$BOOT" -v m="$MONO" 'BEGIN{
		mono=m/1e9; susp=b-mono; if(susp<0)susp=0
		printf "%.0f %.0f %.1f\n", b, susp, susp/b*100
	}' | while read -r rt sp pct; do
		printf "%s\n -深度睡眠:%s (%s%%)" "$(hms "$rt")" "$(hms "$sp")" "$pct"
	done
}
[[ -f /sys/block/sda/size ]] && ROM_TYPE="UFS" || ROM_TYPE="eMMC"
if [[ -f /proc/scsi/scsi ]]; then
	UFS_MODEL="$(sed -n 3p /proc/scsi/scsi | awk '/Vendor/{print $2,$4}')"
else
	UFS_MODEL="$(cat "/sys/class/block/sda/device/inquiry" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	[[ $UFS_MODEL = "" ]] && UFS_MODEL="unknown"
fi
_model="$(getprop ro.product.model 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
Device_name="$(grep -Ew "$_model" "$tools_path/Device_List" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk -F'"' '{print $4}' | head -1)"
[[ $Device_name = "" ]] && Device_name="$_model"
if command -v su >/dev/null 2>&1; then
	Manager_version="$(su -v 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
else
	Manager_version=""
fi
if [[ $Manager_version != "" ]]; then
	[[ $Manager_version = *KernelSU* ]] && ksu="ksu"
	[[ $ksu = "" && -d /data/adb/ksu ]] && ksu="ksu"
else
	if [[ -d /data/adb/ksu ]]; then
		Manager_version=KernelSU
		ksu="ksu"
	fi
fi
Socname="$(getprop ro.soc.model)"
if [[ $Socname != "" && -f $tools_path/soc.json ]]; then
	DEVICE_NAME="$(jq -r --arg device "$Socname" '.[$device] | "處理器:\(.VENDOR) \(.NAME)"' "$tools_path/soc.json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	RAMINFO="$(jq -r --arg device "$Socname" '.[$device] | "RAM:\(.MEMORY) \(.CHANNELS)"' "$tools_path/soc.json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	[[ $DEVICE_NAME = null || $DEVICE_NAME = "" ]] && DEVICE_NAME="處理器:null"
	[[ $RAMINFO = null || $RAMINFO = "" ]] && RAMINFO="RAM:null"
else
	DEVICE_NAME="處理器:null"
	RAMINFO="RAM:null"
fi
_brand="$(getprop ro.product.brand 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
_device="$(getprop ro.product.device 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
_busybox_path="$(which busybox)"
_busybox_ver="$(busybox | head -1 | cut -d' ' -f2)"
echoRgb "---------------------SpeedBackup---------------------"
echoRgb "腳本路徑:$MODDIR\n -已開機:$(Show_boottime)\n -執行時間:$(date +"%Y-%m-%d %H:%M:%S")\n -busybox路徑:$_busybox_path\n -busybox版本:$_busybox_ver\n -腳本版本:$backup_version\n -管理器:$Manager_version\n -品牌:$_brand\n -型號:$Device_name($_device)\n -閃存顆粒:$UFS_MODEL($ROM_TYPE)\n -$DEVICE_NAME\n -$RAMINFO\n -Android版本:$release SDK:$sdk\n -內核:$(uname -r)\n -Selinux狀態:$([[ $(getenforce) = Permissive ]] && echo "寬容" || echo "嚴格")\n -By@YAWAsau\n -Support: https://jq.qq.com/?_wv=1027&k=f5clPNC3"
case $MODDIR in
*Backup_*)
	if [[ -f $MODDIR/app_details.json ]]; then
		if [[ -d ${MODDIR%/*/*}/tools ]]; then
			path_hierarchy="${MODDIR%/*/*}"
		else
			path_hierarchy="${MODDIR%/*}"
		fi
	else
		if [[ -d ${MODDIR%/*}/tools ]]; then
			path_hierarchy="${MODDIR%/*}"
		else
			[[ -d $MODDIR/tools ]] && path_hierarchy="$MODDIR"
		fi
	fi ;;
*) [[ -d $MODDIR/tools ]] && path_hierarchy="$MODDIR" ;;
esac
[[ $SCRIPT_LANG = "" ]] && echoRgb "系統無參數語言獲取失敗\n -如果需要更改腳本語言請於$conf_path\n -Shell_LANG=填入對應數字" "0"
case $SCRIPT_LANG in
*TW* | *tw* | *HK*)
	Script_target_language="zh-TW" ;;
*CN* | *cn*)
	Script_target_language="zh-CN" ;;
esac
echoRgb "$Script_target_language腳本"
# v24.20.14-7.22：dex版本已包含在上方設備資訊，不再額外輸出一次。
# 二選一互動 helper (統一音量鍵)
# 用法 A (return 模式): ask_yn "提示" "選項1" "選項2"
#   選項1 → return 0, 選項2 → return 1
#   例: ask_yn "確認?" "確認" "取消" && do_it
#
# 用法 B (變數模式): ask_yn "提示" "選項1" "選項2" 變數名
#   結果寫入指定變數 (true/false)，同時設 $branch
#   例: ask_yn "備份模式?" "完整" "僅APK" Backup_Mode
ask_yn() {
	local _msg="$1" _opt1="$2" _opt2="$3" _var="$4"
	echoRgb "$_msg\n -音量上=$_opt1, 音量下=$_opt2" "2"
	get_version "$_opt1" "$_opt2"
	# 變數模式: 把結果寫入指定變數
	if [[ -n $_var ]]; then
		eval "$_var=\"\$branch\""
	fi
	[[ $branch = true ]]
}
# 獨立二選一 helper, 不依賴全域 Lo (給 user/update/low_battery_mode/外部儲存等
# 各自有專屬 conf 開關的情境用): 變數已有值就跳過詢問, 沒有就一律走音量鍵詢問
# 用法: ask_yn_indep "提示" "選項1" "選項2" 變數名
ask_yn_indep() {
	local _msg="$1" _opt1="$2" _opt2="$3" _var="$4" _cur
	if [[ -n $_var ]]; then
		eval "_cur=\"\$$_var\""
		if [[ -n $_cur ]]; then
			isBoolean "$_cur" "$_var" && eval "$_var=\"\$nsx\""
			[[ $nsx = true ]]; return
		fi
	fi
	echoRgb "$_msg\n -音量上=$_opt1, 音量下=$_opt2" "2"
	get_version "$_opt1" "$_opt2"
	[[ -n $_var ]] && eval "$_var=\"\$branch\""
	[[ $branch = true ]]
}
if [[ ! -f ${0%/*}/app_details.json ]]; then
	if [[ $user = "" ]]; then
		user_id="$(ls /data/user | tr ' ' '\n')"
		if [[ $user_id != "" && $(ls /data/user | tr ' ' '\n' | wc -l) -gt 1 ]]; then
			echo "$user_id" | while read -r; do
				[[ $REPLY = 0 ]] && echoRgb "主用戶:$REPLY" "2" || echoRgb "分身用戶:$REPLY" "2"
			done
			echoRgb "設備存在多用戶,選擇操作目標用戶"
			if [[ $(printf "%s\n" "$user_id" | awk 'END{print NR}') = 2 ]]; then
				user1="$(echo "$user_id" | sed -n '1p')"
				user2="$(echo "$user_id" | sed -n '2p')"
				echoRgb "音量上選擇用戶:$user1，音量下選擇用戶:$user2" "2"
				Select_user="true"
				get_version "$user1" "$user2" && user="$branch"
				unset Select_user
			else
				while true ;do
					if [[ $option != "" ]]; then
						user="$option"
						break
					else
						echoRgb "請輸入需要操作目標分區" "1"
						read option
					fi
				done
			fi
		else
			user="0"
		fi
	else
		user_id="$(ls /data/user | tr ' ' '\n')"
		if [[ $user_id != "" && $(ls /data/user | tr ' ' '\n' | wc -l) -gt 1 ]]; then
			echo "$user_id" | while read -r; do
				[[ $REPLY = 0 ]] && echoRgb "主用戶:$REPLY" "2" || echoRgb "分身用戶:$REPLY" "2"
			done
		else
			echoRgb "主用戶:$user_id" "2"
		fi
	fi
else
	case $(echo "${0%}") in
	*Backup_zstd_*) user="$(echo "${0%}" | sed 's/.*\/Backup_zstd_\([0-9]*\).*/\1/')" ;;
	*Backup_tar_*) user="$(echo "${0%}" | sed 's/.*\/Backup_tar_\([0-9]*\).*/\1/')" ;;
	*) echoRgb "請勿修改備份資料夾名稱，保持原本的Backup_壓縮算法名稱_使用者id" "0" && exit 2 ;;
	esac
fi
[[ $user != 0 ]] && am start-user "$user"
path="/data/media/$user/Android"
path2="/data/user/$user"
path3="/data/user_de/$user"
[[ ! -d $path2 ]] && echoRgb "$user分區不存在，請將上方提示的用戶id按照需求填入\n -$conf_path配置項user=,一次只能填寫一個" "0" && exit 2
echoRgb "當前操作為用戶$user"
export USER_ID="$user"
unset LD_LIBRARY_PATH
#因接收USER_ID環境變量問題故將函數放在此處
# dex 調用 wrapper: _dex_debug=1 時記錄每次調用到 speed_debug/dex_call.log (用於確認批量/預掃是否生效)
# 平時 _dex_debug 為 0, 零額外開銷; 要監控時在腳本開頭或環境設 _dex_debug=1
# ============================================================
# SpeedBackup single-file section: sb_20_dex_wifi_update.sh
# ============================================================
_dex_context_from_args() {
	local _a _class="" _next=0
	for _a in "$@"; do
		if [[ $_next = 1 ]]; then
			printf '%s:%s\n' "${_class##*.}" "$_a"
			return 0
		fi
		case $_a in
			com.xayah.dex.*) _class="$_a"; _next=1 ;;
		esac
	done
	printf '%s\n' "unknown"
}

_dex_kv_get() {
	local _line="$1" _key="$2"
	printf '%s\n' "$_line" | sed -n "s/.*[[:space:]]$_key=\\([^[:space:]]*\\).*/\\1/p" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_dex_reason_zh() {
	local _r="$1"
	case $_r in
		*VERSION_DOWNGRADE*|*INSTALL_FAILED_VERSION_DOWNGRADE*) echo "版本降級被系統阻擋" ;;
		*UPDATE_INCOMPATIBLE*|*INSTALL_FAILED_UPDATE_INCOMPATIBLE*) echo "簽名或既有安裝版本不相容" ;;
		*MISSING_SPLIT*|*INSTALL_FAILED_MISSING_SPLIT*) echo "缺少必要 split APK" ;;
		*NO_MATCHING_ABIS*|*INSTALL_FAILED_NO_MATCHING_ABIS*) echo "ABI 架構不相容" ;;
		*INSUFFICIENT_STORAGE*|*INSTALL_FAILED_INSUFFICIENT_STORAGE*) echo "儲存空間不足" ;;
		*INVALID_APK*|*INSTALL_PARSE_FAILED*) echo "APK 無效或解析失敗" ;;
		*LOW_TARGET_SDK*|*INSTALL_FAILED_DEPRECATED_SDK_VERSION*) echo "targetSdk 過低被系統阻擋" ;;
		*SecurityException*|*Security*) echo "權限不足或被系統拒絕" ;;
		*NameNotFoundException*|*NameNotFound*) echo "找不到套件或該使用者未安裝" ;;
		*IllegalArgumentException*|*IllegalArgument*) echo "參數格式或值不正確" ;;
		*InvocationTargetException*|*ReflectiveOperationException*) echo "隱藏 API 反射呼叫失敗" ;;
		*NullPointerException*) echo "系統回傳空值導致操作失敗" ;;
		""|-) echo "無詳細原因" ;;
		*) echo "$_r" ;;
	esac
}

_dex_source_zh() {
	case "$1" in
		PACKAGE_SOURCE_STORE|store) echo "商店安裝" ;;
		PACKAGE_SOURCE_LOCAL_FILE|local) echo "本機檔案安裝" ;;
		PACKAGE_SOURCE_DOWNLOADED_FILE|downloaded) echo "下載檔案安裝" ;;
		PACKAGE_SOURCE_OTHER|other) echo "其他來源" ;;
		PACKAGE_SOURCE_UNSPECIFIED|unspecified|""|null) echo "未指定來源" ;;
		*) echo "$1" ;;
	esac
}

_dex_bool_zh() {
	case "$1" in
		true|TRUE|1) echo "是" ;;
		false|FALSE|0) echo "否" ;;
		*) echo "$1" ;;
	esac
}

_dex_human_emit() {
	[[ ${SPEED_DEBUG_DEX_TRANSLATE:-1} = 1 ]] || return 0
	local _pkg="$1" _msg="$2" _line
	[[ -z $_msg ]] && return 0
	[[ -z $_pkg ]] && _pkg="dex"
	_line="[$(date '+%H:%M:%S' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})] $_pkg $_msg"
	if [[ -n ${SPEED_DEBUG_DEX_HUMAN_LOG:-} ]]; then
		mkdir -p "${SPEED_DEBUG_DEX_HUMAN_LOG%/*}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		printf '%s\n' "$_line" >> "$SPEED_DEBUG_DEX_HUMAN_LOG" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	fi
	[[ ${SPEED_DEBUG_DEX_TRANSLATE_TERMINAL:-0} = 1 ]] && echoRgb "$_pkg $_msg" "2"
	return 0
}
_dex_translate_failed_skip() {
	local _line="$1" _key _pkg _reason _msg
	_key="${_line%% *}"
	_pkg="$(_dex_kv_get "$_line" package)"
	_reason="$(_dex_kv_get "$_line" reason)"
	_msg="$(_dex_reason_zh "$_reason")"
	case $_key in
		PACKAGE_UID_FAILED_SKIP) _dex_human_emit "$_pkg" "讀取 UID 失敗：$_msg" ;;
		PACKAGE_LABEL_FAILED_SKIP) _dex_human_emit "$_pkg" "讀取應用名稱失敗：$_msg" ;;
		INSTALL_SOURCE_FAILED_SKIP) _dex_human_emit "$_pkg" "讀取安裝來源診斷失敗：$_msg" ;;
		APPOPS_SCOPE_PACKAGE_FAILED_SKIP) _dex_human_emit "$_pkg" "讀取 AppOps scope 失敗：$_msg" ;;
		FORCE_STOP_FAILED_SKIP) _dex_human_emit "$_pkg" "停止應用失敗，已略過" ;;
		*) _dex_human_emit "${_pkg:-dex}" "dex 操作略過：$_key ${_reason:+原因=$(_dex_reason_zh "$_reason")}" ;;
	esac
}

_appops_cmd_op_name() {
	# v24.20.14-7.55: 依目前 dex/verify 實際 op 編號修正 cmd appops 名稱映射。
	# 映射不確定的 op 保持空值，避免讀錯 AppOp 後產生誤導診斷。
	case "$1" in
	0) echo COARSE_LOCATION ;;
	1) echo FINE_LOCATION ;;
	11) echo POST_NOTIFICATION ;;
	24) echo SYSTEM_ALERT_WINDOW ;;
	26) echo CAMERA ;;
	27) echo RECORD_AUDIO ;;
	66) echo REQUEST_INSTALL_PACKAGES ;;
	67) echo PICTURE_IN_PICTURE ;;
	76) echo START_FOREGROUND ;;
	81) echo READ_MEDIA_AUDIO ;;
	83) echo READ_MEDIA_VIDEO ;;
	85) echo READ_MEDIA_IMAGES ;;
	89) echo READ_DEVICE_IDENTIFIERS ;;
	90) echo ACCESS_MEDIA_LOCATION ;;
	92) echo MANAGE_EXTERNAL_STORAGE ;;
	107) echo SCHEDULE_EXACT_ALARM ;;
	119) echo ACCESS_RESTRICTED_SETTINGS ;;
	123) echo READ_MEDIA_VISUAL_USER_SELECTED ;;
	133) echo USE_FULL_SCREEN_INTENT ;;
	154) echo __CMD_UNSUPPORTED_CAMERA_SOURCE__ ;;
	155) echo __CMD_UNSUPPORTED_RECORD_AUDIO_SOURCE__ ;;
	*) echo "" ;;
	esac
}

_appops_cmd_mode_to_num() {
	case "$1" in
	allow|allowed) echo 0 ;;
	ignore|ignored) echo 1 ;;
	deny|denied|errored) echo 2 ;;
	default) echo 3 ;;
	foreground|fg) echo 4 ;;
	*) echo "?" ;;
	esac
}

_appops_cmd_extract_mode() {
	# v24.20.14-7.64：分開解析 package 行與 Uid mode 行。
	# Android 16 的 cmd appops get 可能同時輸出：
	#   Uid mode: CAMERA: ignore
	#   CAMERA: allow
	# package scope 應讀普通 OP 行；uid scope 應優先讀 Uid mode 行。
	awk -v want="${2:-package}" '
		function clean_mode(x){
			gsub(/^[[:space:]]+/,"",x); gsub(/[;[:space:]].*$/, "", x);
			return x;
		}
		BEGIN{m=""; uidm=""; pkgm=""}
		/No operations|No ops|not set|未設定/ { if(pkgm=="") pkgm="default"; if(uidm=="") uidm="default" }
		/Uid mode[[:space:]]*:/ {
			line=$0;
			sub(/^.*Uid mode[[:space:]]*:[[:space:]]*/,"",line);
			sub(/^[^:]*:[[:space:]]*/,"",line);
			line=clean_mode(line);
			if(line!="") uidm=line;
			next;
		}
		/:/ {
			line=$0;
			sub(/^[^:]*:[[:space:]]*/,"",line);
			line=clean_mode(line);
			if(line!="") pkgm=line;
		}
		END{
			if(want=="uid") m=(uidm!=""?uidm:pkgm);
			else m=(pkgm!=""?pkgm:uidm);
			if(m=="") m="unknown";
			print m;
		}
	' "$1" 2>/dev/null
}
_appops_scope_detail_report() {
	# v24.20.14-7.66-4：修正 dex scope detail awk 相容；保留 runtime actual 補入與 package/uid 分開解析。
	# 這只產生 debug 診斷，不參與 restore/verify 判定。
	local _expect="$1" _actual="${2:-}" _out _raw _scope_in _pkg _op _mode _name _pkgraw _uidraw _pkgmode _uidmode _pkgnum _uidnum _note
	local _scope_args _dex_scope _dex_ok
	[ -n "${SPEED_DEBUG_RUN_DIR:-}" ] && [ -d "$SPEED_DEBUG_RUN_DIR" ] && [ -s "$_expect" ] || return 0
	_out="$SPEED_DEBUG_RUN_DIR/appops_scope_detail.log"
	_raw="$SPEED_DEBUG_RUN_DIR/appops_scope_detail.raw.log"
	_scope_in="$TMPDIR/.appops_scope_expect_$$"
	: > "$_out" 2>/dev/null
	: > "$_raw" 2>/dev/null
	: > "$_scope_in" 2>/dev/null
	cat "$_expect" > "$_scope_in" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# canonical otherAppOps 不重複保存 CAMERA/RECORD_AUDIO/LOCATION 等 permission-linked op；
	# 從 verify actual 補進來，才能診斷「每次詢問」相關 package/uid 雙狀態。
	if [ -n "$_actual" ] && [ -s "$_actual" ]; then
		awk -F'\t' '($2=="0"||$2=="1"||$2=="11"||$2=="26"||$2=="27"||$2=="81"||$2=="83"||$2=="85"||$2=="123"){k=$1"\t"$2; if(!seen[k]++) print $1"\t"$2"\t"$3}' "$_actual" >> "$_scope_in" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	fi
	awk -F'\t' '!seen[$1"\t"$2]++' "$_scope_in" > "$_scope_in.dedup" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	mv "$_scope_in.dedup" "$_scope_in" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_scope_args="$(awk -F'\t' '
		$1!="" && $2!="" { ops[$1]=ops[$1]" "$2 }
		END { for (p in ops) printf "[%s%s] ", p, ops[p] }
	' "$_scope_in" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	_dex_scope="$TMPDIR/.appops_scope_dex_$$"
	_dex_ok=0
	if [ -n "$_scope_args" ]; then
		dex_hiddenapi_raw appOpsScopeDetail "${USER_ID:-0}" "$_scope_args" > "$_dex_scope" 2>>"$_raw"
		if grep -q '^APPOPS_SCOPE_DETAIL_OK' "$_dex_scope" 2>/dev/null; then
			_dex_ok=1
		fi
	fi
	if [ "$_dex_ok" = 1 ]; then
		{
			echo "# appops uid/package scope detail"
			echo "# source=dex appOpsScopeDetail；package_mode/uid_mode/effective_mode 由單次 JVM 讀取。"
			echo "# runtime permission op 已從 verify actual 補入，方便診斷每次詢問/僅前台的 package/uid 雙狀態。"
			echo "# note=ASK_EVERY_TIME_OK/FOREGROUND_OK 屬已知正常語意；SCOPE_MISMATCH_WARN 才需要搭配 permission_semantic_verify 判斷。"
		} >> "$_out" 2>/dev/null
		awk -F'\t' '
			function kv(line,k,  n,a,i,p){ n=split(line,a,/ +/); for(i=1;i<=n;i++){ split(a[i],p,"="); if(p[1]==k){ sub("^[^=]*=","",a[i]); return a[i] } } return "" }
			NR==FNR { key=$1 "\t" $2; expected[key]=$3; next }
			/^APPOPS_SCOPE / {
				pkg=kv($0,"package"); op=kv($0,"op"); name=kv($0,"name"); pm=kv($0,"package_mode"); um=kv($0,"uid_mode"); em=kv($0,"effective_mode"); note=kv($0,"note");
				key=pkg "\t" op;
				if ((key) in expected) e=expected[key]; else e="?";
				if(note=="ASK_EVERY_TIME_OK") n="ASK_EVERY_TIME_OK";
				else if(note=="FOREGROUND_OK") n="FOREGROUND_OK";
				else if(note=="UID_MODE_UNAVAILABLE") n="uid讀取未知";
				else if(note=="OK" && em!=e) n="effective讀回與dex合併mode不同，需確認scope";
				else n=note;
				printf "%s\top=%s\tcmd_op=%s\texpect=%s\tpackage_mode=%s\tuid_mode=%s\teffective_mode=%s\tnote=%s\n", pkg, op, name, e, pm, um, em, n;
			}
		' "$_scope_in" "$_dex_scope" >> "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		rm -f "$_dex_scope" "$_scope_in" 2>/dev/null
		return 0
	fi
	rm -f "$_dex_scope" 2>/dev/null
	command -v cmd >/dev/null 2>&1 || { rm -f "$_scope_in" 2>/dev/null; return 0; }
	{
		echo "# appops uid/package scope detail"
		echo "# source=cmd fallback；新版 dex appOpsScopeDetail 不可用或未輸出 OK。"
		echo "# package_mode 來自: cmd appops get --user ${USER_ID:-0} <pkg> <op>"
		echo "# uid_mode 來自: cmd appops get --uid <pkg> <op> 的 Uid mode 行；若 ROM/cmd 不支援會顯示未知，不算恢復錯。"
		echo "# runtime permission op 已從 verify actual 補入，方便診斷每次詢問/僅前台的 package/uid 雙狀態。"
	} >> "$_out" 2>/dev/null
	while IFS='	' read -r _pkg _op _mode; do
		[ -n "$_pkg" ] && [ -n "$_op" ] || continue
		_name="$(_appops_cmd_op_name "$_op")"
		case "$_name" in
		__CMD_UNSUPPORTED_*)
			printf '%s\top=%s\tcmd_op=不支援cmd查詢\texpect=%s\tpackage_mode=略過\tuid_mode=略過\tnote=dex合併mode可用，cmd scope略過\n' "$_pkg" "$_op" "$_mode" >> "$_out" 2>/dev/null
			continue
			;;
		esac
		if [ -z "$_name" ]; then
			printf '%s\top=%s\tcmd_op=未知\texpect=%s\tpackage_mode=未支援\tuid_mode=未支援\tnote=op未映射\n' "$_pkg" "$_op" "$_mode" >> "$_out" 2>/dev/null
			continue
		fi
		_pkgraw="$TMPDIR/.appops_scope_pkg_${_op}_$$"
		_uidraw="$TMPDIR/.appops_scope_uid_${_op}_$$"
		cmd appops get --user "${USER_ID:-0}" "$_pkg" "$_name" > "$_pkgraw" 2>>"$_raw" < /dev/null
		cmd appops get --uid "$_pkg" "$_name" > "$_uidraw" 2>>"$_raw" < /dev/null
		_pkgmode="$(_appops_cmd_extract_mode "$_pkgraw" package)"
		_uidmode="$(_appops_cmd_extract_mode "$_uidraw" uid)"
		_pkgnum="$(_appops_cmd_mode_to_num "$_pkgmode")"
		_uidnum="$(_appops_cmd_mode_to_num "$_uidmode")"
		_note="OK"
		if [ "$_pkgnum" = "0" ] && [ "$_uidnum" = "1" ] && _appops_is_runtime_scope_op "$_op"; then
			_note="ASK_EVERY_TIME_OK"
		elif { [ "$_pkgnum" = "4" ] || [ "$_uidnum" = "4" ]; } && _appops_is_runtime_scope_op "$_op"; then
			_note="FOREGROUND_OK"
		elif [ "$_pkgnum" != "$_uidnum" ] && [ "$_uidnum" != "unknown" ]; then
			_note="SCOPE_MISMATCH_WARN: package/uid不同"
		elif [ "$_pkgnum" != "$_mode" ]; then
			_note="cmd讀回與dex合併mode不同，需確認cmd_op映射或scope"
		fi
		printf '%s\top=%s\tcmd_op=%s\texpect=%s\tpackage_mode=%s(%s)\tuid_mode=%s(%s)\tnote=%s\n' "$_pkg" "$_op" "$_name" "$_mode" "$_pkgnum" "$_pkgmode" "$_uidnum" "$_uidmode" "$_note" >> "$_out" 2>/dev/null
		rm -f "$_pkgraw" "$_uidraw" 2>/dev/null
	done < "$_scope_in"
	rm -f "$_scope_in" 2>/dev/null
}
_dex_translate_line() {
	local _line="$1" _ctx="$2" _pkg _tag _ev _key _val _msg _b _c _status _source _op _mode _perm
	[[ -n $_line ]] || return 0
	case $_line in
		*FAILED_SKIP*) _dex_translate_failed_skip "$_line"; return 0 ;;
		APPOPS_SCOPE_DETAIL_OK*) _dex_human_emit "dex" "AppOps scope detail 批量讀取完成：${_line#APPOPS_SCOPE_DETAIL_OK }"; return 0 ;;
		INSTALL_METHOD\ *)
			set -- $_line; _pkg="$2"; _ev="$3"
			case $_ev in
				dex_play_session) _msg="安裝方式：Play UID hybrid session 安裝" ;;
				dex_play_session_success) _msg="Play UID hybrid session 安裝成功" ;;
				dex_play_session_failed) _msg="Play UID hybrid session 安裝失敗" ;;
				hybrid_installer_pm) _msg="安裝方式：混合安裝來源 pm" ;;
				hybrid_installer_pm_success) _msg="混合安裝來源commit成功" ;;
				hybrid_installer_pm_failed) _msg="混合安裝來源commit失敗" ;;
				hybrid_installer_pm_source_deferred) _msg="混合安裝來源驗證延後到批量驗證" ;;
				hybrid_installer_pm_source_mismatch) _msg="混合安裝來源不完整，準備回退" ;;
				installer_context_ok) _msg="備份安裝來源有效：${_line#* installer_context_ok }" ;;
				installer_context_pm_only) _msg="備份安裝來源僅用於 pm -i：${_line#* installer_context_pm_only }" ;;
				installer_context_skip) _msg="略過備份安裝來源：${_line#* installer_context_skip }" ;;
				pm_fallback_after_dex_failed) _msg="dex 安裝失敗，已回退 pm 安裝" ;;
				pm_install) _msg="安裝方式：pm install 單 APK" ;;
				pm_install_create) _msg="安裝方式：pm install-create split session" ;;
				dex_play_session_options) _msg="Play session 參數：${_line#* dex_play_session_options }" ;;
				*) _msg="安裝流程：$_ev" ;;
			esac
			_dex_human_emit "$_pkg" "$_msg"; return 0 ;;
	esac
	set -- $_line
	_pkg="$1"; _tag="$2"; _ev="$3"
	case $_tag in
		INSTALL_SESSION)
			case $_ev in
				options) _dex_human_emit "$_pkg" "安裝 session 參數：${_line#* INSTALL_SESSION options }" ;;
				apkCount) _dex_human_emit "$_pkg" "APK 檔案數：$4" ;;
				totalBytes) _dex_human_emit "$_pkg" "APK 總大小：$4 bytes" ;;
				installerContext) _dex_human_emit "$_pkg" "安裝呼叫來源 context：$4" ;;
				sessionId) _dex_human_emit "$_pkg" "已建立安裝 session：$4" ;;
				wrote) _dex_human_emit "$_pkg" "已寫入 APK：$4 ${5:+($5 bytes)}" ;;
				committed) _dex_human_emit "$_pkg" "已提交安裝 session：$4" ;;
				packageFound) _dex_human_emit "$_pkg" "安裝完成，已找到套件 versionCode=${5:-未知}" ;;
				packageNotFoundAfterWait) _dex_human_emit "$_pkg" "安裝提交後等待逾時，仍未找到套件" ;;
				failed) _dex_human_emit "$_pkg" "安裝流程失敗：$(_dex_reason_zh "${4:-UNKNOWN}")" ;;
				failureCode) _dex_human_emit "$_pkg" "安裝失敗代碼：$4（$(_dex_reason_zh "$4")）" ;;
				failureHint) _dex_human_emit "$_pkg" "安裝失敗提示：$(_dex_reason_zh "${_line#* failureHint }")" ;;
				sourceVerifyFailed) _dex_human_emit "$_pkg" "安裝後來源驗證呼叫失敗：$(_dex_reason_zh "${4:-UNKNOWN}")" ;;
				warnNonApkFile) _dex_human_emit "$_pkg" "警告：略過非 APK 檔案 $4" ;;
				warnUnknownOption) _dex_human_emit "$_pkg" "警告：未知 installSession 選項 $4" ;;
				warnUnknownInstallFlag) _dex_human_emit "$_pkg" "警告：系統不支援 install flag $4" ;;
				warnUnknownClearInstallFlag) _dex_human_emit "$_pkg" "警告：系統不支援清除 install flag $4" ;;
				warnInstallFlagsUnsupported) _dex_human_emit "$_pkg" "警告：此系統不支援反射設定 installFlags：$4" ;;
				warnParamUnsupported) _dex_human_emit "$_pkg" "警告：此系統不支援 session 參數 $4" ;;
				warnArchiveUnreadable)
					case "$4" in
						split_config.*.apk)
							_speed_debug_log "$_pkg config split APK 預檢無法讀取，已降噪略過: $4"
							;;
						*) _dex_human_emit "$_pkg" "警告：APK 無法讀取 $4" ;;
					esac ;;
				warnPackageMismatch) _dex_human_emit "$_pkg" "警告：APK package 與目標套件不一致：${_line#* warnPackageMismatch }" ;;
				warnArchiveCheckFailed) _dex_human_emit "$_pkg" "警告：APK 預檢失敗：${_line#* warnArchiveCheckFailed }" ;;
				warnMixedPackages) _dex_human_emit "$_pkg" "警告：APK 組合內含多個 package（$4 種）" ;;
				warnMixedVersionCodes) _dex_human_emit "$_pkg" "警告：APK 組合 versionCode 不一致（$4 種）" ;;
				warnMixedSignatures) _dex_human_emit "$_pkg" "警告：APK 組合簽章不一致（$4 種）" ;;
				archive) _dex_human_emit "$_pkg" "APK 預檢：${_line#* INSTALL_SESSION archive }" ;;
				installFlagAdd) _dex_human_emit "$_pkg" "加入 install flag：$4" ;;
				installFlagClear) _dex_human_emit "$_pkg" "清除 install flag：$4" ;;
				installFlags) _dex_human_emit "$_pkg" "installFlags：${_line#* INSTALL_SESSION installFlags }" ;;
				permissionState) _dex_human_emit "$_pkg" "權限預設狀態：$4" ;;
				*) case $_ev in sessionInfo*|SessionParams*|params*) return 0 ;; *) _dex_human_emit "$_pkg" "安裝 session：$_ev ${_line#* INSTALL_SESSION $_ev }" ;; esac ;;
			esac ;;
		INSTALL_DIAG)
			_key="$3"; _val="$4"
			case $_key in
				installer) _dex_human_emit "$_pkg" "installer=${_val:-null}" ;;
				installing) _dex_human_emit "$_pkg" "installing=${_val:-null}" ;;
				initiating) _dex_human_emit "$_pkg" "initiating=${_val:-null}" ;;
				packageSourceName) _dex_human_emit "$_pkg" "來源類型：$(_dex_source_zh "$_val")" ;;
				versionCode) _dex_human_emit "$_pkg" "目前版本碼：$_val" ;;
				versionName) _dex_human_emit "$_pkg" "目前版本名稱：$_val" ;;
				signingSha256) _dex_human_emit "$_pkg" "目前簽章 SHA-256：$_val" ;;
				splitCount) _dex_human_emit "$_pkg" "split 數量：$_val" ;;
				updateOwner|updateOwnerApi) _dex_human_emit "$_pkg" "update owner：${_val:-null}" ;;
				playStoreInstalled|playServicesInstalled|playStoreEnabled|playServicesEnabled) _dex_human_emit "$_pkg" "${_key}=$(_dex_bool_zh "$_val")" ;;
				*) return 0 ;;
			esac ;;
		*)
			case $_ctx in
				NetworkUtil:restoreNetworks) case $_line in *\ restored) _dex_human_emit "WiFi" "已還原網路：${_line% restored}" ;; *\ not\ exists!) _dex_human_emit "WiFi" "還原失敗：檔案不存在 ${_line% not exists!}" ;; esac ;;
				NotificationUtil:notify) case $_line in *Failed*|*failed*) _dex_human_emit "NotificationUtil" "通知工具失敗：$_line" ;; esac ;;
			esac ;;
	esac
}

_dex_translate_file() {
	[[ ${SPEED_DEBUG_DEX_TRANSLATE:-1} = 1 ]] || return 0
	local _file="$1" _ctx="$2" _line
	[[ -s $_file ]] || return 0
	while IFS= read -r _line; do
		_dex_translate_line "$_line" "$_ctx"
	done < "$_file"
	return 0
}

_dex_filter_human_stdout() {
	# dex 的英文 key/stdout 給腳本解析，HUMAN 中文行不可混入解析結果。
	grep -v ' HUMAN ' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_speed_debug_append_stderr_filtered() {
	# 統一過濾「正常但寫到 stderr」的訊息，避免污染 stderr.log。
	# HUMAN → dex_human.log；SELinux/uidexec context → command.log；其餘才進 stderr.log。
	local _err="$1" _line _cmd_log="${SPEED_DEBUG_CMD_LOG:-${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/command.log}"
	[[ -s $_err ]] || return 0
	while IFS= read -r _line; do
		[[ -z $_line ]] && continue
		case $_line in
		*' HUMAN '*)
			# v23 dex HUMAN 中文提示屬預期提示，寫 dex_human.log，不進 stderr.log。
			if [[ -n ${SPEED_DEBUG_DEX_HUMAN_LOG:-} ]]; then
				mkdir -p "${SPEED_DEBUG_DEX_HUMAN_LOG%/*}" 2>/dev/null
				printf '%s\n' "$_line" >> "$SPEED_DEBUG_DEX_HUMAN_LOG" 2>/dev/null
			fi
			;;
		'SELinux: Loaded file context'*|'SELinux: Skipping restorecon'*|'running as uid='*)
			# restorecon / uidexec 的正常狀態訊息，移到 command.log。
			mkdir -p "${_cmd_log%/*}" 2>/dev/null
			printf '%s\n' "$_line" >> "$_cmd_log" 2>/dev/null
			;;
		'HTTP 0')
			# HttpUtil 更新檢查/普通 GET 離線時會輸出 HTTP 0；流程已有「更新取得失敗」提示，這裡只收進 command.log。
			mkdir -p "${_cmd_log%/*}" 2>/dev/null
			printf '%s\n' "$_line" >> "$_cmd_log" 2>/dev/null
			;;
		*)
			if [[ -n ${SPEED_DEBUG_ERR_LOG:-} && ${SPEED_DEBUG_ERR_LOG:-/dev/null} != /dev/null ]]; then
				printf '%s\n' "$_line" >> "$SPEED_DEBUG_ERR_LOG" 2>/dev/null
			else
				printf '%s\n' "$_line" >&2
			fi
			;;
		esac
	done < "$_err"
}

_dex_append_nonhuman_stderr() {
	# dex/uidexec stderr 統一分類：HUMAN 不進 stderr.log，非預期錯誤才進 stderr.log。
	_speed_debug_append_stderr_filtered "$1"
}

# smbclient 的 -c 命令字串是它自己的簡易解析器, ';' 分隔多命令、'!' 前綴本機 shell 執行,
# 且該解析對雙引號內的內容也一樣切分 (無法靠加引號規避)。任何要拼進 -c 字串的遠端/清單可控
# 名稱, 必須先過這關: 含 ';' '!' 換行/回車一律拒絕, 呼叫端收到非 0 要中止該筆操作。
_smb_safe_component() {
	case "$1" in
	*';'*|*'!'*|*$'\n'*|*$'\r'*) return 1 ;;
	esac
	return 0
}

_smb_output_has_error() {
	# smbclient 對 mkdir 已存在會輸出 NT_STATUS_OBJECT_NAME_COLLISION，這不是錯誤。
	# 其餘 NT_STATUS / denied / badpath / failed 才視為實際失敗。
	printf '%s\n' "$1" \
		| grep -viE 'NT_STATUS_OBJECT_NAME_COLLISION|NT_STATUS_OBJECT_NAME_EXISTS|already exists|File exists' 2>/dev/null \
		| grep -qiE 'NT_STATUS|ERRbadpath|does not exist|Unable to|Failed to|failed|denied|session setup|tree connect|Connection refused|Connection reset'
}

remote_smb_write_precheck() {
	# 真流式 SMB 不會落地完整備份；進入 app 迴圈前必須確認遠端可建立目錄/寫入/刪除。
	# 否則只做 TCP 預檢會把「可連線但不可寫」誤判成功，最後每個流式 put 都失敗。
	[[ ${remote_type:-} = smb ]] || return 0
	remote_parse_smb_url
	local _auth _subdir _base _base_bslash _probe_local _probe_remote _script _out _rc _cur _seg _OLDIFS _opts
	_auth="$(_smb_auth_args_current)" || { echoRgb "SMB 認證資訊不可用，無法做寫入預檢" "0"; return 1; }
	_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	_base="$SMB_REM_PATH/$_subdir"
	_base="${_base#/}"
	_base="${_base%/}"
	if ! _smb_safe_component "$_base"; then
		echoRgb "SMB 遠端路徑含不安全字元，已停止: $_base" "0"
		return 1
	fi
	_probe_local="$TMPDIR/.smb_write_probe_$$"
	_probe_remote=".speedbackup_write_probe_$$.tmp"
	_script="$TMPDIR/.smb_write_precheck_$$"
	printf 'speedbackup-smb-write-precheck\n' > "$_probe_local" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	: > "$_script" || { rm -f "$_probe_local" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; return 1; }
	_cur=""
	_OLDIFS="$IFS"; IFS='/'; set -- $_base; IFS="$_OLDIFS"
	for _seg; do
		[[ -z $_seg ]] && continue
		if [[ -z $_cur ]]; then _cur="$_seg"; else _cur="$_cur\\$_seg"; fi
		printf 'mkdir "%s"\n' "$_cur" >> "$_script"
	done
	_base_bslash="${_base//\//\\}"
	[[ -z $_base_bslash ]] && _base_bslash="\\"
	printf 'cd "%s"\n' "$_base_bslash" >> "$_script"
	printf 'lcd "%s"\n' "${TMPDIR:-/data/local/tmp}" >> "$_script"
	printf 'put "%s" "%s"\n' "${_probe_local##*/}" "$_probe_remote" >> "$_script"
	printf 'del "%s"\n' "$_probe_remote" >> "$_script"
	printf 'exit\n' >> "$_script"
	_opts="-t 30 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
	_out="$(command smbclient "$SMB_SHARE" $_auth $_opts < "$_script" 2>&1)"
	_rc=$?
	remote_raw_log "remote_smb_write_precheck.log" "BEGIN share=$SMB_SHARE base=$_base rc=$_rc probe=$_probe_remote"
	printf '%s\n' "$_out" >> "$(_speed_debug_log_path remote_smb_write_precheck.log)" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	rm -f "$_probe_local" "$_script" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [[ $_rc != 0 ]] || _smb_output_has_error "$_out"; then
		_speed_debug_log "SMB_WRITE_PREFLIGHT_FAIL share=$SMB_SHARE base=$_base rc=$_rc"
		echoRgb "SMB 寫入預檢失敗：遠端可連線，但無法在 $_base 建立/寫入/刪除測試檔" "0"
		echoRgb "請檢查 SMB share 寫入權限、Guest/匿名權限、Windows 共用權限與 NTFS 權限" "3"
		return 1
	fi
	_speed_debug_log "SMB_WRITE_PREFLIGHT_OK share=$SMB_SHARE base=$_base"
	return 0
}

_dex_raw() {
	# 給 JSON / zip / 純文字 payload 使用：不翻譯、不過濾、不暫存，只保留原始 stdout。
	# stderr 先過濾 HUMAN，再收進 speed_debug，避免預期中文提示污染 stderr.log。
	local _dex_err="${TMPDIR:-/data/local/tmp}/.dex_stderr_${$}_$RANDOM" _dex_rc
	_dex_exec_unfiltered "$@" 2>"$_dex_err"
	_dex_rc=$?
	_dex_append_nonhuman_stderr "$_dex_err"
	rm -f "$_dex_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	return $_dex_rc
}

_dex() {
	[[ $_dex_debug = 1 ]] && {
		local _c
		for _c in "$@"; do case $_c in
			getInstalled*|getPackage*|setDisplay*|restoreAppState*|verifyAppState*|getInstallSourceInfo|installSessionCreate|installSessionCommit|appOpsScopeDetail) echo "$_c" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/dex_call.log"; break ;;
		esac; done
	}
	local _dex_out _dex_err _dex_rc _dex_ctx
	_dex_ctx="$(_dex_context_from_args "$@")"
	_dex_out="${TMPDIR:-/data/local/tmp}/.dex_stdout_${$}_$RANDOM"
	_dex_err="${TMPDIR:-/data/local/tmp}/.dex_stderr_${$}_$RANDOM"
	_dex_exec_unfiltered "$@" > "$_dex_out" 2>"$_dex_err"
	_dex_rc=$?
	_dex_append_nonhuman_stderr "$_dex_err"
	_dex_translate_file "$_dex_out" "$_dex_ctx"
	_dex_filter_human_stdout < "$_dex_out"
	rm -f "$_dex_out" "$_dex_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	return $_dex_rc
}

# 批量 dex 調用 wrapper：xargs 不能直接使用 alias / shell function，
# 所以批量恢復統一集中到這裡，避免 _flush_batch_appstate 內散落多段 xargs app_process。
# 用法: _dex_xargs <HiddenApiUtil方法> <輸入檔> [輸出檔]
_dex_xargs() {
	local _method="$1" _in="$2" _out="$3" _tmp _rc
	[[ -n $_method && -s $_in ]] || return 0
	_tmp="${TMPDIR:-/data/local/tmp}/.dex_xargs_${_method}_${$}_$RANDOM"
	local _xerr="${TMPDIR:-/data/local/tmp}/.dex_xargs_stderr_${_method}_${$}_$RANDOM"
	_dex_export_classpath
	xargs "$DEX_APP_PROCESS_BIN" "$DEX_APP_PROCESS_BASE" com.xayah.dex.HiddenApiUtil "$_method" "$USER_ID" < "$_in" > "$_tmp" 2>"$_xerr"
	_rc=$?
	_dex_append_nonhuman_stderr "$_xerr"
	rm -f "$_xerr" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_dex_translate_file "$_tmp" "HiddenApiUtil:$_method"
	if [[ -n $_out ]]; then
		_dex_filter_human_stdout < "$_tmp" > "$_out"
	fi
	rm -f "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	return $_rc
}

# HiddenApi / Notification AF_UNIX daemon：熱路徑避免每次 app_process 重啟。
_hidden_notify_parse_status() {
	local _status="$1" _line
	_line="$(sed -n '1p' "$_status" 2>/dev/null)"
	_HOTDEX_RESULT_CODE="$(printf '%s\n' "$_line" | awk '$1=="RESULT" && $2 ~ /^[0-9]+$/ {print $2; exit}')"
	_HOTDEX_RESULT_NAME="$(printf '%s\n' "$_line" | awk '$1=="RESULT" && NF>=3 {print $3; exit}')"
	case $_HOTDEX_RESULT_CODE in ''|*[!0-9]*) _HOTDEX_RESULT_CODE=70; return 1 ;; esac
	[[ -n $_HOTDEX_RESULT_NAME ]] || _HOTDEX_RESULT_NAME="UNKNOWN"
	return 0
}

_hotdex_body_from_args() {
	local _body="$1" _arg
	shift
	: > "$_body" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	for _arg in "$@"; do
		printf '%s\n' "$_arg" >> "$_body" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	done
}

_HIDDENAPI_DAEMON_SOCKET="${_HIDDENAPI_DAEMON_SOCKET:-$TMPDIR/.hiddenapi_daemon.sock}"
_HIDDENAPI_DAEMON_PID_FILE="${_HIDDENAPI_DAEMON_PID_FILE:-$TMPDIR/.hiddenapi_daemon.pid}"
_HIDDENAPI_DAEMON_START_LOCK="${_HIDDENAPI_DAEMON_START_LOCK:-$TMPDIR/.hiddenapi_daemon.start.lock}"
_HIDDENAPI_DAEMON_READY=0

_hiddenapi_daemon_probe() {
	local _status _body _rc
	_webdav_unixsock_relay_ready || return 1
	[[ -S $_HIDDENAPI_DAEMON_SOCKET ]] || return 1
	_status="$(_webdav_tmp_path hiddenapi_probe_status)"
	_body="$(_webdav_tmp_path hiddenapi_probe_body)"
	rm -f "$_status" "$_body" 2>/dev/null
	printf 'ping\n1\n0\n' | "$EVENT_UNIXSOCK_BIN" relay-unix "$_HIDDENAPI_DAEMON_SOCKET" --header-file "$_status" > "$_body" 2>/dev/null
	_rc=$?
	_hidden_notify_parse_status "$_status"
	if [[ $_rc = 0 && $_HOTDEX_RESULT_CODE = 0 ]] && grep -Fqx 'PONG' "$_body" 2>/dev/null; then
		rm -f "$_status" "$_body" 2>/dev/null
		return 0
	fi
	rm -f "$_status" "$_body" 2>/dev/null
	return 1
}

_hiddenapi_daemon_stop() {
	_dex_watchdog_stop hiddenapi
	local _pid _cmd _i=0
	_pid="$(cat "$_HIDDENAPI_DAEMON_PID_FILE" 2>/dev/null)"
	case $_pid in ''|*[!0-9]*) _pid="" ;; esac
	if [[ -n $_pid ]] && kill -0 "$_pid" 2>/dev/null; then
		_cmd="$(_webdav_proc_cmdline "$_pid")"
		case "$_cmd" in *"com.xayah.dex.HiddenApiUtil daemonunix $_HIDDENAPI_DAEMON_SOCKET"*)
			_event_terminate_pid "$_pid" hiddenapi_daemon_stop
			;;
		esac
	fi
	rm -f "$_HIDDENAPI_DAEMON_PID_FILE" "$TMPDIR/.hiddenapi_daemon_out" "$_HIDDENAPI_DAEMON_SOCKET" 2>/dev/null
	rmdir "$_HIDDENAPI_DAEMON_START_LOCK" 2>/dev/null || true
	_HIDDENAPI_DAEMON_READY=0
}

_hiddenapi_daemon_wait_ready() {
	local _out="$1" _pid="$2" _i=0
	case $_pid in ''|*[!0-9]*) return 1 ;; esac
	_event_filewatch_once "$_out" 5 hiddenapi_ready >/dev/null 2>&1 || true
	_hiddenapi_daemon_probe && return 0
	while [[ $_i -lt 80 ]]; do
		kill -0 "$_pid" 2>/dev/null || return 1
		_hiddenapi_daemon_probe && return 0
		sleep 0.1
		_i=$((_i + 1))
	done
	return 1
}

_hiddenapi_daemon_ensure() {
	local _pid _out="$TMPDIR/.hiddenapi_daemon_out" _err _have_lock=0 _i=0
	if [[ $_HIDDENAPI_DAEMON_READY = 1 ]] && _hiddenapi_daemon_probe; then return 0; fi
	_HIDDENAPI_DAEMON_READY=0
	if _hiddenapi_daemon_probe; then _HIDDENAPI_DAEMON_READY=1; return 0; fi
	_webdav_unixsock_relay_ready || return 1
	if mkdir "$_HIDDENAPI_DAEMON_START_LOCK" 2>/dev/null; then
		_have_lock=1
	else
		while [[ $_i -lt 80 ]]; do
			_hiddenapi_daemon_probe && { _HIDDENAPI_DAEMON_READY=1; return 0; }
			[[ -d $_HIDDENAPI_DAEMON_START_LOCK ]] || break
			sleep 0.1
			_i=$((_i + 1))
		done
		rmdir "$_HIDDENAPI_DAEMON_START_LOCK" 2>/dev/null
		mkdir "$_HIDDENAPI_DAEMON_START_LOCK" 2>/dev/null && _have_lock=1
	fi
	[[ $_have_lock = 1 ]] || return 1
	_hiddenapi_daemon_stop
	: > "$_out" 2>/dev/null || { rmdir "$_HIDDENAPI_DAEMON_START_LOCK" 2>/dev/null; return 1; }
	_err="$(_speed_debug_log_path hiddenapi_daemon_stderr.log)"
	_dex_export_classpath
	nohup "$DEX_APP_PROCESS_BIN" "$DEX_APP_PROCESS_BASE" com.xayah.dex.HiddenApiUtil daemonunix "$_HIDDENAPI_DAEMON_SOCKET" 1800 "$SPEEDBACKUP_MAIN_PID" > "$_out" 2>>"$_err" &
	_pid=$!
	disown "$_pid" 2>/dev/null
	_speedbackup_protect_pid "$_pid" hiddenapi_daemon
	printf '%s\n' "$_pid" > "$_HIDDENAPI_DAEMON_PID_FILE" 2>/dev/null
	chmod 0600 "$_HIDDENAPI_DAEMON_PID_FILE" 2>/dev/null
	if _hiddenapi_daemon_wait_ready "$_out" "$_pid"; then
		_HIDDENAPI_DAEMON_READY=1
		rmdir "$_HIDDENAPI_DAEMON_START_LOCK" 2>/dev/null
		_speed_debug_log "HIDDENAPI_DAEMON_START_OK pid=$_pid socket=$_HIDDENAPI_DAEMON_SOCKET"
		_dex_watchdog_start hiddenapi "$_HIDDENAPI_DAEMON_PID_FILE" "$_HIDDENAPI_DAEMON_SOCKET" com.xayah.dex.HiddenApiUtil daemonunix "$_HIDDENAPI_DAEMON_SOCKET" 1800 "$SPEEDBACKUP_MAIN_PID"
		return 0
	fi
	_speed_debug_log "HIDDENAPI_DAEMON_START_FAIL pid=$_pid out=$(cat "$_out" 2>/dev/null)"
	_hiddenapi_daemon_stop
	return 1
}

_hiddenapi_daemon_call_file() {
	local _command="$1" _in="$2" _out="$3" _status _len _relay_rc _try=0 _max_try=3
	[[ -n $_command && -f $_in && -n $_out ]] || return 2
	while [[ $_try -lt $_max_try ]]; do
		_hiddenapi_daemon_ensure || {
			_speed_debug_log "HIDDENAPI_DAEMON_ENSURE_FAIL command=$_command try=$_try"
			_daemon_retry_sleep "$_try" hiddenapi
			_try=$((_try + 1))
			continue
		}
		_status="$(_webdav_tmp_path hiddenapi_status)"
		_len="$(_local_file_size_debug "$_in")"
		case $_len in ''|*[!0-9]*) _len=0 ;; esac
		rm -f "$_status" "$_out" 2>/dev/null
		{ printf '%s\n1\n%s\n' "$_command" "$_len"; cat "$_in"; } | "$EVENT_UNIXSOCK_BIN" relay-unix "$_HIDDENAPI_DAEMON_SOCKET" --header-file "$_status" > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_relay_rc=$?
		if [[ $_relay_rc = 0 ]] && _hidden_notify_parse_status "$_status"; then
			_speed_debug_log "HIDDENAPI_CALL command=$_command result=$_HOTDEX_RESULT_CODE name=$_HOTDEX_RESULT_NAME bytes=$(_local_file_size_debug "$_out") try=$_try"
			rm -f "$_status" 2>/dev/null
			return "$_HOTDEX_RESULT_CODE"
		fi
		_speed_debug_log "HIDDENAPI_CALL_TRANSPORT_FAIL command=$_command relay_rc=$_relay_rc try=$_try"
		rm -f "$_status" 2>/dev/null
		_HIDDENAPI_DAEMON_READY=0
		_hiddenapi_daemon_stop
		_daemon_retry_sleep "$_try" hiddenapi
		_try=$((_try + 1))
	done
	return 125
}

_hiddenapi_daemon_call_args() {
	local _command="$1" _body _out _rc
	shift
	_body="$(_webdav_tmp_path hiddenapi_args)"
	_out="$(_webdav_tmp_path hiddenapi_out)"
	_hotdex_body_from_args "$_body" "$@" || { rm -f "$_body" "$_out" 2>/dev/null; return 125; }
	_hiddenapi_daemon_call_file "$_command" "$_body" "$_out"
	_rc=$?
	cat "$_out" 2>/dev/null
	rm -f "$_body" "$_out" 2>/dev/null
	return $_rc
}

_NOTIFY_DAEMON_SOCKET="${_NOTIFY_DAEMON_SOCKET:-$TMPDIR/.notify_daemon.sock}"
_NOTIFY_DAEMON_PID_FILE="${_NOTIFY_DAEMON_PID_FILE:-$TMPDIR/.notify_daemon.pid}"
_NOTIFY_DAEMON_START_LOCK="${_NOTIFY_DAEMON_START_LOCK:-$TMPDIR/.notify_daemon.start.lock}"
_NOTIFY_DAEMON_READY=0

_notify_daemon_probe() {
	# v24.20.14-7.66-270: NotificationUtil v2.6.1 may leak PONG to daemon stdout on some ROM/R8 builds.
	# Probe readiness by framed RESULT only; notification body is not required by tools.sh.
	local _status _body _rc
	_webdav_unixsock_relay_ready || return 1
	[[ -S $_NOTIFY_DAEMON_SOCKET ]] || return 1
	_status="$(_webdav_tmp_path notify_probe_status)"
	_body="$(_webdav_tmp_path notify_probe_body)"
	rm -f "$_status" "$_body" 2>/dev/null
	printf 'ping\n1\n0\n' | "$EVENT_UNIXSOCK_BIN" relay-unix "$_NOTIFY_DAEMON_SOCKET" --header-file "$_status" > "$_body" 2>/dev/null
	_rc=$?
	_hidden_notify_parse_status "$_status"
	if [[ $_rc = 0 && $_HOTDEX_RESULT_CODE = 0 ]]; then
		rm -f "$_status" "$_body" 2>/dev/null
		return 0
	fi
	rm -f "$_status" "$_body" 2>/dev/null
	return 1
}

_notify_daemon_alive() {
	local _pid
	[[ -S $_NOTIFY_DAEMON_SOCKET ]] || return 1
	_pid="$(cat "$_NOTIFY_DAEMON_PID_FILE" 2>/dev/null)"
	case $_pid in ''|*[!0-9]*) return 0 ;; esac
	kill -0 "$_pid" 2>/dev/null
}

_notify_daemon_ready_line_ok() {
	local _out="$1"
	grep -Fqx "NOTIFY_DAEMON_READY_UNIX $_NOTIFY_DAEMON_SOCKET" "$_out" 2>/dev/null && [[ -S $_NOTIFY_DAEMON_SOCKET ]] && return 0
	grep -Fqx "NOTIFICATION_DAEMON_READY_UNIX $_NOTIFY_DAEMON_SOCKET" "$_out" 2>/dev/null && [[ -S $_NOTIFY_DAEMON_SOCKET ]] && return 0
	return 1
}

_notify_daemon_wait_ready() {
	local _out="$1" _pid="$2" _i=0
	case $_pid in ''|*[!0-9]*) return 1 ;; esac
	_event_filewatch_once "$_out" 5 notify_ready >/dev/null 2>&1 || true
	_notify_daemon_ready_line_ok "$_out" && return 0
	while [[ $_i -lt 50 ]]; do
		kill -0 "$_pid" 2>/dev/null || break
		_notify_daemon_ready_line_ok "$_out" && return 0
		sleep 0.1
		_i=$((_i + 1))
	done
	return 1
}

_notify_daemon_stop() {
	_dex_watchdog_stop notify
	local _pid _cmd _i=0
	_pid="$(cat "$_NOTIFY_DAEMON_PID_FILE" 2>/dev/null)"
	case $_pid in ''|*[!0-9]*) _pid="" ;; esac
	if [[ -n $_pid ]] && kill -0 "$_pid" 2>/dev/null; then
		_cmd="$(_webdav_proc_cmdline "$_pid")"
		case "$_cmd" in *"com.xayah.dex.NotificationUtil daemonunix $_NOTIFY_DAEMON_SOCKET"*)
			_event_terminate_pid "$_pid" notify_daemon_stop
			;;
		esac
	fi
	rm -f "$_NOTIFY_DAEMON_PID_FILE" "$TMPDIR/.notify_daemon_out" "$_NOTIFY_DAEMON_SOCKET" 2>/dev/null
	rmdir "$_NOTIFY_DAEMON_START_LOCK" 2>/dev/null || true
	_NOTIFY_DAEMON_READY=0
}

_notify_daemon_ensure() {
	local _pid _out="$TMPDIR/.notify_daemon_out" _err _have_lock=0 _i=0
	if [[ $_NOTIFY_DAEMON_READY = 1 ]] && _notify_daemon_alive; then return 0; fi
	_NOTIFY_DAEMON_READY=0
	if _notify_daemon_probe; then _NOTIFY_DAEMON_READY=1; return 0; fi
	_webdav_unixsock_relay_ready || return 1
	if mkdir "$_NOTIFY_DAEMON_START_LOCK" 2>/dev/null; then _have_lock=1; else rmdir "$_NOTIFY_DAEMON_START_LOCK" 2>/dev/null; mkdir "$_NOTIFY_DAEMON_START_LOCK" 2>/dev/null && _have_lock=1; fi
	[[ $_have_lock = 1 ]] || return 1
	_notify_daemon_stop
	: > "$_out" 2>/dev/null || { rmdir "$_NOTIFY_DAEMON_START_LOCK" 2>/dev/null; return 1; }
	_err="$(_speed_debug_log_path notify_daemon_stderr.log)"
	_dex_export_classpath
	nohup "$DEX_APP_PROCESS_BIN" "$DEX_APP_PROCESS_BASE" com.xayah.dex.NotificationUtil daemonunix "$_NOTIFY_DAEMON_SOCKET" 1800 "$SPEEDBACKUP_MAIN_PID" > "$_out" 2>>"$_err" &
	_pid=$!
	disown "$_pid" 2>/dev/null
	_speedbackup_protect_pid "$_pid" notify_daemon
	printf '%s\n' "$_pid" > "$_NOTIFY_DAEMON_PID_FILE" 2>/dev/null
	chmod 0600 "$_NOTIFY_DAEMON_PID_FILE" 2>/dev/null
	if _notify_daemon_wait_ready "$_out" "$_pid"; then
		_NOTIFY_DAEMON_READY=1
		rmdir "$_NOTIFY_DAEMON_START_LOCK" 2>/dev/null
		_speed_debug_log "NOTIFY_DAEMON_START_OK pid=$_pid"
		_dex_watchdog_start notify "$_NOTIFY_DAEMON_PID_FILE" "$_NOTIFY_DAEMON_SOCKET" com.xayah.dex.NotificationUtil daemonunix "$_NOTIFY_DAEMON_SOCKET" 1800 "$SPEEDBACKUP_MAIN_PID"
		return 0
	fi
	# Ready line 可能被舊 daemon stdout 噪音混入；最後只做一次 framed probe，避免每 0.1 秒 ping 造成 PONG 刷屏與卡頓。
	if _notify_daemon_probe; then
		_NOTIFY_DAEMON_READY=1
		rmdir "$_NOTIFY_DAEMON_START_LOCK" 2>/dev/null
		_speed_debug_log "NOTIFY_DAEMON_START_OK pid=$_pid probe=fallback"
		_dex_watchdog_start notify "$_NOTIFY_DAEMON_PID_FILE" "$_NOTIFY_DAEMON_SOCKET" com.xayah.dex.NotificationUtil daemonunix "$_NOTIFY_DAEMON_SOCKET" 1800 "$SPEEDBACKUP_MAIN_PID"
		return 0
	fi
	_speed_debug_log "NOTIFY_DAEMON_START_FAIL pid=$_pid out=$(cat "$_out" 2>/dev/null)"
	_notify_daemon_stop
	return 1
}

_notify_daemon_call_file() {
	local _command="$1" _in="$2" _out="$3" _status _len _relay_rc _try=0 _max_try=2
	[[ -n $_command && -f $_in && -n $_out ]] || return 2
	while [[ $_try -lt $_max_try ]]; do
		_notify_daemon_ensure || {
			_speed_debug_log "NOTIFY_DAEMON_ENSURE_FAIL command=$_command try=$_try"
			_daemon_retry_sleep "$_try" notify
			_try=$((_try + 1))
			continue
		}
		_status="$(_webdav_tmp_path notify_status)"
		_len="$(_local_file_size_debug "$_in")"
		case $_len in ''|*[!0-9]*) _len=0 ;; esac
		rm -f "$_status" "$_out" 2>/dev/null
		{ printf '%s\n1\n%s\n' "$_command" "$_len"; cat "$_in"; } | "$EVENT_UNIXSOCK_BIN" relay-unix "$_NOTIFY_DAEMON_SOCKET" --header-file "$_status" > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_relay_rc=$?
		if [[ $_relay_rc = 0 ]] && _hidden_notify_parse_status "$_status"; then
			_speed_debug_log "NOTIFY_CALL command=$_command result=$_HOTDEX_RESULT_CODE name=$_HOTDEX_RESULT_NAME bytes=$(_local_file_size_debug "$_out") try=$_try"
			rm -f "$_status" 2>/dev/null
			return "$_HOTDEX_RESULT_CODE"
		fi
		_speed_debug_log "NOTIFY_CALL_TRANSPORT_FAIL command=$_command relay_rc=$_relay_rc try=$_try"
		rm -f "$_status" 2>/dev/null
		_NOTIFY_DAEMON_READY=0
		_notify_daemon_stop
		_daemon_retry_sleep "$_try" notify
		_try=$((_try + 1))
	done
	return 125
}

# Play UID PackageInstaller daemon。此 daemon 必須由 uidexec 以 Play UID 啟動，不能與 root/shell HiddenApi daemon 混用。
_INSTALL_DAEMON_SOCKET="${_INSTALL_DAEMON_SOCKET:-$TMPDIR/.install_daemon.sock}"
_INSTALL_DAEMON_PID_FILE="${_INSTALL_DAEMON_PID_FILE:-$TMPDIR/.install_daemon.pid}"
_INSTALL_DAEMON_RUNTIME_DIR=""
_INSTALL_DAEMON_READY=0
_INSTALL_DAEMON_KEY=""

_install_daemon_stop() {
	local _pid _i=0
	_pid="$(cat "$_INSTALL_DAEMON_PID_FILE" 2>/dev/null)"
	case $_pid in ''|*[!0-9]*) _pid="" ;; esac
	if [[ -n $_pid ]] && kill -0 "$_pid" 2>/dev/null; then
		_event_terminate_pid "$_pid" install_daemon_stop
	fi
	rm -f "$_INSTALL_DAEMON_PID_FILE" "$TMPDIR/.install_daemon_out" "$_INSTALL_DAEMON_SOCKET" 2>/dev/null
	case "$_INSTALL_DAEMON_RUNTIME_DIR" in
	"$TMPDIR"/.speedbackup_install_daemon_u*) rm -rf "$_INSTALL_DAEMON_RUNTIME_DIR" 2>/dev/null ;;
	esac
	_INSTALL_DAEMON_RUNTIME_DIR=""
	_INSTALL_DAEMON_READY=0
	_INSTALL_DAEMON_KEY=""
}

_install_daemon_bind_socket_path() {
	local _play_uid="$1" _dir
	case "$TMPDIR" in
	"/data/local/tmp") ;;
	*) _speed_debug_log "INSTALL_DAEMON_SOCKET_BIND_FAIL reason=bad_tmpdir tmp=$TMPDIR"; return 1 ;;
	esac
	case $_play_uid in ""|*[!0-9]*) return 1 ;; esac
	_dir="$TMPDIR/.speedbackup_install_daemon_u${user:-0}_${_play_uid}"
	_INSTALL_DAEMON_RUNTIME_DIR="$_dir"
	_INSTALL_DAEMON_SOCKET="$_dir/install.sock"
	return 0
}

_install_daemon_prepare_socket() {
	local _play_uid="$1" _dir
	_install_daemon_bind_socket_path "$_play_uid" || return 1
	_dir="$_INSTALL_DAEMON_RUNTIME_DIR"
	rm -rf "$_dir" 2>/dev/null
	mkdir -p "$_dir" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	chown "$_play_uid:$_play_uid" "$_dir" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	chmod 0770 "$_dir" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	rm -f "$_INSTALL_DAEMON_SOCKET" 2>/dev/null
	_speed_debug_log "INSTALL_DAEMON_SOCKET_READY dir=$_dir socket=$_INSTALL_DAEMON_SOCKET owner=$_play_uid"
	return 0
}

_install_daemon_probe() {
	local _status _body _rc _daemon_out
	_webdav_unixsock_relay_ready || return 1
	[[ -S $_INSTALL_DAEMON_SOCKET ]] || return 1
	_status="$(_webdav_tmp_path install_probe_status)"
	_body="$(_webdav_tmp_path install_probe_body)"
	rm -f "$_status" "$_body" 2>/dev/null
	printf 'ping\n1\n0\n' | "$EVENT_UNIXSOCK_BIN" relay-unix "$_INSTALL_DAEMON_SOCKET" --header-file "$_status" > "$_body" 2>/dev/null
	_rc=$?
	if [[ $_rc = 0 ]] && _hidden_notify_parse_status "$_status" && [[ $_HOTDEX_RESULT_CODE = 0 ]] && grep -Fqx 'PONG' "$_body" 2>/dev/null; then
		rm -f "$_status" "$_body" 2>/dev/null
		return 0
	fi
	# Some Play-UID HiddenApi daemon builds leak ping output to daemon stdout while
	# relay status is not materialized quickly enough.  Treat a filesystem socket
	# plus READY/PONG stdout as ready, but only for the readiness probe.
	_daemon_out="$TMPDIR/.install_daemon_out"
	if [[ $_rc = 0 && -S $_INSTALL_DAEMON_SOCKET ]] \
		&& grep -q '^HIDDENAPI_DAEMON_READY_UNIX ' "$_daemon_out" 2>/dev/null \
		&& grep -q '^PONG$' "$_daemon_out" 2>/dev/null; then
		_speed_debug_log "INSTALL_DAEMON_PROBE_STDOUT_READY socket=$_INSTALL_DAEMON_SOCKET"
		rm -f "$_status" "$_body" 2>/dev/null
		return 0
	fi
	rm -f "$_status" "$_body" 2>/dev/null
	return 1
}

_install_daemon_ensure() {
	local _play_uid="$1" _art_dir="$2" _dex_dst="$3" _key _pid _out="$TMPDIR/.install_daemon_out" _err _i=0
	_key="$_play_uid|$_art_dir|$_dex_dst"
	# 294: 批量 !AppName 恢復時，主迴圈/清理流程可能讓 shell 狀態歸零，
	# 但 Play UID daemon 與 AF_UNIX socket 仍活著。先綁回固定 socket path 並 probe，
	# 避免誤殺既有 daemon 後每個 App 都重新 uidexec/app_process。
	_install_daemon_bind_socket_path "$_play_uid" || return 1
	if _install_daemon_probe; then
		_INSTALL_DAEMON_READY=1
		_INSTALL_DAEMON_KEY="$_key"
		_speed_debug_log "INSTALL_DAEMON_REUSE_EXISTING_SOCKET play_uid=$_play_uid socket=$_INSTALL_DAEMON_SOCKET key=$_key"
		return 0
	fi
	_INSTALL_DAEMON_READY=0
	_INSTALL_DAEMON_KEY=""
	_install_daemon_stop
	_webdav_unixsock_relay_ready || return 1
	_install_daemon_prepare_socket "$_play_uid" || return 1
	: > "$_out" 2>/dev/null || return 1
	_err="$(_speed_debug_log_path install_daemon_stderr.log)"
	# Install daemon runs as Play UID.  Some ROMs hide the root/su owner pid from
	# app UIDs, causing the shared DaemonBootstrap ownerPid validation to exit
	# before binding the socket.  Start this short-lived install daemon without
	# ownerPid and rely on a small idle timeout plus tools-side socket cleanup.
	_speed_debug_log "INSTALL_DAEMON_OWNERLESS_START play_uid=$_play_uid idleSec=60 reason=play_uid_proc_visibility"
	uidexec "$_play_uid" "$_play_uid" "$_art_dir" "$_dex_dst" \
		"$(_dex_app_process_abs)" "$DEX_APP_PROCESS_BASE" com.xayah.dex.HiddenApiUtil daemonunix "$_INSTALL_DAEMON_SOCKET" 60 > "$_out" 2>>"$_err" &
	_pid=$!
	disown "$_pid" 2>/dev/null
	_speedbackup_protect_pid "$_pid" install_daemon
	printf '%s\n' "$_pid" > "$_INSTALL_DAEMON_PID_FILE" 2>/dev/null
	chmod 0600 "$_INSTALL_DAEMON_PID_FILE" 2>/dev/null
	_event_filewatch_once "$_out" 5 install_ready >/dev/null 2>&1 || true
	_install_daemon_probe && { _INSTALL_DAEMON_READY=1; _INSTALL_DAEMON_KEY="$_key"; _speed_debug_log "INSTALL_DAEMON_START_OK pid=$_pid play_uid=$_play_uid wait=filewatch"; return 0; }
	# uidexec may exit before the Play-UID app_process daemon has fully written its
	# READY/PONG line.  Do not break the readiness loop only because the launcher
	# pid is gone; keep probing the socket/stdout for the bounded window.
	while [[ $_i -lt 50 ]]; do
		_install_daemon_probe && { _INSTALL_DAEMON_READY=1; _INSTALL_DAEMON_KEY="$_key"; _speed_debug_log "INSTALL_DAEMON_START_OK pid=$_pid play_uid=$_play_uid wait=probe_loop i=$_i launcher_alive=$(kill -0 "$_pid" 2>/dev/null && echo 1 || echo 0)"; return 0; }
		if ! kill -0 "$_pid" 2>/dev/null && [[ ! -S $_INSTALL_DAEMON_SOCKET ]] && ! grep -q '^HIDDENAPI_DAEMON_READY_UNIX ' "$_out" 2>/dev/null; then
			_speed_debug_log "INSTALL_DAEMON_WAIT_AFTER_LAUNCHER_EXIT pid=$_pid i=$_i socket=0 ready=0"
		fi
		sleep 0.1
		_i=$((_i + 1))
	done
	_speed_debug_log "INSTALL_DAEMON_START_FAIL pid=$_pid out=$(cat "$_out" 2>/dev/null)"
	_install_daemon_stop
	return 1
}

_install_daemon_call_args() {
	local _play_uid="$1" _art_dir="$2" _dex_dst="$3" _command="$4" _body _out _rc _status _len _relay_rc
	shift 4
	_body="$(_webdav_tmp_path install_args)"
	_out="$(_webdav_tmp_path install_out)"
	_hotdex_body_from_args "$_body" "$@" || { rm -f "$_body" "$_out" 2>/dev/null; return 125; }
	_install_daemon_ensure "$_play_uid" "$_art_dir" "$_dex_dst" || { rm -f "$_body" "$_out" 2>/dev/null; return 125; }
	_status="$(_webdav_tmp_path install_status)"
	_len="$(_local_file_size_debug "$_body")"; case $_len in ''|*[!0-9]*) _len=0 ;; esac
	rm -f "$_out" "$_status" 2>/dev/null
	{ printf '%s\n1\n%s\n' "$_command" "$_len"; cat "$_body"; } | "$EVENT_UNIXSOCK_BIN" relay-unix "$_INSTALL_DAEMON_SOCKET" --header-file "$_status" > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_relay_rc=$?
	if [[ $_relay_rc = 0 ]] && _hidden_notify_parse_status "$_status"; then
		_rc="$_HOTDEX_RESULT_CODE"
		cat "$_out" 2>/dev/null
	else
		# Fallback for relays that return the daemon framed response in stdout
		# instead of splitting RESULT into --header-file.  Keep it install-daemon
		# local; other daemon paths already have stable framing.
		_rc="$(awk 'NR==1 && $1=="RESULT" && $2 ~ /^[0-9]+$/ {print $2; exit}' "$_out" 2>/dev/null)"
		if [[ -n $_rc ]]; then
			_speed_debug_log "INSTALL_DAEMON_RAW_RESULT_FALLBACK command=$_command result=$_rc"
			awk 'NR<=2 {next} {print}' "$_out" 2>/dev/null
		else
			_INSTALL_DAEMON_READY=0
			_rc=125
			cat "$_out" 2>/dev/null
		fi
	fi
	rm -f "$_body" "$_out" "$_status" 2>/dev/null
	return $_rc
}

# AppState daemon framed call；snapshot/restore/verify 共用同一顆 JVM。
# ===== AppState AF_UNIX daemon（Dex 2.5.0 structured engine）=====
# request/response framing 與 WebDAV daemon 相同地由 unixsock v2 做 binary-safe relay；
# AppState payload 為 UTF-8 NDJSON，不使用 command substitution 承載大批量快照。
_APPSTATE_DAEMON_SOCKET="${_APPSTATE_DAEMON_SOCKET:-$TMPDIR/.appstate_daemon.sock}"
_APPSTATE_DAEMON_PID_FILE="${_APPSTATE_DAEMON_PID_FILE:-$TMPDIR/.appstate_daemon.pid}"
_APPSTATE_DAEMON_START_LOCK="${_APPSTATE_DAEMON_START_LOCK:-$TMPDIR/.appstate_daemon.start.lock}"
_APPSTATE_DAEMON_READY=0
_APPSTATE_RESULT_CODE=70
_APPSTATE_RESULT_NAME="INTERNAL_ERROR"
_APPSTATE_CAPABILITY_STATE=0

_appstate_parse_status() {
	local _status="$1" _line
	_line="$(sed -n '1p' "$_status" 2>/dev/null)"
	_APPSTATE_RESULT_CODE="$(printf '%s\n' "$_line" | awk '$1=="RESULT" && $2 ~ /^[0-9]+$/ {print $2; exit}')"
	_APPSTATE_RESULT_NAME="$(printf '%s\n' "$_line" | awk '$1=="RESULT" && NF>=3 {print $3; exit}')"
	case $_APPSTATE_RESULT_CODE in ''|*[!0-9]*) _APPSTATE_RESULT_CODE=70; return 1 ;; esac
	[[ -n $_APPSTATE_RESULT_NAME ]] || _APPSTATE_RESULT_NAME="UNKNOWN"
	return 0
}

_appstate_daemon_probe() {
	local _status _body _rc
	_webdav_unixsock_relay_ready || return 1
	[[ -S $_APPSTATE_DAEMON_SOCKET ]] || return 1
	_status="$(_webdav_tmp_path appstate_probe_status)"
	_body="$(_webdav_tmp_path appstate_probe_body)"
	rm -f "$_status" "$_body" 2>/dev/null
	printf 'ping\n0\nndjson\n\n1\n0\n' \
		| "$EVENT_UNIXSOCK_BIN" relay-unix "$_APPSTATE_DAEMON_SOCKET" --header-file "$_status" > "$_body" 2>/dev/null
	_rc=$?
	_appstate_parse_status "$_status"
	if [[ $_rc = 0 && $_APPSTATE_RESULT_CODE = 0 ]] && grep -Fqx 'PONG' "$_body" 2>/dev/null; then
		rm -f "$_status" "$_body" 2>/dev/null
		return 0
	fi
	rm -f "$_status" "$_body" 2>/dev/null
	return 1
}

_appstate_daemon_stop() {
	_dex_watchdog_stop appstate
	local _keep_lock="$1" _pid _cmd _i=0 _owned=0
	_pid="$(cat "$_APPSTATE_DAEMON_PID_FILE" 2>/dev/null)"
	case $_pid in ''|*[!0-9]*) _pid="" ;; esac
	if [[ -n $_pid ]] && kill -0 "$_pid" 2>/dev/null; then
		_cmd="$(_webdav_proc_cmdline "$_pid")"
		case "$_cmd" in
		*"com.xayah.dex.AppStateUtil daemonunix $_APPSTATE_DAEMON_SOCKET"*)
			_owned=1
			_event_terminate_pid "$_pid" appstate_daemon_stop
			;;
		esac
	fi
	# PID 檔失配但 endpoint 仍能回 PONG 時，不可 unlink 活 daemon 的 socket。
	# owner watcher 會在真正 owner 結束後自行關閉並刪除 inode。
	if [[ $_owned != 1 ]] && _appstate_daemon_probe; then
		_speed_debug_log "APPSTATE_DAEMON_STOP_SKIP reason=live_unowned_endpoint pid=${_pid:-unknown}"
		_APPSTATE_DAEMON_READY=1
		return 0
	fi
	rm -f "$_APPSTATE_DAEMON_PID_FILE" "$TMPDIR/.appstate_daemon_out" "$_APPSTATE_DAEMON_SOCKET" 2>/dev/null
	[[ $_keep_lock = keep_lock ]] || rmdir "$_APPSTATE_DAEMON_START_LOCK" 2>/dev/null || true
	_APPSTATE_DAEMON_READY=0
	_APPSTATE_CAPABILITY_STATE=0
}

_appstate_daemon_wait_ready() {
	local _out="$1" _pid="$2" _i=0 _fw_pid="" _guard_pid=""
	case $_pid in ''|*[!0-9]*) return 1 ;; esac
	_event_filewatch_once "$_out" 5 appstate_ready >/dev/null 2>&1 || true
	_appstate_daemon_probe && return 0
	while [[ $_i -lt 80 ]]; do
		kill -0 "$_pid" 2>/dev/null || return 1
		_appstate_daemon_probe && return 0
		sleep 0.1
		_i=$((_i + 1))
	done
	return 1
}

_appstate_daemon_ensure() {
	local _pid _out="$TMPDIR/.appstate_daemon_out" _err _have_lock=0 _i=0
	if [[ $_APPSTATE_DAEMON_READY = 1 ]] && _appstate_daemon_probe; then return 0; fi
	_APPSTATE_DAEMON_READY=0
	if _appstate_daemon_probe; then _APPSTATE_DAEMON_READY=1; return 0; fi
	_webdav_unixsock_relay_ready || return 1

	if mkdir "$_APPSTATE_DAEMON_START_LOCK" 2>/dev/null; then
		_have_lock=1
	else
		while [[ $_i -lt 80 ]]; do
			_appstate_daemon_probe && { _APPSTATE_DAEMON_READY=1; return 0; }
			[[ -d $_APPSTATE_DAEMON_START_LOCK ]] || break
			sleep 0.1
			_i=$((_i + 1))
		done
		rmdir "$_APPSTATE_DAEMON_START_LOCK" 2>/dev/null
		mkdir "$_APPSTATE_DAEMON_START_LOCK" 2>/dev/null && _have_lock=1
	fi
	[[ $_have_lock = 1 ]] || return 1
	_appstate_daemon_probe && { _APPSTATE_DAEMON_READY=1; rmdir "$_APPSTATE_DAEMON_START_LOCK" 2>/dev/null; return 0; }
	# 已持有 start lock；停止 stale daemon 時不可把自己的鎖一併刪掉。
	_appstate_daemon_stop keep_lock
	# PID/state 失配但 endpoint 仍然可用時，沿用既有 daemon，不再啟第二顆 JVM。
	if _appstate_daemon_probe; then
		_APPSTATE_DAEMON_READY=1
		rmdir "$_APPSTATE_DAEMON_START_LOCK" 2>/dev/null
		return 0
	fi
	: > "$_out" 2>/dev/null || { rmdir "$_APPSTATE_DAEMON_START_LOCK" 2>/dev/null; return 1; }
	_err="$(_speed_debug_log_path appstate_daemon_stderr.log)"
	_dex_export_classpath
	nohup "$DEX_APP_PROCESS_BIN" "$DEX_APP_PROCESS_BASE" com.xayah.dex.AppStateUtil \
		daemonunix "$_APPSTATE_DAEMON_SOCKET" 1800 "$SPEEDBACKUP_MAIN_PID" > "$_out" 2>>"$_err" &
	_pid=$!
	disown "$_pid" 2>/dev/null
	_speedbackup_protect_pid "$_pid" appstate_daemon
	printf '%s\n' "$_pid" > "$_APPSTATE_DAEMON_PID_FILE" 2>/dev/null
	chmod 0600 "$_APPSTATE_DAEMON_PID_FILE" 2>/dev/null
	if _appstate_daemon_wait_ready "$_out" "$_pid"; then
		_APPSTATE_DAEMON_READY=1
		rmdir "$_APPSTATE_DAEMON_START_LOCK" 2>/dev/null
		_speed_debug_log "APPSTATE_DAEMON_START_OK pid=$_pid socket=$_APPSTATE_DAEMON_SOCKET"
		_dex_watchdog_start appstate "$_APPSTATE_DAEMON_PID_FILE" "$_APPSTATE_DAEMON_SOCKET" com.xayah.dex.AppStateUtil daemonunix "$_APPSTATE_DAEMON_SOCKET" 1800 "$SPEEDBACKUP_MAIN_PID"
		return 0
	fi
	_speed_debug_log "APPSTATE_DAEMON_START_FAIL pid=$_pid out=$(cat "$_out" 2>/dev/null)"
	_appstate_daemon_stop
	return 1
}

# $1=command $2=request body file $3=response body file
_appstate_daemon_call() {
	local _command="$1" _in="$2" _out="$3" _status _len _relay_rc _try=0 _max_try=3
	[[ -n $_command && -f $_in && -n $_out ]] || return 2
	while [[ $_try -lt $_max_try ]]; do
		_appstate_daemon_ensure || {
			_speed_debug_log "APPSTATE_DAEMON_ENSURE_FAIL command=$_command try=$_try"
			_daemon_retry_sleep "$_try" appstate
			_try=$((_try + 1))
			continue
		}
		_status="$(_webdav_tmp_path appstate_status)"
		_len="$(_local_file_size_debug "$_in")"
		case $_len in ''|*[!0-9]*) _len=0 ;; esac
		rm -f "$_status" "$_out" 2>/dev/null
		{
			printf '%s\n%s\nndjson\n\n1\n%s\n' "$_command" "${USER_ID:-0}" "$_len"
			cat "$_in"
		} | "$EVENT_UNIXSOCK_BIN" relay-unix "$_APPSTATE_DAEMON_SOCKET" --header-file "$_status" > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_relay_rc=$?
		if [[ $_relay_rc = 0 ]] && _appstate_parse_status "$_status"; then
			_speed_debug_log "APPSTATE_CALL command=$_command result=$_APPSTATE_RESULT_CODE name=$_APPSTATE_RESULT_NAME bytes=$(_local_file_size_debug "$_out") try=$_try"
			rm -f "$_status" 2>/dev/null
			case $_APPSTATE_RESULT_CODE in 0|10|60) return 0 ;; *) return 1 ;; esac
		fi
		_speed_debug_log "APPSTATE_CALL_TRANSPORT_FAIL command=$_command relay_rc=$_relay_rc try=$_try"
		rm -f "$_status" 2>/dev/null
		_APPSTATE_DAEMON_READY=0
		_APPSTATE_CAPABILITY_STATE=0
		_appstate_daemon_stop
		_daemon_retry_sleep "$_try" appstate
		_try=$((_try + 1))
	done
	return 125
}

# 透過已啟動的 AppState daemon 驗證機器可讀能力契約。
# 只檢查明確、版本化的 critical capabilities，不依賴 help 文本，避免自檢假陰性。
_appstate_capabilities_check() {
	case ${_APPSTATE_CAPABILITY_STATE:-0} in
	1) return 0 ;;
	-1) return 1 ;;
	esac
	local _in="$TMPDIR/.appstate_cap_in_$$" _out="$TMPDIR/.appstate_cap_out_$$"
	: > "$_in" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || { _APPSTATE_CAPABILITY_STATE=-1; return 1; }
	if ! _appstate_daemon_call capabilities "$_in" "$_out"; then
		_speed_debug_log "APPSTATE_CAPABILITIES_FAIL stage=transport result=${_APPSTATE_RESULT_CODE:-unknown} name=${_APPSTATE_RESULT_NAME:-unknown}"
		rm -f "$_in" "$_out" 2>/dev/null
		_APPSTATE_CAPABILITY_STATE=-1
		return 1
	fi
	if jq -e '
		def cap($n): any(.capabilities[]?; .name == $n and .enabled == true);
		def removed($n): any(.capabilities[]?; .name == $n and .enabled == false);
		(.schemaVersion == 2) and
		(.daemonProtocolVersion == 1) and
		((.dexVersion // "") | startswith("v2.6.61-device-list-sharded-clean")) and
		cap("dex.capabilities.v1") and
		cap("dex.machine_stdout.v1") and
		cap("appstate.snapshot.batch.v2") and
		cap("appstate.snapshot.compact_persist.v1") and
		cap("appstate.shared_payload.v1") and
		cap("appstate.special_access.integrated.v1") and
		cap("appstate.restore.batch.v4") and
		cap("appstate.verify.batch.v4") and
		cap("appstate.appops_reset.integrated.v1") and
		cap("appstate.ssaid.integrated.v1") and
		cap("appstate.daemon.af_unix.v1") and
		cap("appstate.daemon.runtime_preinit.v1") and
		cap("appstate.structured_result_codes.v2") and
		cap("appstate.scoped_appops_fields.v1") and
		cap("appstate.explicit_package_mode_snapshot.v1") and
		cap("appstate.default_appop_missing_equivalent.v1") and
		cap("appstate.runtime_permission_uid_restore.v1") and
		cap("appstate.permission_flags.stable_mask.v1") and
		cap("appstate.special_access.deduplicated.v1") and
		cap("appstate.localization.dex.v1") and
		cap("appstate.localization.raw_plus_cn.v1") and
		cap("webdav.managed_put.v1") and
		cap("webdav.managed_probe.v1") and
		cap("webdav.rclone_json_direct_put.dex.v1") and
		cap("webdav.rclone_direct_all.dex.v1") and
		cap("webdav.compat_probe.v1") and
		cap("webdav.atomic_probe.v2") and
		cap("webdav.vendor_quirks.v1") and
		cap("webdav.vendor_auto_detect.v1") and
		cap("webdav.pacer_retry_backoff.v1") and
		cap("webdav.directory_cache.v1") and
		cap("webdav.propfind_xml_tolerant.v2") and
		cap("webdav.error_policy_table.v1") and
		cap("webdav.regression_suite.v1") and
		cap("webdav.pan123_managed_direct.dex.v1") and
		cap("dex.daemon_hardening.oom_protect.v1") and cap("dex.daemon_supervisor.watchdog.v1") and cap("dex.http_util.get.v1") and removed("dex.device_list.download.v1") and
		cap("appstate.batch_preflight_validation.v1") and
		removed("appstate.token_sections") and
		removed("appops.reset.package_batch")
	' "$_out" >/dev/null 2>&1; then
		_APPSTATE_CAPABILITY_STATE=1
		[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d ${SPEED_DEBUG_RUN_DIR:-} ]] && cp -f "$_out" "$SPEED_DEBUG_RUN_DIR/appstate_capabilities.json" 2>/dev/null
		_speed_debug_log "APPSTATE_CAPABILITIES_OK dex=v2.6.61 schema=2 protocol=1 appstate-localization=raw-plus-cn json-refresh-ready webdav=managed-put rclone-direct-all webr5-consolidated pan123-managed-direct daemon-hardening-watchdog device-list-sharded-clean"
		rm -f "$_in" "$_out" 2>/dev/null
		return 0
	fi
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d ${SPEED_DEBUG_RUN_DIR:-} ]] && cp -f "$_out" "$SPEED_DEBUG_RUN_DIR/appstate_capabilities_invalid.json" 2>/dev/null
	local _dexv _cap_summary
	_dexv="$(jq -r '.dexVersion // "unknown"' "$_out" 2>/dev/null | head -n 1)"
	_cap_summary="$(jq -r '[.capabilities[]? | select(.enabled==true) | .name] | join(",")' "$_out" 2>/dev/null | cut -c1-600)"
	_speed_debug_log "APPSTATE_CAPABILITIES_FAIL stage=contract dex=${_dexv:-unknown} enabled_caps=${_cap_summary:-unknown}"
	rm -f "$_in" "$_out" 2>/dev/null
	_APPSTATE_CAPABILITY_STATE=-1
	return 1
}

# 優先常駐 daemon；能力契約不符時視為 tools/Dex 混版，不再靜默回退舊 API。
_appstate_snapshot_batch_raw() {
	local _pkg_file="$1" _out="$2" _rc
	[[ -s $_pkg_file && -n $_out ]] || return 1
	_appstate_capabilities_check || return 2
	if _appstate_daemon_call snapshotAppStateBatch "$_pkg_file" "$_out"; then
		return 0
	fi
	# capabilities 已通過後 daemon request 仍失敗，屬 transport/runtime 錯誤；不再改走另一顆 JVM 掩蓋問題。
	_rc=$?
	_speed_debug_log "APPSTATE_SNAPSHOT_FAIL result=${_APPSTATE_RESULT_CODE:-unknown} name=${_APPSTATE_RESULT_NAME:-unknown} rc=$_rc"
	return 1
}
# structured snapshot NDJSON → 既有狀態 maps；只接受 snapshot record，summary/error 不會混入。
_appstate_snapshot_to_maps() {
	local _ndjson="$1" _base _states _errors
	[[ -s $_ndjson ]] || return 1
	jq -e -s '
		any(.[];
			.recordType == "summary" and
			.command == "snapshotAppStateBatch" and
			.schemaVersion == 2 and
			(.result.name == "OK" or .result.name == "PARTIAL"))
	' "$_ndjson" >/dev/null 2>&1 || return 1

	_base="$TMPDIR/.appstate_maps_${$}_$RANDOM"
	_states="${_base}.states"
	_errors="${_base}.errors"
	rm -f "$_base"* 2>/dev/null

	# app_state 是唯一持久化資料模型；restore / verify 直接重用這份 canonical snapshot NDJSON。
	jq -r '
		select(.recordType=="snapshot" and (.result.name=="OK" or .result.name=="PARTIAL"))
		| select((.packageName // "") != "")
		| [.packageName, (.|tojson)] | @tsv
	' "$_ndjson" > "$_states" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || { rm -f "$_base"* 2>/dev/null; return 1; }

	jq -r '
		select((.recordType=="snapshot" and (.result.name != "OK")) or .recordType=="error")
		| [(.packageName // "-"), (.result.name // "UNKNOWN"), (.result.message // ""), ((.errors // [])|tojson)] | @tsv
	' "$_ndjson" > "$_errors" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || { rm -f "$_base"* 2>/dev/null; return 1; }

	mv -f "$_states" "$TMPDIR/.pkg_appstate" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || { rm -f "$_base"* 2>/dev/null; return 1; }
	mv -f "$_errors" "$TMPDIR/.appstate_snapshot_errors" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || { rm -f "$_base"* 2>/dev/null; return 1; }
	return 0
}

# 設定 dex 取應用名稱用的 locale (export 給 HiddenApiUtil 的 applyLocale 讀)
# 優先序: Shell_LANG 明確指定 > dex getLocale 取系統實際語言 > 退出提示手動設定
case $Shell_LANG in
1) export APP_LABEL_LOCALE="zh-CN" ;;
0) export APP_LABEL_LOCALE="zh-TW" ;;
*)
	# 用 settings 取用戶實際設定的語言 (system_locales, 如 zh-Hant-TW / zh-Hans-CN), 命令列可靠取得
	_syslocale="$(settings get system system_locales 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | head -1)"
	[[ -z $_syslocale || $_syslocale = null ]] && _syslocale="$(getprop persist.sys.locale)"
	case $_syslocale in
	zh-Hant*|zh_Hant*|zh-TW*|zh_TW*|zh-HK*|zh_HK*|zh-MO*) export APP_LABEL_LOCALE="zh-TW" ;;
	zh-Hans*|zh_Hans*|zh-CN*|zh_CN*|zh-SG*|zh*)            export APP_LABEL_LOCALE="zh-CN" ;;
	*)
		echoRgb "系統語言取得失敗或非中文 (取得: ${_syslocale:-空})" "0"
		echoRgb "dex 將取得英文應用名稱, 可能導致名稱比對/恢復異常" "0"
		echoRgb "請於 backup_settings.conf 設定 Shell_LANG=0 (繁中) 或 1 (簡中)" "3"
		exit 1 ;;
	esac
	;;
esac
appinfo() { dex_hiddenapi getInstalledPackagesAsUser "$USER_ID" "$@"; }
appinfo2() { dex_hiddenapi getPackageLabel "$USER_ID" "$@"; }
appinfo3() { dex_hiddenapi getPackageArchiveInfo "$@"; }
get_uid() { dex_hiddenapi getPackageUid "$USER_ID" "$@"; }
# AppOps package reset 已內聚於 restoreAppStateBatch；不再存在公開 reset 入口或 shell token 區段。
setDisplay() { dex_hiddenapi setDisplayPowerMode "$@"; }

_prepare_timed() {
	# 統一量測所有 prepare_* 預掃耗時。stdout/stderr 不改向，由原函式自己控制。
	local _name="$1" _start _end _elapsed
	shift
	_start="$(date +%s%3N 2>/dev/null)"
	case $_start in ''|*[!0-9]*) _start="$(date +%s 2>/dev/null)000" ;; esac
	_speed_debug_log "PREPARE_BEGIN name=$_name args=$*"
	"$_name" "$@"
	local _rc=$?
	_end="$(date +%s%3N 2>/dev/null)"
	case $_end in ''|*[!0-9]*) _end="$(date +%s 2>/dev/null)000" ;; esac
	_elapsed=$((_end - _start))
	_speed_debug_log "PREPARE_END name=$_name rc=$_rc elapsedMs=$_elapsed"
	if [[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d ${SPEED_DEBUG_RUN_DIR:-} ]]; then
		printf '%s	%s	%s
' "$_name" "$_rc" "$_elapsed" >> "$SPEED_DEBUG_RUN_DIR/prepare_timing.tsv" 2>/dev/null
	fi
	return $_rc
}

_speed_debug_first_pid_pkg() {
	local _pkg
	_pkg="$(ps -A -o pid=,args= 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '
		$2 ~ /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$/ && $2 !~ /^(com\.android\.shell|com\.android\.systemui)$/ {print $2; exit}
	')"
	[[ -z $_pkg ]] && _pkg="$(cmd package list packages --user "$USER_ID" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sed 's/^package://' | awk 'NF{print; exit}')"
	[[ -z $_pkg ]] && _pkg="android"
	printf '%s\n' "$_pkg"
}

# Dex/uidexec/helper 自檢已從 tools.sh 分離。
# tools.sh 只負責決定何時呼叫；測試內容固定集中在 tools/dex_check.sh。
# 只接受 dex_check.sh 這個檔名，避免版本尾碼或舊 speedbackup_dex_selftest.sh 被誤用。
_speed_debug_dex_selftest_script_path() {
	# 啟動早期路徑搜尋保持最保守寫法：不用 for 續行、不用 [[ ]]，避免部分 Android sh/mksh 在解析階段誤炸。
	local _p
	_p="$tools_path/dex_check.sh"
	[ -f "$_p" ] && { printf '%s\n' "$_p"; return 0; }
	return 1
}
_speed_debug_dex_full_test() {
	[[ "${SPEED_DEBUG_ENABLE:-1}" = 1 ]] || return 0
	[[ "${SPEED_DEBUG_FIRST_BOOT:-0}" = 1 ]] || return 0
	[[ -d "$SPEED_DEBUG_RUN_DIR" ]] || return 0
	[[ -f "$tools_path/classes.dex" ]] || return 0
	local _target _script _tools_selftest_path _rc _level _ok _fail
	_target="$(_speed_debug_first_pid_pkg)"
	_script="$(_speed_debug_dex_selftest_script_path)"
	_tools_selftest_path="$tools_path/tools.sh"
	[[ -f "$_tools_selftest_path" ]] || _tools_selftest_path="$0"
	: > "$SPEED_DEBUG_RUN_DIR/dex_full_test.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	: > "$SPEED_DEBUG_RUN_DIR/dex_full_test.summary" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	: > "$SPEED_DEBUG_RUN_DIR/dex_full_test_human.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	{
		echo "time=$(date '+%Y-%m-%d %H:%M:%S' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		echo "target=$_target"
		echo "user=$USER_ID"
		echo "script=$_script"
		echo "tools_path=$_tools_selftest_path"
		echo "mode=$([[ ${SPEED_DEBUG_DEEP_SELF_TEST:-0} = 1 ]] && echo diagnostic || echo quick)"
	} > "$SPEED_DEBUG_RUN_DIR/dex_full_test.info" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [[ -z $_script ]]; then
		echo "FAIL dex_selftest script_not_found" >> "$SPEED_DEBUG_RUN_DIR/dex_full_test.summary" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		echoRgb "dex 自檢腳本不存在：請把 dex_check.sh 放到 tools/" "0"
		return 0
	fi
	_level="quick"
	[[ "${SPEED_DEBUG_DEEP_SELF_TEST:-0}" = 1 ]] && _level="diagnostic"
	echoRgb "首次建立 /data/speed_debug，調用獨立 dex 自檢腳本" "3"
	echoRgb "測試目標app: $_target" "3"
	CLASSPATH_PATH="$tools_path/classes.dex" \
	TOOLS_PATH="$_tools_selftest_path" \
	SPEEDBACKUP_PATCH_BUILD="${speedbackup_patch_build:-}" \
	TEST_LOG_DIR="$SPEED_DEBUG_RUN_DIR" \
	TEST_LOG_FILE="$SPEED_DEBUG_RUN_DIR/dex_check.log" \
	TEST_SUMMARY_FILE="$SPEED_DEBUG_RUN_DIR/dex_full_test.summary" \
	BACKUP_WIFI_ENABLE="${backup_wifi_enable:-1}" \
	REMOTE_TYPE="${remote_type:-}" \
	SB_SELFTEST_LEVEL="$_level" \
	CHANGELOG_URL="${SPEED_DEBUG_DEX_TEST_URL:-https://api.github.com/repos/XayahSuSuSu/Android-DataBackup/releases/latest}" \
	sh "$_script" "$_target" "${USER_ID:-0}"
	_rc=$?
	{
		echo "===== DEX SELFTEST script=$_script level=$_level rc=$_rc ====="
		cat "$SPEED_DEBUG_RUN_DIR/dex_check.log" 2>/dev/null
	} >> "$SPEED_DEBUG_RUN_DIR/dex_full_test.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [[ $_rc -eq 0 ]]; then
		echo "OK dex_selftest rc=0 script=$_script level=$_level" >> "$SPEED_DEBUG_RUN_DIR/dex_full_test.summary" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	else
		echo "FAIL dex_selftest rc=$_rc script=$_script level=$_level" >> "$SPEED_DEBUG_RUN_DIR/dex_full_test.summary" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	fi
	_ok="$(grep -c '^OK ' "$SPEED_DEBUG_RUN_DIR/dex_full_test.summary" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	_fail="$(grep -c '^FAIL ' "$SPEED_DEBUG_RUN_DIR/dex_full_test.summary" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	echoRgb "dex 自檢完成: ✅${_ok:-0} ❌${_fail:-0}，詳情會打包在 speed_debug tar 內: dex_full_test.log" "3"
	# dex_check rc=2 只代表版本化 critical capability contract 失敗；一般 smoke FAIL 仍為 rc=1 並只記錄。
	if [[ $_rc = 2 ]]; then
		echoRgb "Dex 核心能力不可用或 tools/Dex 混版，已中止腳本，避免產生不完整備份/恢復" "0"
		_speed_debug_normal_finish_pack 2
		exit 2
	fi
	return 0
}

_speed_debug_dex_full_test
find_tools_path="$(find "$path_hierarchy"/* -maxdepth 1 -name "tools" -type d ! -path "$path_hierarchy/tools" | grep -v "/Backup_[^/]*/tools$")"
# 等待指定子程序並提供 timeout：
# - 有 pidfd 時：procwait 阻塞 poll(pidfd)，另用一顆一次性 sleep 作 watchdog。
# - 核心不支援 pidfd / 工具缺失：回傳 125，呼叫端使用原有限輪詢保底。
# 返回：子程序 rc；124=逾時；125=請使用 fallback。
_wait_child_timeout_procwait() {
	local _pid="$1" _timeout="$2" _tag="${3:-child}" _watch_rc _child_rc _state _i
	[[ -x ${EVENT_PROCWAIT_BIN:-} ]] || return 125
	command -v timeout >/dev/null 2>&1 || return 125
	case $_pid in ''|*[!0-9]*) return 125 ;; esac
	case $_timeout in ''|*[!0-9]*) return 125 ;; esac

	# 不再建立會繼承主腳本 EXIT trap 的 background watchdog shell。
	# timeout 只限制 procwait 本身；逾時後由目前主 shell 精準 TERM/KILL 目標 child。
	timeout "$_timeout" "$EVENT_PROCWAIT_BIN" pid "$_pid" >/dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_watch_rc=$?

	case $_watch_rc in
	0)
		wait "$_pid" 2>/dev/null
		_child_rc=$?
		_speed_debug_log "PROCWAIT_DONE tag=$_tag pid=$_pid child_rc=$_child_rc watcher_rc=$_watch_rc"
		return "$_child_rc"
		;;
	3)
		# procwait 定義：pidfd_open 不支援時返回 3，交回原有限輪詢。
		_speed_debug_log "PROCWAIT_FALLBACK tag=$_tag pid=$_pid watcher_rc=$_watch_rc reason=pidfd_unsupported"
		return 125
		;;
	124|137|143)
		if kill -0 "$_pid" 2>/dev/null; then
			kill -TERM "$_pid" 2>/dev/null
			_i=0
			while [[ $_i -lt 10 ]] && kill -0 "$_pid" 2>/dev/null; do
				sleep 0.1
				_i=$((_i + 1))
			done
			kill -0 "$_pid" 2>/dev/null && kill -KILL "$_pid" 2>/dev/null
		fi
		wait "$_pid" 2>/dev/null
		_speed_debug_log "PROCWAIT_TIMEOUT tag=$_tag pid=$_pid timeout=$_timeout watcher_rc=$_watch_rc"
		return 124
		;;
	*)
		_state="$(awk '/^State:/{print $2; exit}' /proc/"$_pid"/status 2>/dev/null)"
		case "$_state" in
		''|Z)
			wait "$_pid" 2>/dev/null
			_child_rc=$?
			_speed_debug_log "PROCWAIT_DONE tag=$_tag pid=$_pid child_rc=$_child_rc watcher_rc=$_watch_rc state=${_state:-gone}"
			return "$_child_rc"
			;;
		*)
			_speed_debug_log "PROCWAIT_FALLBACK tag=$_tag pid=$_pid watcher_rc=$_watch_rc state=$_state"
			return 125
			;;
		esac
		;;
	esac
}

# 備份 WiFi 密碼到指定目錄, 用 classes.dex 讀 system 內的 WifiConfigStore
# ============================================================
# SpeedBackup single-file section: sb_30_backup_prepare_maps.sh
# ============================================================
backup_wifi() {
	local wifi_dir="$1"
	[[ -z $wifi_dir ]] && echoRgb "backup_wifi: 目錄參數為空" "0" && return 1
	case ${backup_wifi_enable:-1} in
	0|false|False|FALSE)
		echoRgb "WiFi備份已關閉，略過" "3"
		return 0
		;;
	esac
	[[ ! -d $wifi_dir ]] && mkdir -p "$wifi_dir"
	if [[ -d $wifi_dir ]]; then
		echoRgb "備份wifi密碼"
		rm -rf "${wifi_dir:?}"/*
		local _wifi_tmp _wifi_err _wifi_rc _wifi_pid _wifi_wait _wifi_timeout
		_wifi_timeout="${WIFI_BACKUP_TIMEOUT:-20}"
		case $_wifi_timeout in ""|*[!0-9]*) _wifi_timeout=20 ;; esac
		_wifi_tmp="$TMPDIR/.speedbackup_wifi_save_${$}_$RANDOM.json"
		_wifi_err="$TMPDIR/.speedbackup_wifi_save_${$}_$RANDOM.err"
		rm -f "$_wifi_tmp" "$_wifi_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		# saveNetworks 會輸出完整 JSON，必須直跑 app_process；不可走 _dex 翻譯/過濾包裝層。
		_dex_export_classpath
		command "$DEX_APP_PROCESS_BIN" "$DEX_APP_PROCESS_BASE" com.xayah.dex.NetworkUtil saveNetworks >"$_wifi_tmp" 2>"$_wifi_err" &
		_wifi_pid=$!
		_wait_child_timeout_procwait "$_wifi_pid" "$_wifi_timeout" wifi_backup
		_wifi_rc=$?
		if [[ $_wifi_rc = 125 ]]; then
			# 舊核心或特殊 ROM 的相容保底；只有 pidfd 不可用時才進入。
			_wifi_wait=0
			while kill -0 "$_wifi_pid" 2>/dev/null; do
				if [[ $_wifi_wait -ge $_wifi_timeout ]]; then
					kill -TERM "$_wifi_pid" 2>/dev/null
					sleep 1
					kill -KILL "$_wifi_pid" 2>/dev/null
					wait "$_wifi_pid" 2>/dev/null
					_wifi_rc=124
					break
				fi
				sleep 1
				_wifi_wait=$((_wifi_wait + 1))
			done
			if [[ $_wifi_rc = 125 ]]; then
				wait "$_wifi_pid" 2>/dev/null
				_wifi_rc=$?
			fi
		fi
		[[ -s $_wifi_err ]] && cat "$_wifi_err" >> "${SPEED_DEBUG_ERR_LOG:-/dev/null}" 2>/dev/null
		if [[ $_wifi_rc = 0 && -s $_wifi_tmp ]]; then
			cat "$_wifi_tmp" > "$wifi_dir/wifi.json"
			rm -f "$_wifi_tmp" "$_wifi_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			echo_log "wifi備份"
		else
			rm -f "$wifi_dir/wifi.json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			case $_wifi_rc in
			124) echoRgb "wifi備份逾時 ${_wifi_timeout}s，已略過，不影響其他備份" "0" ;;
			*) echoRgb "wifi備份失敗 rc=$_wifi_rc，已略過，不影響其他備份" "0" ;;
			esac
			[[ -s $_wifi_err ]] && echoRgb "WiFi備份錯誤已寫入 speed_debug 包內: stderr.log" "3"
			rm -f "$_wifi_tmp" "$_wifi_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			result=1
			Set_back_1
			return 1
		fi
	fi
}
# 從備份恢復 WiFi 密碼 (寫回 WifiConfigStore)
recover_wifi() {
	if [[ -d $1 ]]; then
		if [[ -f $1/wifi.json ]]; then
			echoRgb "恢復wifi密碼"
			_dex com.xayah.dex.NetworkUtil restoreNetworks "$1/wifi.json"
			echo_log "wifi恢復"
		else
			echoRgb "wifi.json遺失"
		fi
	else
		echoRgb "$1不存在 wifi無法恢復" "0"
	fi
}
Rename_script () {
	HT="${HT:=0}"
	find "$path_hierarchy" -maxdepth 3 -name "*.sh" -type f -not -name "tools.sh" | sort | while read -r; do
		MODDIR_NAME="${REPLY%/*}"
		FILE_NAME="${REPLY##*/}"
		if [[ -f ${REPLY%/*}/app_details.json || -f ${REPLY%/*}/app_details ]]; then
			if [[ $FILE_NAME = backup.sh ]]; then
				touch_shell "1" "$REPLY"
			elif [[ $FILE_NAME = recover.sh ]]; then
				touch_shell "3" "$REPLY"
			elif [[ $FILE_NAME = upload.sh ]]; then
				touch_shell "5" "$REPLY"
			fi
		else
			if [[ -d ${REPLY%/*}/tools ]]; then
				if [[ $FILE_NAME = start.sh ]]; then
					[[ -f ${REPLY%/*}/backup_settings.conf ]] && touch_shell "0" "$REPLY"
					[[ -f ${REPLY%/*}/restore_settings.conf ]] && touch_shell "2" "$REPLY"
				fi
			fi
			let HT++
		fi
	done
	unset HT
}
# 在指定路徑生成入口腳本 (start.sh / backup.sh / recover.sh / upload.sh)
# $1=模式 (0/1/2/3/5), $2=目標檔案路徑
# 模式對應的 MODDIR 路徑推算規則不同 (依腳本放置位置)
touch_shell() {
	unset conf_path MODDIR_Path
	case $1 in
	0)
		MODDIR_Path='${0%/*}'
		MODDIR_Path1="$MODDIR_Path"
		conf_path='${0%/*}/backup_settings.conf' ;;
	1)
		MODDIR_Path='${0%/*/*/*}'
		MODDIR_Path1="$MODDIR_Path"
		conf_path='${0%/*/*/*}/backup_settings.conf' ;;
	2)
		MODDIR_Path='${0%/*}'
		MODDIR_Path1="$MODDIR_Path"
		conf_path='${0%/*}/restore_settings.conf' ;;
	3)
		MODDIR_Path='${0%/*/*}'
		MODDIR_Path1='${0%/*}'
		conf_path='${0%/*/*}/restore_settings.conf' ;;
	5)
		# upload.sh: 放在 Backup_zstd_X/<app>/, MODDIR 是 Backup_zstd_X 自己
		MODDIR_Path='${0%/*/*/*}'
		MODDIR_Path1='${0%/*/*}'
		conf_path='${0%/*/*/*}/backup_settings.conf' ;;
	esac
	# 用 heredoc 產生內容, 避免手動計算 echo 內反斜線轉義層數出錯 (曾因此漏轉一個引號,
	# 導致外層字串提前截斷、後續整段內容引號錯位)。'MODDIR_PATH_PLACEHOLDER' 是佔位字串,
	# 因為 heredoc 內同名變數 (MODDIR_Path) 在生成腳本裡也需要保留字面 ${0%/*/*/*} 語法,
	# 不能被這裡的 shell 展開，改用 sed 事後替換。
	cat > "$2" <<'TOUCH_SHELL_EOF'
#!/system/bin/sh
if [ -f "MODDIR_PATH_PLACEHOLDER/tools/tools.sh" ]; then
	MODDIR="MODDIR1_PATH_PLACEHOLDER"
	conf_path="CONF_PATH_PLACEHOLDER"
	[ ! -f "$conf_path" ] && . "MODDIR_PATH_PLACEHOLDER/tools/tools.sh"
else
	echo "MODDIR_PATH_PLACEHOLDER/tools/tools.sh遺失"
fi
# 入口腳本自己的 log 目錄必須自行建立；不能引用 tools.sh 上一次 run 的 speed_debug 路徑。
_log_dir="${0%/*}/log"
mkdir -p "$_log_dir" 2>/dev/null || _log_dir="/data/local/tmp"
logfile="$_log_dir/log_$(date +%Y-%m-%d_%H-%M).txt"
: > "$logfile" 2>/dev/null || logfile="/dev/null"
# 由入口腳本啟動時，trap 收尾訊息只寫 speed_debug，不刷終端，避免單獨恢復開頭出現 trap 訊息。
export SPEEDBACKUP_ENTRY_QUIET_TRAP=1
export SPEEDBACKUP_ENTRY_MODE="ENTRY_MODE_PLACEHOLDER"
export SPEEDBACKUP_ENTRY_SCRIPT="$0"
# 防止舊入口腳本 / 父 shell 殘留上一輪 speed_debug run_xxx 變數，導致單獨腳本誤寫已被 final 刪除的 main.log/stderr.log。
unset SPEED_DEBUG_RUN_DIR SPEED_DEBUG_MAIN_LOG SPEED_DEBUG_PENDING_ERR_LOG SPEED_DEBUG_CMD_LOG SPEED_DEBUG_INFO_LOG SPEED_DEBUG_DEX_HUMAN_LOG SPEED_DEBUG_ARCHIVE SPEED_DEBUG_PACKED SPEED_DEBUG_SNAPSHOT_DONE SPEED_DEBUG_RUN_DIR_REMOVED SPEED_DEBUG_ERR_LOG
set -o pipefail 2>/dev/null || true
. "MODDIR_PATH_PLACEHOLDER/tools/tools.sh" 2>&1 | tee "$logfile"
_entry_rc=$?
case "$_entry_rc" in
	''|*[!0-9]*) _entry_rc=1 ;;
esac
if [ "$logfile" != "/dev/null" ] && [ -f "$logfile" ]; then
	sed -i "$(printf 's/\033\[[0-9;]*m//g')" "$logfile" 2>/dev/null || true
fi
exit "$_entry_rc"
TOUCH_SHELL_EOF
	# 佔位字串換成真正路徑 (MODDIR_Path/MODDIR_Path1/conf_path 本身是字面 ${0%/*...} 語法字串, 用 sed 逐字替換, 不經 shell 展開避免被提前求值)
	sed -i \
		-e "s#MODDIR1_PATH_PLACEHOLDER#$MODDIR_Path1#g" \
		-e "s#CONF_PATH_PLACEHOLDER#$conf_path#g" \
		-e "s#MODDIR_PATH_PLACEHOLDER#$MODDIR_Path#g" \
		-e "s#ENTRY_MODE_PLACEHOLDER#$1#g" \
		"$2" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}
# 用 ts 翻譯檔案 (取代散落各處的 ts<X>temp && cp temp X && rm temp 模式)
# 用法: ts_inplace <檔案>
ts_inplace() {
	local f="$1" tmp="$TMPDIR/.ts_$$"
	if ts < "$f" > "$tmp"; then
		cp "$tmp" "$f"
		rm -f "$tmp"
	else
		rm -f "$tmp"
		return 1
	fi
}

# 從 zip 檔自動更新腳本 (檢測 $MODDIR 內的 .zip 並提取 tools.sh)
# 用法: update_script [zip路徑]  — 有傳入時直接用，否則掃 $MODDIR
update_script() {
	[[ -n $1 ]] && zipFile="$1"
	[[ -z $zipFile ]] && zipFile="$(find "$MODDIR" -maxdepth 1 -name "*.zip" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	if [[ -n $zipFile ]]; then
		# 多個 zip 用 case 判斷, 取代 echo|wc -l
		case $zipFile in
		*$'\n'*)
			echoRgb "錯誤 請刪除當前目錄多餘zip\n -保留一個最新的數據備份.zip\n -下列為當前目錄zip\n$zipFile" "0"
			exit 1 ;;
		esac
		if unzip -l "$zipFile" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -q "backup_settings\.conf$"; then
			# 在應用備份目錄內執行: 不解壓、不更新，僅給出導引提示
			case $MODDIR in
			*Backup_*)
				if [[ -f $MODDIR/app_details.json ]]; then
					local _hint_path="${path_hierarchy:-${MODDIR%/*}}"
					echoRgb "偵測到更新包: ${zipFile##*/}" "2"
					echoRgb "⚠ 目前在應用備份目錄內，無法在此執行更新" "0"
					echoRgb "請到以下目錄執行 start.sh 後即可自動更新:\n -$_hint_path" "3"
					return 0
				fi ;;
			esac
			unzip -o "$zipFile" -j "tools/tools.sh" -d "$MODDIR" &>/dev/null
			if [[ -f $MODDIR/tools.sh ]]; then
				# 版本比對: 12 碼純數字時間戳 (e.g. 202605161200), awk 一次抓取
				local _new_ver _cur_ver
				_new_ver=$(awk -F= '/^backup_version=/ {gsub(/[a-zA-Z"]/, "", $2); print $2; exit}' "$MODDIR/tools.sh")
				_cur_ver=$(echo "$backup_version" | tr -d 'a-zA-Z')
				if [[ ${_new_ver:-0} -ge ${_cur_ver:-0} ]]; then
					shell_language="$(awk -F= '/^shell_language=/ {gsub(/"/, "", $2); print $2}' "$MODDIR/tools.sh")"
					echoRgb "從$zipFile更新"
					if [[ -d $path_hierarchy/tools ]]; then
						mv "$path_hierarchy/tools" "$TMPDIR"
						[[ -d $TMPDIR/tools ]] && {
						unzip -o "$zipFile" tools/* -d "$path_hierarchy" | sed 's/inflating/釋放/g ; s/creating/創建/g ; s/Archive/解壓縮/g'
						chmod -R 0755 "$path_hierarchy/tools" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
						echo_log "解壓縮${zipFile##*/}"
						if [[ $result = 0 ]]; then
							if [[ $shell_language != $Script_target_language ]]; then
								echoRgb "腳本語言為$shell_language....轉換為$Script_target_language中,請稍後等待轉換...."
								ts_inplace "$path_hierarchy/tools/Device_List"
								echo_log "$path_hierarchy/tools/Device_List翻譯"
								ts_inplace "$path_hierarchy/tools/tools.sh" && sed -i "s/shell_language=\"$shell_language\"/shell_language=\"$Script_target_language\"/g" "$path_hierarchy/tools/tools.sh"
								echo_log "$path_hierarchy/tools/tools.sh翻譯"
								HT=1
							fi
							update_backup_settings_conf>"$path_hierarchy/backup_settings.conf"
							ts_inplace "$path_hierarchy/backup_settings.conf"
							echo_log "$path_hierarchy/backup_settings.conf翻譯"
							echo "$find_tools_path" | while read -r; do
								if [[ $REPLY != $path_hierarchy/tools ]]; then
									# 安全守衛: REPLY 必須是絕對路徑且深度≥2層才操作, 防異常路徑誤刪
									local _reply_parent="${REPLY%/*}"
									[[ -z $_reply_parent || $_reply_parent = "/" || ${#_reply_parent} -lt 4 ]] && continue
									[[ $REPLY != /* ]] && continue
									rm -rf "$REPLY" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
									cp -r "$path_hierarchy/tools" "$_reply_parent"
									update_Restore_settings_conf>"$_reply_parent/restore_settings.conf"
									ts_inplace "${REPLY%/*}/restore_settings.conf"
									echo_log "${REPLY%/*}/restore_settings.conf翻譯"
								fi
							done
							Rename_script
							if [[ -n $Output_path ]]; then
								[[ ${Output_path: -1} = / ]] && Output_path="${Output_path%?}"
								if [[ ${Output_path:0:1} != / ]]; then
									update_path="$MODDIR/$Output_path/$(get_backup_dirname)"
								else
									update_path="$Output_path/$(get_backup_dirname)"
								fi
								# FUSE 層 rm -rf 可能因權限問題失敗; 改 cp -rf 直接覆蓋無需先刪
								mkdir -p "$update_path/tools" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
								cp -rf "$path_hierarchy/tools/." "$update_path/tools/" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || cp -r "$path_hierarchy/tools" "$update_path"
								chmod -R 0755 "$update_path/tools" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
								echoRgb "$update_path/tools已經更新完成"
							fi
						else
							mv "$TMPDIR/tools" "$MODDIR"
						fi
						# TMPDIR 清理加保護，避免變數為空時誤刪
						[[ -n $TMPDIR ]] && rm -rf "$TMPDIR/tools" "$zipFile" "$MODDIR/tools.sh"
						echoRgb "更新完成 請重新執行腳本" "2"
						exit 0
						} || echoRgb "tools移動到TMPDIR失敗" "0"
					fi
				else
					echoRgb "${zipFile##*/}版本低於當前版本,自動刪除" "0"
					rm -rf "$zipFile" "$path_hierarchy/tools.sh"
				fi
			else
				rm -rf "$zipFile"
				unset zipFile
			fi
		fi
	fi
	unset NAME
}
update_script
# 掃 Download 和 QQ 收件匣，找到有效 zip 直接傳入 update_script
# 兩個來源都嘗試 (Download 有無關 zip 時不該擋住 QQ 的更新包)。
# 不用 ls <dir>/*.zip：目錄存在但沒有 zip 時，未匹配 glob 會把「No such file or directory」寫進 stderr.log。
_latest_zip_in_dir() {
	local _dir="$1"
	[[ -d $_dir ]] || return 0
	find "$_dir" -maxdepth 1 -type f -name '*.zip' -printf '%T@\t%p\n' 2>/dev/null |
		sort -nr 2>/dev/null | head -1 | cut -f2-
}
_dl_zip="$(_latest_zip_in_dir /storage/emulated/0/Download)"
_qq_zip="$(_latest_zip_in_dir /storage/emulated/0/Android/data/com.tencent.mobileqq/Tencent/QQfile_recv)"
for _try_zip in "$_dl_zip" "$_qq_zip"; do
	[[ -z $_try_zip ]] && continue
	# 只有「含 backup_settings.conf 的更新包」才傳入; 普通 zip 略過不處理
	if unzip -l "$_try_zip" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -q "backup_settings\.conf$"; then
		echoRgb "偵測到更新包: ${_try_zip##*/}" "2"
		update_script "$_try_zip"
	fi
done
unset _dl_zip _qq_zip _try_zip
unset -f _latest_zip_in_dir 2>/dev/null || true
# APK 安裝統一走 installapk() 內部函數。
# Play 來源 app 可優先使用 Play UID daemon 建立/提交 session，APK bytes 仍由 root pm install-write 寫入；
# 傳統 pm fallback 仍保留 -i <installer> 偽裝來源，但 initiatingPackageName 仍會是 shell。
#settings get system system_locales
Language="https://api.github.com/repos/YAWAsau/backup_script/releases/latest"
if [[ $path_hierarchy != "" && $Script_target_language != ""  ]]; then
	K=1
	J="$(find "$path_hierarchy" -maxdepth 3 -name "tools.sh" -type f | wc -l)"
	find "$path_hierarchy" -maxdepth 3 -name "tools.sh" -type f | while read -r; do
		unset shell_language
		shell_language="$(awk -F= '/^shell_language=/ {gsub(/"/, "", $2); print $2}' "$REPLY")"
		case $shell_language in
		zh-CN|zh-TW)
			if [[ $Script_target_language != $shell_language ]]; then
				[[ $K = 1 ]] && echoRgb "腳本語言為$shell_language....轉換為$Script_target_language中,請稍後等待轉換...."
				ts_inplace "$REPLY"
				if [[ $? = 0 ]]; then
					touch "$TMPDIR/0"
					echo_log "$(echo "$REPLY" | sed "s|^$path_hierarchy/||")翻譯"
					MODDIR="${0%/*}"
					if [[ -f ${REPLY%/*/*}/backup_settings.conf ]]; then
						update_backup_settings_conf>"${REPLY%/*/*}/backup_settings.conf"
						ts_inplace "${REPLY%/*/*}/backup_settings.conf"
						echo_log "${REPLY%/*/*}/backup_settings.conf翻譯"
					fi
					if [[ -f ${REPLY%/*/*}/restore_settings.conf ]]; then
						update_Restore_settings_conf>"${REPLY%/*/*}/restore_settings.conf"
						ts_inplace "${REPLY%/*/*}/restore_settings.conf"
						echo_log "${REPLY%/*/*}/restore_settings.conf翻譯"
					fi
					sed "s/shell_language=\"$shell_language\"/shell_language=\"$Script_target_language\"/g" "$REPLY" > temp && cp temp "$REPLY" && rm temp
					[[ $shell_language != $(awk -F= '/^shell_language=/ {gsub(/"/, "", $2); print $2}' "$REPLY") ]] && echoRgb "$(echo "$REPLY" | sed "s|^$path_hierarchy/||")變量修改成功" || echoRgb "$(echo "$REPLY" | sed "s|^$path_hierarchy/||")變量修改失敗" "0"
					ts_inplace "${REPLY%/*}/Device_List"
					echo_log "${REPLY%/*}/Device_List翻譯"
					[[ $K = 1 ]] && Rename_script
				else
					echoRgb "$REPLY ts進程出現錯誤" "0"
				fi
				let K++
			fi ;;
		esac
	done
	[[ -e $TMPDIR/0 ]] && rm "$TMPDIR/0" && echoRgb "轉換腳本完成，退出腳本重新執行即可使用" && exit 2
fi
#校驗選填是否正確
ask_yn_indep "自動更新腳本?" "更新" "不更新" update
if [[ $update = true ]]; then
	json="$(down "$Language")"
else
	echoRgb "自動更新被關閉" "0"
fi
if [[ $json != "" ]]; then
	tag="$(printf "%s\n" "$json" | jq -r '.tag_name'  2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	if [[ $tag != "" && $backup_version != $tag ]]; then
		if [[ $(expr "$(echo "$backup_version" | tr -d "a-zA-Z")" \> "$(echo "$tag" | tr -d "a-zA-Z")") -eq 0 ]]; then
			download="$(printf "%s\n" "$json" | jq -r '.assets[].browser_download_url' )"
			case $cdn in
			0) zip_url="$download" ;;
			1) zip_url="https://ghfast.top/$download" ;;
			2) zip_url="https://shrill-pond-3e81.hunsh.workers.dev/$download" ;;
			*) echoRgb "$conf_path cdn=設置錯誤 範圍只能是0-2" && exit 2 ;;
			esac
			if [[ $(expr "$(echo "$backup_version" | tr -d "a-zA-Z")" \> "$(echo "$download" | tr -d "a-zA-Z")") -eq 0 ]]; then
				echoRgb "發現新版本:$tag"
				# 在應用備份目錄內: 僅提示去正確目錄，不執行下載
				_skip_update_dl=0
				case $MODDIR in
				*Backup_*)
					if [[ -f $MODDIR/app_details.json ]]; then
						echoRgb "⚠ 目前在應用備份目錄內，無法在此下載更新" "0"
						echoRgb "請到以下目錄執行 start.sh 後即可自動更新:\n -${path_hierarchy:-${MODDIR%/*}}" "3"
						_skip_update_dl=1
					fi ;;
				esac
				if [[ $_skip_update_dl = 0 && $update = true ]]; then
					echoRgb "$(ts "更新日誌:\n$(down "$Language" | jq -r '.body')")"
					if ask_yn "是否更新腳本?" "更新" "不更新" choose; then
						echoRgb "下載中.....耐心等待 如果下載失敗請掛飛機"
						starttime1="$(date -u "+%s")"
						_dl_dest="${path_hierarchy:-$MODDIR}"
						down "$zip_url" >"$_dl_dest/update.zip" &
						wait $!
						endtime 1
						[[ ! -f $_dl_dest/update.zip ]] && echoRgb "下載失敗" && exit 2
						zipFile="$_dl_dest/update.zip"
						unset _dl_dest
					fi
				elif [[ $_skip_update_dl = 0 ]]; then
					echoRgb "$conf_path內update選項為0忽略更新僅提示更新" "0"
				fi
				unset _skip_update_dl
			fi
		fi
	fi
else
	[[ $update = true ]] && echoRgb "更新獲取失敗" "0"
fi
update_script
# 給定路徑, 穿透 bind/FUSE 找出真實底層的「可餵給 df 的路徑」
# 用於 Android emulated storage (sdcardfs/FUSE) 上 bind 了其他分區的情況
# 例: /storage/emulated/0/虛擬分區 實際是 /mnt/YAWAsau/備份 的 bind, 應回傳 /mnt/YAWAsau
# 策略:
#   1) 先把已知的 sdcardfs/FUSE 視圖路徑顯式轉成內核真實路徑 /data/media/<N>/<X>
#      (不能用 realpath, /storage/emulated 通常是 symlink 到 /mnt/installer/.../emulated,
#       resolve 後反而會撞到 FUSE 掛載點, 拿不到底下的 bind)
#   2) 在 /proc/self/mountinfo 找 mp 是 target 祖先的最長匹配 → 取得 source
#   3) 找同 source 且 root="/" 的 canonical mountpoint, 回傳該路徑
#      (Android toybox df 不接受 block device, 必須回傳真實「路徑」)
#   4) 找不到 canonical 時, 若 source 是現存目錄就用 source, 否則原樣回傳
_resolve_real_mount() {
	local p="$1" rp target rest out
	[[ -z $p ]] && { echo "$p"; return; }
	# 先 readlink -f 一次, 解開常見入口 symlink (/sdcard, /storage/self/primary, /mnt/sdcard 等)
	# 注意: 之前嘗試過 realpath 會把 /storage/emulated/0 解成 /mnt/installer/.../emulated/0,
	# 撞到 FUSE 掛載點; 現在下方 case 已涵蓋 /mnt/installer/... 等視圖, 所以 readlink 後也能正確處理
	rp="$(readlink -f "$p" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	[[ -n $rp ]] && p="$rp"
	# 把已知 sdcardfs/FUSE 視圖路徑剝皮成 /data/media/<N>/<X>
	case "$p" in
		/storage/emulated/*)            rest="${p#/storage/emulated/}"; target="/data/media/$rest" ;;
		/mnt/installer/*/emulated/*)    rest="${p##*/emulated/}"; target="/data/media/$rest" ;;
		/mnt/runtime/*/emulated/*)      rest="${p##*/emulated/}"; target="/data/media/$rest" ;;
		/mnt/pass_through/*/emulated/*) rest="${p##*/emulated/}"; target="/data/media/$rest" ;;
		/mnt/user/*/emulated/*)         rest="${p##*/emulated/}"; target="/data/media/$rest" ;;
		*)                              target="$p" ;;
	esac
	out="$(awk -v target="$target" '
	function unesc(s) { gsub(/\\040/, " ", s); return s }
	{
		root=unesc($4); mp=unesc($5)
		i=6; while (i<=NF && $i!="-") i++
		src=unesc($(i+2))
		n++; mp_a[n]=mp; root_a[n]=root; src_a[n]=src
	}
	END {
		best_len=-1
		for (i=1; i<=n; i++) {
			m=mp_a[i]
			if (m==target || index(target, m"/")==1) {
				if (length(m) > best_len) { best_len=length(m); R_src=src_a[i] }
			}
		}
		if (best_len<0) exit
		# 找同 source 且 root="/" 的 canonical mountpoint
		for (i=1; i<=n; i++) {
			if (src_a[i]==R_src && root_a[i]=="/") { print mp_a[i]; exit }
		}
		# 沒 canonical 且 source 是路徑而非 /dev/*, 就用 source
		if (substr(R_src,1,1)=="/" && R_src !~ /^\/dev\//) print R_src
	}' /proc/self/mountinfo 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	if [[ -n $out ]] && [[ -d $out || -b $out ]]; then
		echo "$out"
	else
		echo "$p"
	fi
}
_backup_df_target() {
	local _p="$1" _fallback
	[[ -n $_p ]] || return 1
	if df -h "$_p" >/dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
		echo "$_p"
		return 0
	fi
	_fallback="$(_resolve_real_mount "${_p%/*}")"
	[[ -n $_fallback ]] && echo "$_fallback" || echo "$_p"
}
_backup_mount_point() {
	local _p="$1" _mp
	_mp="$(df -h "$_p" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk 'NR==2{print $NF; exit}')"
	printf '%s\n' "$_mp"
}
_backup_underlying_storage_path() {
	local _p="$1" _rest _candidate
	case "$_p" in
	/storage/emulated/0/*)
		_rest="${_p#/storage/emulated/0/}"
		_candidate="/data/media/0/$_rest"
		;;
	/storage/emulated/*)
		_rest="${_p#/storage/emulated/}"
		_candidate="/data/media/$_rest"
		;;
	/sdcard/*)
		_rest="${_p#/sdcard/}"
		_candidate="/data/media/0/$_rest"
		;;
	*) return 1 ;;
	esac
	[[ -e $_candidate ]] && printf '%s\n' "$_candidate"
}
_backup_mount_display_suffix() {
	local _backup="$1" _df_target="$2" _mp _under _out=""
	_mp="$(_backup_mount_point "$_df_target")"
	[[ -n $_mp ]] && _out=" -└─ 掛載點: $_mp"
	_under="$(_backup_underlying_storage_path "$_backup")"
	if [[ -n $_under && $_under != "$_backup" ]]; then
		if [[ -n $_out ]]; then
			_out="$_out
 -└─ 底層對應: $_under"
		else
			_out=" -└─ 底層對應: $_under"
		fi
	fi
	printf '%s' "$_out"
}
_backup_partition_summary() {
	local _target="$1" _summary _fs
	_summary="$(df -h "$_target" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk 'NR==2{print "總共:"$2"已用:"$3"剩餘:"$4"使用率:"$5; exit}')"
	_fs="$(df -T "$_target" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk 'NR==2{print $2; exit}')"
	[[ -z $_summary ]] && _summary="總共:未知已用:未知剩餘:未知使用率:未知"
	printf '%s檔案系統:%s\n' "$_summary" "${_fs:-未知}"
}

# 計算本地備份目錄路徑
# 格式: $Output_path/Backup_${Compression_method}_${user}
# 並建立目錄, 設定 $Backup 全域變數供其他函數使用
# 返回帶後綴的備份目錄名 (Backup_${Compression_method}_${user}${suffix})
# 解析 Backup_suffix 中的日期時間變量: %yyyymmdd %hhmmss %yyyymmddhhmmss %yyyy %mm %dd
get_backup_dirname() {
	local base="Backup_${Compression_method}_${user:-0}"
	if [[ -n $Backup_suffix ]]; then
		local resolved="$Backup_suffix"
		local now="$(date '+%Y%m%d%H%M%S')"
		resolved="${resolved//%yyyymmddhhmmss/$now}"
		resolved="${resolved//%yyyymmdd/${now:0:8}}"
		resolved="${resolved//%hhmmss/${now:8}}"
		resolved="${resolved//%yyyy/${now:0:4}}"
		resolved="${resolved//%mm/${now:4:2}}"
		resolved="${resolved//%dd/${now:6:2}}"
		echo "${base}${resolved}"
	else
		echo "$base"
	fi
}

# ======================================================
# 備份路徑 / 預掃 / app_details 讀取
# ======================================================
backup_path() {
	if [[ $Output_path != "" ]]; then
		[[ ${Output_path: -1} = / ]] && Output_path="${Output_path%?}"
		if [[ ${Output_path:0:1} != / ]]; then
			Directory_type="相對路徑"
			Backup="$MODDIR/$Output_path/$(get_backup_dirname)"
		else
			Directory_type="絕對路徑"
			Backup="$Output_path/$(get_backup_dirname)"
		fi
		outshow="使用自定義目錄($Directory_type)"
	else
		Backup="$MODDIR/$(get_backup_dirname)"
		if [[ ! -f ${0%/*}/app_details.json ]]; then
			outshow="使用當前路徑作為備份目錄"
		else
			[[ -d $Backup ]] && outshow="使用上層路徑作為備份目錄" || echoRgb "$Backup目錄不存在" "0"
		fi
	fi
	PU="$(mount | awk '$3 ~ "/mnt/media_rw/[^/]+$" {print $3, $5}' | grep -Ev "$mount_point")"
	OTGPATH="$(echo "$PU" | cut -d' ' -f1)"
	OTGFormat="$(echo "$PU" | cut -d' ' -f2)"
	if [[ -d $OTGPATH ]]; then
		if [[ $(echo "$MODDIR" | grep -Eo "^${OTGPATH}") != "" ]]; then
			hx="true"
			Backup="$MODDIR/$(get_backup_dirname)"
		else
			ask_yn_indep "檢測到隨身碟 是否在隨身碟備份?" "選擇了隨身碟備份" "選擇了本地備份"
			[[ $branch = true ]] && hx="$branch"
			[[ $hx = true ]] && Backup="$OTGPATH/$(get_backup_dirname)"
		fi
		if [[ $hx = true ]]; then
			if [[ $OTGFormat = vfat ]]; then
				echoRgb "隨身碟檔案系統$OTGFormat不支持超過單檔4GB\n -請格式化為exfat" "0"
				exit
			fi
			outshow="於隨身碟備份" && hx=usb
		fi
	fi
	# 流式遠端備份不應建立本機 Backup_zstd_X 空殼；$Backup 只保留作為顯示/相對路徑基準。
	# 實際 app/json/wifi/media staging 全部走 $TMPDIR/.stream_stage，再直接 _stream_upload 到遠端。
	if stream_enabled; then
		_speed_debug_log "STREAM_LOCAL_BACKUP_ROOT_SKIP path=$Backup"
		# 舊版可能已留下空的 Backup_zstd_X；只刪空殼，不碰已有內容的舊本地備份。
		if [[ -d $Backup ]]; then
			if find "$Backup" -mindepth 1 -print -quit 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -q .; then
				_speed_debug_log "STREAM_LOCAL_BACKUP_ROOT_PRESERVE_NONEMPTY path=$Backup"
			else
				rmdir "$Backup" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && _speed_debug_log "STREAM_LOCAL_BACKUP_ROOT_REMOVED_EMPTY path=$Backup"
			fi
		fi
	else
		[[ ! -d $Backup ]] && mkdir -p "$Backup"
	fi
	# 分區詳細：非流式用實際 Backup 路徑；流式不落地，df 只用 MODDIR 作顯示 fallback。
	if stream_enabled; then
		_df_target="$(_backup_df_target "$MODDIR")"
	else
		_df_target="$(_backup_df_target "$Backup")"
	fi
	_real_suffix="$(_backup_mount_display_suffix "$Backup" "$_df_target")"
	if [[ ${SPEEDBACKUP_DEFER_REMOTE_SETUP:-0} = 1 ]]; then
		SPEEDBACKUP_REMOTE_SETUP_DEFERRED=1
		_speed_debug_log "REMOTE_SETUP_DEFERRED phase=backup_path remote_type=${remote_type:-none}"
	else
		backup_path_remote_finalize
	fi
}

# 完成備份路徑階段被延後的遠端初始化。
# 目的：避免 WebDAV daemon / chunked probe / remote_dir_size 在本機 dirsize 預掃前先啟動，
# 用來驗證「只有遠端模式卡 prepare_dir_size_map」是否由 remote_setup 前置副作用造成。
backup_path_remote_finalize() {
	if [[ ${remote_stream:-0} = 1 ]]; then
		_remote_stream_fatal_reset "backup_path_remote_finalize"
	fi
	remote_setup
	# 一致性保護: remote_stream=1 但 remote_type 無效/空 → 直接終止。
	# 真流式沒有安全本地回退目標，不反寫 conf。
	if [[ $remote_stream = 1 && -z $remote_type ]]; then
		echoRgb "真流式上傳不可用：遠端初始化失敗，已終止" "0"
		echoRgb "remote_stream=1 不允許回退成本地備份；請修正遠端連線或設 remote_stream=0" "3"
		_speed_debug_normal_finish_pack 1
		exit 1
	fi
	if [[ $remote_stream = 1 && $remote_type = smb ]]; then
		if ! remote_smb_write_precheck; then
			echoRgb "真流式 SMB 寫入預檢未通過，已終止，避免產生半套遠端備份" "0"
			_speed_debug_normal_finish_pack 1
			exit 1
		fi
	fi
	# 分區統計放在 remote_setup/一致性保護之後：
	# 連線失敗自動轉純本機備份時，也能正確顯示本地資訊；流式不顯示本地分區統計。
	if [[ $remote_stream != 1 ]]; then
		echoRgb "${hx}備份資料夾所使用分區統計如下↓\n -$(_backup_partition_summary "$_df_target")\n -備份目錄輸出位置↓\n -$Backup${_real_suffix:+\n$_real_suffix}"
		echoRgb "$outshow" "2"
	fi
	# 快照備份前遠端大小 (結尾算差異，對齊本地備份的整體資料夾差異統計)。
	if [[ -n $remote_type ]]; then
		_RTOTAL_BEFORE="$(remote_dir_size "$(get_backup_dirname)" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		[[ -z $_RTOTAL_BEFORE ]] && _RTOTAL_BEFORE=0
		_speed_debug_log "REMOTE_TOTAL_BEFORE subdir=$(get_backup_dirname) bytes=$_RTOTAL_BEFORE"
	fi
	SPEEDBACKUP_REMOTE_SETUP_DEFERRED=0
}

backup_finalize_remote_setup_if_deferred() {
	if [[ ${SPEEDBACKUP_REMOTE_SETUP_DEFERRED:-0} = 1 ]]; then
		_prepare_timed backup_path_remote_finalize
	fi
}


# 真流式模式的早期硬性連線檢查。
# 只做 URL/host/port/TCP 這類低成本檢查，不啟動 WebDAV daemon / chunked PUT probe，
# 避免恢復舊版「遠端前置干擾 dirsize 預掃」問題；但若遠端根本沒開，立即終止，不進入本地備份流程。
remote_stream_early_hard_precheck() {
	[[ ${remote_stream:-0} = 1 ]] || return 0
	[[ -n ${remote_type:-} ]] || return 0
	case $remote_type in
	webdav|smb) ;;
	*)
		echoRgb "真流式上傳已開啟，但 remote_type=$remote_type 不支援；已終止，避免回退成本地備份" "0"
		_speed_debug_normal_finish_pack 1
		exit 1
		;;
	esac
	[[ -n ${remote_url:-} ]] || {
		echoRgb "真流式上傳已開啟，但遠端位址未設定；已終止，避免回退成本地備份" "0"
		_speed_debug_normal_finish_pack 1
		exit 1
	}
	remote_parse_endpoint
	[[ $remote_type = smb ]] && remote_parse_smb_url
	if ! remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "真流式上傳不可用：遠端不可連線 ($REMOTE_HOST:$REMOTE_PORT)，已終止" "0"
		echoRgb "remote_stream=1 不允許回退成本地備份；請開啟遠端伺服器、修正網路，或設 remote_stream=0" "3"
		echoRgb "詳情已寫入 speed_debug 包內: remote_precheck.log" "3"
		_speed_debug_normal_finish_pack 1
		exit 1
	fi
	echoRgb "真流式早期連線檢查通過 ($REMOTE_HOST:$REMOTE_PORT)" "1"
	return 0
}
prepare_app_state_prescan_batch() {
	local _all_pkgs _rc
	if [[ -n $1 ]]; then
		_all_pkgs="$*"
	else
		_all_pkgs="$(echo "$txt" | awk '{print $2}' | grep -v '^$' | paste -sd' ' -)"
	fi
	[[ -z $_all_pkgs ]] && return 0
	local _snapshot_pkgs="$TMPDIR/.appstate_snapshot_pkgs_$$" _snapshot_out="$TMPDIR/.appstate_snapshot_out_$$"
	rm -f "$_snapshot_pkgs" "$_snapshot_out" 2>/dev/null
	echoRgb "預掃應用狀態中... (AppState daemon: 權限/特殊存取/安裝來源/電池/SSAID)" "2"
	printf '%s\n' $_all_pkgs | sed '/^$/d' | sort -u > "$_snapshot_pkgs"
	# 294: 同一輪若已經有完整 canonical AppState map，不重複打 daemon snapshot。
	if [[ -s $TMPDIR/.pkg_appstate ]]; then
		local _miss
		_miss="$(awk 'NR==FNR{need[$1]=1; next} {seen[$1]=1} END{for (k in need) if (!(k in seen)) {print k; exit}}' "$_snapshot_pkgs" "$TMPDIR/.pkg_appstate" 2>/dev/null)"
		if [[ -z $_miss ]]; then
			_speed_debug_log "APPSTATE_PRESCAN_CACHE_HIT packages=$(wc -l < "$_snapshot_pkgs" 2>/dev/null | tr -d ' ')"
			rm -f "$_snapshot_pkgs" "$_snapshot_out" 2>/dev/null
			return 0
		fi
		_speed_debug_log "APPSTATE_PRESCAN_CACHE_MISS firstMissing=$_miss"
	fi
	_appstate_snapshot_batch_raw "$_snapshot_pkgs" "$_snapshot_out"
	_rc=$?
	if [[ $_rc = 0 ]] && _appstate_snapshot_to_maps "$_snapshot_out"; then
		[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d ${SPEED_DEBUG_RUN_DIR:-} ]] && {
			cp -f "$_snapshot_out" "$SPEED_DEBUG_RUN_DIR/appstate_snapshot.ndjson" 2>/dev/null
			printf 'APPSTATE_SNAPSHOT_OK packages=%s result=%s name=%s
' 				"$(wc -l < "$_snapshot_pkgs" 2>/dev/null | tr -d ' ')" 				"${_APPSTATE_RESULT_CODE:-0}" "${_APPSTATE_RESULT_NAME:-OK}" 				>> "$SPEED_DEBUG_RUN_DIR/appstate_prescan_batch.log" 2>/dev/null
		}
		rm -f "$_snapshot_pkgs" "$_snapshot_out" 2>/dev/null
		return 0
	fi
	_speed_debug_log "APPSTATE_STRUCTURED_PRESCAN_FATAL rc=$_rc result=${_APPSTATE_RESULT_CODE:-unknown} name=${_APPSTATE_RESULT_NAME:-unknown}"
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d ${SPEED_DEBUG_RUN_DIR:-} && -s $_snapshot_out ]] && 		cp -f "$_snapshot_out" "$SPEED_DEBUG_RUN_DIR/appstate_snapshot_invalid.ndjson" 2>/dev/null
	rm -f "$_snapshot_pkgs" "$_snapshot_out" 2>/dev/null
	return 2
}

# 預掃 pkg → uid map (給備份主迴圈用, 避免每個 app 都 fork 一次 pm + awk)
# 寫到 $TMPDIR/.pkg_uid 格式: pkg<TAB>uid
# 用法: prepare_pkg_uid_map (backup / backup_update_apk 開頭呼叫)
prepare_pkg_uid_map() {
	: > "$TMPDIR/.pkg_uid" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	pm list packages -U --user "${user:-0}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} 		| awk '
			{
				pkg=""; uid=""
				for (i=1; i<=NF; i++) {
					f=$i
					if (f ~ /^package:/) { pkg=f; sub(/^package:/, "", pkg) }
					else if (f ~ /^uid[:=]/) { uid=f; sub(/^uid[:=]/, "", uid) }
				}
				if (pkg != "" && uid ~ /^[0-9]+$/ && !(pkg in seen)) { print pkg "	" uid; seen[pkg]=1 }
			}
		' >> "$TMPDIR/.pkg_uid" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}
# 預掃所有待備份 app 的數據目錄大小 (data/user/user_de/obb), 並行加速 (約快 3 倍)
# 寫到 $TMPDIR/.dir_sizes, 格式: pkg<TAB>type<TAB>size; 主迴圈 _dir_size 查此表免重複遍歷
prepare_dir_size_map() {
	local _map="$TMPDIR/.dir_sizes"
	: > "$_map"
	local _list
	if [[ -n $1 ]]; then
		_list="$1"
	else
		_list="$(echo "$txt" | awk '{print $2}' | grep -v '^$')"
	fi
	[[ -z $_list ]] && return
	local _workdir="$TMPDIR/.dirsize_work"
	rm -rf "$_workdir"; mkdir -p "$_workdir"
	local _total _i=0 _running=0 _par=8 _dsz_pids=""
	_total="$(echo "$_list" | grep -vc '^$')"
	_speed_debug_log "DIRSIZE_MAP_START total=$_total par=$_par remote_type=${remote_type:-none} deferred_remote=${SPEEDBACKUP_REMOTE_SETUP_DEFERRED:-0}"
	# 用 here-string 餵 while, 避免管道把迴圈丟進子 shell (子 shell 內背景任務的變數作用域問題)
	local _pkg _typ _dp
	while read -r _pkg; do
		[[ -z $_pkg ]] && continue
		let _i++
		printf '\r -預掃數據大小 %d/%d %s' "$_i" "$_total" "$(progress_bar $((_i * 100 / _total)))" >&2
		for _typ in user user_de data obb; do
			case $_typ in
				user|user_de)
					if [[ ${Backup_Mode:-false} != true || ${Backup_user_data:-false} != true ]]; then
						_speed_debug_log "DIRSIZE_SKIP pkg=$_pkg type=$_typ reason=user_data_disabled"
						continue
					fi
					;;
				data|obb)
					if [[ ${Backup_Mode:-false} != true || ${Backup_obb_data:-false} != true ]]; then
						_speed_debug_log "DIRSIZE_SKIP pkg=$_pkg type=$_typ reason=obb_data_disabled"
						continue
					fi
					;;
			esac
			case $_typ in
				user)    _dp="$path2/$_pkg" ;;
				user_de) _dp="$path3/$_pkg" ;;
				data)    _dp="$path/data/$_pkg" ;;
				obb)     _dp="$path/obb/$_pkg" ;;
			esac
			[[ ! -d $_dp ]] && continue
			# 背景並行算大小, 各寫獨立檔 (無共享寫入, 安全); 背景內再確認 workdir 存在防競態
			{
				if [[ -d $_workdir ]]; then
					_ds_start="$(date -u +%s%3N 2>/dev/null)"; [[ -z $_ds_start ]] && _ds_start=$(( $(date -u +%s 2>/dev/null) * 1000 ))
					_speed_debug_log "DIRSIZE_BEGIN pkg=$_pkg type=$_typ path=$_dp"
					_ds_size="$(find "$_dp" -type f -printf '%s\n' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{s+=$1}END{print s+0}')"
					printf '%s\t%s\t%s\n' "$_pkg" "$_typ" "$_ds_size" > "$_workdir/${_pkg}.${_typ}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					_ds_end="$(date -u +%s%3N 2>/dev/null)"; [[ -z $_ds_end ]] && _ds_end=$(( $(date -u +%s 2>/dev/null) * 1000 ))
					_ds_elapsed=$((_ds_end - _ds_start))
					_speed_debug_log "DIRSIZE_END pkg=$_pkg type=$_typ elapsedMs=$_ds_elapsed size=$_ds_size path=$_dp"
					[[ $_ds_elapsed -ge 5000 ]] && _speed_debug_log "DIRSIZE_SLOW pkg=$_pkg type=$_typ elapsedMs=$_ds_elapsed size=$_ds_size path=$_dp"
				fi
				# 上一條 [[ elapsed -ge 5000 ]] 在非慢目錄時會回 1；背景 size 任務本身已成功，避免 wait list 顯示 rc=1。
				true
			} &
			_dsz_pids="$_dsz_pids $!"
			SPEEDBACKUP_DIRSIZE_PIDS="${SPEEDBACKUP_DIRSIZE_PIDS:-} $!"
			_running=$((_running+1))
			[[ $_running -ge $_par ]] && { _event_wait_pid_list "$_dsz_pids" dirsize_batch; _dsz_pids=""; SPEEDBACKUP_DIRSIZE_PIDS=""; _running=0; }
		done
	done <<EOF
$_list
EOF
	_event_wait_pid_list "$_dsz_pids" dirsize_final
	SPEEDBACKUP_DIRSIZE_PIDS=""
	echo >&2
	cat "$_workdir"/* 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} > "$_map"
	_speed_debug_log "DIRSIZE_MAP_END rows=$(wc -l < "$_map" 2>/dev/null)"
	rm -rf "$_workdir"
}

# WebDAV 遠端總列表已成功取得時，若明確沒有某個檔案，視為已知不存在。
# 用途：避免對全新/剛刪除的 app_details.json 發 GET；部分輕量 WebDAV server
# 對不存在檔案會短暫回 2xx + Content-Length 但 body 提前 EOF，造成 fixed body EOF 噪音。
_remote_webdav_filelist_absent() {
	local _rel="$1"
	[[ $remote_type = webdav && $remote_stream = 1 ]] || return 1
	[[ -f $TMPDIR/.remote_files ]] || return 1
	# 7.66-277：清掉 275/276 測試殘留的 shell 變數 gate，統一只信任 marker file。
	# 避免函式重定向 / 子流程邊界造成變數可見性誤判。
	[[ -f $TMPDIR/.remote_filelist_ok ]] || return 1
	awk -v r="$_rel" '$0==r{f=1;exit} END{exit !f}' "$TMPDIR/.remote_files" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && return 1
	return 0
}

# SMB 遠端總列表已成功取得且路徑為純 ASCII 時，若明確沒有某個檔案，視為已知不存在。
# 中文/非 ASCII app 名稱保留原本 get fallback，避免 smbclient 代碼頁轉碼造成 false missing。
_remote_smb_filelist_absent() {
	local _rel="$1"
	[[ $remote_type = smb && $remote_stream = 1 ]] || return 1
	[[ -f $TMPDIR/.remote_files ]] || return 1
	grep -q . "$TMPDIR/.remote_files" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	printf '%s\n' "$_rel" | LC_ALL=C grep -Eq '^[ -~]+$' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	awk -v r="$_rel" '$0==r{f=1;exit} END{exit !f}' "$TMPDIR/.remote_files" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && return 1
	return 0
}

_remote_appdetails_filelist_absent() {
	_remote_webdav_filelist_absent "$1" && return 0
	_remote_smb_filelist_absent "$1" && return 0
	return 1
}

# 遠端模式: 並發預掃所有 app 的遠端 app_details.json 到本地快取
# 主迴圈 apk/data 增量比對直接讀快取, 免每 app 多次遠端往返
prepare_remote_json_map() {
	local _cache="$TMPDIR/.remote_json"
	rm -rf "$_cache"; mkdir -p "$_cache"
	[[ -z $remote_type ]] && return
	local _list
	# appList/txt 格式是「備份顯示名 package version...」；主備份迴圈的遠端資料夾固定使用第 1 欄 name1。
	# 舊寫法只移除最後一欄，遇到三欄格式會變成「AdobeScan com.adobe.scan.android」，
	# 導致預掃去找 AdobeScan com.adobe.scan.android/app_details.json，
	# 實際遠端卻是 AdobeScan/app_details.json，第二輪仍被誤判為「遠端無此備份」。
	_list="$(echo "$txt" | awk '{n=$1; sub(/^[!！]+/,"",n); if(n!="") print n}' | grep -v '^$')"
	[[ -z $_list ]] && { touch "$_cache/.done"; return; }
	local _subdir
	_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	# WebDAV 根備份目錄 404 時代表遠端是全新備份或目錄不存在；
	# 此時逐 app GET app_details.json 只會打出大量 404，直接標記完成並走全量備份。
	if [[ $remote_type = webdav && ${REMOTE_BACKUP_ROOT_MISSING:-0} = 1 ]]; then
		_speed_debug_log "REMOTE_JSON_SKIP reason=backup_root_404 total=$(printf '%s\n' "$_list" | grep -vc '^$' 2>/dev/null) subdir=$_subdir"
		echoRgb "遠端備份目錄不存在，跳過 app_details 預抓，改走全量備份" "2"
		touch "$TMPDIR/.remote_json/.done"
		return 0
	fi
	# 全部 app 直接批量抓 json (不靠遠端列表交集 — smbclient 列表對中文名會轉碼毀名導致誤配)
	# 不存在的檔 get 失敗即空, 內容驗證會濾掉; 批量模式連線數不增
	echo "$_list" > "$TMPDIR/.json_fetch"
	local _total _i=0
	_total="$(grep -vc '^$' "$TMPDIR/.json_fetch")"
	if [[ $_total -eq 0 ]]; then
		rm -f "$TMPDIR/.json_fetch"; touch "$_cache/.done"; echo >&2; return
	fi
	if [[ $remote_type = smb ]]; then
		# SMB: 單連線批量 get (每批 20 檔), 連線數 120→6
		local _auth SMB_OPTS _batchcmd="" _app _n=0
		_auth="$(_smb_auth_args_current)" || { echoRgb "SMB 認證資訊不可用，已停止操作" "0"; return 1; }
		SMB_OPTS="-t 300 -s $(_smb_client_conf)${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _base="$SMB_REM_PATH/$_subdir"; _base="${_base#/}"; _base="${_base//\//\\}"
		while read -r _app; do
			[[ -z $_app ]] && continue
			let _i++
			if _remote_smb_filelist_absent "$_app/app_details.json"; then
				_speed_debug_log "SMB_REMOTE_APPDETAILS_LIST_MISS app=$_app rel=$_app/app_details.json"
				continue
			fi
			let _n++
			_batchcmd="$_batchcmd get \"${_app//\//\\}\\app_details.json\" \"$_cache/$_app.json\";"
			if [[ $_n -ge 20 ]]; then
				printf '\r -預掃遠端清單 %d/%d' "$_i" "$_total" >&2
				command smbclient "$SMB_SHARE" $_auth $SMB_OPTS -c "cd \"$_base\"; $_batchcmd" >/dev/null 2>&1
				_batchcmd=""; _n=0
			fi
		done < "$TMPDIR/.json_fetch"
		[[ -n $_batchcmd ]] && command smbclient "$SMB_SHARE" $_auth $SMB_OPTS -c "cd \"$_base\"; $_batchcmd" >/dev/null 2>&1
		printf '\r -預掃遠端清單 %d/%d' "$_total" "$_total" >&2
	else
		# WebDAV: 預掃 app_details 改用單檔 GET。
		# v24.20.14-7.66-15：部分 WebDAV 服務在 _stream_download 預掃小 JSON 時會回下載 rc=18，
		# 但同一路徑用 remote_download_single_file/WEBDAV_SINGLE_GET 可成功。
		# 因此這裡直接走已驗證較穩的單檔 GET，避免遠端已有 app_details 卻 seed 失敗後不必要重備份。
		local _running=0 _app _json_pids=""
		while read -r _app; do
			[[ -z $_app ]] && continue
			let _i++
			printf '\r -預掃遠端清單 %d/%d' "$_i" "$_total" >&2
			(
				local _tmp_json="$_cache/$_app.json.part" _final_json="$_cache/$_app.json" _ok=0 _try=1
				rm -f "$_tmp_json" "$_final_json" 2>/dev/null
				if _remote_appdetails_filelist_absent "$_app/app_details.json"; then
					_speed_debug_log "WEBDAV_REMOTE_APPDETAILS_LIST_MISS app=$_app rel=$_app/app_details.json"
					exit 0
				fi
				# 只有 HTTP 0 / daemon 無回應 / 連線類錯誤才 retry。
				# HTTP 404 代表該 app 遠端本來就沒有 app_details，不重試，避免冷遠端 50 app 變 100 次 GET。
				while [[ $_try -le 2 ]]; do
					if remote_download_single_file "$_app/app_details.json" "$_tmp_json"; then
						_ok=1
						break
					fi
					case ${_WEBDAV_HTTP_CODE:-0} in
					0)
						_speed_debug_log "WEBDAV_REMOTE_APPDETAILS_RETRY app=$_app try=$_try http=${_WEBDAV_HTTP_CODE:-0}"
						rm -f "$_tmp_json" 2>/dev/null
						let _try++
						[[ $_try -le 2 ]] && sleep 1
						;;
					*)
						_speed_debug_log "WEBDAV_REMOTE_APPDETAILS_NO_RETRY app=$_app try=$_try http=${_WEBDAV_HTTP_CODE:-0}"
						break
						;;
					esac
				done
				if [[ $_ok = 1 ]]; then
					# 遠端 app_details 快取必須是完整 object，且至少含 PackageName/apk_version。
					if [[ -s $_tmp_json ]] && jq -e 'type=="object" and ([.[] | objects | select(.PackageName != null and .apk_version != null)] | length > 0)' "$_tmp_json" >/dev/null 2>&1; then
						mv "$_tmp_json" "$_final_json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					else
						_speed_debug_log "WEBDAV_REMOTE_APPDETAILS_INVALID_DROP app=$_app file=$_tmp_json"
						rm -f "$_tmp_json" "$_final_json" 2>/dev/null
					fi
				else
					_speed_debug_log "WEBDAV_REMOTE_APPDETAILS_MISSING_OR_FAIL app=$_app method=single_get_retry"
					rm -f "$_tmp_json" "$_final_json" 2>/dev/null
				fi
			) &
			_json_pids="$_json_pids $!"
			let _running++
			if [[ $_running -ge 8 ]]; then _event_wait_pid_list "$_json_pids" webdav_json_fetch_batch; _json_pids=""; _running=0; fi
		done < "$TMPDIR/.json_fetch"
		_event_wait_pid_list "$_json_pids" webdav_json_fetch_final
	fi
	rm -f "$TMPDIR/.json_fetch"
	# 內容驗證: 必須是完整 JSON object；非 JSON / 半截 JSON 一律視為不存在。
	local _jf
	for _jf in "$_cache"/*.json; do
		[[ -f $_jf ]] || continue
		if ! jq -e 'type=="object" and ([.[] | objects | select(.PackageName != null and .apk_version != null)] | length > 0)' "$_jf" >/dev/null 2>&1; then
			_speed_debug_log "REMOTE_APPDETAILS_CACHE_DROP_INVALID file=${_jf##*/}"
			rm -f "$_jf" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		fi
	done
	echo >&2
	local _got=0
	for _jf in "$_cache"/*.json; do
		[[ -f $_jf ]] || continue
		_got=$((_got + 1))
	done
	echoRgb "遠端清單快取: $_got/$_total 個 app 有遠端紀錄" "2"
	touch "$_cache/.done"
}

# 取遠端 app_details: 預掃快取命中直接用。
# return: 0=取得成功, 1=下載/網路異常, 2=預掃已確認遠端不存在。
_get_remote_appdetails() {
	local _cache="$TMPDIR/.remote_json" _name="$1" _out="$2"
	# Media 不在批量預掃範圍內 (prepare_remote_json_map 只抓 appList.txt 裡的 app 名稱),
	# 但流式模式已經有遠端總列表；若列表沒有 Media/app_details.json，視為「已知不存在」而不是錯誤。
	if [[ $_name = Media ]]; then
		if [[ $remote_stream = 1 && -f $TMPDIR/.remote_files ]]; then
			awk -v r="Media/app_details.json" '$0==r{f=1;exit} END{exit !f}' "$TMPDIR/.remote_files" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 2
		fi
		remote_download_single_file "$_name/app_details.json" "$_out"
		return $?
	fi
	if [[ -f $_cache/.done ]]; then
		if [[ -s "$_cache/$_name.json" ]]; then
			# v24.20.14-7.15：讀快取前再驗一次，避免舊壞快取被健康檢查當成「遠端 json 損壞」。
			if jq -e 'type=="object" and ([.[] | objects | select(.PackageName != null and .apk_version != null)] | length > 0)' "$_cache/$_name.json" >/dev/null 2>&1; then
				cp "$_cache/$_name.json" "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				if jq -e 'type=="object" and ([.[] | objects | select(.PackageName != null and .apk_version != null)] | length > 0)' "$_out" >/dev/null 2>&1; then
					return 0
				fi
			fi
			_speed_debug_log "REMOTE_APPDETAILS_CACHE_INVALID_DROP name=$_name cache=$_cache/$_name.json"
			rm -f "$_cache/$_name.json" "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			return 2
		fi
		# 批量預掃已完成且沒有此 app 的 json：這是全新遠端備份/遠端缺檔，不是下載失敗。
		return 2
	fi
	remote_download_single_file "$_name/app_details.json" "$_out"
}

# 流式模式: 並發預掃遠端各 app 是否已有入口腳本 (recover.sh)
# 結果寫 $TMPDIR/.remote_scripts (一行一個「已有腳本」的 app 名), 主迴圈查表零開銷
# 一次抓遠端檔案總列表 (供腳本檢查/核驗共用, 單連線取代逐檔往返)
prepare_remote_filelist() {
	: > "$TMPDIR/.remote_files"
	rm -f "$TMPDIR/.remote_filelist_ok" "$TMPDIR/.remote_webdav_last_list_ok" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	REMOTE_FILELIST_HTTP_CODE=0
	REMOTE_BACKUP_ROOT_MISSING=0
	[[ -z $remote_type ]] && return
	echoRgb "預掃遠端檔案列表 (單次連線)..." "3"
	remote_list_files "${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}" > "$TMPDIR/.remote_files" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [[ $remote_type = webdav ]]; then
		if [[ -f $TMPDIR/.remote_webdav_last_list_ok ]]; then
			REMOTE_FILELIST_HTTP_CODE=207
			: > "$TMPDIR/.remote_filelist_ok"
			_speed_debug_log "WEBDAV_REMOTE_FILELIST_OK rows=$(grep -vc '^$' "$TMPDIR/.remote_files" 2>/dev/null)"
		else
			REMOTE_FILELIST_HTTP_CODE="${_WEBDAV_HTTP_CODE:-0}"
			case $REMOTE_FILELIST_HTTP_CODE in
			404)
				REMOTE_BACKUP_ROOT_MISSING=1
				_speed_debug_log "REMOTE_FILELIST_ROOT_MISSING http=404 subdir=${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
				;;
			esac
		fi
	else
		: > "$TMPDIR/.remote_filelist_ok"
	fi
	echoRgb "遠端列表取得 $(grep -vc '^$' "$TMPDIR/.remote_files" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) 筆" "2"
}

prepare_remote_scripts_map() {
	local _map="$TMPDIR/.remote_scripts"
	: > "$_map"
	[[ $remote_stream != 1 ]] && return
	# 從總列表取「已有 recover.sh」的 app (零額外連線)
	awk -F'/recover.sh' '/\/recover.sh$/{print $1}' "$TMPDIR/.remote_files" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} > "$_map"
}

# 預掃 pkg → version code map (取代 Backup_apk 內每個 app 都 fork pm 的開銷)
# 寫到 $TMPDIR/.pkg_ver 格式: pkg<TAB>versionCode
prepare_pkg_ver_map() {
	# 正確解析 pm list packages --show-versioncode 輸出
	# 兼容格式:
	#   package:<pkg> versionCode:<code>
	#   package:<pkg> versionCode=<code>
	#   package:<pkg> versionCode:<code>:...
	# 同 pkg 多行只取第一個；只輸出純數字，避免 map 命中但比較式失準。
	: > "$TMPDIR/.pkg_ver" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	pm list packages --show-versioncode --user "${user:-0}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} 		| awk '
			{
				pkg = ""; ver = ""
				for (i = 1; i <= NF; i++) {
					f = $i
					if (f ~ /^package:/) {
						pkg = f
						sub(/^package:/, "", pkg)
					} else if (f ~ /^versionCode[:=]/) {
						ver = f
						sub(/^versionCode[:=]/, "", ver)
						sub(/:.*/, "", ver)
						sub(/[^0-9].*/, "", ver)
					}
				}
				if (pkg != "" && ver ~ /^[0-9]+$/ && !(pkg in seen)) {
					print pkg "	" ver
					seen[pkg] = 1
				}
			}
		' >> "$TMPDIR/.pkg_ver" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}
app_details_read() {
	local file="$1" tmpf
	APK_VER=""; PKG_NAME=""; BACKUP_TIME=""
	SIZE_user=""; SIZE_data=""; SIZE_obb=""; SIZE_user_de=""; SIZE_media=""
	[[ ! -f $file ]] && return
	tmpf="$TMPDIR/.app_details_read_$$"
	jq -r '
		(try (([.[] | objects | select(.apk_version != null).apk_version] | .[0]) // "") catch ""),
		(try (([.[] | objects | select(.PackageName != null).PackageName] | .[0]) // "") catch ""),
		(try (."Backup time".date // "") catch ""),
		(try (.user.Size // "") catch ""),
		(try (.data.Size // "") catch ""),
		(try (.obb.Size // "") catch ""),
		(try (.user_de.Size // "") catch ""),
		(try (.media.Size // "") catch "")
	' "$file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} > "$tmpf"
	exec 3< "$tmpf"
	read -r APK_VER <&3
	read -r PKG_NAME <&3
	read -r BACKUP_TIME <&3
	read -r SIZE_user <&3
	read -r SIZE_data <&3
	read -r SIZE_obb <&3
	read -r SIZE_user_de <&3
	read -r SIZE_media <&3
	exec 3<&-
	rm -f "$tmpf"
}

# 判斷目前 app_details.json 的指定 entry 是否已存在指定欄位。
# 用途：app_details 被 APK/Size 流程重建後，即使舊值與當前值相同，也必須補寫缺失欄位。
# 回傳：0=欄位存在且不是 null，1=缺失/檔案不存在/JSON異常
app_details_has_key() {
	local _file="$1" _entry="$2" _key="$3"
	[[ -s $_file && -n $_entry && -n $_key ]] || return 1
	jq -e --arg e "$_entry" --arg k "$_key" 'try (.[$e] | has($k) and .[$k] != null) catch false' "$_file" >/dev/null 2>&1
}

# Chrome 特例: trichromelibrary 會留多個舊版本, 只保留最新一個
# 在 Backup_apk 末尾 (name2=com.android.chrome 時) 呼叫
cleanup_chrome_legacy() {
	local files
	files=$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})
	[[ -z $files ]] && return
	local n
	n=$(printf "%s\n" "$files" | awk 'END{print NR}')
	# 多於 1 個 → 按時間刪掉舊的, 只留最新
	if [[ $n -gt 1 ]]; then
		echo "$files" \
			| while read -r f; do
				printf '%s %s\n' "$(stat -c '%Y' "$f" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})" "$f"
			done \
			| sort -n \
			| head -n -1 \
			| while read -r _ts oldfile; do
				rm -rf "${oldfile%/*/*}" && echo "刪除文件:${oldfile%/*/*}"
			done
	fi
	# 拷貝最新一個到備份目錄
	local kept
	kept=$(ls /data/app/*/com.google.android.trichromelibrary_*/base.apk 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | head -1)
	[[ -f $kept ]] && cp -r "$kept" "$Backup_folder/nmsl.apk"
}

# 查 app uid (三層 fallback, 優先用 prepare_pkg_uid_map 預掃的 .pkg_uid)
# 用法: uid=$(get_app_uid "$pkg")
get_app_uid() {
	local pkg="$1" uid
	# 優先從預掃 map 查
	if [[ -f $TMPDIR/.pkg_uid ]]; then
		uid=$(awk -v p="$pkg" -F'\t' '$1 == p {print $2; exit}' "$TMPDIR/.pkg_uid")
		[[ -n $uid ]] && { echo "$uid"; return; }
	fi
	# fallback 1: pm list，兼容 uid:123 / uid=123
	uid=$(pm list packages -U --user "${user:-0}" </dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk -v pkg="$pkg" '
		{
			p=""; u=""
			for (i=1;i<=NF;i++) {
				f=$i
				if (f ~ /^package:/) {p=f; sub(/^package:/,"",p)}
				else if (f ~ /^uid[:=]/) {u=f; sub(/^uid[:=]/,"",u)}
			}
			if (p == pkg && u ~ /^[0-9]+$/) {print u; exit}
		}')
	# fallback 2: dumpsys
	[[ -z $uid ]] && uid=$(dumpsys package "$pkg" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk -F'uid=' '{print $2}' | grep -Eo '[0-9]+' | head -n 1)
	# fallback 3: get_uid
	[[ -z $uid ]] && uid=$(get_uid "$pkg" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})
	echo "$uid" | grep -Eo '[0-9]+' | head -n 1
}

# 恢復用: 一次抓 Release_data 需要的 Size / keystore / path
# 用法: release_details_read <app_details.json> <entry>
# 設定全域變數: REL_SIZE / REL_KEYSTORE / REL_PATH
release_details_read() {
	local file="$1" entry="$2"
	REL_SIZE=""; REL_KEYSTORE=""; REL_PATH=""
	[[ ! -f $file ]] && return
	local tmpf="$TMPDIR/.rel_jq_$$"
	jq -r --arg e "$entry" '
		(try (.[$e].Size // "") catch ""),
		(try (([.[] | objects | select(.keystore != null).keystore] | .[0]) // "") catch ""),
		(try (.[$e].path // "") catch "")
	' "$file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} > "$tmpf"
	exec 3< "$tmpf"
	read -r REL_SIZE <&3
	read -r REL_KEYSTORE <&3
	read -r REL_PATH <&3
	exec 3<&-
	rm -f "$tmpf"
}

# 預掃 pm list packages --user (取代 Restore 主迴圈內每 app fork)
# 寫到 $TMPDIR/.installed_pkgs (一行一個 pkg name)
prepare_installed_pkgs_map() {
	# v24.20.14-7.3：先建立空檔，避免 pm/cut 在特殊 ROM 或權限情境失敗時，後續 awk 讀不到檔案造成 stderr 雜訊。
	: > "$TMPDIR/.installed_pkgs" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	pm list packages --user "${user:-0}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} \
		| cut -f2 -d':' >> "$TMPDIR/.installed_pkgs" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

# 計算指定目錄的總大小並輸出可讀字串 (KB/MB/GB)
Calculate_size() {
	#計算出備份大小跟差異性
	filesizee="$(calc_dir_size "$1")"
	# awk 比較大小差異 (無 32-bit 溢位)
	local _diff
	_diff=$(awk -v a="$filesizee" -v b="${filesize:-0}" 'BEGIN{print a-b}')
	case $_diff in
	-*)
		NJL="本次備份減少 $(size "$(awk -v a="${filesize:-0}" -v b="$filesizee" 'BEGIN{print a-b}')")" ;;
	0)
		NJL="文件大小未改變" ;;
	*)
		NJL="本次備份增加 $(size "$_diff")" ;;
	esac
	echoRgb "備份資料夾路徑↓↓↓\n -$1"
	echoRgb "備份資料夾總體大小$(size "$filesizee") $filesizee"
	echoRgb "$NJL"
}
# 把 bytes 轉成人類可讀格式 (B/KB/MB/GB)
# 用法: size <bytes 數值> 或 size <檔案路徑> (會 stat 取大小)
size() {
	local b_size get_size
	case $1 in
	*[!0-9]*)
		b_size="$(stat -c%s "$1" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})" ;;
	*)
		b_size="$1" ;;
	esac
	# 用 awk printf 四捨五入 (跟檔案管理器一致), awk 處理大數無 32-bit 溢位問題
	if [[ $b_size -eq 0 ]]; then
		get_size="0 bytes"
	elif [[ $(awk -v n="$b_size" 'BEGIN{print (n<1024)?1:0}') -eq 1 ]]; then
		get_size="${b_size} bytes"
	elif [[ $(awk -v n="$b_size" 'BEGIN{print (n<1048576)?1:0}') -eq 1 ]]; then
		get_size="$(awk "BEGIN{printf \"%.2f\", $b_size/1024}") KB"
	elif [[ $(awk -v n="$b_size" 'BEGIN{print (n<1073741824)?1:0}') -eq 1 ]]; then
		get_size="$(awk "BEGIN{printf \"%.2f\", $b_size/1048576}") MB"
	else
		get_size="$(awk "BEGIN{printf \"%.2f\", $b_size/1073741824}") GB"
	fi
	echo "$get_size"
}
#分區佔用信息
partition_info() {
	unset Skip
	Occupation_status="$(df -B1 "$(_resolve_real_mount "${1%/*}")" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1)}')"
	Filesize2="$(size "$Filesize")"
	# 流式模式: 數據不落地本機, 本機剩餘空間跟這次備份無關, 不顯示 (避免誤導使用者以為是遠端容量)
	if [[ $remote_stream = 1 ]]; then
		echo " -$2大小:$Filesize2"
	else
		echo " -$2大小:$Filesize2 剩餘大小:$(size "$Occupation_status")"
	fi
	if [[ $remote_stream != 1 && -n $Filesize ]]; then
		if awk -v a="$Filesize" -v b="$Occupation_status" 'BEGIN{exit !(a+0 > b+0)}'; then
			echoRgb "$2備份大小將超出rom可用大小" "0"
			Skip=1
		fi
	fi
	Occupation_status="$(df -h "$(_resolve_real_mount "${Backup%/*}")" | sed -n 's|% /.*|%|p' | awk '{print $(NF-1),$(NF)}')"
}
_progress_local_storage_suffix() {
	# 若整輪都只是跳過備份，partition_info() 可能未被呼叫；此時仍要即時查一次本地剩餘空間，避免進度列顯示「本地剩餘:使用率:」。
	[[ $remote_stream = 1 ]] && return 0
	local _occ="${Occupation_status:-}" _target
	if [[ -z $_occ ]]; then
		_target="${Backup%/*}"
		[[ -z $_target || $_target = "$Backup" ]] && _target="$MODDIR"
		_occ="$(df -h "$(_resolve_real_mount "$_target")" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sed -n 's|% /.*|%|p' | awk '{print $(NF-1),$(NF); exit}')"
	fi
	printf '%s
' "$_occ" | awk -v pfx="${hx:-本地}" '
		END {
			if ($1 == "" || $2 == "") print " " pfx "剩餘:未知使用率:未知";
			else print " " pfx "剩餘:" $1 "使用率:" $2;
		}'
}
# 取得指定 app 的後台運行 PID (Dex daemon 不可用時的 fallback)
Process_Information() {
	dumpsys activity processes 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk -v key="$1" -v user="$user" '
	function getUserFromUid(uid){return int(uid/100000)}
	# 進程塊起點: ProcessRecord{hash PID:name/uid} → 抓 pid (兼容無獨立 pid= 行的新格式)
	/ProcessRecord\{/ {tmp=$0; sub(/^.*ProcessRecord\{[^ ]+ /,"",tmp); sub(/:.*/,"",tmp); pid=tmp; uid=""; pkg=""; next}
	/^ *user #[0-9]+ uid=/ {if($0 ~ /ISOLATED uid=[0-9]+/){uid="";next} tmp=$0; sub(/^.*uid=/,"",tmp); sub(/ .*/,"",tmp); uid=tmp}
	/packageList=\{/ {tmp=$0; sub(/^.*packageList=\{/,"",tmp); sub(/\}.*/,"",tmp); pkg=tmp; if(pkg!="" && uid!="" && pid!=""){if((key=="" || pkg==key) && (user=="" || getUserFromUid(uid)==user)) print pid}}
	'
}

# foregroundStateBatch 指定包名 active 查詢：正式流程優先走 AppState daemon。
# 回傳: 0=active=true, 1=active=false, 2=查詢失敗。
_foreground_state_pkg_active() {
	local _pkg="$1" _in _out _active
	[[ -n $_pkg ]] || return 2
	_in="$TMPDIR/.foreground_state_one_${$}_$RANDOM.in"
	_out="$TMPDIR/.foreground_state_one_${$}_$RANDOM.out"
	printf '%s\n' "$_pkg" > "$_in" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 2
	if _appstate_daemon_call foregroundStateBatch "$_in" "$_out"; then
		_active="$(jq -r --arg p "$_pkg" 'select(.recordType=="foregroundState" and .packageName==$p) | .active' "$_out" 2>/dev/null | tail -n 1)"
		_speed_debug_log "FOREGROUND_STATE_BATCH_DAEMON pkg=$_pkg active=${_active:-unknown} result=${_APPSTATE_RESULT_CODE:-unknown}/${_APPSTATE_RESULT_NAME:-unknown}"
		rm -f "$_in" "$_out" 2>/dev/null
		case $_active in
		true) return 0 ;;
		false) return 1 ;;
		esac
		return 2
	fi
	_speed_debug_log "FOREGROUND_STATE_BATCH_DAEMON_FAIL pkg=$_pkg result=${_APPSTATE_RESULT_CODE:-unknown}/${_APPSTATE_RESULT_NAME:-unknown}"
	rm -f "$_in" "$_out" 2>/dev/null
	return 2
}

# 透過 HiddenApi daemon forceStopPackageBatch 單獨終止指定 app。
# 回傳: 0=daemon force-stop 成功, 1=daemon force-stop 失敗。
_force_stop_pkg_daemon() {
	local _pkg="$1" _out _rc
	[[ -n $_pkg ]] || return 1
	_out="$(_webdav_tmp_path hiddenapi_force_stop_${$}_$RANDOM)"
	_hiddenapi_daemon_call_args forceStopPackageBatch "${USER_ID:-${user:-0}}" "$_pkg" > "$_out"
	_rc=$?
	if [[ $_rc = 0 ]] && grep -F "FORCE_STOP_OK package=$_pkg " "$_out" >/dev/null 2>&1; then
		_speed_debug_log "FORCE_STOP_PACKAGE_BATCH_DAEMON_OK pkg=$_pkg out=$(tr '\n' '|' < "$_out" | cut -c1-300)"
		rm -f "$_out" 2>/dev/null
		return 0
	fi
	_speed_debug_log "FORCE_STOP_PACKAGE_BATCH_DAEMON_FAIL pkg=$_pkg rc=$_rc out=$(tr '\n' '|' < "$_out" | cut -c1-300)"
	rm -f "$_out" 2>/dev/null
	return 1
}

# 強制終止指定 app (foregroundStateBatch daemon + HiddenApi forceStopPackageBatch daemon + fallback am force-stop)
kill_app() {
	local _active_rc _process_after
	[[ -n $name2 ]] || return 0
	case $name2 in
	bin.mt.plus|com.termux|bin.mt.plus.canary)
		_speed_debug_log "KILL_APP_SKIP_SELF pkg=$name2"
		return 0
		;;
	esac

	_foreground_state_pkg_active "$name2"
	_active_rc=$?
	case $_active_rc in
	0)
		if _force_stop_pkg_daemon "$name2"; then
			_process_after="$(Process_Information "$name2")"
			printf '%s\n' "$_process_after" | while read -r _kp; do
				case $_kp in ''|*[!0-9]*) continue ;; esac
				kill -0 "$_kp" 2>/dev/null && kill -9 "$_kp" 2>/dev/null
			done
			pkill -9 -f "$name2$|$name2[:/_]" 2>/dev/null
			echoRgb "殺死$name1進程"
			_speed_debug_log "KILL_APP_DONE method=foregroundStateBatch_daemon+forceStopPackageBatch_daemon pkg=$name2 active=true remaining_pids=$(printf '%s\n' "$_process_after" | awk 'NF{n++} END{print n+0}')"
		else
			am force-stop --user "$user" "$name2" &>/dev/null
			_process_after="$(Process_Information "$name2")"
			printf '%s\n' "$_process_after" | while read -r _kp; do
				case $_kp in ''|*[!0-9]*) continue ;; esac
				kill -0 "$_kp" 2>/dev/null && kill -9 "$_kp" 2>/dev/null
			done
			pkill -9 -f "$name2$|$name2[:/_]" 2>/dev/null
			echoRgb "殺死$name1進程"
			_speed_debug_log "KILL_APP_DONE method=foregroundStateBatch_daemon+am_fallback pkg=$name2 active=true remaining_pids=$(printf '%s\n' "$_process_after" | awk 'NF{n++} END{print n+0}')"
		fi
		;;
	1)
		_speed_debug_log "KILL_APP_SKIP_INACTIVE method=foregroundStateBatch_daemon pkg=$name2 active=false"
		;;
	*)
		# daemon/協定不可用時才回舊 dumpsys PID 路線，避免混版直接失去 kill 行為。
		process_Information="$(Process_Information "$name2")"
		if [[ $process_Information != "" ]]; then
			am force-stop --user "$user" "$name2" &>/dev/null
			printf '%s\n' "$process_Information" | while read -r _kp; do
				case $_kp in ''|*[!0-9]*) continue ;; esac
				kill -0 "$_kp" 2>/dev/null && kill -9 "$_kp" 2>/dev/null
			done
			pkill -9 -f "$name2$|$name2[:/_]" 2>/dev/null
			echoRgb "殺死$name1進程"
			_speed_debug_log "KILL_APP_DONE method=dumpsys_fallback pkg=$name2 pids=$(printf '%s\n' "$process_Information" | awk 'NF{n++} END{print n+0}')"
		else
			_speed_debug_log "KILL_APP_SKIP_NO_PROCESS method=dumpsys_fallback pkg=$name2"
		fi
		;;
	esac
}
# ======================================================

# 取得當前 apk versionCode。優先使用預掃 .pkg_ver，失敗才 fallback。
# 避免單獨備份/部分 ROM 下 .pkg_ver 未命中時，把 app_details.apk_version 覆蓋成空值。
get_current_apk_version_code() {
	local _pkg="$1" _v=""
	[[ -z $_pkg ]] && { echo ""; return 0; }
	if [[ -f $TMPDIR/.pkg_ver ]]; then
		_v="$(_kv_file_get "$TMPDIR/.pkg_ver" "$_pkg" | tr -d ' \t\r\n')"
	fi
	if [[ -z $_v ]]; then
		_v="$(pm list packages --show-versioncode --user "${user:-0}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} 			| awk -v pkg="$_pkg" '
				{
					p=""; v=""
					for (i=1;i<=NF;i++) {
						f=$i
						if (f ~ /^package:/) {p=f; sub(/^package:/,"",p)}
						else if (f ~ /^versionCode[:=]/) {v=f; sub(/^versionCode[:=]/,"",v); sub(/:.*/,"",v); sub(/[^0-9].*/,"",v)}
					}
					if (p == pkg && v ~ /^[0-9]+$/) {print v; exit}
				}
			' | tr -d ' \t\r\n')"
	fi
	if [[ -z $_v ]]; then
		_v="$(dumpsys package "$_pkg" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} 			| awk '
				{
					if (match($0, /versionCode=[0-9]+/)) {
						v = substr($0, RSTART, RLENGTH); sub(/^versionCode=/, "", v); print v; exit
					}
					if (match($0, /versionCode: *[0-9]+/)) {
						v = substr($0, RSTART, RLENGTH); sub(/^versionCode: */, "", v); print v; exit
					}
				}
			' 			| tr -d ' \t\r\n')"
	fi
	echo "$_v"
}

# 備份核心函數 (Backup_apk / Backup_data / unified AppState)
# ======================================================
# 備份 app 的 apk 檔 (含 split apk, 用 tar/zstd 打包)
Backup_apk() {
	# 契約 guard：nobackup 只可能是 "true"/"false"，兩個既有呼叫點 (12610/12612)
	# 呼叫前都已經 [[ $nobackup != true ]] 過濾，所以這裡進來時 nobackup 必為 "false"。
	# 明確寫成 guard，不再依賴函式內部一個「其實恆真」的 if 分支。
	[[ $nobackup = false ]] || return 0
	#檢測apk狀態進行備份
	#創建APP備份文件夾
	[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
	[[ ! -f $app_details ]] && echo "{\n}">"$app_details"
	# 從預掃 map 查當前版本 (取代 fork pm + cut + head)；未命中時 fallback，避免單獨備份把版本寫成空值
	eval "apk_version2=\${_pv_${name2//[!a-zA-Z0-9]/_}}"
	[[ -z $apk_version2 ]] && apk_version2="$(get_current_apk_version_code "$name2")"
	if [[ -z $apk_version2 ]]; then
		# 最後防線：保留舊版本值，避免 app_details.apk_version 被覆蓋成空字串而觸發 JSON 健全度缺 apk_version
		apk_version2="$APK_VER"
		[[ -z $apk_version2 ]] && apk_version2="unknown"
		echoRgb "當前apk版本號獲取失敗，保留/寫入保底版本:$apk_version2" "0"
	fi
	# 如果啟用遠程備份，從遠端獲取 app_details.json 進行對比
	local _remote_checked=0
	if [[ -n $remote_type ]]; then
		local remote_app_details="$TMPDIR/.remote_app_details_$$"
		local remote_rel="${name1}/app_details.json"
		if _get_remote_appdetails "$name1" "$remote_app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
			[[ -s $remote_app_details ]] && {
				_remote_checked=1
				# 從遠端 app_details 讀取版本號
				local remote_apk_ver
				remote_apk_ver=$(jq -r --arg name "$name1" 'try (.[$name].apk_version // "") catch ""' "$remote_app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})
				# 如果遠端版本與當前版本一致，且本地或遠端已有 apk 備份，才跳過備份。
				# v24.20.14-7.13：非流式 remote_keep_local=0 會在上傳成功後刪本地 tar，
				# 下一輪應以遠端檔案存在作為 skip 依據，避免本地缺檔而重壓/重傳。
				local _local_apk_exists=0
				if [[ -f "$Backup_folder/apk.tar.zst" ]] || [[ -f "$Backup_folder/apk.tar" ]]; then
					_local_apk_exists=1
				fi
				if [[ $remote_stream != 1 && -n $remote_type && -f $TMPDIR/.remote_files ]]; then
					if awk -v a="$name1/apk.tar.zst" -v b="$name1/apk.tar" '$0==a||$0==b{f=1;exit} END{exit !f}' "$TMPDIR/.remote_files" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
						_local_apk_exists=1
						_speed_debug_log "REMOTE_APK_EXISTS package=$name2 app=$name1 source=remote_files"
					fi
				fi
				# 流式模式: 遠端有且版本一致即可跳過 (不需本機 tar, 因流式本就不留本地)
				[[ $remote_stream = 1 ]] && _local_apk_exists=1
				if [[ -s "$TMPDIR/.listver_changed" ]] && awk -v p="$name2" '$0==p{f=1} END{exit !f}' "$TMPDIR/.listver_changed" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
					# 啟動檢查偵測到實機版本已變: 遠端 json 版本號不可信 (可能被失敗輪汙染), 強制重備
					echoRgb "清單偵測到版本已更新, 重新備份apk" "3"
				elif [[ -n $remote_apk_ver && $remote_apk_ver = "$apk_version2" && $_local_apk_exists = 1 ]]; then
					# 版本相符再核對遠端 apk 檔實際存在 (json 可能被舊版/失敗輪汙染而 apk 缺檔)
					_rapk_ok=0
					if [[ $remote_stream = 1 ]]; then
						if awk -v a="$name1/apk.tar.zst" -v b="$name1/apk.tar" '$0==a||$0==b{f=1;exit} END{exit !f}' "$TMPDIR/.remote_files" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
							_rapk_ok=1
						else
							# 列表沒找到 (可能中文名轉碼) → 單檔下載開頭確認
							case "$(_stream_download "${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}/$name1/apk.tar.zst" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | head -c 60)" in
							""|*NT_STATUS*) _rapk_ok=0 ;;
							*) _rapk_ok=1 ;;
							esac
						fi
					else
						_rapk_ok=1
					fi
					if [[ $_rapk_ok = 1 ]]; then
						_backup_mark_done_pkg
						# 遠端非流式且 APK 無變化時，要先用遠端 app_details.json 作為本輪本地種子。
						# 否則本地 app_details 只是新建的 {}，後續 Backup_metadata_once 會誤判 permissions/installer/battery 全部缺失，
						# 造成第二次增量仍重新備份/上傳 JSON。
						if [[ $remote_stream != 1 && -n $remote_type && -s $remote_app_details ]]; then
							cp "$remote_app_details" "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
							app_details_read "$app_details"
							_speed_debug_log "REMOTE_APPDETAILS_SEED app=$name1 package=$name2 source=remote_apk_skip"
						fi
						unset xb
						let osj++
						result=0
						echoRgb "Apk版本無更新(遠端備份無變化) 跳過備份" "2"
						rm -f "$remote_app_details"
						return 0
					fi
					echoRgb "版本相符但遠端缺apk檔, 補備份一次" "0"
				fi
			}
		fi
		rm -f "$remote_app_details"
		# 遠端啟用但查無此備份: 即使本地版本未變, 仍會備份並上傳一次
		[[ $_remote_checked = 0 ]] && echoRgb "遠端無此備份 將備份一次並上傳" "2"
	fi
	# APK_VER 已經由 app_details_read 載入 (在主迴圈呼叫過)
	apk_version="$APK_VER"
	# 遠端已啟用但無備份時，不應依據本地 app_details 跳過，應上傳到遠端
	_local_apk_exists=0
	if [[ -f "$Backup_folder/apk.tar.zst" ]] || [[ -f "$Backup_folder/apk.tar" ]]; then
		_local_apk_exists=1
	fi
	# 流式模式: 不依賴本機 tar (本機可能有舊備份殘留), 強制當作無本機檔, 走重新壓縮流式
	[[ $remote_stream = 1 ]] && _local_apk_exists=0
	if [[ $apk_version = $apk_version2 ]] && [[ $_local_apk_exists = 1 ]]; then
		# 版本一致且本地已有備份: 不重新打包
		_backup_mark_done_pkg
		unset xb
		let osj++
		result=0
		# 遠端啟用但查無此備份: 不重壓, 直接把現有本地檔標記為待上傳 (流式無本地檔, 不走此路)
		if [[ $remote_stream != 1 && -n $remote_type && $_remote_checked = 0 ]]; then
			backup_has_changes=1
			_mark_changed
			echoRgb "Apk版本無更新 遠端缺檔: 直接上傳本地備份(免重壓)" "2"
		else
			echoRgb "Apk版本無更新 跳過備份" "2"
		fi
	else
		# nobackup=false 已由函式開頭 guard 保證，這裡不再重複判斷。
		# 版本一致且本地已有 apk 備份: 不重壓 (避免重複備份)
		if [[ $apk_version != "" && $apk_version = "$apk_version2" && $_local_apk_exists = 1 ]]; then
			let osj++
			echoRgb "版本:$apk_version 無更新 跳過備份" "2"
			_backup_mark_done_pkg
			result=0
			return 0
		fi
		if [[ $apk_version != "" ]]; then
			if [[ $apk_version = "$apk_version2" ]]; then
				let osj++
				if [[ $remote_stream = 1 || -n $remote_type ]]; then
					echoRgb "版本:$apk_version (遠端無此版本, 補備份一次)"
				else
					echoRgb "版本:$apk_version (本機無備份檔, 補備份一次)"
				fi
			else
				let osn++
				# 用暫存檔取代字串拼接
				echo "$name1 \"$name2\"" >> "$TMPDIR/.update_apks"
				echoRgb "版本:$apk_version>$apk_version2"
			fi
		else
			let osk++
			echo "$name1 \"$name2\"" >> "$TMPDIR/.add_apks"
			echoRgb "版本:$apk_version2"
		fi
		unset Filesize
		Filesize="$(calc_dir_size "$apk_path2")"
		_archive_cleanup "$Backup_folder/apk"
		partition_info "$Backup" "$name1 apk"
		if [[ $Skip != 1 ]]; then
			#備份apk
			echoRgb "$1"
			echo "$apk_path" | sed -e '/^$/d' | while read -r; do
				echoRgb "${REPLY##*/} $(size "$REPLY")"
			done
			_backup_apk_archive_stage
			if [[ $result = 0 ]]; then
				_backup_apk_stage_record_success "$apk_version" "$apk_version2"
			else
				rm -rf "$Backup_folder"
			fi
		fi
	fi
	[[ $name2 = bin.mt.plus && ! -f $Backup/$name1.apk ]] && cp -r "$apk_path" "$Backup/$name1.apk"
}
# 壓縮持久化 AppState：Dex 可輸出完整診斷快照，但 app_details.json 只保存恢復必要欄位 + 快速查看 cn 欄位。
# 目的：移除 engineVersion/dexVersion/package uid/installDiagnostics/result/json_refresh 等 debug/診斷資料。
# 注意：raw 欄位仍完整保留；nameCn/modeCn/keyCn 等 cn 欄位保留作快速查看，不參與恢復判斷。
_appstate_persist_compact() {
	jq -c '
		def addif($o; $k): if (($o|type) == "object" and ($o|has($k))) then {($k): $o[$k]} else {} end;
		def notnull: with_entries(select(.value != null));
		def perm($p): (
			{} + addif($p;"name") + addif($p;"nameCn") + addif($p;"granted") + addif($p;"flags") +
			addif($p;"runtime") + addif($p;"development") + addif($p;"appOp") +
			addif($p;"appOpName") + addif($p;"appOpNameCn") + addif($p;"packageMode") + addif($p;"uidMode") +
			addif($p;"scope") + addif($p;"appOpMode") + addif($p;"appOpModeName") + addif($p;"appOpModeCn")
		) | notnull;
		def special($s): (
			{} + addif($s;"keyCn") + addif($s;"publicName") + addif($s;"publicNameCn") + addif($s;"manifestPermission") +
			addif($s;"manifestPermissionCn") + addif($s;"requested") + addif($s;"supported") + addif($s;"op") +
			addif($s;"packageMode") + addif($s;"uidMode") + addif($s;"scope") +
			addif($s;"mode") + addif($s;"modeName") + addif($s;"modeCn")
		) | notnull;
		def opobj($o): (
			{} + addif($o;"op") + addif($o;"publicName") + addif($o;"publicNameCn") + addif($o;"supported") +
			addif($o;"packageMode") + addif($o;"uidMode") + addif($o;"scope") +
			addif($o;"mode") + addif($o;"modeName") + addif($o;"modeCn")
		) | notnull;
		. as $s |
		({
			schemaVersion: ($s.schemaVersion // 2),
			recordType: ($s.recordType // "snapshot"),
			userId: ($s.userId // 0),
			packageName: $s.packageName,
			installer: ($s.package.installer // $s.installDiagnostics.installer // $s.installDiagnostics.installing // null),
			permissions: [($s.permissions // [])[] | perm(.)],
			specialAccess: (($s.specialAccess // {}) | with_entries(.value = special(.value))),
			batterySettings: (($s.batterySettings // {}) | with_entries(if (.value|type)=="object" then .value = opobj(.value) else . end)),
			otherAppOps: [($s.otherAppOps // [])[] | opobj(.)],
			ssaid: $s.ssaid
		} | notnull)
	' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

# 將 app_details.json 收斂成唯一 canonical restore profile；保留快速查看 cn 欄位。
# 正常備份與「重生現有備份JSON」都必須走同一個出口，避免兩邊 app_state/app entry/root metadata 結構不一致。
# 輸出固定使用 jq pretty JSON；所有正常備份/JSON重生出口都應保持同一格式。
_app_details_normalize_restore_profile_file() {
	local _file="$1" _tmp _rc
	[[ -s $_file ]] || return 1
	_tmp="${_file}.canon_${$}_$RANDOM"
	jq '
		def addif($o; $k): if (($o|type) == "object" and ($o|has($k))) then {($k): $o[$k]} else {} end;
		def notnull: with_entries(select(.value != null));
		def perm($p): (
			{} + addif($p;"name") + addif($p;"nameCn") + addif($p;"granted") + addif($p;"flags") +
			addif($p;"runtime") + addif($p;"development") + addif($p;"appOp") +
			addif($p;"appOpName") + addif($p;"appOpNameCn") + addif($p;"packageMode") + addif($p;"uidMode") +
			addif($p;"scope") + addif($p;"appOpMode") + addif($p;"appOpModeName") + addif($p;"appOpModeCn")
		) | notnull;
		def special($s): (
			{} + addif($s;"keyCn") + addif($s;"publicName") + addif($s;"publicNameCn") + addif($s;"manifestPermission") +
			addif($s;"manifestPermissionCn") + addif($s;"requested") + addif($s;"supported") + addif($s;"op") +
			addif($s;"packageMode") + addif($s;"uidMode") + addif($s;"scope") +
			addif($s;"mode") + addif($s;"modeName") + addif($s;"modeCn")
		) | notnull;
		def opobj($o): (
			{} + addif($o;"op") + addif($o;"publicName") + addif($o;"publicNameCn") + addif($o;"supported") +
			addif($o;"packageMode") + addif($o;"uidMode") + addif($o;"scope") +
			addif($o;"mode") + addif($o;"modeName") + addif($o;"modeCn")
		) | notnull;
		def state($s): (
			{
				schemaVersion: ($s.schemaVersion // 2),
				recordType: ($s.recordType // "snapshot"),
				userId: ($s.userId // 0),
				packageName: $s.packageName,
				installer: ($s.installer // $s.package.installer // $s.installDiagnostics.installer // $s.installDiagnostics.installing // null),
				permissions: [($s.permissions // [])[] | perm(.)],
				specialAccess: (($s.specialAccess // {}) | with_entries(.value = special(.value))),
				batterySettings: (($s.batterySettings // {}) | with_entries(if (.value|type)=="object" then .value = opobj(.value) else . end)),
				otherAppOps: [($s.otherAppOps // [])[] | opobj(.)],
				ssaid: $s.ssaid
			} | notnull
		);
		def pick_entry($e):
			reduce ["keystore","path","Size","size","apk_size","data_size","obb_size","media_size","origin_size","apk_version","versionCode","PackageName"][] as $k
			({}; if (($e|type)=="object" and ($e|has($k))) then .[$k]=$e[$k] else . end);
		def is_payload_entry($e):
			(($e|type)=="object") and (
				($e|has("Size")) or ($e|has("size")) or ($e|has("path")) or ($e|has("keystore")) or
				($e|has("apk_size")) or ($e|has("data_size")) or ($e|has("obb_size")) or
				($e|has("media_size")) or ($e|has("origin_size"))
			);
		def entry($e): (
			pick_entry($e) +
			{PackageName: ($e.PackageName // $e.app_state.packageName // null)} +
			(if (($e.app_state // null)|type) == "object" then {app_state: state($e.app_state)} else {} end)
		) | notnull;
		def payload_entry($e): (pick_entry($e)) | notnull;
		. as $root |
		({}
		 + (if ($root|has("Backup time")) then {"Backup time": $root["Backup time"]} else {} end)
		) as $base |
		reduce ($root|to_entries[]) as $it ($base;
			if ($it.key == "Backup time") then .
			elif (($it.value|type)=="object" and ($it.value.PackageName != null or $it.value.app_state.packageName != null)) then .[$it.key] = entry($it.value)
			elif is_payload_entry($it.value) then .[$it.key] = payload_entry($it.value)
			else . end)
	' "$_file" > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || { rm -f "$_tmp" 2>/dev/null; return 1; }
	_json_cat_replace "$_tmp" "$_file"
	_rc=$?
	if [[ $_rc = 0 ]]; then
		rm -f "$_file.pre360.bak" "$_file".pre*.bak 2>/dev/null
	fi
	rm -f "$_tmp" 2>/dev/null
	return $_rc
}

# 寫入每個 App 的唯一 canonical AppState 快照。
# 權限、AppOps、特殊存取、電池與 SSAID 均已包含在同一份 schema v2 JSON。
Backup_AppState() {
	local _state _state_raw _old _missing=0
	_state_raw="$(_kv_file_get "$TMPDIR/.pkg_appstate" "$name2")"
	_state="$_state_raw"
	if [[ -z $_state ]] || ! printf '%s\n' "$_state" | jq -e '
		type == "object" and .recordType == "snapshot" and .schemaVersion == 2 and
		.packageName != null and (.permissions|type)=="array" and
		(.specialAccess|type)=="object" and (.otherAppOps|type)=="array" and
		(.batterySettings|type)=="object"
	' >/dev/null 2>&1; then
		echoRgb "AppState快照缺失或格式錯誤: $name2" "0"
		_speed_debug_log "APPSTATE_BACKUP_SKIP package=$name2 reason=missing_or_invalid_canonical_snapshot"
		return 1
	fi
	_state="$(printf '%s\n' "$_state_raw" | _appstate_persist_compact)"
	if [[ -z $_state ]] || ! printf '%s\n' "$_state" | jq -e '
		type == "object" and .recordType == "snapshot" and .schemaVersion == 2 and
		.packageName != null and (.permissions|type)=="array" and
		(.specialAccess|type)=="object" and (.otherAppOps|type)=="array" and
		(.batterySettings|type)=="object"
	' >/dev/null 2>&1; then
		echoRgb "AppState持久化裁剪失敗: $name2" "0"
		_speed_debug_log "APPSTATE_BACKUP_SKIP package=$name2 reason=persist_compact_failed"
		return 1
	fi
	app_details_has_key "$app_details" "$name1" "app_state" || _missing=1
	_old="$(jq -c --arg entry "$name1" 'try (.[$entry].app_state // null) catch null' "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	if [[ $_missing = 1 || $_old != "$_state" ]]; then
		[[ $_missing = 0 ]] && _appstate_show_backup_diff "$_old" "$_state"
		if jq_inplace "$app_details" --arg entry "$name1" --argjson state "$_state" '
			.[$entry].app_state = $state |
			.[$entry] |= del(.permissions, .special_access, .battery_settings, .battery_opt,
				.installer, .install_diagnostics, .Ssaid, .permission_policy_v2)
		'; then
			if _app_details_normalize_restore_profile_file "$app_details"; then
				_speed_debug_log "APPDETAILS_CANONICAL_PROFILE_OK source=normal_backup app=$name1 package=$name2"
			else
				_speed_debug_log "APPDETAILS_CANONICAL_PROFILE_FAIL source=normal_backup app=$name1 package=$name2"
			fi
			# echo_log 依賴上一條命令退出碼；不能放在 [[ $_missing = 1 ]] && echoRgb 後面，
			# 否則 app_state 已成功寫入但 _missing=0 時會被誤報失敗。
			echo_log "備份統一AppState快照"
			[[ $_missing = 1 ]] && echoRgb "寫入統一AppState快照" "2"
			_mark_changed
			return 0
		fi
		result=1
		_speed_debug_log "APPSTATE_BACKUP_JQ_UPDATE_FAILED package=$name2 app_details=$app_details"
		return 1
	fi
	return 0
}

# 每個 app metadata 只寫一次 canonical app_state；不再拆成 permissions/AppOps/特殊存取/電池/SSAID 多份欄位。
Backup_metadata_once() {
	local _md_vn="_md_${name2//[!a-zA-Z0-9]/_}" _md_done
	eval "_md_done=\${$_md_vn:-0}"
	[[ $_md_done = 1 ]] && return 0
	[[ -f $app_details ]] || return 0
	Backup_AppState || return 1
	eval "$_md_vn=1"
}

#檢測數據位置進行備份
# ============================================================
# SpeedBackup single-file section: sb_40_backup_data_restore_data.sh
# ============================================================
Backup_data() {
	data_path="$path/$1/$name2"
	MODDIR_NAME="${data_path%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	# 取舊 Size:
	# - 應用備份 ($1 = user/data/obb/user_de): 直接讀 app_details_read 預讀的變數
	# - 媒體備份 ($1 = 動態資料夾名 Download/DCIM/...): 預讀變數沒有, fallback 用 jq 即時查
	# - 其他 (thanox 等): 同 fallback
	Size=""
	case $1 in
	user|data|obb|user_de|media)
		eval "Size=\"\$SIZE_$1\""
		;;
	*)
		[[ -f $app_details ]] && Size="$(jq -r --arg entry "$1" 'try (.[$entry].Size // "") catch ""' "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		;;
	esac
	[[ -z $Size ]] && Size=""
	case $1 in
	user) data_path="$path2/$name2" ;;
	user_de) data_path="$path3/$name2" ;;
	data|obb|media) ;;
	*)
		data_path="$2"
		# 自訂資料夾固定用 tar 打包 (不透過暫改全域 Compression_method 再復原這種做法,
		# 改用 local override 變數, 避免備份結尾等其他環節讀到中途被污染的全域值)
		[[ $1 != thanox && $1 != hma ]] && local _comp_override=tar
		zsize=1
		zmediapath=1
		;;
	esac
	# 如果啟用遠程備份，從遠端獲取 app_details.json 進行對比
	local _remote_data_checked=0
	if [[ -n $remote_type ]]; then
		local remote_app_details="$TMPDIR/.remote_app_details_$$"
		local _remote_lookup_name
		case $1 in
		user|data|obb|user_de|media|thanox|hma) _remote_lookup_name="$name1" ;;
		# 自訂資料夾 (如 Download/DCIM): 所有資料夾共用同一份 Media/app_details.json,
		# 不是各自獨立的 "$1/app_details.json" — 查詢路徑必須固定用 "Media"
		*) _remote_lookup_name="Media" ;;
		esac
		local remote_rel="${_remote_lookup_name}/app_details.json"
		local _remote_appdetails_rc=0
		_get_remote_appdetails "$_remote_lookup_name" "$remote_app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_remote_appdetails_rc=$?
		if [[ $_remote_appdetails_rc != 0 && $_remote_appdetails_rc != 2 ]]; then
			# 重試一次, 避免單次網路抖動導致整段增量比對失效。
			# rc=2 代表預掃已確認遠端不存在，不能當錯誤重試/刷診斷。
			sleep 1
			_get_remote_appdetails "$_remote_lookup_name" "$remote_app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			_remote_appdetails_rc=$?
		fi
		if [[ -s $remote_app_details ]]; then
			{
				# 從遠端 app_details 讀取 Size
				local remote_size
				remote_size=$(jq -r --arg entry "$1" 'try (.[$entry].Size // "") catch ""' "$remote_app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})
				[[ $_INCREMENTAL_DEBUG = 1 ]] && _speed_debug_log "REMOTE_APPDETAILS_SIZE query=$_remote_lookup_name entry=$1 json_bytes=$(wc -c < "$remote_app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) remote_size=$remote_size"
				# 如果遠端 Size 與當前一致，跳過備份
				if [[ -n $remote_size && $remote_size != "null" ]]; then
					_remote_data_checked=1
					local current_size
					_dir_size "$name2" "$1" "$data_path"; current_size="$_DIR_SIZE_RET"
					# 本地或遠端必須已有該 tar 才可跳過，否則全新備份會漏掉。
					# v24.20.14-7.13：非流式 remote_keep_local=0 會刪除本地 tar，
					# 若遠端 app_details Size 與目前一致且遠端 tar 存在，應直接跳過，不重壓/重傳。
					local _local_data_exists=0
					ls "$Backup_folder/$1.tar"* >/dev/null 2>&1 && _local_data_exists=1
					if [[ $remote_stream != 1 && -n $remote_type && -f $TMPDIR/.remote_files ]]; then
						local _remote_data_rel_a _remote_data_rel_b
						case $1 in
						user|data|obb|user_de|media|thanox|hma)
							_remote_data_rel_a="$name1/$1.tar.zst"; _remote_data_rel_b="$name1/$1.tar" ;;
						*)
							_remote_data_rel_a="Media/$1.tar.zst"; _remote_data_rel_b="Media/$1.tar" ;;
						esac
						if awk -v a="$_remote_data_rel_a" -v b="$_remote_data_rel_b" '$0==a||$0==b{f=1;exit} END{exit !f}' "$TMPDIR/.remote_files" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
							_local_data_exists=1
							_speed_debug_log "REMOTE_DATA_EXISTS app=$name1 entry=$1 source=remote_files"
						fi
					fi
					# 流式模式: 遠端 Size 一致即可跳過 (不需本機 tar)
					[[ $remote_stream = 1 ]] && _local_data_exists=1
					if [[ "$remote_size" = "$current_size" && $_local_data_exists = 1 ]]; then
						echoRgb "$1數據無變化(遠端備份無變化) 跳過備份" "2"
						rm -f "$remote_app_details"
						return 0
					fi
				fi
			}
		else
			if [[ $_INCREMENTAL_DEBUG = 1 ]]; then
				if [[ $_remote_appdetails_rc = 2 ]]; then
					_speed_debug_log "REMOTE_APPDETAILS_MISSING query=$_remote_lookup_name rel=$remote_rel known_missing=1"
				else
					echoRgb "[診斷] 查詢=$_remote_lookup_name _get_remote_appdetails失敗(重試後仍下載失敗 rc=$_remote_appdetails_rc)" "0" >&2
				fi
			fi
		fi
		rm -f "$remote_app_details"
	fi
	if [[ -d $data_path ]]; then
		unset Filesize ssaid Get_Permissions result Permissions
		_dir_size "$name2" "$1" "$data_path"; Filesize="$_DIR_SIZE_RET"
		# ssaid/permissions 只要是 user 類型就無條件執行 (不依賴 size 變化)
		case $1 in
		user)
			Backup_metadata_once
			;;
		esac
		# 太小不備份是使用者設定語義：不能把 0 bytes / <1KB 寫成正常 payload Size，
		# 否則 app_details 會看起來像「已有 user_de/data 備份」，但遠端實際沒有 tar。
		# 這裡只做早期 skip，避免遠端缺 Size 時每輪進入備份、kill_app、partition_info，
		# 但不更新 payload entry、不標 changed_apps、不觸發上傳 app_details。
		if [[ -n $Filesize && ${#Filesize} -lt 4 ]]; then
			local _small_size_text
			_small_size_text="$(size "${Filesize:-0}")"
			echoRgb "$1數據 $_small_size_text太小，依設定不備份" "2"
			_speed_debug_log "DATA_SMALL_SKIP_NO_RECORD app=$name1 package=$name2 entry=$1 size=${Filesize:-0}"
			result=0
			return 0
		fi
		[[ $Filesize != "" ]] && {
		# 遠端缺檔但本地 Size 無變化且本地 tar 已存在: 不重壓, 直接標記上傳現有本地檔
		local _local_data_exists2=0
		_archive_exists "$Backup_folder/$1" && _local_data_exists2=1
		# 流式模式: 忽略本機殘留 tar, 強制重新壓縮流式上傳
		stream_enabled && _local_data_exists2=0
		if ! stream_enabled && remote_enabled && [[ $_remote_data_checked = 0 && $Size = $Filesize && $_local_data_exists2 = 1 ]]; then
			backup_has_changes=1
			case $1 in user|data|obb|user_de|media) _mark_changed ;; esac
			echoRgb "$1數據無變化 遠端缺檔: 直接上傳本地備份(免重壓)" "2"
			return 0
		fi
		# 遠端已啟用但無備份時，即使本地 Size 無變化也應上傳到遠端
		local _force_data_backup=0
		# 遠端已啟用時，匹配的情況已在上面 return 0，走到這裡代表遠端要嘛沒有 Size 要嘛不匹配，都應備份
		remote_enabled && _force_data_backup=1
		# v24.20.14-7.66-14：本地模式不能只依賴殘留 app_details.json 的 Size 判斷跳過。
		# remote_keep_local=0 上傳成功後可能刪除 data/user tar，但舊 JSON 仍殘留；
		# 若 Size 一致但本機 tar 已不存在，必須補備份一次，避免本地備份目錄只有 JSON 沒有資料包。
		if ! remote_enabled && [[ $Size = $Filesize && $_local_data_exists2 != 1 ]]; then
			_force_data_backup=1
			echoRgb "$1數據無變化但本機無備份檔, 補備份一次" "2"
		fi
		if [[ $Size != $Filesize ]] || [[ $_force_data_backup = 1 ]]; then
			case $1 in
			user)
				# 從預掃的 pkg→uid map 查 uid (省去 fork pm + awk)
				local _uid
				eval "_uid=\${_pu_${name2//[!a-zA-Z0-9]/_}}"
				if [[ -n $_uid ]] && [[ $(su "$_uid" -c keystore_cli_v2 list 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | wc -l) -ge 2 ]]; then
					echoRgb "$name1包含keystore 恢復可能閃退" "0"
					jq_inplace "$app_details" --arg entry "$name1" '.[$entry].keystore |= "true"'
				else
					jq_inplace "$app_details" --arg entry "$name1" '.[$entry].keystore |= "false"'
				fi ;;
			esac
			#停止應用
			case $1 in
			user|data|obb|user_de) kill_app ;;
			esac
			_archive_cleanup "$Backup_folder/$1"
			partition_info "$Backup" "$1"
			if [[ $Skip != 1 ]]; then
				echoRgb "備份$1數據"
				# 判斷是否超過 1KB (太小的數據不值得備份, 可能是空目錄)
				# 注意: Android mksh 在 32-bit 環境下 [[ $a -gt N ]] 對超過 ~2GB 的數值會溢位
				# 改用字串長度判斷: bytes 數值字串長度 >= 4 就是 >= 1000 bytes (約 1KB)
				if [[ ${#Filesize} -ge 4 ]]; then
					Start_backup="true"
				else
					Start_backup="false"
				fi
				if [[ $Start_backup = true ]]; then
					_backup_data_archive_stage "$1" "$data_path" "$Backup_folder/$1"
				else
					echoRgb "$1數據 $Filesize2太小" "0" && result=1
				fi
				if [[ $result = 0 ]]; then
					_backup_stage_validate_and_ratio "$1" "$Backup_folder/$1" "$Filesize"
					if [[ $result = 0 ]]; then
								_backup_data_stage_record_success "$1" "$2" "$Filesize"
					else
						rm -rf "$Backup_folder/$1".tar.*
					fi
				fi
			fi
		else
			[[ $Size != "" ]] && echoRgb "$1數據無發生變化 跳過備份" "2"
		fi
		}
	else
		[[ -f $data_path ]] && echoRgb "$1是一個文件 不支持備份" "0"
	fi
}
# 恢復 app 的 data 資料 (解壓 tar.zst 到 /data/data/<pkg>/)
# 處理 selinux context、uid 綁定
_restore_mount_fstype() {
	local _path="$1"
	[[ -n $_path && -r /proc/mounts ]] || return 1
	awk -v p="$_path" '
		BEGIN { best_len = -1; best_type = "" }
		{
			m = $2; t = $3
			if (p == m || index(p, m "/") == 1) {
				l = length(m)
				if (l > best_len) { best_len = l; best_type = t }
			}
		}
		END { if (best_type != "") print best_type }
	' /proc/mounts 2>/dev/null
}

_restore_path_available_bytes_one() {
	local _path="$1" _df _kb
	[[ -z $_path ]] && { echo 0; return 1; }
	[[ -d $_path ]] || _path="${_path%/*}"
	[[ -d $_path ]] || { echo 0; return 1; }
	_df="$(df -k "$_path" 2>/dev/null | tail -n 1)"
	_kb="$(printf '%s\n' "$_df" | awk '{print $4; exit}' 2>/dev/null)"
	case $_kb in ''|*[!0-9]*) echo 0; return 1 ;; esac
	echo $((_kb * 1024))
	return 0
}

_restore_media_target_candidates() {
	local _target="$1" _rel
	[[ -n $_target ]] || return 0
	echo "$_target"
	case "$_target" in
	/storage/emulated/0/*)
		_rel="${_target#/storage/emulated/0/}"
		echo "/data/media/0/$_rel"
		echo "/mnt/pass_through/0/emulated/0/$_rel"
		;;
	/sdcard/*)
		_rel="${_target#/sdcard/}"
		echo "/data/media/0/$_rel"
		echo "/mnt/pass_through/0/emulated/0/$_rel"
		;;
	/data/media/0/*)
		_rel="${_target#/data/media/0/}"
		echo "/storage/emulated/0/$_rel"
		echo "/mnt/pass_through/0/emulated/0/$_rel"
		;;
	/mnt/pass_through/0/emulated/0/*)
		_rel="${_target#/mnt/pass_through/0/emulated/0/}"
		echo "/data/media/0/$_rel"
		echo "/storage/emulated/0/$_rel"
		;;
	esac
}

_restore_media_space_precheck() {
	local _target="$1" _need="$2" _avail _margin _need_with_margin _cand _c_avail _c_type _picked _tmpfs_seen=0
	case $_need in ''|*[!0-9]*|0) return 0 ;; esac
	[[ -n $_target ]] || return 0

	_avail=0
	while read -r _cand; do
		[[ -n $_cand ]] || continue
		[[ -d $_cand ]] || _cand="${_cand%/*}"
		[[ -d $_cand ]] || continue
		_c_avail="$(_restore_path_available_bytes_one "$_cand")"
		case $_c_avail in ''|*[!0-9]*|0) continue ;; esac
		_c_type="$(_restore_mount_fstype "$_cand")"
		{
			echo "MEDIA_SPACE_CANDIDATE file=$FILE_NAME path=$_cand fstype=$_c_type avail=$_c_avail need=$_need stream=${_RESTORE_STREAM:-0} src=${_STREAM_SRC:-$tar_path}"
		} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/media_space_precheck.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		# Android 可能把 /data/media/0/DCIM 或 Pictures 額外 tmpfs 掛載；df /storage/emulated/0 會看到 300GB，
		# 但 tar 實際寫入會打到 tmpfs，必須優先以 tmpfs 的可用空間判斷。
		if [[ $_c_type = tmpfs ]]; then
			_tmpfs_seen=1
			if [[ $_avail -eq 0 || $_c_avail -lt $_avail ]]; then
				_avail="$_c_avail"
				_picked="$_cand"
			fi
		elif [[ $_tmpfs_seen != 1 ]]; then
			if [[ $_avail -eq 0 || $_c_avail -lt $_avail ]]; then
				_avail="$_c_avail"
				_picked="$_cand"
			fi
		fi
	done <<EOFMSPC
$(_restore_media_target_candidates "$_target")
EOFMSPC

	case $_avail in ''|*[!0-9]*|0) return 0 ;; esac
	# Media 解壓需要額外 metadata/目錄項/相簿索引餘量；至少保留 64MiB。
	_margin=$((64 * 1024 * 1024))
	_need_with_margin=$((_need + _margin))
	if [[ $_tmpfs_seen = 1 ]]; then
		echoRgb "偵測到 Media 目標路徑被 tmpfs 掛載，實際可用空間以 $_picked 為準" "2"
	fi
	if [[ $_avail -lt $_need_with_margin ]]; then
		echoRgb "Media恢復空間不足，跳過 $FILE_NAME" "0"
		echoRgb "目標路徑：$_target" "0"
		echoRgb "實際檢查：${_picked:-$_target}" "0"
		echoRgb "需要約 $(size "$_need")，可用 $(size "$_avail")，至少需額外保留 64MiB" "0"
		{
			echo "MEDIA_SPACE_SKIP file=$FILE_NAME target=$_target picked=$_picked tmpfs=$_tmpfs_seen need=$_need avail=$_avail margin=$_margin stream=${_RESTORE_STREAM:-0} src=${_STREAM_SRC:-$tar_path}"
		} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/media_space_precheck.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 1
	fi
	return 0
}

Release_data() {
	tar_path="$1"
	X="$path2/$name2"
	MODDIR_NAME="${tar_path%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	FILE_NAME="${tar_path##*/}"
	case "$FILE_NAME" in
	speed_debug_*.tar|speed_debug_*.tar.zst)
		_speed_debug_log "SKIP debug archive in app restore dir: $tar_path"
		return 0 ;;
	esac
	# 只去 .tar / .tar.zst 後綴 (不可用 %%.* , 否則 service.d.tar 會被砍成 service)
	FILE_NAME2="${FILE_NAME%.zst}"
	FILE_NAME2="${FILE_NAME2%.tar}"
	case ${FILE_NAME##*.} in
	zst | tar)
		unset FILE_PATH Size Selinux_state
		# 一次 jq 抓 Size / keystore / path (取代 3 個獨立 jq fork)
		release_details_read "$app_details" "$FILE_NAME2"
		Size="$REL_SIZE"
		case $FILE_NAME2 in
		user)
			if [[ -d $X ]]; then
				[[ $REL_KEYSTORE = true ]] && echoRgb "$name1存在keystore 恢復可能閃退" "0"
				FILE_PATH="$path2"
				# 合併 LS|awk|sed → 1 個 awk (省 2 fork)
				Selinux_state="$(LS "$X" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk 'NF>1 {gsub(/system_data_file/, "app_data_file"); print $1; exit}')"
			else
				echoRgb "$X不存在 無法恢復$FILE_NAME2數據" "0"
			fi ;;
		user_de)
			X="$path3/$name2"
			if [[ -d $X ]]; then
				FILE_PATH="$path3"
				Selinux_state="$(LS "$X" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk 'NF>1 {gsub(/system_data_file/, "app_data_file"); print $1; exit}')"
			else
				echoRgb "$X不存在 無法恢復$FILE_NAME2數據" "0"
			fi ;;
		data)
			FILE_PATH="$path/data"
			Selinux_state="$(LS "$FILE_PATH" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk 'NF>1 {gsub(/system_data_file/, "app_data_file"); print $1; exit}')"
			;;
		obb)
			FILE_PATH="$path/obb"
			Selinux_state="$(LS "$FILE_PATH" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk 'NF>1 {gsub(/system_data_file/, "app_data_file"); print $1; exit}')"
			;;
		media)
			FILE_PATH="$path/media"
			;;
		thanox)
			FILE_PATH="/data/system"
			find "/data/system" -maxdepth 1 -type d -name "thanos*" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _td; do
				case $_td in
					/data/system/thanos*) [[ -n $_td ]] && rm -rf "$_td" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} ;;
				esac
			done
			;;
		hma)
			FILE_PATH="/data/misc"
			find "/data/misc" -maxdepth 1 -mindepth 1 -type d -name "hide_my_applist_*" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _hd; do
				case $_hd in
					/data/misc/hide_my_applist_*) [[ -n $_hd ]] && rm -rf "$_hd" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} ;;
				esac
			done
			;;
		*)
			if [[ $A != "" ]]; then
				if [[ ${MODDIR_NAME##*/} = Media ]]; then
					FILE_PATH="$REL_PATH"
					if [[ $FILE_PATH = "" ]]; then
						echoRgb "路徑獲取失敗" "0"
					else
						echoRgb "解壓路徑↓\n -$FILE_PATH" "2"
						FILE_PATH="${FILE_PATH%/*}"
						[[ ! -d $FILE_PATH ]] && mkdir -p "$FILE_PATH"
					fi
				fi
			else
				echoRgb "$tar_path名稱似乎有誤" "0"
			fi ;;
		esac
		echoRgb "恢復$FILE_NAME2數據 釋放$(size "$Size")" "3"
		if [[ $FILE_PATH != "" ]]; then
			if [[ ${MODDIR_NAME##*/} = Media ]]; then
				_restore_media_space_precheck "$FILE_PATH" "$Size" || { result=1; echo_log "解壓縮$FILE_NAME"; return 1; }
			fi
			[[ ${MODDIR_NAME##*/} != Media ]] && rm -rf "$FILE_PATH/$name2"
			# 流式恢復: 從遠端拉 → 管道解壓 (不落地本機); _STREAM_SRC 為遠端相對路徑
			if [[ $_RESTORE_STREAM = 1 && -n $_STREAM_SRC ]]; then
				case ${FILE_NAME##*.} in
				zst) _stream_download "$_STREAM_SRC" | zstd -d 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | tar --checkpoint-action="ttyout=%T\r" -xmpf - -C "$FILE_PATH" ;;
				tar) [[ ${MODDIR_NAME##*/} = Media ]] && _stream_download "$_STREAM_SRC" | tar --checkpoint-action="ttyout=%T\r" -axf - -C "$FILE_PATH" || _stream_download "$_STREAM_SRC" | tar --checkpoint-action="ttyout=%T\r" -amxf - -C "$FILE_PATH" ;;
				esac
				result=$?
			else
				local _extract_raw_log _extract_raw_start _extract_size
				_extract_size="$(_local_file_size_debug "$tar_path")"
				_extract_raw_start="$(date +%s%3N 2>/dev/null)"; case $_extract_raw_start in ''|*[!0-9]*) _extract_raw_start="$(date +%s 2>/dev/null)000" ;; esac
				_extract_raw_log="$(_local_raw_debug_begin extract "kind=data file=$tar_path name=$FILE_NAME dest=$FILE_PATH ext=${FILE_NAME##*.} size=$_extract_size")"
				case ${FILE_NAME##*.} in
				zst) tar --checkpoint-action="ttyout=%T\r" -I zstd -xmpf "$tar_path" -C "$FILE_PATH" 2>>"$_extract_raw_log" ;;
				tar) [[ ${MODDIR_NAME##*/} = Media ]] && tar --checkpoint-action="ttyout=%T\r" -axf "$tar_path" -C "$FILE_PATH" 2>>"$_extract_raw_log" || tar --checkpoint-action="ttyout=%T\r" -amxf "$tar_path" -C "$FILE_PATH" 2>>"$_extract_raw_log" ;;
				esac
				result=$?
				_local_raw_debug_end extract "$_extract_raw_log" "$result" "$_extract_raw_start" "kind=data dest=$FILE_PATH"
			fi
		else
			Set_back_1
		fi
		echo_log "解壓縮$FILE_NAME"
		if [[ $result = 0 ]]; then
			case $FILE_NAME2 in
			user|data|obb|user_de)
				# 用 helper 查 uid (取代 3 層 fallback 散落)
				G="$(get_app_uid "$name2")"
				if [[ $G != "" ]]; then
					if [[ -d $X ]]; then
						case ${#G} in
						5)
							if [[ $user = 0 ]]; then
								uid="$G:$G"
							else
								uid="$user$G:$user$G"
							fi ;;
						6|7|8|9|10)
							uid="$G:$G" ;;
						esac
						case $FILE_NAME2 in
						user|user_de)
							case $FILE_NAME2 in
							user) [[ $X = $path2/$name2 ]] && Validation_settings="true" || Validation_settings="false" ;;
							user_de) [[ $X = $path3/$name2 ]] && Validation_settings="true" || Validation_settings="false" ;;
							esac
							if [[ $Validation_settings = true ]]; then
								chown -hR "$uid" "$X/"
								echo_log "設置用戶組$uid"
								chcon -hR "$Selinux_state" "$X/" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
								echo_log "selinux上下文設置"
							else
								echoRgb "路徑:$X出現錯誤"
							fi ;;
						data|obb)
							chown -hR "$uid" "$FILE_PATH/$name2/"
							echo_log "設置用戶組$uid"
							chcon -hR "$Selinux_state" "$FILE_PATH/$name2/" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
							echo_log "selinux上下文設置" ;;
						esac
					else
						echoRgb "$FILE_NAME2路徑$X不存在" "0"
					fi
				else
					echoRgb "uid獲取失敗" "0"
				fi
				;;
			thanox)
				restorecon -RF "$(find "/data/system" -name "thanos"* -maxdepth 1 -type d 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})/" 2>>${SPEED_DEBUG_CMD_LOG:-/dev/null}
				echo_log "selinux上下文設置" && echoRgb "警告 thanox配置恢復後務必重啟\n -否則不生效" "0"
				;;
			hma)
				find "/data/misc" -maxdepth 1 -mindepth 1 -type d -name "hide_my_applist_*" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _hd; do
					case $_hd in
					/data/misc/hide_my_applist_*) restorecon -RF "$_hd" 2>>${SPEED_DEBUG_CMD_LOG:-/dev/null} ;;
					esac
				done
				echo_log "selinux上下文設置" && echoRgb "警告 HMA-OSS配置恢復後建議重啟\n -否則 Hide My Applist 設定可能不立即生效" "0"
				;;
			esac
		fi
		;;
	*)
		echoRgb "$FILE_NAME 壓縮包不支持解壓縮" "0"
		Set_back_1
		;;
	esac
	cleanup_tmpdir_contents || exit 1
}
# 取得備份記錄的 installer；若 .installer 缺失，從 install_diagnostics.installer/installing fallback
_restore_backup_installer_value() {
	local _json="$1" _v=""
	[[ -s $_json ]] || return 0
	_v="$(jq -r 'try (([.[] | objects | select(.app_state != null).app_state | (.installer // .package.installer // .installDiagnostics.installing // "")] | .[0]) // "") catch ""' "$_json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	[[ -n $_v && $_v != null ]] && { echo "$_v"; return; }
	_v="$(jq -r 'try (([.[] | objects | select(.installer != null).installer] | .[0]) // "") catch ""' "$_json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	case $_v in null|NULL) _v="" ;; esac
	if [[ -z $_v ]]; then
		_v="$(jq -r 'try (([.[] | objects | select(.install_diagnostics != null).install_diagnostics | (.installer // .installing // "")] | .[0]) // "") catch ""' "$_json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	fi
	echo "$_v"
}

# 安裝來源上下文解析：只使用備份記錄且目前系統真的存在的 installer。
# 流程：讀備份 installer → 檢查目前 user 是否存在 → 取得 UID → 取得可用 data dir → 安裝時才套用 -i/UID context。
# 目的：避免無腦使用 com.android.vending 或其他已不存在的來源，造成 pm -i 無效、install-create 失敗或來源欄位污染。
_restore_pkg_exists_for_user() {
	local _pkg="$1"
	[[ -n $_pkg ]] || return 1
	pm path --user "$user" "$_pkg" >/dev/null 2>&1 && return 0
	pm list packages --user "$user" "$_pkg" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -q "^package:${_pkg}$"
}

_restore_pkg_uid_for_user() {
	local _pkg="$1" _uid=""
	[[ -n $_pkg ]] || return 1
	_uid="$(pm list packages -U --user "$user" "$_pkg" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk -F'uid:' -v p="$_pkg" '$0=="package:"p || index($0,"package:"p" ")==1 {print $2; exit}')"
	if [[ -z $_uid ]]; then
		_uid="$(dex_hiddenapi_raw getPackageUid "$USER_ID" "$_pkg" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '/^[0-9]+$/ {print; exit}')"
	fi
	case $_uid in ''|*[!0-9]*) return 1 ;; esac
	echo "$_uid"
}

_restore_pkg_data_dir_for_user() {
	local _pkg="$1" _dir
	for _dir in "/data/user/${USER_ID}/$_pkg" "/data/user_de/${USER_ID}/$_pkg"; do
		[[ -d $_dir ]] && { echo "$_dir"; return 0; }
	done
	return 1
}

_restore_select_installer_context() {
	local _target_pkg="$1" _installer="$2" _uid _data_dir
	RESTORE_INSTALLER_PKG=""
	RESTORE_INSTALLER_UID=""
	RESTORE_INSTALLER_DATA_DIR=""
	case $_installer in ''|null|NULL|clear|CLEAR|none|NONE)
		_restore_log_install_method "$_target_pkg" "installer_context_skip" "reason=empty backupInstaller=${_installer:-null}"
		return 1
		;;
	esac
	# 只有備份記錄的原始安裝來源是 Google Play 商店本身才做安裝來源偽裝 (installer/initiating/UID hybrid)。
	# 非 Play 來源 (其他應用商店/側載) 偽裝成該商店會有假安裝失敗風險, 直接跳過偽裝、走原生 pm 正常安裝。
	if [[ $_installer != com.android.vending ]]; then
		echoRgb "備份安裝來源 $_installer 非 Google Play, 不偽裝安裝來源, 使用原生 pm 安裝" "2"
		_restore_log_install_method "$_target_pkg" "installer_context_skip" "reason=non_play_installer installer=$_installer"
		return 1
	fi
	if ! _restore_pkg_exists_for_user "$_installer"; then
		echoRgb "備份安裝來源 $_installer 目前不存在，跳過安裝來源偽裝" "2"
		_restore_log_install_method "$_target_pkg" "installer_context_skip" "reason=package_missing installer=$_installer"
		return 1
	fi
	_uid="$(_restore_pkg_uid_for_user "$_installer")"
	case $_uid in ''|*[!0-9]*)
		echoRgb "備份安裝來源 $_installer 無法取得 UID，跳過安裝來源偽裝" "2"
		_restore_log_install_method "$_target_pkg" "installer_context_skip" "reason=uid_missing installer=$_installer"
		return 1
		;;
	esac
	_data_dir="$(_restore_pkg_data_dir_for_user "$_installer")"
	if [[ -z $_data_dir ]]; then
		# pm -i 仍可使用，但 UID hybrid 需要一個穩定 app data dir 給 uidexec。
		_restore_log_install_method "$_target_pkg" "installer_context_pm_only" "installer=$_installer uid=$_uid reason=data_dir_missing"
	else
		_restore_log_install_method "$_target_pkg" "installer_context_ok" "installer=$_installer uid=$_uid dataDir=$_data_dir"
	fi
	RESTORE_INSTALLER_PKG="$_installer"
	RESTORE_INSTALLER_UID="$_uid"
	RESTORE_INSTALLER_DATA_DIR="$_data_dir"
	return 0
}

_restore_bool_enabled() {
	case "$1" in 1|true|True|TRUE|yes|YES|on|ON) return 0 ;; *) return 1 ;; esac
}

_restore_play_uid() {
	local _uid=""
	_uid="$(pm list packages -U --user "$user" com.android.vending 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk -F'uid:' '/com\.android\.vending/ {print $2; exit}')"
	if [[ -z $_uid ]]; then
		_uid="$(dex_hiddenapi_raw getPackageUid "$USER_ID" com.android.vending 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '/^[0-9]+$/ {print; exit}')"
	fi
	echo "$_uid"
}

_restore_has_play_store() {
	local _uid="" _path_ok=0 _disabled=0
	pm path --user "$user" com.android.vending >/dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && _path_ok=1
	pm list packages -d --user "$user" com.android.vending 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -q '^package:com.android.vending$' && _disabled=1
	_uid="$(_restore_play_uid)"
	case $_uid in ''|*[!0-9]*)
		_speed_debug_log "PLAY_STORE_CHECK result=fail reason=uid_missing path_ok=$_path_ok disabled=$_disabled"
		return 1
		;;
	esac
	if [[ $_path_ok != 1 ]]; then
		_speed_debug_log "PLAY_STORE_CHECK result=fail reason=package_path_missing uid=$_uid disabled=$_disabled"
		return 1
	fi
	if [[ $_disabled = 1 ]]; then
		_speed_debug_log "PLAY_STORE_CHECK result=fail reason=package_disabled uid=$_uid"
		return 1
	fi
	_speed_debug_log "PLAY_STORE_CHECK result=ok uid=$_uid path_ok=$_path_ok disabled=$_disabled"
	return 0
}

_restore_line_requests_play_session() {
	local _line="$1"
	_line="$(printf '%s\n' "$_line" | sed 's/^[ 	]*//')"
	case "$_line" in
	\#*|＃*|'') return 1 ;;
	!play[[:space:]]*|！play[[:space:]]*|![[:space:]]*|！[[:space:]]*|!*) return 0 ;;
	esac
	return 1
}

_restore_list_has_play_markers() {
	local _list="$1" _line=""
	[[ -s $_list ]] || return 1
	while IFS= read -r _line; do
		_restore_line_requests_play_session "$_line" && return 0
	done < "$_list"
	return 1
}

_restore_play_work_root() {
	# 使用備份目錄下的專用子目錄，避免寫入或污染 Google Play 私有資料目錄。
	# 279 起 APK bytes 由 root pm install-write 寫入；此處只給 Play UID daemon 載入 classes.dex。
	echo "$filepath/.speedbackup_play_session/u$user"
}

_restore_prepare_play_dex() {
	local _play_uid="$1" _root _art_dir _dex_dst
	[[ -n $_play_uid && -f $tools_path/classes.dex ]] || return 1
	_root="$(_restore_play_work_root)"
	_art_dir="$_root/art"
	_dex_dst="$_art_dir/classes.dex"
	mkdir -p "$_art_dir/tmp" "$_art_dir/dalvik-cache" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	chown "$_play_uid:$_play_uid" "$_root" "$_art_dir" "$_art_dir/tmp" "$_art_dir/dalvik-cache" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	chmod 700 "$_root" "$_art_dir" "$_art_dir/tmp" "$_art_dir/dalvik-cache" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	local _src_sha _dst_sha _copy_reason="missing"
	if [[ -f $_dex_dst ]]; then
		if command -v cmp >/dev/null 2>&1 && cmp -s "$tools_path/classes.dex" "$_dex_dst" 2>/dev/null; then
			_speed_debug_log "PLAY_DEX_REUSE method=cmp dst=$_dex_dst"
		else
			_src_sha="$(sha256sum "$tools_path/classes.dex" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{print $1}')"
			_dst_sha="$(sha256sum "$_dex_dst" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{print $1}')"
			if [[ -n $_src_sha && $_src_sha = $_dst_sha ]]; then
				_speed_debug_log "PLAY_DEX_REUSE method=sha256 dst=$_dex_dst sha=$_src_sha"
			else
				_copy_reason="changed"
				cp -f "$tools_path/classes.dex" "$_dex_dst" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
				_speed_debug_log "PLAY_DEX_COPY reason=$_copy_reason dst=$_dex_dst src_sha=${_src_sha:-unknown} dst_sha=${_dst_sha:-missing}"
			fi
		fi
	else
		cp -f "$tools_path/classes.dex" "$_dex_dst" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
		_speed_debug_log "PLAY_DEX_COPY reason=$_copy_reason dst=$_dex_dst"
	fi
	chown "$_play_uid:$_play_uid" "$_dex_dst" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# Android 14+/16 ART 禁止載入對呼叫 UID 可寫的 dex；必須只讀
	chmod 400 "$_dex_dst" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	restorecon -R "$_root" 2>>${SPEED_DEBUG_CMD_LOG:-/dev/null}
	echo "$_dex_dst"
}

_restore_apk_stage_root() {
	echo "$TMPDIR/.speedbackup_apk_stage"
}

_restore_apk_stage_dir() {
	local _pkg="$1"
	[[ -n $_pkg ]] || _pkg="unknown"
	printf '%s/%s\n' "$(_restore_apk_stage_root)" "${_pkg//[!a-zA-Z0-9_.-]/_}"
}

_restore_prepare_apk_stage_dir() {
	local _pkg="$1" _root _work
	case "$TMPDIR" in
	"/data/local/tmp") ;;
	*) echoRgb "TMPDIR異常，拒絕建立 APK stage: $TMPDIR" "0"; return 1 ;;
	esac
	_root="$(_restore_apk_stage_root)"
	_work="$(_restore_apk_stage_dir "$_pkg")"
	rm -rf "$_work" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	mkdir -p "$_work" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	chmod 711 "$_root" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	chmod 700 "$_work" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	restorecon -R "$_root" 2>>${SPEED_DEBUG_CMD_LOG:-/dev/null}
	echo "$_work"
}

_restore_apk_work_root() {
	echo "$TMPDIR/.speedbackup_apk_work"
}

_restore_clear_apk_work_dir() {
	local _work="$(_restore_apk_work_root)"
	case "$_work" in
	"/data/local/tmp/.speedbackup_apk_work") ;;
	*) echoRgb "APK work 路徑異常，拒絕清理: $_work" "0"; return 1 ;;
	esac
	[[ -d $_work ]] || return 0
	find "$_work" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_restore_prepare_apk_work_dir() {
	local _pkg="$1" _work
	case "$TMPDIR" in
	"/data/local/tmp") ;;
	*) echoRgb "TMPDIR異常，拒絕建立 APK work: $TMPDIR" "0"; return 1 ;;
	esac
	_work="$(_restore_apk_work_root)"
	mkdir -p "$_work" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	chmod 700 "$_work" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_restore_clear_apk_work_dir || return 1
	echo "$_work"
}

_restore_cleanup_play_session() {
	local _pkg="$1" _root _art_dir _install_root _work
	[[ ${restore_play_install_keep_workdir:-0} = 1 ]] && return 0
	if [[ ${_RESTORE_DEFER_PLAY_CLEANUP:-0} = 1 ]]; then
		[[ -n $_pkg ]] && _restore_log_install_stage "$_pkg" "CLEANUP_SKIP" "reason=deferred_for_fallback"
		return 0
	fi
	[[ -z $_pkg ]] && return 0
	_root="$(_restore_play_work_root)"
	_art_dir="$_root/art"
	_install_root="$_root/install"
	_work="$_install_root/$_pkg"
	# 只清本腳本建立的集中二進制目錄專用工作區，絕不清 Play 商店私有資料。
	# 294: 若 Install daemon 仍可 probe，保留 art/classes.dex 與 root，讓批量 !AppName 共用同一顆
	# Play UID app_process；只清每個 App 的 APK stage / install work，避免佔空間。
	if _install_daemon_probe; then
		rm -rf "$_work" "$(_restore_apk_stage_dir "$_pkg")" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_restore_log_install_stage "$_pkg" "CLEANUP_KEEP_DAEMON" "apk_stage=removed art=kept socket=$_INSTALL_DAEMON_SOCKET"
		[ -d "$_install_root" ] && rmdir "$_install_root" 2>/dev/null || true
		return 0
	fi
	rm -rf "$_art_dir" "$_work" "$(_restore_apk_stage_dir "$_pkg")" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_restore_log_install_stage "$_pkg" "CLEANUP_OK" "workdir=removed"
	[ -d "$_install_root" ] && rmdir "$_install_root" 2>/dev/null || true
	[ -d "$_root" ] && rmdir "$_root" 2>/dev/null || true
	[ -d "$filepath/.speedbackup_play_session" ] && rmdir "$filepath/.speedbackup_play_session" 2>/dev/null || true
}

_restore_now_ms() {
	local _ms
	_ms="$(date +%s%3N 2>/dev/null)"
	case $_ms in ''|*[!0-9]*) _ms="$(date +%s 2>/dev/null)000" ;; esac
	case $_ms in ''|*[!0-9]*) _ms=0 ;; esac
	printf '%s' "$_ms"
}

_restore_log_install_stage() {
	local _pkg="$1" _stage="$2" _detail="$3"
	[[ -z $_pkg ]] && _pkg="unknown"
	[[ -z $_stage ]] && _stage="unknown"
	_restore_log_install_method "$_pkg" "INSTALL_STAGE_${_stage}" "$_detail"
}

_restore_log_install_timing() {
	local _pkg="$1" _name="$2" _start="$3" _end _elapsed
	[[ -z $_pkg ]] && _pkg="unknown"
	[[ -z $_name ]] && _name="unknown"
	_end="$(_restore_now_ms)"
	case $_start in ''|*[!0-9]*) _elapsed="unknown" ;; *) _elapsed=$((_end-_start)) ;; esac
	_restore_log_install_method "$_pkg" "INSTALL_TIMING" "${_name}Ms=$_elapsed"
}

_restore_count_stage_apks() {
	local _dir="$1" _n=0 _a
	for _a in "$_dir"/*.apk; do [[ -f $_a ]] && _n=$((_n+1)); done
	echo "$_n"
}

_restore_sum_stage_apk_bytes() {
	local _dir="$1" _sum=0 _a _sz
	for _a in "$_dir"/*.apk; do
		[[ -f $_a ]] || continue
		_sz=$(stat -c '%s' "$_a" 2>/dev/null || echo 0)
		case $_sz in *[!0-9]*|'') _sz=0 ;; esac
		_sum=$((_sum+_sz))
	done
	echo "$_sum"
}

_restore_log_install_method() {
	local _pkg="$1" _method="$2" _detail="$3" _line _log
	[[ -z $_pkg ]] && _pkg="unknown"
	[[ -z $_method ]] && _method="unknown"
	_line="INSTALL_METHOD $_pkg $_method"
	[[ -n $_detail ]] && _line="$_line $_detail"
	# INSTALL_METHOD 是機器判讀/除錯用資料，不直接顯示到終端，避免一般用戶看到 uid/uidexec/flags 等技術細節。
	echo "$_line" >> "$TMPDIR/.install_method_log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_log="${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/install_method.log"
	mkdir -p "${_log%/*}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $_line" >> "$_log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# v24.20.14-7.46 installer source strategy report：抽出使用者可讀的策略摘要，完整原始資料仍留 install_method.log。
# v24.20.14-7.47 mksh here-string cleanup：移除 <<< / done<<<，避免 Android sh 解析 unexpected redirection。
	case "$_method" in
		installer_context_ok|installer_context_pm_only|installer_context_skip|hybrid_installer_pm|hybrid_installer_pm_success|hybrid_installer_pm_failed|hybrid_installer_pm_source_mismatch|dex_play_session|dex_play_session_success|dex_play_session_failed|pm_install|pm_install_create|pm_fallback_after_*|play_session_requested_by_appList)
			local _slog="${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/install_strategy.log"
			mkdir -p "${_slog%/*}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] $_pkg $_method ${_detail:-}" >> "$_slog" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			;;
	esac
}

_restore_save_play_session_raw_log() {
	local _pkg="$1" _file="$2" _log
	[[ -s $_file ]] || return 0
	_log="${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/install_session.log"
	mkdir -p "${_log%/*}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	{
		echo "===== [$(date '+%Y-%m-%d %H:%M:%S')] $_pkg ====="
		cat "$_file"
		echo
	} >> "$_log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_restore_save_play_session_raw_log_from_line() {
	local _pkg="$1" _file="$2" _start="${3:-0}" _tmp
	[[ -s $_file ]] || return 0
	case $_start in ''|*[!0-9]*) _start=0 ;; esac
	_tmp="$(_webdav_tmp_path play_session_log_delta)"
	awk -v s="$_start" 'NR>s {print}' "$_file" > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_restore_save_play_session_raw_log "$_pkg" "$_tmp"
	rm -f "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_restore_print_play_session_output() {
	local _file="$1" _mode="${restore_play_install_log_mode:-summary}"
	[[ -s $_file ]] || return 0
	case $_mode in
		raw|RAW|full|FULL)
			cat "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _l; do [[ -n $_l ]] && echoRgb "$_l" "2"; done
			;;
		quiet|QUIET|0|off|OFF)
			return 0
			;;
		*)
			cat "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -E 'INSTALL_SESSION (failed|failureCode|failureHint|packageNotFoundAfterWait|sourceVerifyFailed)' | while read -r _l; do
				[[ -n $_l ]] && echoRgb "$_l" "2"
			done
			;;
	esac
}

_restore_get_install_diag_value() {
	local _file="$1" _pkg="$2" _key="$3"
	awk -v p="$_pkg" -v k="$_key" '$1==p && $2=="INSTALL_DIAG" && $3==k {print $4; exit}' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_restore_verify_play_install_source_from_file() {
	local _pkg="$1" _diag="$2" _installer _installing _initiating _source
	[[ ${restore_play_install_verify_source:-1} = 1 ]] || return 0
	[[ -n $_pkg && -s $_diag ]] || return 1
	_installer="$(_restore_get_install_diag_value "$_diag" "$_pkg" installer)"
	_installing="$(_restore_get_install_diag_value "$_diag" "$_pkg" installing)"
	_initiating="$(_restore_get_install_diag_value "$_diag" "$_pkg" initiating)"
	_source="$(_restore_get_install_diag_value "$_diag" "$_pkg" packageSourceName)"
	if [[ $_installer = com.android.vending && $_installing = com.android.vending && $_initiating = com.android.vending ]]; then
		echoRgb "Play 來源驗證通過" "1"
		return 0
	fi
	# PackageInstaller session 失敗或未回完整 INSTALL_DIAG 時，交回 getInstallSourceInfo 路徑。
	[[ -z $_installer && -z $_installing && -z $_initiating ]] && return 1
	echoRgb "⚠️ Play來源驗證未完全通過: installer=${_installer:-null} installing=${_installing:-null} initiating=${_initiating:-null} source=${_source:-null}" "0"
	return 0
}

_restore_verify_play_install_source() {
	local _pkg="$1" _diag _installer _installing _initiating _source
	[[ ${restore_play_install_verify_source:-1} = 1 ]] || return 0
	[[ -n $_pkg ]] || return 1
	_diag="$TMPDIR/.play_install_source_${_pkg//[!a-zA-Z0-9]/_}"
	local _diag_err
	_diag_err="${TMPDIR:-/data/local/tmp}/.play_install_source_stderr_${_pkg//[!a-zA-Z0-9]/_}_$$"
	dex_hiddenapi_raw getInstallSourceInfo "$USER_ID" "$_pkg" 2>"$_diag_err" | _dex_filter_human_stdout > "$_diag"
	_dex_append_nonhuman_stderr "$_diag_err"
	rm -f "$_diag_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_dex_translate_file "$_diag" "HiddenApiUtil:getInstallSourceInfo"
	# 詳細 INSTALL_DIAG 已寫入 speed_debug/install_session.log；終端只顯示通過/異常結論。
	_installer="$(_restore_get_install_diag_value "$_diag" "$_pkg" installer)"
	_installing="$(_restore_get_install_diag_value "$_diag" "$_pkg" installing)"
	_initiating="$(_restore_get_install_diag_value "$_diag" "$_pkg" initiating)"
	_source="$(_restore_get_install_diag_value "$_diag" "$_pkg" packageSourceName)"
	if [[ $_installer = com.android.vending && $_installing = com.android.vending && $_initiating = com.android.vending ]]; then
		echoRgb "Play 來源驗證通過" "1"
		rm -f "$_diag" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 0
	fi
	echoRgb "⚠️ Play來源驗證未完全通過: installer=${_installer:-null} installing=${_installing:-null} initiating=${_initiating:-null} source=${_source:-null}" "0"
	[[ ${restore_play_install_keep_workdir:-0} = 1 ]] || rm -f "$_diag" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# 安裝本身已成功，不在這裡回退 pm；pm 反而會導致 initiating=shell。
	return 0
}

_restore_play_install_options() {
	local _flags="INSTALL_REPLACE_EXISTING" _bypass="${restore_play_install_bypass_low_target:-auto}"
	_restore_bool_enabled "${restore_play_install_allow_test:-1}" && _flags="$_flags,INSTALL_ALLOW_TEST"
	_restore_bool_enabled "${restore_play_install_allow_downgrade:-0}" && _flags="$_flags,INSTALL_ALLOW_DOWNGRADE,INSTALL_REQUEST_DOWNGRADE"
	_restore_bool_enabled "${restore_play_install_grant_runtime_permissions:-0}" && _flags="$_flags,INSTALL_GRANT_RUNTIME_PERMISSIONS"
	case $_bypass in
		1|true|TRUE|yes|YES|on|ON) _flags="$_flags,INSTALL_BYPASS_LOW_TARGET_SDK_BLOCK" ;;
		auto|AUTO) [[ ${sdk:-0} -gt 33 ]] && _flags="$_flags,INSTALL_BYPASS_LOW_TARGET_SDK_BLOCK" ;;
	esac
	[[ -n ${restore_play_install_extra_flags:-} ]] && _flags="$_flags,${restore_play_install_extra_flags}"
	# 這些值預期為無空白 token；extra_flags 請用逗號分隔，不要加入空白。
	printf '%s' "--installer=com.android.vending --package-source=${restore_play_install_package_source:-store} --install-reason=${restore_play_install_reason:-user} --require-user-action=${restore_play_install_require_user_action:-not_required} --install-location=${restore_play_install_location:-auto} --install-flags=$_flags --dont-kill=${restore_play_install_dont_kill:-0} --human-log=${restore_play_install_human_log:-0}"
}

# 舊批量/預檢安裝路線已於 7.66-284 清除；!play 只保留 create=Play/write=root/commit=Play。

_restore_play_session_id_from_file() {
	local _pkg="$1" _file="$2"
	awk -v p="$_pkg" '$1==p && $2=="INSTALL_SESSION_CREATE" && $3=="sessionId" {print $4; exit}' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_restore_run_play_session_create_once() {
	local _pkg="$1" _play_uid="$2" _art_dir="$3" _dex_dst="$4" _apk_work="$5" _session_opts="$6" _out="$7" _sess_err _raw _rc _t0 _total
	_sess_err="${TMPDIR:-/data/local/tmp}/.play_install_create_stderr_${_pkg//[!a-zA-Z0-9]/_}_$$"
	_raw="$(_webdav_tmp_path play_session_create_raw)"
	rm -f "$_out" "$_sess_err" "$_raw" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_total="$(_restore_sum_stage_apk_bytes "$_apk_work")"
	case $_total in ''|*[!0-9]*) _total=0 ;; esac
	_t0="$(_restore_now_ms)"
	# !play/STORE 路線改為 hybrid：Play UID daemon 建 session，APK bytes 仍由 root pm install-write 寫入。
	# 不能用 pipeline 承接 daemon call，否則 mksh 會在子 shell 內更新 _INSTALL_DAEMON_READY，commit 階段又重啟 daemon。
	# shellcheck disable=SC2086
	_install_daemon_call_args "$_play_uid" "$_art_dir" "$_dex_dst" installSessionCreate "$USER_ID" "$_pkg" "$_total" $_session_opts > "$_raw" 2>"$_sess_err"
	_rc=$?
	_dex_filter_human_stdout < "$_raw" > "$_out"
	rm -f "$_raw" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [[ $_rc = 125 ]]; then
		_speed_debug_log "INSTALL_DAEMON_REQUIRED_NO_SPAWN command=installSessionCreate pkg=$_pkg play_uid=$_play_uid"
	fi
	_restore_log_install_timing "$_pkg" "session_create" "$_t0"
	_dex_append_nonhuman_stderr "$_sess_err"
	rm -f "$_sess_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_dex_translate_file "$_out" "HiddenApiUtil:installSessionCreate"
	_restore_save_play_session_raw_log "$_pkg" "$_out"
	_restore_print_play_session_output "$_out"
	return $_rc
}

_restore_play_session_write_root() {
	local _pkg="$1" _session_id="$2" _apk_work="$3" _out="$4" _err="$5" _a _name _rc _write_failed=0 _t0 _start_line
	[[ -n $_pkg && -n $_session_id && -d $_apk_work ]] || return 1
	_t0="$(_restore_now_ms)"
	_start_line="$(wc -l < "$_out" 2>/dev/null || echo 0)"
	case $_start_line in ''|*[!0-9]*) _start_line=0 ;; esac
	_restore_log_install_method "$_pkg" "dex_play_session_write_root" "session=$_session_id apkDir=$_apk_work writer=root"
	for _a in "$_apk_work"/*.apk; do
		[[ -f $_a ]] || continue
		_name="${_a##*/}"
		_name="${_name%.apk}"
		_restore_log_install_method "$_pkg" "dex_play_session_write_root_file" "session=$_session_id file=${_a##*/} splitName=$_name"
		pm install-write "$_session_id" "$_name" "$_a" >>"$_out" 2>>"$_err"
		_rc=$?
		echo "PLAY_SESSION_WRITE_ROOT file=${_a##*/} name=$_name rc=$_rc" >>"$_out"
		if [[ $_rc != 0 ]]; then _write_failed=1; break; fi
		echo_log "${_a##*/}寫入session"
	done
	_restore_log_install_timing "$_pkg" "session_write_root" "$_t0"
	_restore_save_play_session_raw_log_from_line "$_pkg" "$_out" "$_start_line"
	[[ $_write_failed = 0 ]]
}

_restore_run_play_session_commit_once() {
	local _pkg="$1" _play_uid="$2" _art_dir="$3" _dex_dst="$4" _session_id="$5" _session_opts="$6" _out="$7" _sess_err _raw _rc _t0 _start_line
	_sess_err="${TMPDIR:-/data/local/tmp}/.play_install_commit_stderr_${_pkg//[!a-zA-Z0-9]/_}_$$"
	_raw="$(_webdav_tmp_path play_session_commit_raw)"
	rm -f "$_sess_err" "$_raw" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_t0="$(_restore_now_ms)"
	_start_line="$(wc -l < "$_out" 2>/dev/null || echo 0)"
	case $_start_line in ''|*[!0-9]*) _start_line=0 ;; esac
	# 不能用 pipeline 承接 daemon call，避免 create 成功後的 daemon ready 狀態丟在子 shell。
	# shellcheck disable=SC2086
	_install_daemon_call_args "$_play_uid" "$_art_dir" "$_dex_dst" installSessionCommit "$USER_ID" "$_pkg" "$_session_id" $_session_opts > "$_raw" 2>"$_sess_err"
	_rc=$?
	_dex_filter_human_stdout < "$_raw" >> "$_out"
	rm -f "$_raw" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [[ $_rc = 125 ]]; then
		_speed_debug_log "INSTALL_DAEMON_REQUIRED_NO_SPAWN command=installSessionCommit pkg=$_pkg play_uid=$_play_uid"
	fi
	_restore_log_install_timing "$_pkg" "session_commit" "$_t0"
	_dex_append_nonhuman_stderr "$_sess_err"
	rm -f "$_sess_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_dex_translate_file "$_out" "HiddenApiUtil:installSessionCommit"
	_restore_save_play_session_raw_log_from_line "$_pkg" "$_out" "$_start_line"
	_restore_print_play_session_output "$_out"
	return $_rc
}

_restore_hybrid_installer_source_ok() {
	local _pkg="$1" _installer="$2"
	[[ -n $_pkg && -n $_installer ]] || return 1
	# hybrid 成功後不再逐 app 額外啟動 dex 查來源；來源/完整性集中到最後 verifyAppStateBatch。
	# 這可省下每個 app 一次 app_process 啟動與 getInstallSourceInfo 診斷時間。
	_restore_log_install_method "$_pkg" "hybrid_installer_pm_source_deferred" "verify=verifyAppStateBatch installerExpected=$_installer installingExpected=$_installer initiatingExpected=$_installer packageSourceExpected=OTHER"
	return 0
}

_restore_uidexec_bin() {
	local _u="${tools_path:-/data/backup_tools}/uidexec"
	if [[ -x $_u ]]; then
		printf '%s' "$_u"
		return 0
	fi
	_u="$(command -v uidexec 2>/dev/null || true)"
	if [[ -n $_u && -x $_u ]]; then
		printf '%s' "$_u"
		return 0
	fi
	return 1
}

_restore_install_with_hybrid_installer_pm() {
	local _pkg="$1" _apk_src="$2" _inst_pkg="$3" _inst_uid="$4" _inst_data_dir="$5"
	local _apk_work _rc _t_prepare _t_install _iarg _bypass="" _out _err _apk_count=0 _a _uidexec_bin
	local _session_id="" _session_raw="" _write_failed=0 _commit_rc=1 _nmsl="" _main_count=0 _legacy="" _name="" _commit_raw=""
	[[ -n $_pkg && -n $_inst_pkg ]] || return 1
	case $_inst_uid in ""|*[!0-9]*) echoRgb "安裝來源 $_inst_pkg UID 無效，跳過混合來源安裝流程" "0"; return 1 ;; esac
	[[ -d $_inst_data_dir ]] || { echoRgb "安裝來源 $_inst_pkg 缺少 data dir，跳過混合來源安裝流程" "2"; return 1; }
	_uidexec_bin="$(_restore_uidexec_bin)" || { echoRgb "找不到 uidexec，跳過混合來源安裝流程" "0"; return 1; }
	echoRgb "使用混合安裝來源安裝: $_inst_pkg" "3"
	# uidexec 會把 TMPDIR 指向 installer app data；pm install-create 可能需要此 tmp 目錄存在且 installer UID 可寫。
	mkdir -p "$_inst_data_dir/tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	chown "$_inst_uid:$_inst_uid" "$_inst_data_dir/tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	chmod 700 "$_inst_data_dir/tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_t_prepare="$(_restore_now_ms)"
	[[ -n $_apk_src && -d $_apk_src ]] || { echoRgb "APK 目錄不存在，跳過混合來源安裝流程" "0"; return 1; }
	if ! ls "$_apk_src"/*.apk >/dev/null 2>&1; then
		echoRgb "APK 目錄沒有 apk，跳過混合來源安裝流程" "0"
		return 1
	fi
	_apk_work="$_apk_src"
	_restore_log_install_stage "$_pkg" "READY" "mode=direct_root_write dir=$_apk_work apkCount=$(_restore_count_stage_apks "$_apk_work") bytes=skipped"
	_restore_log_install_timing "$_pkg" "prepare_hybrid_installer_pm" "$_t_prepare"
	_restore_log_install_method "$_pkg" "hybrid_installer_pm" "installer=$_inst_pkg uid=$_inst_uid uidexec=$_uidexec_bin dataDir=$_inst_data_dir apkDir=$_apk_work sourceNote=packageSource_OTHER_expected stage=direct_root_write"
	_iarg="$(_pm_installer_arg "$_inst_pkg")"
	[[ $sdk -gt 33 ]] && _bypass="--bypass-low-target-sdk-block"
	[[ $sdk -lt 30 ]] && _legacy="-l"
	_out="$TMPDIR/.hybrid_installer_pm_${_pkg//[!a-zA-Z0-9]/_}"
	_err="$TMPDIR/.hybrid_installer_pm_stderr_${_pkg//[!a-zA-Z0-9]/_}_$$"
	rm -f "$_out" "$_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	for _a in "$_apk_work"/*.apk; do
		[[ -f $_a ]] || continue
		_apk_count=$((_apk_count+1))
		[[ ${_a##*/} = nmsl.apk ]] && _nmsl="$_a" || _main_count=$((_main_count+1))
	done
	if [[ $_apk_count -lt 1 || $_main_count -lt 1 ]]; then
		_restore_log_install_method "$_pkg" "hybrid_installer_pm_failed" "rc=1 reason=no_apk apkCount=$_apk_count mainCount=$_main_count installer=$_inst_pkg"
		_restore_log_install_stage "$_pkg" "CLEANUP_SKIP" "reason=hybrid_installer_pm_failed_keep_for_fallback"
		return 1
	fi
	if [[ $_main_count -gt 1 ]]; then
		echoRgb "恢復split apk（混合安裝來源）" "2"
	else
		echoRgb "恢復普通apk（混合安裝來源）" "2"
	fi
	_t_install="$(_restore_now_ms)"
	{
		echo "HYBRID_INSTALLER_PM_BEGIN pkg=$_pkg installer=$_inst_pkg uid=$_inst_uid apkCount=$_apk_count mainCount=$_main_count sdk=$sdk"
		echo "HYBRID_INSTALLER_PM_ROUTE create=InstallerUID write=root commit=InstallerUID packageSource=OTHER_expected"
	} >>"$_out"

	# nmsl.apk 若存在，沿用舊版特殊處理：先獨立安裝，其他 APK 仍走混合 session。
	if [[ -n $_nmsl && -f $_nmsl ]]; then
		_restore_log_install_method "$_pkg" "hybrid_installer_pm_nmsl" "cmd=/system/bin/pm subcmd=install user=$user apk=nmsl.apk bypass=${_bypass:-none} installerArg=${_iarg:-none} writer=root installer=$_inst_pkg"
		# shellcheck disable=SC2086
		pm install -r $_bypass --user "$user" -t $_legacy $_iarg "$_nmsl" >>"$_out" 2>>"$_err"
		_rc=$?
		if [[ $_rc != 0 ]]; then
			_restore_log_install_method "$_pkg" "hybrid_installer_pm_failed" "rc=$_rc stage=nmsl_install installer=$_inst_pkg"
			_restore_log_install_timing "$_pkg" "hybrid_installer_pm_install" "$_t_install"
			cat "$_out" "$_err" 2>/dev/null >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/install_session.log"
			rm -f "$_err" 2>/dev/null
			_restore_log_install_stage "$_pkg" "CLEANUP_SKIP" "reason=hybrid_installer_pm_failed_keep_for_fallback"
			[[ ${restore_play_install_keep_workdir:-0} = 1 ]] || rm -f "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			return 1
		fi
		echo "HYBRID_INSTALLER_PM_NMSL_OK pkg=$_pkg installer=$_inst_pkg" >>"$_out"
		echo_log "nmsl.apk安裝"
	fi

	_restore_log_install_method "$_pkg" "hybrid_installer_pm_route" "create=InstallerUID write=root commit=InstallerUID user=$user apkCount=$_main_count packageSource=OTHER installer=$_inst_pkg"
	# Session ownership/initiating 在 install-create 當下決定：這一步必須由備份 installer UID 建立。
	# shellcheck disable=SC2086
	_session_raw="$("$_uidexec_bin" "$_inst_uid" "$_inst_uid" "$_inst_data_dir" "${tools_path}/classes.dex" \
		/system/bin/pm install-create -r $_bypass --user "$user" -t $_legacy $_iarg 2>>"$_err")"
	_rc=$?
	echo "HYBRID_INSTALLER_PM_CREATE rc=$_rc raw=$_session_raw" >>"$_out"
	_session_id="$(printf '%s\n' "$_session_raw" | sed -n 's/.*\[\([0-9][0-9]*\)\].*/\1/p' | head -n1)"
	if [[ $_rc = 0 && -n $_session_id ]]; then
		for _a in "$_apk_work"/*.apk; do
			[[ -f $_a && ${_a##*/} != nmsl.apk ]] || continue
			_name="${_a##*/}"
			_name="${_name%.apk}"
			_restore_log_install_method "$_pkg" "hybrid_installer_pm_write_root" "session=$_session_id file=${_a##*/} splitName=$_name installer=$_inst_pkg"
			# APK bytes 寫入由 root/shell 執行，使用原生 pm reverse-path，避開 installer UID reverse-mode 限制並保持速度。
			pm install-write "$_session_id" "$_name" "$_a" >>"$_out" 2>>"$_err"
			_rc=$?
			echo "HYBRID_INSTALLER_PM_WRITE_ROOT file=${_a##*/} name=$_name rc=$_rc" >>"$_out"
			if [[ $_rc != 0 ]]; then
				_write_failed=1
				break
			fi
			echo_log "${_a##*/}寫入session"
		done
		if [[ $_write_failed = 0 ]]; then
			# commit 優先由 installer UID 執行；若 ROM 對 ownership/權限有差異，再 root commit fallback。
			_commit_raw="$("$_uidexec_bin" "$_inst_uid" "$_inst_uid" "$_inst_data_dir" "${tools_path}/classes.dex" \
				/system/bin/pm install-commit "$_session_id" 2>>"$_err")"
			_commit_rc=$?
			echo "HYBRID_INSTALLER_PM_COMMIT_INSTALLER session=$_session_id rc=$_commit_rc raw=$_commit_raw" >>"$_out"
			if [[ $_commit_rc != 0 ]]; then
				_commit_raw="$(pm install-commit "$_session_id" 2>>"$_err")"
				_commit_rc=$?
				echo "HYBRID_INSTALLER_PM_COMMIT_ROOT session=$_session_id rc=$_commit_rc raw=$_commit_raw" >>"$_out"
			fi
			_rc=$_commit_rc
		else
			"$_uidexec_bin" "$_inst_uid" "$_inst_uid" "$_inst_data_dir" "${tools_path}/classes.dex" \
				/system/bin/pm install-abandon "$_session_id" >>"$_out" 2>>"$_err" || true
			pm install-abandon "$_session_id" >>"$_out" 2>>"$_err" || true
			_rc=1
		fi
	else
		_restore_log_install_method "$_pkg" "hybrid_installer_pm_failed" "rc=$_rc stage=install-create raw=${_session_raw:-empty} installer=$_inst_pkg"
		_rc=1
	fi
	_restore_log_install_timing "$_pkg" "hybrid_installer_pm_install" "$_t_install"
	cat "$_out" "$_err" 2>/dev/null >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/install_session.log"
	rm -f "$_err" 2>/dev/null
	if [[ $_rc = 0 ]]; then
		if [[ $_main_count -gt 1 ]]; then
			echoRgb "split Apk安裝成功" "1"
		else
			echoRgb "Apk安裝成功" "1"
		fi
		_speed_debug_log "OK: Apk安裝"
		result=0
		Set_back_0
		_restore_log_install_method "$_pkg" "hybrid_installer_pm_success" "rc=0 apkCount=$_apk_count mainCount=$_main_count mode=create_installer_write_root_commit_installer installer=$_inst_pkg sourceExpected=installer_installing_initiating_${_inst_pkg}_packageSource_OTHER"
		echoRgb "混合安裝來源commit成功: $_inst_pkg" "1"
		if _restore_hybrid_installer_source_ok "$_pkg" "$_inst_pkg"; then
			rm -f "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			return 0
		fi
		_restore_log_install_method "$_pkg" "hybrid_installer_pm_source_mismatch" "fallback=pm installer=$_inst_pkg"
	else
		_restore_log_install_method "$_pkg" "hybrid_installer_pm_failed" "rc=$_rc apkCount=$_apk_count mainCount=$_main_count mode=create_installer_write_root_commit_installer installer=$_inst_pkg"
		echoRgb "混合安裝來源commit失敗: $_inst_pkg" "0"
	fi
	# 失敗或來源不完整時不能清理 APK 目錄；後續 pm fallback 或 !play 慢速模式仍要共用同一批 APK。
	_restore_log_install_stage "$_pkg" "CLEANUP_SKIP" "reason=hybrid_installer_pm_failed_keep_for_fallback"
	[[ ${restore_play_install_keep_workdir:-0} = 1 ]] || rm -f "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	return 1
}
_restore_install_with_play_session() {
	local _pkg="$1" _apk_src="$2" _play_uid _dex_dst _apk_work _out _err _rc _art_dir _session_opts _session_id _t_prepare
	[[ -n $_pkg ]] || return 1
	_restore_has_play_store || { echoRgb "未找到 Google Play 商店，跳過 Play UID 安裝流程" "2"; return 1; }
	_play_uid="$(_restore_play_uid)"
	case $_play_uid in ""|*[!0-9]*) echoRgb "無法取得 Google Play UID，跳過 Play UID 安裝流程" "0"; return 1 ;; esac
	[[ -n $_apk_src && -d $_apk_src ]] || return 1
	_apk_work="$_apk_src"
	_t_prepare="$(_restore_now_ms)"
	_dex_dst="$(_restore_prepare_play_dex "$_play_uid")" || { echoRgb "準備 Play 私有 dex 失敗，跳過 Play UID 安裝流程" "0"; _restore_cleanup_play_session "$_pkg"; return 1; }
	_restore_log_install_timing "$_pkg" "prepare" "$_t_prepare"
	_art_dir="$(_restore_play_work_root)/art"
	_out="$TMPDIR/.play_install_session_${_pkg//[!a-zA-Z0-9]/_}"
	_err="$TMPDIR/.play_install_session_write_stderr_${_pkg//[!a-zA-Z0-9]/_}_$$"
	rm -f "$_out" "$_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_restore_log_install_method "$_pkg" "dex_play_session" "installer=com.android.vending uid=$_play_uid uidexec=uidexec mode=create_play_write_root_commit_play apkDir=$_apk_work"
	echoRgb "使用 Google Play UID hybrid session 安裝 APK..." "3"
	_session_opts="$(_restore_play_install_options)"
	_restore_log_install_method "$_pkg" "dex_play_session_options" "flags=${restore_play_install_extra_flags:-default} downgrade=${restore_play_install_allow_downgrade:-0} test=${restore_play_install_allow_test:-1} source=${restore_play_install_package_source:-store} logMode=${restore_play_install_log_mode:-summary} humanLog=${restore_play_install_human_log:-0} route=createPlay_writeRoot_commitPlay"
	if ! _restore_run_play_session_create_once "$_pkg" "$_play_uid" "$_art_dir" "$_dex_dst" "$_apk_work" "$_session_opts" "$_out"; then
		echoRgb "Play UID 建立安裝 session 失敗" "0"
		_restore_log_install_method "$_pkg" "dex_play_session_failed" "stage=create installer=com.android.vending"
		_RESTORE_DEFER_PLAY_CLEANUP=1 _restore_cleanup_play_session "$_pkg"
		[[ ${restore_play_install_keep_workdir:-0} = 1 ]] || rm -f "$_out" "$_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 1
	fi
	_session_id="$(_restore_play_session_id_from_file "$_pkg" "$_out")"
	case $_session_id in ''|*[!0-9]*)
		echoRgb "Play UID 建立 session 後無 sessionId" "0"
		_restore_log_install_method "$_pkg" "dex_play_session_failed" "stage=parse_session_id raw=empty"
		_RESTORE_DEFER_PLAY_CLEANUP=1 _restore_cleanup_play_session "$_pkg"
		[[ ${restore_play_install_keep_workdir:-0} = 1 ]] || rm -f "$_out" "$_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 1
		;;
	esac
	if ! _restore_play_session_write_root "$_pkg" "$_session_id" "$_apk_work" "$_out" "$_err"; then
		echoRgb "root 寫入 Play session 失敗" "0"
		_restore_log_install_method "$_pkg" "dex_play_session_failed" "stage=write_root session=$_session_id installer=com.android.vending"
		pm install-abandon "$_session_id" >>"$_out" 2>>"$_err" || true
		cat "$_out" "$_err" 2>/dev/null >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/install_session.log"
		rm -f "$_err" 2>/dev/null
		_RESTORE_DEFER_PLAY_CLEANUP=1 _restore_cleanup_play_session "$_pkg"
		[[ ${restore_play_install_keep_workdir:-0} = 1 ]] || rm -f "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 1
	fi
	cat "$_err" 2>/dev/null >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/install_session.log"
	rm -f "$_err" 2>/dev/null
	_restore_run_play_session_commit_once "$_pkg" "$_play_uid" "$_art_dir" "$_dex_dst" "$_session_id" "$_session_opts" "$_out"
	_rc=$?
	if [[ $_rc = 0 ]] && grep -q "$_pkg INSTALL_SESSION packageFound" "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
		echoRgb "Play UID hybrid session 安裝成功" "1"
		_restore_log_install_method "$_pkg" "dex_play_session_success" "installer=com.android.vending mode=create_play_write_root_commit_play session=$_session_id"
		_restore_verify_play_install_source_from_file "$_pkg" "$_out" || _restore_verify_play_install_source "$_pkg"
		_restore_cleanup_play_session "$_pkg"
		rm -f "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 0
	fi
	echoRgb "Play UID hybrid session 安裝失敗" "0"
	_restore_log_install_method "$_pkg" "dex_play_session_failed" "stage=commit session=$_session_id installer=com.android.vending"
	_RESTORE_DEFER_PLAY_CLEANUP=1 _restore_cleanup_play_session "$_pkg"
	[[ ${restore_play_install_keep_workdir:-0} = 1 ]] || rm -f "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	return 1
}

_pm_installer_arg() {
	local _installer="$1"
	_restore_bool_enabled "${restore_pm_install_with_installer:-1}" || return 0
	# 呼叫端必須先經過 _restore_select_installer_context 驗證；這裡只負責組 pm 參數。
	case $_installer in ""|null|NULL|clear|CLEAR|none|NONE) return 0 ;; esac
	printf '%s\n' "-i $_installer"
}

_pm_install_single() {
	local _apk="$1" _installer="$2" _iarg _bypass="" _legacy=""
	[[ -f $_apk ]] || return 1
	_iarg="$(_pm_installer_arg "$_installer")"
	[[ $sdk -gt 33 ]] && _bypass="--bypass-low-target-sdk-block"
	# 與 _pm_install_create_session / _restore_install_with_hybrid_installer_pm 一致：
	# sdk<30 (Android 9/10) 需要 -l，這裡原本漏掉，單一 apk (最常見路徑) 在舊機上會跟其他安裝路線不一致。
	[[ $sdk -lt 30 ]] && _legacy="-l"
	# shellcheck disable=SC2086
	pm install -r $_bypass --user "$user" -t $_legacy $_iarg "$_apk" >/dev/null
}

_pm_install_create_session() {
	local _installer="$1" _iarg _bypass="" _legacy=""
	_iarg="$(_pm_installer_arg "$_installer")"
	[[ $sdk -gt 33 ]] && _bypass="--bypass-low-target-sdk-block"
	[[ $sdk -lt 30 ]] && _legacy="-l"
	# shellcheck disable=SC2086
	pm install-create $_bypass --user "$user" -t $_legacy $_iarg
}

# 安裝 apk (含 split apk 處理), 自動繞過安裝驗證
installapk() {
	local _apk_stage
	if [[ ${_restore_force_play_session:-0} = 1 ]]; then
		_apk_stage="$(_restore_prepare_apk_stage_dir "$name2")" || { result=1; Set_back_1; return 1; }
	else
		_apk_stage="$(_restore_prepare_apk_work_dir "$name2")" || { result=1; Set_back_1; return 1; }
	fi
	# 流式恢復: 從遠端拉 apk.tar.zst → 解壓到本次 APK work 目錄 (apk 安裝需檔案, pm install 不能用 stdin)
	if [[ $_RESTORE_STREAM = 1 && -n $_STREAM_APK_SRC ]]; then
		case ${_STREAM_APK_SRC##*.} in
		zst) _stream_download "$_STREAM_APK_SRC" | zstd -d 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | tar --checkpoint-action="ttyout=%T\r" -xmpf - -C "$_apk_stage" ;;
		tar) _stream_download "$_STREAM_APK_SRC" | tar --checkpoint-action="ttyout=%T\r" -xmpf - -C "$_apk_stage" ;;
		esac
		result=$?
		echo_log "apk流式解壓"
	else
		apkfile="$(find "$Backup_folder" -maxdepth 1 -name "apk.*" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		if [[ $apkfile != "" ]]; then
			local _apk_extract_raw_log _apk_extract_raw_start _apk_size
			_apk_size="$(_local_file_size_debug "$apkfile")"
			_apk_extract_raw_start="$(date +%s%3N 2>/dev/null)"; case $_apk_extract_raw_start in ''|*[!0-9]*) _apk_extract_raw_start="$(date +%s 2>/dev/null)000" ;; esac
			_apk_extract_raw_log="$(_local_raw_debug_begin extract "kind=apk file=$apkfile dest=$_apk_stage ext=${apkfile##*.} size=$_apk_size")"
			case ${apkfile##*.} in
			zst) tar --checkpoint-action="ttyout=%T\r" -I zstd -xmpf "$apkfile" -C "$_apk_stage" 2>>"$_apk_extract_raw_log" ;;
			tar) tar --checkpoint-action="ttyout=%T\r" -xmpf "$apkfile" -C "$_apk_stage" 2>>"$_apk_extract_raw_log" ;;
			*)
				echoRgb "${apkfile##*/} 壓縮包不支持解壓縮" "0"
				Set_back_1
				;;
			esac
			result=$?
			_local_raw_debug_end extract "$_apk_extract_raw_log" "$result" "$_apk_extract_raw_start" "kind=apk dest=$_apk_stage"
			echo_log "${apkfile##*/}解壓縮" && [[ -f $Backup_folder/nmsl.apk ]] && cp -r "$Backup_folder/nmsl.apk" "$_apk_stage"
		else
			echoRgb "你的Apk壓縮包離家出走了，可能備份後移動過程遺失了\n -解決辦法手動安裝Apk後再執行恢復腳本" "0"
			result=1
			Set_back_1
		fi
	fi
	if [[ $result = 0 ]]; then
		# 用 glob + 計數取代 find | wc (省 2 fork)
		local _apks _apk_count=0 _installer _installer_raw _used_play_session=0 _fallback_pm=0
		for _apks in "$_apk_stage"/*.apk; do
			[[ -f $_apks ]] && let _apk_count++
		done
		_installer_raw="$(_restore_backup_installer_value "$app_details")"
		_installer=""
		# 備份 installer 只作為候選；必須在目前 user 真的存在且能取得 UID，才允許用於 -i / UID hybrid。
		if [[ $_apk_count -gt 0 ]]; then
			if _restore_select_installer_context "$name2" "$_installer_raw"; then
				_installer="$RESTORE_INSTALLER_PKG"
			else
				_installer=""
			fi
		fi
		# !play 是使用者明確指定的慢速 STORE 來源路線，仍維持 Play Java session；失敗固定回退原生 pm。
		if [[ $_apk_count -gt 0 && ${_restore_force_play_session:-0} = 1 ]]; then
			echoRgb "${_restore_force_play_marker:-!play} 標記：使用 Play UID hybrid session 安裝（create/commit=Play，write=root）" "3"
			_restore_log_install_method "$name2" "play_session_requested_by_appList" "marker=${_restore_force_play_marker:-!play} mode=play_daemon_create_root_write_play_commit installerBackup=${_installer_raw:-null} validatedInstaller=${_installer:-null} fallback=pm packageSource=STORE"
			if _restore_install_with_play_session "$name2" "$_apk_stage"; then
				_used_play_session=1
				result=0
				Set_back_0
			else
				echoRgb "Play UID hybrid session 安裝失敗，回退原生 pm" "3"
				_restore_log_install_method "$name2" "pm_fallback_after_play_session_failed" "installer=${_installer:-null} rawInstaller=${_installer_raw:-null}"
				_fallback_pm=1
			fi
		elif [[ $_apk_count -gt 0 && -n $_installer && -n ${RESTORE_INSTALLER_UID:-} && -n ${RESTORE_INSTALLER_DATA_DIR:-} ]]; then
			if [[ ${_restore_hybrid_installer_pm_disabled:-0} = 1 ]]; then
				echoRgb "本輪已停用混合安裝來源，直接使用原生 pm" "3"
				_restore_log_install_method "$name2" "hybrid_installer_pm_skip_disabled" "fallback=pm installer=${_installer:-null} rawInstaller=${_installer_raw:-null}"
				_fallback_pm=1
			elif _restore_install_with_hybrid_installer_pm "$name2" "$_apk_stage" "$RESTORE_INSTALLER_PKG" "$RESTORE_INSTALLER_UID" "$RESTORE_INSTALLER_DATA_DIR"; then
				_used_play_session=1
				result=0
				Set_back_0
			else
				echoRgb "混合安裝來源commit失敗，本輪後續全部回退原生 pm" "3"
				_restore_hybrid_installer_pm_disabled=1
				_restore_log_install_method "$name2" "hybrid_installer_pm_disable_for_batch" "fallback=pm installer=${_installer:-null} rawInstaller=${_installer_raw:-null}"
				_fallback_pm=1
			fi
		fi
		if [[ $_used_play_session != 1 ]]; then
			case $_apk_count in
			1)
				echoRgb "恢復普通apk" "2"
				_restore_log_install_method "$name2" "pm_install" "apk=single installer=${_installer:-null}"
				_pm_install_single "$_apk_stage"/*.apk "$_installer"
				echo_log "Apk安裝"
				;;
			0)
				echoRgb "$_apk_stage 中沒有apk" "0"
				Set_back_1
				;;
			*)
				echoRgb "恢復split apk" "2"
				_restore_log_install_method "$name2" "pm_install_create" "apk=split count=$_apk_count installer=${_installer:-null}"
				b="$(_pm_install_create_session "$_installer" | grep -Eo '[0-9]+')"
				if [[ -z $b ]]; then
					echoRgb "pm install-create 失敗" "0"
					Set_back_1
					[[ ${_restore_force_play_session:-0} != 1 ]] && _restore_clear_apk_work_dir
					return 1
				fi
				if [[ -f $_apk_stage/nmsl.apk ]]; then
					_pm_install_single "$_apk_stage/nmsl.apk" "$_installer"
					echo_log "nmsl.apk安裝"
				fi
				# 用 glob 取代 find | grep -v (省 fork)
				for _apks in "$_apk_stage"/*.apk; do
					[[ -f $_apks && ${_apks##*/} != nmsl.apk ]] || continue
					pm install-write "$b" "${_apks##*/}" "$_apks" </dev/null >/dev/null
					echo_log "${_apks##*/}寫入session"
				done
				pm install-commit "$b" >/dev/null
				echo_log "split Apk安裝"
				;;
			esac
		fi
	fi
	[[ ${_restore_force_play_session:-0} != 1 ]] && _restore_clear_apk_work_dir
}
# 關閉 apk 安裝驗證 (verifier_verify_adb_installs)
# 避免 Play Protect / 系統驗證攔截批次安裝
disable_verify() {
	#禁用apk驗證
	settings put global verifier_verify_adb_installs 0 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	#禁用安裝包驗證
	settings put global package_verifier_enable 0 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	#未知來源
	settings put secure install_non_market_apps 1 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	#關閉play安全校驗
	if [[ $(settings get global package_verifier_user_consent 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) != -1 ]]; then
		settings put global package_verifier_user_consent -1 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		settings put global upload_apk_enable 0 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		echoRgb "PLAY安全驗證為開啟狀態已被腳本關閉防止apk安裝失敗" "3"
	fi
	# 額外安全性攔截
	settings put global harmful_app_warning_on 0 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# 關閉應用的受限模式 (針對 Android 13/14 側載應用)
	settings put secure enhanced_confirmation_states 0 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# 設定檔案路徑
	FILE="/data/data/com.android.vending/shared_prefs/finsky.xml"
	if [[ -f $FILE ]]; then
		# 提取當前的 auto_update_enabled 值
		CURRENT_VALUE="$(sed -n '/<boolean name="auto_update_enabled" /s/.*value="\([^"]*\)".*/\1/p' "$FILE")"
		if [[ $CURRENT_VALUE = true ]]; then
			sed -i '/<boolean name="auto_update_enabled" /s/value="true"/value="false"/' "$FILE"
			[[ $(sed -n '/<boolean name="auto_update_enabled" /s/.*value="\([^"]*\)".*/\1/p' "$FILE") = false ]] && echoRgb "play自動更新已關閉" "3"
			echoRgb "殺死 Google Play 商店..."
			am force-stop com.android.vending
		else
			if [[ $CURRENT_VALUE = "" ]]; then
				sed -i '/<\/map>/i \    <boolean name="auto_update_enabled" value="false" />' "$FILE"
				[[ $(sed -n '/<boolean name="auto_update_enabled" /s/.*value="\([^"]*\)".*/\1/p' "$FILE") = false ]] && echoRgb "auto_update_enabled已插入false,play自動更新已關閉" "3"
				echoRgb "殺死 Google Play 商店..."
				am force-stop com.android.vending
			else
				[[ $CURRENT_VALUE != false ]] && echoRgb "無法識別play auto_update_enabled當前$CURRENT_VALUE值" "0"
			fi
		fi
	fi
}
# 從 app 安裝資訊取得 app 名稱 / apk 路徑 / 版本等資料
# 用 classes.dex 透過 hidden API 拿到完整 PackageInfo
get_name(){
	txt="$MODDIR/appList.txt"
	txt2="$MODDIR/mediaList.txt"
	if [[ $1 = Apkname ]]; then
		rm -rf "$txt" "$txt2"
		echoRgb "列出全部資料夾內應用名與自定義目錄壓縮包名稱" "3"
	fi
	rgb_a=118
	user="$(echo "${0%}" | sed 's/.*\/Backup_zstd_\([0-9]*\).*/\1/')"
	Apk_info="$(pm list packages --user "$user" | cut -f2 -d ':' | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	if [[ $Apk_info != "" ]]; then
		[[ $Apk_info = *"Failure calling service package"* ]] && Apk_info="$(appinfo "user|system" "pkgName" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	else
		Apk_info="$(appinfo "user|system" "pkgName" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	fi
	[[ $Apk_info = "" ]] && echoRgb "Apk_info變量為空" "0" && exit
	starttime1="$(date -u "+%s")"
	i=1
	_apk_scan_list="$TMPDIR/.apk_scan_list"
	find "$MODDIR" -maxdepth 2 -name "apk.*" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sort > "$_apk_scan_list"
	while read -r; do
		Folder="${REPLY%/*}"
		[[ $rgb_a -ge 229 ]] && rgb_a=118
		unset PackageName NAME DUMPAPK ChineseName apk_version Ssaid dataSize userSize obbSize
		if [[ -f $Folder/app_details.json ]]; then
			ChineseName="$(jq -r 'try ((([.[] | objects | select(.PackageName != null)] | length) as $n | if $n > 0 then (to_entries[] | select(.value.PackageName != null).key) else (to_entries[] | select(.key != null).key) end) // "") catch ""' "$Folder/app_details.json" | head -n 1)"
			PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$Folder/app_details.json")"
		fi
		if [[ $PackageName = "" || $ChineseName = "" ]]; then
			echoRgb "${Folder##*/}包名獲取失敗，解壓縮獲取包名中..." "0"
			cleanup_tmpdir_contents || exit 1
			local _probe_extract_raw_log _probe_extract_raw_start _probe_size
			_probe_size="$(_local_file_size_debug "$REPLY")"
			_probe_extract_raw_start="$(date +%s%3N 2>/dev/null)"; case $_probe_extract_raw_start in ''|*[!0-9]*) _probe_extract_raw_start="$(date +%s 2>/dev/null)000" ;; esac
			_probe_extract_raw_log="$(_local_raw_debug_begin extract "kind=apk_probe file=$REPLY dest=$TMPDIR ext=${REPLY##*.} size=$_probe_size")"
			case ${REPLY##*.} in
			zst) tar -I zstd -xmpf "$REPLY" -C "$TMPDIR" --wildcards --no-anchored 'base.apk' 2>>"$_probe_extract_raw_log" ;;
			tar) tar -xmpf "$REPLY" -C "$TMPDIR" --wildcards --no-anchored 'base.apk' 2>>"$_probe_extract_raw_log" ;;
			*)
				echoRgb "${REPLY##*/} 壓縮包不支持解壓縮" "0"
				Set_back_1
				;;
			esac
			result=$?
			_local_raw_debug_end extract "$_probe_extract_raw_log" "$result" "$_probe_extract_raw_start" "kind=apk_probe dest=$TMPDIR"
			echo_log "${REPLY##*/}解壓縮"
			if [[ $result = 0 ]]; then
				if [[ -f $TMPDIR/base.apk ]]; then
					DUMPAPK="$(appinfo3 "$TMPDIR/base.apk")"
					if [[ $DUMPAPK != "" ]]; then
						# getPackageArchiveInfo 固定輸出「無空白標籤 套件名」；直接拆欄位，避免 shell array。
						ChineseName="${DUMPAPK%% *}"
						PackageName="${DUMPAPK#* }"
						PackageName="${PackageName%% *}"
						cleanup_tmpdir_contents || exit 1
					else
						echoRgb "appinfo輸出失敗" "0"
					fi
				fi
			fi
		fi
		if [[ $PackageName != "" && $ChineseName != "" ]]; then
			if [[ $(echo "$Apk_info" | awk -v pkg="$PackageName" '$1 == pkg {print $1}') = "" ]]; then
				echoRgb "$ChineseName已經不存在$user使用者中"
				if [[ $delete_app = "" ]]; then
					delete_app="$ChineseName $PackageName"
				else
					delete_app="$delete_app\n$ChineseName $PackageName"
				fi
			fi
			case $1 in
			Apkname)
				[[ -f $Folder/${PackageName}.sh ]] && rm -rf "$Folder/${PackageName}.sh"
				[[ ! -f $Folder/recover.sh ]] && touch_shell "3" "$Folder/recover.sh"
				[[ ! -f $Folder/backup.sh ]] && touch_shell "1" "$Folder/backup.sh"
				echoRgb "$i:$ChineseName $PackageName"
				if [[ $TMPTXT = "" ]]; then
					TMPTXT="#不需要恢復還原的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market\n$ChineseName $PackageName"
				else
					TMPTXT="$TMPTXT\n$ChineseName $PackageName"
				fi
				let i++ ;;
			convert)
				if [[ ${Folder##*/} = $PackageName ]]; then
					DIR_NAME="${Folder%/*}/$ChineseName"
					echoRgb "${Folder##*/} > $ChineseName"
				else
					DIR_NAME="${Folder%/*}/$PackageName"
					echoRgb "${Folder##*/} > $PackageName"
				fi
				if [[ -d $DIR_NAME ]]; then
					i=1
					NEW_DIR_NAME="${DIR_NAME}_${i}"
					while [[ -d $NEW_DIR_NAME ]]; do
						i=$((i + 1))
						NEW_DIR_NAME="${DIR_NAME}_${i}"
					done
					DIR_NAME="$NEW_DIR_NAME"
				fi
				mv "$Folder" "$DIR_NAME" ;;
			esac
		fi
		let rgb_a++
	done < "$_apk_scan_list"
	rm -f "$_apk_scan_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	[[ $TMPTXT != "" ]] && echo "$TMPTXT">"$txt"
	# 重新生成後一致性檢查: 比對資料夾與 appList.txt
	if [[ -f $txt ]]; then
		local _chk_folders="$TMPDIR/.chk_folders" _chk_listed="$TMPDIR/.chk_listed"
		for d in "$MODDIR"/*/; do
			d="${d%/}"; d="${d##*/}"
			case "$d" in wifi|Media|tools|log) continue ;; esac
			echo "$d"
		done | sort > "$_chk_folders"
		awk '!/^#|^＃/ && NF {print $1}' "$txt" | sort > "$_chk_listed"
		local _only_folder _only_list
		_only_folder="$(comm -23 "$_chk_folders" "$_chk_listed")"
		_only_list="$(comm -13 "$_chk_folders" "$_chk_listed")"
		if [[ -n $_only_folder || -n $_only_list ]]; then
			echoRgb "_______________________________________" "2"
			echoRgb "一致性檢查發現異常:" "0"
			[[ -n $_only_folder ]] && { echoRgb "有資料夾但不在清單:" "0"; echo "$_only_folder"; }
			[[ -n $_only_list ]] && { echoRgb "在清單但無資料夾:" "0"; echo "$_only_list"; }
		else
			echoRgb "一致性檢查通過: 資料夾與清單完全對應" "1"
		fi
		rm -f "$_chk_folders" "$_chk_listed" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	fi
	if [[ -d $MODDIR/Media ]]; then
		echoRgb "存在媒體資料夾" "2"
		[[ ! -f $txt2 ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$txt2"
		find "$MODDIR/Media" -maxdepth 1 -name "*.tar*" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r; do
			echoRgb "${REPLY##*/}" && echo "${REPLY##*/}" >> "$txt2"
		done
		echoRgb "$txt2重新生成" "1"
	fi
	if [[ $delete_app != "" ]]; then
		if [[ $(echo "$delete_app" | awk 'NF != 0 { count++ } END { print count }') != "" ]]; then
			echoRgb "列出需要刪除的應用中....\n -$delete_app"
			if ! ask_yn "確認列表無誤後刪除?" "刪除" "退出腳本編輯列表"; then
				exit 0
			fi
			if true; then
				echoRgb "警告 即將刪除未安裝應用資料夾，請再三確認後在執行" "0"
				echoRgb "以下資料夾將被刪除:" "0"
				echo "$delete_app" | sed '/^$/d' | awk '{print "  - "$1}'
				if ! ask_yn "確認刪除?" "確認刪除" "取消"; then
					echoRgb "已取消刪除" "1"
					exit 0
				fi
				i=1
				r="$(echo "$delete_app" | awk 'NF != 0 { count++ } END { print count }')"
				while [[ $i -le $r ]]; do
					name1="$(echo "$delete_app" | awk -v n=$i 'NF{c++} c==n{print $1; exit}')"
					name2="$(echo "$delete_app" | awk -v n=$i 'NF{c++} c==n{print $2; exit}')"
					if [[ -z $name1 ]]; then
						echoRgb "第$i個應用名稱解析失敗 跳過刪除以保護備份" "0"
						let i++ && continue
					fi
					Backup_folder="$MODDIR/$name1"
					[[ -d $Backup_folder ]] && rm -rf "$Backup_folder"
					# 按應用名(第一欄)整行刪除, 避免 sed 對中文/特殊字元誤刪或留半截行
					if [[ -f $txt ]]; then
						awk -v t="$name1" 'NF==0 || $1 != t' "$txt" > "$txt.tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && mv "$txt.tmp" "$txt"
					fi
					let i++
				done
				# 刪除後一致性檢查: 確認資料夾與 appList.txt 同步
				if [[ -f $txt ]]; then
					_dchk_f="$TMPDIR/.dchk_folders"; _dchk_l="$TMPDIR/.dchk_listed"
					for d in "$MODDIR"/*/; do
						d="${d%/}"; d="${d##*/}"
						case "$d" in wifi|Media|tools|log) continue ;; esac
						echo "$d"
					done | sort > "$_dchk_f"
					awk '!/^#|^＃/ && NF {print $1}' "$txt" | sort > "$_dchk_l"
					_d_of="$(comm -23 "$_dchk_f" "$_dchk_l")"
					_d_ol="$(comm -13 "$_dchk_f" "$_dchk_l")"
					if [[ -n $_d_of || -n $_d_ol ]]; then
						echoRgb "_______________________________________" "2"
						echoRgb "刪除後一致性檢查發現異常:" "0"
						[[ -n $_d_of ]] && { echoRgb "有資料夾但不在清單:" "0"; echo "$_d_of"; }
						[[ -n $_d_ol ]] && { echoRgb "在清單但無資料夾:" "0"; echo "$_d_ol"; }
					else
						echoRgb "刪除後一致性檢查通過: 資料夾與清單完全對應" "1"
					fi
					rm -f "$_dchk_f" "$_dchk_l" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				fi
			else
				exit 0
			fi
		fi
	fi
	chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt"
	endtime 1
	exit 0
}
# 低電量檢測 (依 low_battery_mode conf 設定決定行為; 留空則跳音量鍵詢問)
# ============================================================
# SpeedBackup single-file section: sb_50_validation_appstate.sh
# ============================================================
self_test() {
	local _level _charging
	_charging="$(dumpsys deviceidle get charging)"
	_level="$(dumpsys battery | awk '/level/{print $2}' | grep -Eo '[0-9]+')"
	[[ $_charging = true || -z $_level || $_level -gt 15 ]] && return
	case $low_battery_mode in
	1)
		echoRgb "電量${_level}%太低且未充電\n -為防止備份檔案或是恢復因低電量強制關機導致檔案損毀\n -請連接充電器後備份" "0" && exit 2
		;;
	2)
		echoRgb "電量${_level}%太低且未充電 (low_battery_mode=2, 已忽略繼續執行)" "0"
		;;
	*)
		echoRgb "電量${_level}%太低且未充電\n -音量上: 無視風險繼續操作 / 音量下: 退出" "0"
		get_version "繼續" "退出"
		[[ $branch != true ]] && exit 2
		;;
	esac
}
# 驗證單一檔案的 sha256 校驗碼 (對照 tools 目錄內預存的雜湊)
Validation_file() {
	MODDIR_NAME="${1%/*}"
	MODDIR_NAME="${MODDIR_NAME##*/}"
	FILE_NAME="${1##*/}"
	local _raw_log _raw_start _fsize _rc
	_fsize="$(_local_file_size_debug "$1")"
	_raw_start="$(date +%s%3N 2>/dev/null)"; case $_raw_start in ''|*[!0-9]*) _raw_start="$(date +%s 2>/dev/null)000" ;; esac
	_raw_log="$(_local_raw_debug_begin checksum "file=$1 name=$FILE_NAME ext=${FILE_NAME##*.} size=$_fsize")"
	echoRgb "校驗$FILE_NAME"
	case ${FILE_NAME##*.} in
	zst)
		# zstd -t 成功時會把「file.tar.zst: N bytes」寫到 stderr，這是正常資訊，不進全域 stderr.log，但會保存到 checksum raw。
		zstd -t "$1" 2>>"$_raw_log"
		_rc=$?
		[[ $_rc = 0 ]]
		;;
	tar) tar -tf "$1" > /dev/null 2>>"$_raw_log"; _rc=$?; [[ $_rc = 0 ]] ;;
	esac
	result=$?
	_local_raw_debug_end checksum "$_raw_log" "${_rc:-$result}" "$_raw_start" "result=$result"
	echo_log "${FILE_NAME##*.}校驗"
}
# 檢查壓縮檔完整性 (zstd -t / tar -t)
# 主選單「壓縮檔完整性檢查」呼叫
Check_archive() {
	starttime1="$(date -u "+%s")"
	error_log="$TMPDIR/error_log"
	rm -rf "$error_log"
	FIND_PATH="$(find "$1" -maxdepth 3 -name "*.tar*" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sort)"
	i=1
	r="$(find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | wc -l)"
	find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sort | while read -r; do
		REPLY="${REPLY%/*}"
		echoRgb "校驗第$i/$r個資料夾 剩下$((r - i))個" "3"
		echoRgb "校驗:${REPLY##*/}"
		find "$REPLY" -maxdepth 1 -name "*.tar*" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sort | while read -r; do
			Validation_file "$REPLY"
			[[ $result != 0 ]] && echo "$REPLY">>"$error_log"
		done
		echoRgb "$(safe_percent "$i" "$r")% $(progress_bar $(safe_percent "$i" "$r"))"
		let i++ nskg++
	done
	endtime 1
	[[ -f $error_log ]] && echoRgb "以下為失敗的檔案\n $(cat "$error_log")" || echoRgb "恭喜~~全數校驗通過"
	rm -rf "$error_log"
}
# 產生 ASCII 進度條, 用法: progress_bar 42 → [████████░░░░░░░░░░░░]
progress_bar() {
	local pct="${1:-0}" width=20 filled i=0 bar=""
	[[ $pct -lt 0 ]] && pct=0
	[[ $pct -gt 100 ]] && pct=100
	filled=$((pct * width / 100))
	while [[ $i -lt $width ]]; do
		[[ $i -lt $filled ]] && bar="$bar█" || bar="$bar░"
		let i++
	done
	echo "[$bar]"
}
# 毫秒轉可讀時間 (15000 → 15秒, 60000 → 1分鐘, 1800000 → 30分鐘)
ms_to_readable() {
	local ms="$1" s
	[[ -z $ms || $ms = null ]] && { echo "$ms"; return; }
	# INT_MAX 附近 = 系統「永不休眠」
	[[ $ms -ge 2147483 ]] && [[ $ms -ge 2000000000 ]] && { echo "永不休眠"; return; }
	s=$((ms / 1000))
	if [[ $s -lt 60 ]]; then
		echo "${s}秒"
	elif [[ $s -lt 3600 ]]; then
		local m=$((s / 60)) rs=$((s % 60))
		[[ $rs = 0 ]] && echo "${m}分鐘" || echo "${m}分${rs}秒"
	else
		local h=$((s / 3600)) rm=$(((s % 3600) / 60))
		[[ $rm = 0 ]] && echo "${h}小時" || echo "${h}小時${rm}分鐘"
	fi
}
# 把過去時間字串 (YYYY.MM.DD HH:MM:SS) 轉成「幾天幾小時幾分前」
time_ago() {
	local ts="$1"
	[[ -z $ts || $ts = null ]] && { echo "$ts"; return; }
	local norm past now diff
	norm="$(echo "$ts" | sed 's/\./-/g')"
	past="$(date -d "$norm" +%s 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	now="$(date +%s)"
	[[ -z $past ]] && { echo "$ts"; return; }
	diff=$((now - past))
	[[ $diff -lt 0 ]] && { echo "$ts"; return; }
	if [[ $diff -lt 60 ]]; then
		echo "${diff}秒前"
	elif [[ $diff -lt 3600 ]]; then
		echo "$((diff / 60))分鐘前"
	elif [[ $diff -lt 86400 ]]; then
		local h=$((diff / 3600)) m=$(((diff % 3600) / 60))
		[[ $m = 0 ]] && echo "${h}小時前" || echo "${h}小時${m}分前"
	else
		local d=$((diff / 86400)) h=$(((diff % 86400) / 3600)) m=$(((diff % 3600) / 60))
		echo "${d}天${h}小時${m}分前"
	fi
}
Set_screen_pause_seconds () {
	local _scr_save="$TMPDIR/.screen_timeout_orig"
	if [[ $1 = on ]]; then
		#獲取系統設置的無操作息屏秒數
		if [[ $Get_dark_screen_seconds = "" ]]; then
			Get_dark_screen_seconds="$(settings get system screen_off_timeout)"
			# 防呆: 若讀到的已是我們設定的 1800000 (代表上次沒還原成功),
			# 改用上次存檔的原值, 避免把 1800000 當成原值記下來
			if [[ $Get_dark_screen_seconds = 1800000 && -f $_scr_save ]]; then
				Get_dark_screen_seconds="$(cat "$_scr_save" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
			fi
			# 原值存檔, 即使進程異常結束下次也能還原
			[[ $Get_dark_screen_seconds != 1800000 ]] && echo "$Get_dark_screen_seconds" > "$_scr_save"
			#設置30分鐘後息屏
			settings put system screen_off_timeout 1800000
			echo_log "設置無操作息屏時間30分鐘"
		fi
		[[ $setDisplayPowerMode = true ]] && {
		setDisplay 0
		echo_log "設置螢幕狀態false"
		}
	elif [[ $1 = off ]]; then
		# 還原: 優先用變數, 沒有則讀存檔
		[[ $Get_dark_screen_seconds = "" && -f $_scr_save ]] && Get_dark_screen_seconds="$(cat "$_scr_save" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		if [[ $Get_dark_screen_seconds != "" && $Get_dark_screen_seconds != 1800000 ]]; then
			settings put system screen_off_timeout "$Get_dark_screen_seconds"
			echo_log "設置無操作息屏時間為$(ms_to_readable "$Get_dark_screen_seconds")"
			input keyevent 224
			rm -f "$_scr_save"
			Get_dark_screen_seconds=""
		fi
		[[ $setDisplayPowerMode = true ]] && {
		setDisplay 2
		echo_log "設置螢幕狀態true"
		}
	fi
}
_appstate_record_from_app_details() {
	local _json="$1" _entry="$2" _pkg="$3" _out="$4"
	[[ -s $_json && -n $_pkg && -n $_out ]] || return 1
	jq -c --arg entry "$_entry" --arg pkg "$_pkg" '
		def mode_num($v):
			if $v == null then 3
			elif ($v|type) == "number" then $v
			else ($v|tostring|ascii_downcase) as $s |
				if ($s|test("^[0-9]+$")) then ($s|tonumber)
				elif ($s=="allow" or $s=="allowed" or $s=="true") then 0
				elif ($s=="ignore" or $s=="ignored" or $s=="false") then 1
				elif ($s=="deny" or $s=="denied" or $s=="error" or $s=="errored") then 2
				elif $s=="foreground" then 4 else 3 end
			end;
		def mode_name($m):
			if $m==0 then "allow" elif $m==1 then "ignored" elif $m==2 then "errored"
			elif $m==3 then "default" elif $m==4 then "foreground" else "mode_\($m)" end;
		def ensure_scoped:
			if type != "object" then . else
				(if has("packageMode") then . else . + {packageMode:null} end) |
				(if has("uidMode") then . else . + {uidMode:null} end) |
				(if has("scope") then . else . + {scope:"default"} end)
			end;
		def normalize_appstate_v2:
			.permissions=[(.permissions // [])[] | if (((.appOp // -1)|tonumber? // -1) >= 0) then ensure_scoped else . end] |
			.specialAccess=((.specialAccess // {}) | with_entries(.value |= ensure_scoped)) |
			.otherAppOps=[(.otherAppOps // [])[] | ensure_scoped] |
			.batterySettings=((.batterySettings // {}) |
				(if has("RUN_IN_BACKGROUND") then .RUN_IN_BACKGROUND |= ensure_scoped else . end) |
				(if has("RUN_ANY_IN_BACKGROUND") then .RUN_ANY_IN_BACKGROUND |= ensure_scoped else . end));
		def pparts($v): ($v|tostring|split(" "));
		def pflag($v): ((pparts($v)|map(select(startswith("pflags=")))|.[0]//"pflags=0")|sub("^pflags=";"")|tonumber? // 0);
		def merged_objects($xs): reduce ($xs[]? | select(type=="object")) as $x ({}; . * $x);
		def first_value($xs): ([$xs[]? | select(. != null)] | .[0] // null);
		def special_key($k;$v):
			(($v.publicName // "")|tostring) as $n |
			(($k // "")|tostring|ascii_upcase) as $u |
			if ($n=="android:system_alert_window" or $u=="SYSTEM_ALERT_WINDOW") then "SYSTEM_ALERT_WINDOW"
			elif ($n=="android:picture_in_picture" or $u=="PICTURE_IN_PICTURE") then "PICTURE_IN_PICTURE"
			elif ($n=="android:manage_external_storage" or $u=="MANAGE_EXTERNAL_STORAGE") then "MANAGE_EXTERNAL_STORAGE"
			elif ($n=="android:write_settings" or $u=="WRITE_SETTINGS") then "WRITE_SETTINGS"
			elif ($n=="android:request_install_packages" or $u=="REQUEST_INSTALL_PACKAGES") then "REQUEST_INSTALL_PACKAGES"
			elif ($n=="android:get_usage_stats" or $u=="GET_USAGE_STATS") then "GET_USAGE_STATS"
			elif ($n=="android:use_full_screen_intent" or $u=="USE_FULL_SCREEN_INTENT") then "USE_FULL_SCREEN_INTENT"
			elif ($n=="android:schedule_exact_alarm" or $u=="SCHEDULE_EXACT_ALARM") then "SCHEDULE_EXACT_ALARM"
			elif ($n=="android:access_notification_policy" or $u=="ACCESS_NOTIFICATION_POLICY") then "ACCESS_NOTIFICATION_POLICY"
			else "" end;
		def special_public($key):
			if $key=="SYSTEM_ALERT_WINDOW" then "android:system_alert_window"
			elif $key=="PICTURE_IN_PICTURE" then "android:picture_in_picture"
			elif $key=="MANAGE_EXTERNAL_STORAGE" then "android:manage_external_storage"
			elif $key=="WRITE_SETTINGS" then "android:write_settings"
			elif $key=="REQUEST_INSTALL_PACKAGES" then "android:request_install_packages"
			elif $key=="GET_USAGE_STATS" then "android:get_usage_stats"
			elif $key=="USE_FULL_SCREEN_INTENT" then "android:use_full_screen_intent"
			elif $key=="SCHEDULE_EXACT_ALARM" then "android:schedule_exact_alarm"
			elif $key=="ACCESS_NOTIFICATION_POLICY" then "android:access_notification_policy"
			else "" end;
		def special_permission($key):
			if $key=="SYSTEM_ALERT_WINDOW" then "android.permission.SYSTEM_ALERT_WINDOW"
			elif $key=="MANAGE_EXTERNAL_STORAGE" then "android.permission.MANAGE_EXTERNAL_STORAGE"
			elif $key=="WRITE_SETTINGS" then "android.permission.WRITE_SETTINGS"
			elif $key=="REQUEST_INSTALL_PACKAGES" then "android.permission.REQUEST_INSTALL_PACKAGES"
			elif $key=="GET_USAGE_STATS" then "android.permission.PACKAGE_USAGE_STATS"
			elif $key=="USE_FULL_SCREEN_INTENT" then "android.permission.USE_FULL_SCREEN_INTENT"
			elif $key=="SCHEDULE_EXACT_ALARM" then "android.permission.SCHEDULE_EXACT_ALARM"
			elif $key=="ACCESS_NOTIFICATION_POLICY" then "android.permission.ACCESS_NOTIFICATION_POLICY"
			else null end;
		def canonical_special_state($key;$v):
			($v // {}) as $x |
			mode_num($x.mode // $x.effectiveMode // $x.packageMode // 3) as $m |
			(($x.op // -1)|tonumber? // -1) as $op |
			{publicName:(($x.publicName // special_public($key))|tostring),
			 manifestPermission:($x.manifestPermission // $x.permission // special_permission($key)),
			 requested:($x.requested // true), supported:($x.supported // ($op >= 0)), op:$op,
			 source:"legacy-migrated", packageMode:(if $x.packageMode==null then $m else mode_num($x.packageMode) end),
			 uidMode:(if $x.uidMode==null then null else mode_num($x.uidMode) end),
			 scope:($x.scope // "package"), mode:$m, modeName:mode_name($m), allowed:($m==0 or $m==4)};
		def legacy_permissions($p):
			[$p|to_entries[]? | select(.key|startswith("android.permission.")) |
			 (pparts(.value)) as $v |
			 {name:.key, granted:($v[0]=="true"), flags:pflag(.value), runtime:true, development:false,
			  appOp:(if ($v|length)>=3 then ($v[1]|tonumber? // -1) else -1 end),
			  appOpMode:(if ($v|length)>=3 then mode_num($v[2]) else 3 end),
			  appOpModeName:mode_name(if ($v|length)>=3 then mode_num($v[2]) else 3 end),
			  packageMode:(if ($v|length)>=3 then mode_num($v[2]) else null end), uidMode:null, scope:"package"}];
		def special_from_permissions($p):
			reduce ($p|to_entries[]?) as $e ({};
				(special_key($e.key; {publicName:$e.key})) as $key |
				if $key=="" then . else
					(pparts($e.value)) as $v |
					(($v[1]|tonumber? // -1)) as $op |
					(mode_num($v[2] // 3)) as $m |
					.[$key]=canonical_special_state($key; {publicName:$e.key,op:$op,mode:$m,packageMode:$m,requested:true,supported:($op>=0)})
				end);
		def normalize_special($raw):
			reduce (($raw // {})|to_entries[]?) as $e ({};
				(special_key($e.key; $e.value)) as $key |
				if $key=="" then . else .[$key]=canonical_special_state($key;$e.value) end);
		def legacy_battery($b; $bo):
			($b//{}) as $x |
			def opstate($k): (($x[$k]//"")|tostring|split(" ")) as $v |
				if ($v|length)>=2 then (mode_num($v[1])) as $m |
					{supported:true,op:($v[0]|tonumber? // -1),mode:$m,modeName:mode_name($m),packageMode:$m,uidMode:null,scope:"package"}
				else {supported:false,op:-1,mode:3,modeName:"default",packageMode:null,uidMode:null,scope:"none"} end;
			(mode_num($bo)) as $bom |
			{RUN_IN_BACKGROUND:opstate("BATTERY:RUN_IN_BACKGROUND"),
			 RUN_ANY_IN_BACKGROUND:(if ($x|has("BATTERY:RUN_ANY_IN_BACKGROUND")) then opstate("BATTERY:RUN_ANY_IN_BACKGROUND")
				else {supported:($bo!=null and ($bo|tostring)!=""),op:-1,mode:$bom,modeName:mode_name($bom),packageMode:null,uidMode:null,scope:"legacy"} end),
			 deviceidleWhitelist:(((($x["BATTERY:deviceidle_whitelist"] // $x["BATTERY:idle_whitelist"] // $x["BATTERY:doze_whitelist"] // false)|tostring|ascii_downcase)) == "true")};
		def legacy_ops($p;$special;$battery):
			([$special[]? | .op | select(type=="number" and .>=0)] +
			 [$battery[]? | objects | .op | select(type=="number" and .>=0)]) as $handled |
			[$p|to_entries[]? | select((.key|startswith("android:")) or (.key|startswith("EXTRA_OP_"))) |
			 (pparts(.value)) as $v |
			 {publicName:.key,
			  op:(if (.key|startswith("EXTRA_OP_")) then ($v[0]|tonumber? // -1) else ($v[1]|tonumber? // -1) end),
			  mode:(if (.key|startswith("EXTRA_OP_")) then mode_num($v[1]) else mode_num($v[2]) end)} |
			 . as $item | select($item.op>=0 and (($handled|index($item.op))==null)) | $item |
			 .modeName=mode_name(.mode) | .allowed=(.mode==0 or .mode==4) |
			 .packageMode=.mode | .uidMode=null | .scope="package"] | unique_by(.op);
		(.[$entry].app_state // ([.[]|objects|select(.app_state!=null).app_state]|.[0]) // null) as $state |
		if $state != null then
			$state | normalize_appstate_v2 | .schemaVersion=2 | .recordType="snapshot" | .packageName=$pkg
		else
			[.[]|objects] as $objects |
			($objects|map(select(.PackageName==$pkg))|.[0] // $objects[0] // {}) as $meta |
			merged_objects($objects|map(.permissions)) as $p |
			merged_objects($objects|map(.special_access)) as $raw_special |
			merged_objects($objects|map(.battery_settings)) as $battery_raw |
			first_value($objects|map(.battery_opt)) as $battery_opt |
			first_value($objects|map(.install_diagnostics)) as $install_diag |
			first_value($objects|map(.installer)) as $installer |
			first_value($objects|map(.Ssaid)) as $ssaid |
			((special_from_permissions($p)) * (normalize_special($raw_special))) as $special |
			(legacy_battery($battery_raw;$battery_opt)) as $battery |
			{schemaVersion:2,recordType:"snapshot",packageName:$pkg,userId:0,
			 package:{installer:($installer//$install_diag.installer//$install_diag.installing//null),
			          versionCode:($meta.apk_version//null)},
			 installDiagnostics:($install_diag//{}),
			 permissions:legacy_permissions($p), specialAccess:$special,
			 otherAppOps:legacy_ops($p;$special;$battery), batterySettings:$battery,
			 ssaid:($ssaid//null), sourceFormat:"legacy-app-details-migrated"}
		end |
		select((.permissions|type)=="array" and (.specialAccess|type)=="object" and
		       (.otherAppOps|type)=="array" and (.batterySettings|type)=="object")
	' "$_json" > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	[[ -s $_out ]]
}

restore_appstate() {
	echoRgb "加入統一AppState恢復佇列"
	local _restore_appstate_autoflush=0 _record="$TMPDIR/.appstate_record_$$"
	if [[ ${_batch_appstate_mode:-0} != 1 ]]; then
		_restore_appstate_autoflush=1
		_batch_appstate_mode=1
		: > "$TMPDIR/.batch_appstate_ndjson" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	fi
	if ! _appstate_record_from_app_details "$app_details" "$name1" "$name2" "$_record"; then
		echoRgb "$name1 AppState資料缺失或無法轉換，略過狀態恢復" "0"
		_speed_debug_log "RESTORE_APPSTATE_QUEUE_FAIL package=${name2:-} source=$app_details"
		rm -f "$_record" 2>/dev/null
		[[ $_restore_appstate_autoflush = 1 ]] && _batch_appstate_mode=0
		return 1
	fi
	# 同 package 只保留最後一筆，避免重複恢復。
	if [[ -s $TMPDIR/.batch_appstate_ndjson ]]; then
		jq -c --arg pkg "$name2" 'select((.packageName // "") != $pkg)' "$TMPDIR/.batch_appstate_ndjson" > "$TMPDIR/.batch_appstate_ndjson.tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || : > "$TMPDIR/.batch_appstate_ndjson.tmp"
		cat "$_record" >> "$TMPDIR/.batch_appstate_ndjson.tmp"
		mv -f "$TMPDIR/.batch_appstate_ndjson.tmp" "$TMPDIR/.batch_appstate_ndjson"
	else
		cat "$_record" > "$TMPDIR/.batch_appstate_ndjson"
	fi
	rm -f "$_record" 2>/dev/null
	if [[ $_restore_appstate_autoflush = 1 ]]; then
		flush_batch_appstate
		local _flush_rc=$?
		_batch_appstate_mode=0
		return $_flush_rc
	fi
	return 0
}

# v24.20.14-3 appstate auto chunk：使用者仍可一次恢復 100+ app；內部只切 dex stdin 批次。
_appstate_chunk_size() {
	local _v="$1" _fallback="$2"
	case $_v in ''|*[!0-9]*) echo "$_fallback" ;; 0) echo "$_fallback" ;; *) echo "$_v" ;; esac
}

_appstate_debug_reset_aggregate() {
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d "$SPEED_DEBUG_RUN_DIR" ]] || return 0
	: > "$SPEED_DEBUG_RUN_DIR/app_state_stdin.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	: > "$SPEED_DEBUG_RUN_DIR/app_state_output.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	: > "$SPEED_DEBUG_RUN_DIR/verify_app_state_stdin.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	: > "$SPEED_DEBUG_RUN_DIR/verify_app_state_output.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_appstate_debug_append_file() {
	local _dst="$1" _src="$2" _label="$3"
	[[ -f $_src ]] || return 0
	{
		echo
		echo "===== ${_label} BEGIN ====="
		cat "$_src" 2>/dev/null
		echo "===== ${_label} END ====="
	} >> "$_dst" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_appstate_debug_save_chunk() {
	local _kind="$1" _idx="$2" _in="$3" _out="$4" _tag
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d "$SPEED_DEBUG_RUN_DIR" ]] || return 0
	_tag="$(printf '%03d' "$_idx")"
	case $_kind in
		restore)
			_appstate_debug_append_file "$SPEED_DEBUG_RUN_DIR/app_state_stdin.log" "$_in" "restore chunk ${_tag} stdin"
			_appstate_debug_append_file "$SPEED_DEBUG_RUN_DIR/app_state_output.log" "$_out" "restore chunk ${_tag} output"
			;;
		verify)
			_appstate_debug_append_file "$SPEED_DEBUG_RUN_DIR/verify_app_state_stdin.log" "$_in" "verify chunk ${_tag} stdin"
			_appstate_debug_append_file "$SPEED_DEBUG_RUN_DIR/verify_app_state_output.log" "$_out" "verify chunk ${_tag} output"
			;;
	esac
}

# 批量沖刷：同一份 canonical AppState NDJSON 依序交給 restore 與 verify；AppOps reset、特殊存取、電池與 SSAID 均由引擎內部處理。
flush_batch_appstate() {
	local _queue="$TMPDIR/.batch_appstate_ndjson" _count _chunk_size _offset=0 _idx=0
	local _restore_ok=0 _restore_partial=0 _restore_failed=0
	local _verify_ok=0 _verify_mismatch=0 _verify_failed=0
	[[ -s $_queue ]] || return 0
	_appstate_capabilities_check || {
		echoRgb "AppState能力契約不符，已中止狀態恢復" "0"
		return 1
	}
	_count="$(awk 'NF{n++} END{print n+0}' "$_queue" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	[[ ${_count:-0} -gt 0 ]] || return 0
	_chunk_size="$(_appstate_chunk_size "${APPSTATE_RESTORE_CHUNK_SIZE:-30}" 30)"
	_appstate_debug_reset_aggregate
	: > "$TMPDIR/.appstate_restore_issues" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	: > "$TMPDIR/.appstate_verify_issues" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	while [[ $_offset -lt $_count ]]; do
		_idx=$((_idx+1))
		local _in="$TMPDIR/.appstate_chunk_${_idx}.ndjson"
		local _ro="$TMPDIR/.appstate_restore_${_idx}.ndjson"
		local _vo="$TMPDIR/.appstate_verify_${_idx}.ndjson"
		local _chunk_count
		awk -v off="$_offset" -v size="$_chunk_size" 'NF{n++; if(n>off && n<=off+size) print}' "$_queue" > "$_in" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		[[ -s $_in ]] || break
		_chunk_count="$(awk 'NF{n++} END{print n+0}' "$_in" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		case $_chunk_count in ''|*[!0-9]*) _chunk_count=0 ;; esac

		if _appstate_daemon_call restoreAppStateBatch "$_in" "$_ro" \
				&& jq -s -e 'any(.[]; .recordType=="summary" and .command=="restoreAppStateBatch")' "$_ro" >/dev/null 2>&1; then
			_appstate_debug_save_chunk restore "$_idx" "$_in" "$_ro"
			_restore_ok=$((_restore_ok + $(jq -r 'select(.recordType=="restore" and .result.name=="OK")|1' "$_ro" 2>/dev/null | awk '{n+=$1} END{print n+0}')))
			_restore_partial=$((_restore_partial + $(jq -r 'select(.recordType=="restore" and (.result.name=="PARTIAL" or .result.name=="VERIFY_MISMATCH"))|1' "$_ro" 2>/dev/null | awk '{n+=$1} END{print n+0}')))
			_restore_failed=$((_restore_failed + $(jq -r 'select(.recordType=="restore" and (.result.name!="OK" and .result.name!="PARTIAL" and .result.name!="VERIFY_MISMATCH"))|1' "$_ro" 2>/dev/null | awk '{n+=$1} END{print n+0}')))
			jq -r 'select(.recordType=="restore" and .result.name!="OK") | "RESTORE\t\(.packageName)\t\(.result.name)\t\(.result.message // \"\")"' "$_ro" 2>/dev/null >> "$TMPDIR/.appstate_restore_issues"
		else
			_restore_failed=$((_restore_failed+_chunk_count))
			_verify_failed=$((_verify_failed+_chunk_count))
			printf 'RESTORE\tchunk_%s\tTRANSPORT_OR_PROTOCOL_FAIL\tcode=%s name=%s packages=%s\n' \
				"$_idx" "${_APPSTATE_RESULT_CODE:-unknown}" "${_APPSTATE_RESULT_NAME:-unknown}" "$_chunk_count" >> "$TMPDIR/.appstate_restore_issues"
			_speed_debug_log "APPSTATE_RESTORE_CHUNK_FAIL idx=$_idx packages=$_chunk_count code=${_APPSTATE_RESULT_CODE:-unknown} name=${_APPSTATE_RESULT_NAME:-unknown}"
			rm -f "$_in" "$_ro" "$_vo" 2>/dev/null
			_offset=$((_offset+_chunk_size))
			continue
		fi

		if _appstate_daemon_call verifyAppStateBatch "$_in" "$_vo" \
				&& jq -s -e 'any(.[]; .recordType=="summary" and .command=="verifyAppStateBatch")' "$_vo" >/dev/null 2>&1; then
			_appstate_debug_save_chunk verify "$_idx" "$_in" "$_vo"
			_verify_ok=$((_verify_ok + $(jq -r 'select(.recordType=="verify" and .result.name=="OK")|1' "$_vo" 2>/dev/null | awk '{n+=$1} END{print n+0}')))
			_verify_mismatch=$((_verify_mismatch + $(jq -r 'select(.recordType=="verify" and .result.name=="VERIFY_MISMATCH")|1' "$_vo" 2>/dev/null | awk '{n+=$1} END{print n+0}')))
			_verify_failed=$((_verify_failed + $(jq -r 'select(.recordType=="verify" and (.result.name!="OK" and .result.name!="VERIFY_MISMATCH"))|1' "$_vo" 2>/dev/null | awk '{n+=$1} END{print n+0}')))
			jq -r 'select(.recordType=="verify" and .result.name!="OK") | "VERIFY\t\(.packageName)\t\(.result.name)\t\((.mismatches // [])|length)"' "$_vo" 2>/dev/null >> "$TMPDIR/.appstate_verify_issues"
		else
			_verify_failed=$((_verify_failed+_chunk_count))
			printf 'VERIFY\tchunk_%s\tTRANSPORT_OR_PROTOCOL_FAIL\tpackages=%s\n' "$_idx" "$_chunk_count" >> "$TMPDIR/.appstate_verify_issues"
			_speed_debug_log "APPSTATE_VERIFY_CHUNK_FAIL idx=$_idx packages=$_chunk_count code=${_APPSTATE_RESULT_CODE:-unknown} name=${_APPSTATE_RESULT_NAME:-unknown}"
		fi
		rm -f "$_in" "$_ro" "$_vo" 2>/dev/null
		_offset=$((_offset+_chunk_size))
	done
	echoRgb "AppState恢復摘要: 成功=$_restore_ok 部分=$_restore_partial 失敗=$_restore_failed" "2"
	if [[ $_verify_mismatch -gt 0 || $_verify_failed -gt 0 ]]; then
		echoRgb "AppState驗證摘要: 一致=$_verify_ok 不一致=$_verify_mismatch 失敗=$_verify_failed（詳情見speed_debug）" "0"
	else
		echoRgb "AppState驗證摘要: 一致=$_verify_ok" "1"
	fi
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d ${SPEED_DEBUG_RUN_DIR:-} ]] && {
		[[ -s $TMPDIR/.appstate_restore_issues ]] && cp -f "$TMPDIR/.appstate_restore_issues" "$SPEED_DEBUG_RUN_DIR/appstate_restore_issues.log" 2>/dev/null
		[[ -s $TMPDIR/.appstate_verify_issues ]] && cp -f "$TMPDIR/.appstate_verify_issues" "$SPEED_DEBUG_RUN_DIR/appstate_verify_issues.log" 2>/dev/null
	}
	rm -f "$_queue" "$TMPDIR/.appstate_restore_issues" "$TMPDIR/.appstate_verify_issues" 2>/dev/null
	[[ $_restore_failed -eq 0 && $_verify_failed -eq 0 && $_verify_mismatch -eq 0 ]]
}

# 取得當前正在前台/後台運行的 app 列表
# 配合「後台應用忽略」設定, 跳過正在運行的 app 不備份/恢復。
# 正式流程優先走 Dex/AppState foregroundStateBatch；啟動自檢(debug)不啟 JVM，避免主選單變慢。
Background_application_list() {
	[[ $activity != false ]] || return 0
	[[ $Background_apps_ignore = true || $1 = debug ]] || return 0
	if [[ $1 != debug && ${_BACKGROUND_STATE_READY:-0} = 1 ]]; then
		return 0
	fi
	unset Backstage
	if [[ $1 != debug ]]; then
		local _pkg_file="$TMPDIR/.foreground_state_pkgs_$$" _out="$TMPDIR/.foreground_state_out_$$" _run _fg _bg
		pm list packages --user "$user" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sed 's/^package://' | awk 'NF==1 && $1 ~ /^[A-Za-z0-9_.-]+$/ {print $1}' > "$_pkg_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		if [[ -s $_pkg_file ]] && _appstate_daemon_call foregroundStateBatch "$_pkg_file" "$_out"; then
			Backstage="$(jq -r 'select(.recordType=="foregroundState" and .active==true) | .packageName' "$_out" 2>/dev/null | awk 'NF && !seen[$0]++')"
			_run="$(printf '%s
' "$Backstage" | awk 'NF{n++} END{print n+0}')"
			_fg="$_run"
			_bg=0
			_speed_debug_log "DEX_FOREGROUND_STATE_SIMPLE_DAEMON active_pkgs=$_run result=${_APPSTATE_RESULT_CODE:-unknown}/${_APPSTATE_RESULT_NAME:-unknown}"
			[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d ${SPEED_DEBUG_RUN_DIR:-} ]] && cp -f "$_out" "$SPEED_DEBUG_RUN_DIR/foreground_state.ndjson" 2>/dev/null
			_BACKGROUND_STATE_READY=1
		fi
		rm -f "$_pkg_file" "$_out" 2>/dev/null
	fi
	if [[ $Backstage = "" ]]; then
		# fallback：保留舊 dumpsys/am stack 路線，避免舊 Dex 或 ROM 限制時功能直接失效。
		Backstage="$(dumpsys activity activities 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk -v uid="$user" '/ActivityRecord\{/{split($4,a,"/"); user=$3; pkg=a[1]; if(user~/^u[0-9]+$/ && pkg!~/\//){sub(/^u/,"",user); if(uid=="" || user==uid) if(!seen[user","pkg]++) print pkg}}')"
		if [[ $Backstage = "" ]]; then
			Backstage="$(am stack list 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk -v uid="$user" '/taskId/&&!/unknown/{split($2,a,"/"); pkg=a[1]; user="unknown"; for(i=1;i<=NF;i++) if($i~/^userId=/){split($i,b,"="); user=b[2]; break} if(uid==""||user==uid) if(!seen[pkg]++) print pkg}')"
		fi
		[[ $Backstage != "" && $1 != debug ]] && _BACKGROUND_STATE_READY=1
	fi
	if [[ $Backstage = "" ]]; then
		echoRgb "獲取當前前台/後台應用失敗" "0"
		unset Backstage
	fi
}
Background_application_list debug
pkgs="$(pm list packages --user "$user" | cut -f2 -d ':' | awk -v pkg="$(echo "$Backstage" | head -1)" '$1 == pkg {print $1}')"
if [[ $pkgs != "" ]]; then
	echoRgb "前台/後台應用獲取成功($pkgs)" "1"
	[[ $(Process_Information "$pkgs") = "" ]] && echoRgb "應用pid獲取失敗" "0" || echoRgb "應用pid獲取成功$(Process_Information "$pkgs")" "1"
else
	echoRgb "前台/後台應用啟動自檢未命中，正式流程將優先使用Dex即時狀態" "2" activity=dex
fi
unset Backstage
# ======================================================
# backup() 主函數
# ======================================================
# 主備份函數 - 對 appList.txt 內所有 app 執行完整備份
# 流程: 讀清單 → 逐個 app → 備份 apk + data + user_de + obb → 保存 canonical AppState
# 結尾備份 wifi、生成 start.sh、設置 REMOTE_TRIGGER=1 觸發遠端上傳
# ============================================================
# SpeedBackup single-file section: sb_60_backup_main_media_stats.sh
# ============================================================
backup() {
	self_test
	if ! _appstate_capabilities_check; then
		echoRgb "Dex/AppState 核心能力不完整或 tools/Dex 版本不匹配，已中止應用備份" "0"
		echoRgb "需要 Dex v2.6.61、AppState AF_UNIX daemon、HiddenApi forceStopPackageBatch daemon bodyfix、runtime UID AppOps、真實 package mode、canonical snapshot/restore/verify、foreground state-simple/list-simple-json + WebDAV daemon opt + buffer v3 + WebDAV hang guard、hot CLI removed、shared daemon bootstrap / sequential guard / Google snapshot、WEBR5、123pan managed direct、daemon hardening/watchdog、Device_List HttpUtil 分片能力" "3"
		_speed_debug_normal_finish_pack 2
		exit 2
	fi
	case $MODDIR in
	/storage/emulated/0/Android/* | /data/media/0/Android/* | /sdcard/Android/*) echoRgb "請勿在$MODDIR內備份" "0" && exit 2 ;;
	esac
	case $Compression_method in
	zstd | Zstd | ZSTD | tar | Tar | TAR) ;;
	*) echoRgb "$Compression_method為不支持的壓縮算法" "0" && exit 2 ;;
	esac
	# 流式上傳路徑快取: 在 Compression_method 還未被 Backup_data() 暫時污染前固定一次
	_BACKUP_DIRNAME_CACHED="$(get_backup_dirname)"
	_prepare_timed prepare_pkg_uid_map
	_prepare_timed prepare_pkg_ver_map
	load_kv_map "$TMPDIR/.pkg_uid" _pu
	load_kv_map "$TMPDIR/.pkg_ver" _pv
	: > "$TMPDIR/.backup_done"
	: > "$TMPDIR/.update_apks"
	: > "$TMPDIR/.add_apks"
	: > "$TMPDIR/.changed_apps"
	: > "$TMPDIR/.listver_changed"
	# 初始化備份變更標記
	backup_has_changes=0
	#校驗選填是否正確
	[[ $Backup_Mode != "" ]] && isBoolean "$Backup_Mode" "Backup_Mode" && Backup_Mode="$nsx" || {
	echoRgb "選擇備份模式\n -音量上備份應用+數據，音量下僅應用不包含數據" "2"
	get_version "應用+數據" "僅應用" && Backup_Mode="$branch"
	}
	if [[ $Backup_Mode = true ]]; then
		if [[ -n $(printf "%s\n" "$blacklist" | awk '!/[#＃]/ && NF') ]]; then
			if [[ $blacklist_mode != "" ]]; then
				isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx"
			else
				echoRgb "選擇黑名單模式\n -音量上不備份，音量下僅備份安裝檔\n -警告! " "2"
				get_version "不備份" "備份安裝檔" && blacklist_mode="$branch"
			fi
		fi
	fi
	if [[ $Backup_Mode = true ]]; then
		[[ $Backup_obb_data != "" ]] && isBoolean "$Backup_obb_data" "Backup_obb_data" && Backup_obb_data="$nsx" || {
		echoRgb "是否備份外部數據 即比如原神的數據包\n -音量上備份，音量下不備份" "2"
		get_version "備份" "不備份" && Backup_obb_data="$branch"
		}
		[[ $Backup_user_data != "" ]] && isBoolean "$Backup_user_data" "Backup_user_data" && Backup_user_data="$nsx" || {
		echoRgb "是否備份使用者數據\n -音量上備份，音量下不備份" "2"
		get_version "備份" "不備份" && Backup_user_data="$branch"
		}
	else
		Backup_user_data="false"
		Backup_obb_data="false"
	fi
	[[ $backup_media != "" ]] && isBoolean "$backup_media" "backup_media" && backup_media="$nsx" || {
	echoRgb "全部應用備份結束後是否備份自定義目錄\n -音量上備份，音量下不備份" "2"
	get_version "備份" "不備份" && backup_media="$branch"
	}
	[[ $setDisplayPowerMode != "" ]] && isBoolean "$setDisplayPowerMode" "setDisplayPowerMode" && setDisplayPowerMode="$nsx" || {
	echoRgb "應用備份開始後關閉螢幕\n -音量上關閉，音量下不關閉" "2"
	get_version "關閉" "不關閉" && setDisplayPowerMode="$branch"
	}
	[[ $Background_apps_ignore != "" ]] && isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx" || {
	echoRgb "存在進程忽略備份\n -音量上忽略，音量下備份" "2"
	get_version "忽略" "備份" && Background_apps_ignore="$branch"
	}
	i=1
	#數據目錄
	if [[ $list_location != "" ]]; then
		if [[ ${list_location:0:1} = / ]]; then
			txt="$list_location"
		else
			txt="$MODDIR/$list_location"
		fi
	else
		txt="$MODDIR/appList.txt"
	fi
	txt_path="$txt"
	[[ ! -f $txt ]] && echoRgb "請執行start.sh獲取應用列表再來備份" "0" && exit 1
	TXT_NAME="${txt##*/}"
	case ${TXT_NAME##*.} in
	txt) ;;
	*) echoRgb "$txt不是腳本讀取格式" "0" && exit 2 ;;
	esac
	sort -u "$txt" -o "$txt" &>/dev/null
	data="$MODDIR"
	hx="本地"
	echoRgb "腳本受到內核機制影響 息屏後IO性能嚴重影響\n -請勿關閉終端或是息屏備份 如需終止腳本\n -請執行start.sh選擇終止腳本即可停止" "3"
	SPEEDBACKUP_DEFER_REMOTE_SETUP=1
	backup_path
	unset SPEEDBACKUP_DEFER_REMOTE_SETUP
	show_conf backup
	remote_stream_early_hard_precheck
	D="1"
	Apk_info="$(pm list packages --user "$user" | cut -f2 -d ':' | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	if [[ $Apk_info != "" ]]; then
		[[ $Apk_info = *"Failure calling service package"* ]] && Apk_info="$(appinfo "user|system" "pkgName" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	else
		Apk_info="$(appinfo "user|system" "pkgName" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
	fi
	[[ $Apk_info = "" ]] && echoRgb "Apk_info變量為空" "0" && exit
	[[ ! -f ${0%/*}/app_details.json ]] && {
	echoRgb "檢查備份列表中是否存在已經卸載應用" "3"
	while read -r ; do
		if [[ $(echo "$REPLY" | sed -E 's/^[ \t]*//; /^[ \t]*[#＃!]/d') != "" ]]; then
			_list_name="${REPLY%% *}"
			_list_pkg="${REPLY#* }"
			_list_pkg="${_list_pkg%% *}"
			if [[ $_list_name != "" && $_list_pkg != "" && $_list_pkg != "$REPLY" ]]; then
				if [[ $(echo "$Apk_info" | awk -v pkg="$_list_pkg" '$1 == pkg {print $1}') != "" ]]; then
					[[ $Tmplist = "" ]] && Tmplist='#不需要備份的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market（忽略安裝包和數據）\n#不需要備份數據的應用請在開頭使用!注釋 比如：!酷安 com.coolapk.market（僅忽略數據）'
					Tmplist="$Tmplist\n$REPLY"
				else
					echoRgb "$REPLY不存在系統，從列表中刪除" "0"
				fi
			fi
		else
			Tmplist="$Tmplist\n$REPLY"
		fi
	done < "$txt"
	}
	[[ $Update_backup = true ]] && {
	echoRgb "檢查備份列表中已經更新應用" "3"
	# 用暫存檔取代 here-string (mksh 不支援 <<<)
	local _upd_tmp="$TMPDIR/.update_check_$$"
	grep -Ev '^[#＃!]' "$txt" | awk '{print $1 ":" $2}' > "$_upd_tmp"
	# 預掃 pkg→version map (若還沒掃過), 取代每 app fork pm
	[[ ! -f $TMPDIR/.pkg_ver ]] && prepare_pkg_ver_map
	while read -r apk; do
		Backup_folder="$Backup/${apk%%:*}"
		app_details="$Backup_folder/app_details.json"
		if [[ -d $Backup_folder ]]; then
			# 讀本地同步副本 (流式模式上傳成功後 cp 到本地, 記錄上次成功備份的版本)
			# 與實機比對才有意義; 遠端快取是給 apk 跳過比對用的, 職責不同
			apk_version="$(jq -r 'try (.[] | select(.apk_version != null).apk_version) catch ""' "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | head -n 1 | tr -d ' \t\r\n')"
			# 從預掃 map 查 versionCode (取代每 app fork pm)
			local _pkg
			_pkg="${apk#*:}"
			apk_version2="$(get_current_apk_version_code "$_pkg")"
			# debug: 比對版本失敗時印出來。map/fallback 仍命中失敗時，不把空值當版本變化，避免誤觸發整批重備 APK。
			if [[ -z $apk_version2 || $apk_version2 = unknown ]]; then
				echoRgb "${apk%%:*} 當前版本讀取失敗，略過版本變化判斷" "0"
				SpeedDebug_log "WARN: update_backup_version_map_miss package=$_pkg oldVersion=$apk_version"
			elif [[ $apk_version != $apk_version2 ]]; then
				echoRgb "$(echo "$apk" | cut -d':' -f1) 版本變化: $apk_version → $apk_version2" "3"
				[[ $Tmplist2 = "" ]] && Tmplist2="${apk/:/ }" || Tmplist2="$Tmplist2\n${apk/:/ }"
				# 記錄包名: 本輪強制重備 apk (遠端 json 可能被失敗輪汙染成新版本號而 apk 仍是舊檔)
				echo "$_pkg" >> "$TMPDIR/.listver_changed"
			fi

		fi
	done < "$_upd_tmp"
	rm -f "$_upd_tmp"
	}
	[[ $Tmplist != ""  ]] && echo "$Tmplist" | sed -e '/^$/d' | sort>"$txt"
	if [[ $Tmplist2 != "" ]]; then
		txt="$(echo "$Tmplist2" | sort)"
	else
		[[ $Update_backup != "" ]] && echoRgb "應用目前無更新" "0" && exit 0
	fi
	if [[ ! -f $txt ]]; then
		[[ $(echo "$txt") != "" ]] && txt="$(echo "$txt" | sed -e '/^$/d')"
	else
		txt="$(grep -Ev '#|＃' "$txt" | sed -e '/^$/d')"
	fi
	r="$(echo "$txt" | awk 'NF != 0 { count++ } END { print count }')"
	[[ -f ${0%/*}/app_details.json ]] && r=1
	[[ $r = "" && ! -f ${0%/*}/app_details.json ]] && echoRgb "$MODDIR_NAME/appList.txt是空的或是包名被注釋備份個鬼\n -檢查是否注釋亦或者執行$MODDIR_NAME/start.sh" "0" && exit 1
	if [[ $Backup_Mode = true ]]; then
		[[ $Backup_user_data = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -Backup_user_data=0將不備份user數據" "0"
		[[ $Backup_obb_data = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -Backup_obb_data=0將不備份外部數據" "0"
	fi
		[[ $backup_media = false ]] && echoRgb "當前$MODDIR_NAME/backup_settings.conf的\n -backup_media=0將不備份自定義資料夾" "0"
		if stream_enabled; then
			# 真流式不建立本地 Backup_zstd_X；但仍需要一份本輪恢復清單。
			# 因此 appList.txt / start.sh / restore_settings.conf 只放 TMPDIR staging，
			# 結束時由 stream_upload_infra() 上傳到遠端根目錄。
			mkdir -p "$TMPDIR/.stream_stage/.infra" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			txt2="$TMPDIR/.stream_stage/.infra/appList.txt"
			STREAM_APPLIST_PATH="$txt2"
		else
			# 首次本地備份時 Backup_zstd_X 尚不存在；必須先建立根目錄，
			# 再寫 appList.txt / tools / start.sh / restore_settings.conf，避免首輪 No such file or directory。
			if [[ ! -d $Backup ]]; then
				mkdir -p "$Backup" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || {
					echoRgb "建立備份目錄失敗: $Backup" "0"
					return 1
				}
			fi
			txt2="$Backup/appList.txt"
			unset STREAM_APPLIST_PATH
		fi
		txt_path2="$txt2"
		[[ ! -f $txt2 ]] && echo "#不需要恢復還原的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market">"$txt2"
		txt2="$(cat "$txt2")"
		if ! stream_enabled; then
			[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
			[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
			[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
			if [[ -d $Backup/tools ]]; then
				find "$Backup/tools" -maxdepth 1 -type f | while read -r; do
					Tools_FILE_NAME="${REPLY##*/}"
					if [[ -f $tools_path/$Tools_FILE_NAME ]]; then
						filesha256="$(sha256sum "$tools_path/$Tools_FILE_NAME" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | cut -d" " -f1)"
						filesha256_1="$(sha256sum "$REPLY" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | cut -d" " -f1)"
						if [[ $filesha256 != $filesha256_1 ]]; then
							cp -r "$tools_path/$Tools_FILE_NAME" "$REPLY"
							echoRgb "更新$REPLY"
						fi
					fi
				done
			fi
			filesize="$(calc_dir_size "$Backup")"
		else
			filesize=0
		fi
	Quantity=0
	#開始循環$txt內的資料進行備份
	#記錄開始時間
	en=118
	osn=0; osj=0; osk=0
	#獲取已經開啟的無障礙
	var="$(settings get secure enabled_accessibility_services 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	#獲取預設鍵盤
	keyboard="$(settings get secure default_input_method 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	Set_screen_pause_seconds on
	[[ $txt != "" ]] && [[ $(echo "$txt" | cut -d' ' -f2 | grep -w "^${keyboard%/*}$") != ${keyboard%/*} ]] && unset keyboard
	if [[ -f ${0%/*}/app_details.json ]]; then
		# 單獨備份模式: 只預掃這一個 app 的權限
		local _single_pkg
		_single_pkg="$(jq -r '.[] | select(.PackageName != null).PackageName' "${0%/*}/app_details.json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		# 單獨備份也走批量同一套預掃/解析邏輯，避免 inline jq 解析差異導致 permissions 漏寫。
		if _prepare_timed prepare_app_state_prescan_batch "$_single_pkg"; then
			:
		else
			echoRgb "AppState snapshot 預掃失敗，已中止單獨應用備份；不回退舊位置性預掃" "0"
			_speed_debug_normal_finish_pack 2
			exit 2
		fi
		backup_finalize_remote_setup_if_deferred
		_prepare_timed prepare_remote_filelist
		_prepare_timed prepare_remote_scripts_map
		_prepare_timed prepare_remote_json_map
		[[ -s $TMPDIR/.pkg_appstate ]] || { echoRgb "AppState snapshot map缺失" "0"; exit 2; }
	else
		if _prepare_timed prepare_app_state_prescan_batch; then
			:
		else
			echoRgb "AppState snapshot 預掃失敗，已中止應用備份；不回退舊位置性預掃" "0"
			_speed_debug_normal_finish_pack 2
			exit 2
		fi
		_prepare_timed prepare_dir_size_map
		load_dir_size_map
		backup_finalize_remote_setup_if_deferred
		_prepare_timed prepare_remote_filelist
		_prepare_timed prepare_remote_scripts_map
		_prepare_timed prepare_remote_json_map
		[[ -s $TMPDIR/.pkg_appstate ]] || { echoRgb "AppState snapshot map缺失" "0"; exit 2; }
	fi
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	notification_progress "101" "$r" 0 "開始備份"
	# 保存本次備份實際使用的清單,供遠端上傳用 (純變數,不寫檔)
	# 子目錄 backup.sh (app_details.json 存在於 0%/*) 只備份單一 app,
	# 上傳時也只該上傳這一個 app 的目錄
	if [[ -n $remote_type ]]; then
		if [[ -f ${0%/*}/app_details.json ]]; then
			# 單獨備份: REMOTE_APPLIST 只設這個 app
			# ${0%/*} 是子目錄路徑, 末段就是 app 名 (例 Chrome)
			_app_dirname="${0%/*}"
			REMOTE_APPLIST="${_app_dirname##*/}"
			unset _app_dirname
		elif [[ -n $txt ]]; then
			REMOTE_APPLIST="$txt"
		fi
	fi
	while [[ $i -le $r ]]; do
		[[ $en -ge 229 ]] && en=118
		unset name1 name2 apk_path apk_path2
		if [[ ! -f ${0%/*}/app_details.json ]]; then
			# 一次 sed 抓行, 用 parameter expansion 拆欄位 (省 3 fork)
			_line="$(echo "$txt" | sed -n "${i}p")"
			name1="${_line%% *}"
			name2="${_line#* }"
			name2="${name2%% *}"
			unset _line
		else
			ChineseName="$(jq -r 'try ((([.[] | objects | select(.PackageName != null)] | length) as $n | if $n > 0 then (to_entries[] | select(.value.PackageName != null).key) else (to_entries[] | select(.key != null).key) end) // "") catch ""' "${0%/*}/app_details.json" | head -n 1)"
			PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "${0%/*}/app_details.json")"
			name1="$ChineseName"
			name2="$PackageName"
		fi
		[[ $name2 = "" || $name1 = "" ]] && echoRgb "警告! appList.txt應用包名獲取失敗，可能修改有問題" "0" && exit 1
		apk_path="$(pm path --user "$user" "$name2" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | cut -f2 -d ':')"
		apk_path2="${apk_path%%$'\n'*}"
		apk_path2="${apk_path2%/*}"
		if [[ -d $apk_path2 ]]; then
			echoRgb "備份第$i/$r個應用 剩下$((r - i))個" "3"
			echoRgb "備份 $name1" "2"
			notification_progress "101" "$r" "$((i - 1))" "備份第$i/$r個應用 剩下$((r - i))個
備份 $name1"
			unset Backup_folder ChineseName PackageName nobackup No_backupdata result apk_version apk_version2  zsize zmediapath Size data_path Ssaid ssaid
			nobackup="false"
			Background_application_list
			if [[ $Backstage != "" ]] && printf '%s
' "$Backstage" | awk -v p="$name2" '$0==p{found=1} END{exit !found}'; then
				echoRgb "$name1存在前台/後台，忽略備份" "0"
				nobackup="true"
			fi
			if [[ $Backup_Mode = true ]]; then
				if [[ $name1 = !* || $name1 = ！* ]]; then
					name1="${name1//!/}"
					name1="${name1//！/}"
					echoRgb "跳過備份所有數據" "0"
					No_backupdata=1
				fi
				if [[ $(echo "$blacklist" | grep -w "^$name2$") = $name2 ]]; then
					if [[ $blacklist_mode = true ]]; then
						echoRgb "黑名單應用跳過備份" "0"
						nobackup="true"
					else
						echoRgb "黑名單應用跳過備份所有數據" "0"
					fi
					No_backupdata=1
				fi
			fi
			Backup_folder="$Backup/$name1"
			app_details="$Backup_folder/app_details.json"
			# 流式模式: 設遠端目標目錄 (鏡像 $name1), 遠端目錄由 _stream_upload 自動建
			# 用 TMPDIR 暫存區取代本機 $Backup (不碰用戶既有本地備份, 結束無需大清理)
			if [[ $remote_stream = 1 && -n $remote_type ]]; then
				_STREAM_DEST="$name1"
				Backup_folder="$TMPDIR/.stream_stage/$name1"
				app_details="$Backup_folder/app_details.json"
				# 每 app 先清空 staging (防上輪殘留), 再無條件以遠端 json 快取為種:
				# 1. 權限/SSAID/installer/版本比對有舊值參照, 無變化正確跳過
				# 2. 本輪只更新部分欄位時, 其餘欄位 (如版本) 不會在上傳時被覆蓋丟失
				rm -rf "$Backup_folder" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				mkdir -p "$Backup_folder" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				[[ -s $TMPDIR/.remote_json/$name1.json ]] && \
				cp "$TMPDIR/.remote_json/$name1.json" "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				# 種子可能是舊版/從未經過新增分支寫入的 json, 缺 PackageName 會導致流式恢復失敗;
				# 在此補上 (不影響其他欄位, 用 jq 確認該 key 存在才寫, 避免空 json 結構錯誤)
				if [[ -s $app_details ]] && [[ "$(jq -r ".[\"$name1\"].PackageName // empty" "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})" = "" ]]; then
					jq_inplace "$app_details" --arg software "$name1" --arg pkg "$name2" \
						'if .[$software] then .[$software].PackageName = $pkg else . end' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				fi
			fi
			# 一次讀取 app_details.json 的 APK／包名／時間／大小欄位；App 狀態只讀 app_state
			# 取代後續每個函數內各自 fork jq
			app_details_read "$app_details"
			if [[ -f $app_details ]]; then
				PackageName="$PKG_NAME"
				[[ $PackageName != $name2 ]] && jq_inplace "$app_details" --arg name2 "$name2" 'walk(if type == "object" and .PackageName then .PackageName = $name2 else . end)'
				echoRgb "上次備份時間$(time_ago "$BACKUP_TIME")"
			fi
			[[ $hx = USB && $PT = "" ]] && echoRgb "隨身碟意外斷開 請檢查穩定性" "0" && exit 1
			starttime2="$(date -u "+%s")"
			[[ $name2 = com.tencent.mobileqq ]] && echoRgb "QQ可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份" "0"
			[[ $name2 = com.tencent.mm ]] && echoRgb "WX可能恢復備份失敗或是丟失聊天記錄，請自行用你信賴的應用備份" "0"
			# 算 apk_path 有幾行 (省 echo|wc -l)
			apk_number=1
			case $apk_path in
			*$'\n'*) apk_number=$(echo "$apk_path" | wc -l) ;;
			esac
			if [[ $nobackup != true ]]; then
				if [[ $apk_number = 1 ]]; then
					Backup_apk "非Split Apk" "3"
				else
					Backup_apk "Split Apk支持備份" "3"
				fi
				# metadata 不應綁死 user data 備份；APK-only / 不備份 user data 也要補寫。
				[[ $result = 0 && -f $app_details ]] && Backup_metadata_once
				if [[ $result = 0 && $No_backupdata = "" ]]; then
					if [[ $Backup_Mode = true ]]; then
						if [[ $Backup_obb_data = true ]]; then
							if [[ $name2 != bin.mt.plus ]]; then
								#備份data數據
								[[ $name1 = Nekogram ]] && rm -rf /data/media/0/Android/data/tw.nekomimi.nekogram/files/Telegram/Telegram\ {Video,Stories,Documents,Images}/{*,.*} 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
								Backup_data "data"
								#備份obb數據
								Backup_data "obb"
								#備份media數據 (部分app如FB Messenger使用 Android/media/<pkg> 存放媒體檔)
								Backup_data "media"
							else
								echoRgb "$name1無法備份" "0"
							fi
						fi
						#備份user數據
						[[ $name2 != bin.mt.plus ]] && {
							[[ $Backup_user_data = true ]] && {
							Backup_data "user"
							Backup_data "user_de"
							}
						}
						[[ $name2 = github.tornaco.android.thanos ]] && Backup_data "thanox" "$(find "/data/system" -name "thanos"* -maxdepth 1 -type d 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
						[[ $name2 = org.frknkrc44.hma_oss ]] && Backup_data "hma" "$(find "/data/misc" -name "hide_my_applist_"* -maxdepth 1 -type d 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
					fi
				fi
				[[ -f $Backup_folder/${name2}.sh ]] && rm -rf "$Backup_folder/${name2}.sh"
			# 入口腳本: 非流式寫本地; 流式查預掃表 (.remote_scripts) 缺才傳 (有就不傳, 省流量)
			if [[ $remote_stream = 1 ]]; then
				if ! awk -v a="$name1" '$0==a{f=1} END{exit !f}' "$TMPDIR/.remote_scripts" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
					mkdir -p "$Backup_folder" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					touch_shell "3" "$Backup_folder/recover.sh"
					touch_shell "1" "$Backup_folder/backup.sh"
					touch_shell "5" "$Backup_folder/upload.sh"
					_stream_upload "$name1/recover.sh" < "$Backup_folder/recover.sh" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					_stream_upload "$name1/backup.sh" < "$Backup_folder/backup.sh" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					_stream_upload "$name1/upload.sh" < "$Backup_folder/upload.sh" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				fi
			else
				[[ ! -f $Backup_folder/recover.sh ]] && touch_shell "3" "$Backup_folder/recover.sh"
				[[ ! -f $Backup_folder/backup.sh ]] && touch_shell "1" "$Backup_folder/backup.sh"
				[[ ! -f $Backup_folder/upload.sh ]] && touch_shell "5" "$Backup_folder/upload.sh"
			fi
			fi
			# App app_details 最終出口：所有 APK/data/keystore/PackageName jq_inplace 寫入後，再統一收斂一次。
			# 這是 370 判斷錯誤後補上的真正 final writer；不能放在 Backup_AppState 中間，否則後續 Size/path 更新仍會覆寫格式。
			if [[ -f $app_details ]] && [[ "$(jq 'length' "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})" != "0" ]]; then
				if _app_details_normalize_restore_profile_file "$app_details"; then
					_speed_debug_log "APPDETAILS_FINAL_PRETTY_OK app=$name1 package=$name2 file=$app_details"
				else
					_speed_debug_log "APPDETAILS_FINAL_PRETTY_FAIL app=$name1 package=$name2 file=$app_details"
				fi
			fi
			# 備份全部跳過時清理空的 app_details.json 殘留
			[[ -f $app_details ]] && [[ "$(jq 'length' "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})" = "0" ]] && rm -f "$app_details"
			endtime 2 "$name1 備份" "3"
			# 流式: 數據 tar 已在壓縮時直接流到遠端, 此處補傳 app_details.json
			# 只在本輪該 app 有變更 (.changed_apps) 時上傳, 全跳過則遠端 json 本就最新
			# 該 app 本輪有任一流式上傳失敗 → 不傳 json (缺 json 下輪必整個重備, 避免壞數據被增量跳過殘留)
			if [[ -s "$TMPDIR/.stream_failed" ]] && awk -v n="$name1" '$0==n{f=1} END{exit !f}' "$TMPDIR/.stream_failed" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
				echoRgb "$name1 本輪有上傳失敗, 不更新遠端 json (下次將重新備份此應用)" "0"
			elif [[ $remote_stream = 1 && -n $remote_type && -f $app_details ]] && \
				awk -v n="$name1" '$0==n{f=1} END{exit !f}' "$TMPDIR/.changed_apps" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
				# 防線: staging 未以快取為種 (此 app 無 .remote_json 快取) 時,
				# 先抓遠端現有 json 合併, 避免部分欄位覆蓋掉遠端完整 json (版本等丟失)
				if [[ ! -s $TMPDIR/.remote_json/$name1.json ]]; then
					_mergetmp="$TMPDIR/.merge_remote_$$"
					if _remote_appdetails_filelist_absent "$name1/app_details.json"; then
						case $remote_type in
						smb) _speed_debug_log "SMB_MERGE_REMOTE_APPDETAILS_LIST_MISS app=$name1 rel=$name1/app_details.json" ;;
						*) _speed_debug_log "WEBDAV_MERGE_REMOTE_APPDETAILS_LIST_MISS app=$name1 rel=$name1/app_details.json" ;;
						esac
					elif remote_download_single_file "$name1/app_details.json" "$_mergetmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && \
						[[ "$(head -c 1 "$_mergetmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})" = "{" ]]; then
						if jq -s '.[0] * .[1]' "$_mergetmp" "$app_details" > "$_mergetmp.out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && \
							[[ -s $_mergetmp.out ]]; then
							cat "$_mergetmp.out" > "$app_details"
						fi
					fi
					rm -f "$_mergetmp" "$_mergetmp.out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				fi
				# stream 上傳前最後收斂一次，因為上面的遠端 merge 可能重新改寫 app_details。
				_app_details_normalize_restore_profile_file "$app_details" || _speed_debug_log "APPDETAILS_STREAM_FINAL_PRETTY_FAIL app=$name1 package=$name2 file=$app_details"
				if _stream_upload "$name1/app_details.json" < "$app_details"; then
					echoRgb "app_details.json 已上傳遠端" "1"
				else
					echoRgb "app_details.json 上傳失敗" "0"
				fi
			fi
			# 邊備份邊上傳：每個應用備份完立即上傳遠端，然後刪除本機檔案節省空間
			# 流式模式不走此路徑 (數據已流式傳走, 無本機 tar 可上傳, json 上面已傳)
			if [[ $remote_stream = 1 ]]; then
				:
			elif [[ $remote_upload_per_app = 1 && -n $remote_type ]]; then
				# 有備份變更 → 上傳
				if awk -v n="$name1" 'BEGIN{f=1} $0==n{f=0} END{exit f}' "$TMPDIR/.changed_apps" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
					per_app_upload_and_cleanup "$name1"
				else
					# 本地無變更，但遠端可能沒有備份 → 檢查遠端 app_details.json
					_remote_has_backup=0
					_remote_check_file="$TMPDIR/.remote_check_$$"
					if remote_download_single_file "${name1}/app_details.json" "$_remote_check_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
						[[ -s $_remote_check_file ]] && _remote_has_backup=1
					fi
					rm -f "$_remote_check_file"
					if [[ $_remote_has_backup = 0 ]]; then
						echoRgb "遠端無備份，上傳到遠端" "2"
						per_app_upload_and_cleanup "$name1"
					else
						echoRgb "無備份變更，跳過上傳" "2"
					fi
				fi
			fi
			lxj="$(echo "$Occupation_status" | awk '{print $3}' | sed 's/%//g')"
			echoRgb "完成$(safe_percent "$i" "$r")% $(progress_bar $(safe_percent "$i" "$r"))$(_progress_local_storage_suffix)" "3"
			notification_progress "101" "$r" "$i" "備份進度 $i/$r $(safe_percent "$i" "$r")%"
			rgb_d="$rgb_a"
			rgb_a=188
			echoRgb "_________________$(endtime 1 "已經")___________________"
			rgb_a="$rgb_d"
		else
			echoRgb "$name1[$name2] 不在安裝列表，備份個寂寞？" "0"
		fi
		if [[ $i = $r ]]; then
			endtime 1 "應用備份" "3"
			#設置無障礙開關
			if [[ $var != "" ]]; then
				if [[ $var != null ]]; then
					settings put secure enabled_accessibility_services "$var" &>/dev/null
					echo_log "設置無障礙"
					settings put secure accessibility_enabled 1 &>/dev/null
					echo_log "打開無障礙開關"
				fi
			fi
			#設置鍵盤
			if [[ $keyboard != "" ]]; then
				ime enable "$keyboard" &>/dev/null
				ime set "$keyboard" &>/dev/null
				settings put secure default_input_method "$keyboard" &>/dev/null
				echo_log "設置鍵盤$(appinfo2 "${keyboard%/*}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
			fi
			# 某些流程/並發 trap 可能已清掉暫存清單；不存在時視為空，避免 stderr.log 出現 cat: No such file。
			if [[ -f "$TMPDIR/.update_apks" ]]; then update_apk2="$(cat "$TMPDIR/.update_apks" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"; else update_apk2=""; fi
			if [[ -f "$TMPDIR/.add_apks" ]]; then add_app2="$(cat "$TMPDIR/.add_apks" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"; else add_app2=""; fi
			update_apk2="${update_apk2:=" -暫無更新"}"
			add_app2="${add_app2:=" -暫無更新"}"
			echoRgb "\n -已更新的apk=\"$osn\"\n -已新增的備份=\"$osk\"\n -apk版本號無變化=\"$osj\"\n -下列為版本號已變更的應用\n$update_apk2\n -新增的備份....\n$add_app2" "3"
			notification_progress "101" "$r" "$r" "app備份完成 $(endtime 1 "應用備份" "3")"
			# 把 backup_done 暫存檔的新項目合併進 txt_path2 (保留舊內容, 用 sort -u 去重)
			if [[ -s $TMPDIR/.backup_done ]]; then
				if [[ -f $txt_path2 ]]; then
					cat "$txt_path2" "$TMPDIR/.backup_done" | sort -u | sed '/^$/d' > "$txt_path2.new"
					mv "$txt_path2.new" "$txt_path2"
				else
					sort -u "$TMPDIR/.backup_done" | sed '/^$/d' > "$txt_path2"
				fi
			fi
			# 清掉備份用的暫存檔
			rm -f "$TMPDIR/.backup_done" "$TMPDIR/.update_apks" "$TMPDIR/.add_apks" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			if [[ $backup_media = true && ! -f ${0%/*}/app_details.json ]]; then
				A=1
				B="$(printf "%s\n" "$Custom_path" | awk '!/[#＃]/ && NF{count++} END{print count}')"
				if [[ $B != "" ]]; then
					echoRgb "備份結束，備份多媒體" "1"
					notification_progress "102" "$B" 0 "Media備份開始"
					starttime1="$(date -u "+%s")"
					Backup_folder="$Backup/Media"
					app_details="$Backup_folder/app_details.json"
					mediatxt="$Backup/mediaList.txt"
					if [[ $remote_stream = 1 && -n $remote_type ]]; then
						_STREAM_DEST="Media"
						Backup_folder="$TMPDIR/.stream_stage/Media"
						app_details="$Backup_folder/app_details.json"
						mediatxt="$TMPDIR/.stream_stage/mediaList.txt"
						mkdir -p "$Backup_folder" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					fi
					# 延遲建立: 只有實際備份了至少一個資料夾才建立 (避免空殼)
					_media_created=0
					_ensure_media_dirs() {
						[[ $_media_created = 1 ]] && return
						if [[ $remote_stream = 1 && -n $remote_type ]]; then
							[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
						else
							[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
							[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
						fi
						[[ ! -f $app_details ]] && echo "{\n}">"$app_details"
						[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$mediatxt"
						_media_created=1
					}
					echo "$Custom_path" | sed -e '/^#/d; /^$/d; s/\/$//' > "$TMPDIR/.media_custom_paths"
					while read -r; do
						echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
						notification_progress "102" "$B" "$((A - 1))" "備份第$A/$B個資料夾 剩下$((B - A))個"
						starttime2="$(date -u "+%s")"
						if [[ ${REPLY##*/} = adb ]]; then
							if [[ $ksu != ksu ]]; then
								echoRgb "Magisk adb"
								_ensure_media_dirs
								Backup_data "${REPLY##*/}" "$REPLY"
							else
								echoRgb "KernelSU adb不支持備份" "0"
								Set_back_0
							fi
						else
							_ensure_media_dirs
							Backup_data "${REPLY##*/}" "$REPLY"
						fi
						endtime 2 "${REPLY##*/}備份" "1"
						echoRgb "完成$(safe_percent "$A" "$B")% $(progress_bar $(safe_percent "$A" "$B"))$(_progress_local_storage_suffix)" "2"
						notification_progress "102" "$B" "$A" "Media備份進度 $A/$B $(safe_percent "$A" "$B")%"
						rgb_d="$rgb_a"
						rgb_a=188
						echoRgb "_________________$(endtime 1 "已經")___________________"
						rgb_a="$rgb_d" && let A++
					done < "$TMPDIR/.media_custom_paths"
					rm -f "$TMPDIR/.media_custom_paths"
					# 收尾: 無實際備份檔則清空殼
					# 流式模式: .tar 壓縮完即上傳, 本機不會留 .tar 檔 (設計如此), 改用 _media_created 旗標判斷
					if [[ $remote_stream = 1 && -n $remote_type ]]; then
						if [[ $_media_created != 1 ]]; then
							echoRgb "Media 無實際備份內容, 清除 mediaList.txt" "0"
							rm -rf "$Backup_folder" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
							[[ -f $mediatxt ]] && [[ ! -s $mediatxt || $(grep -vc "^#" "$mediatxt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) = 0 ]] && rm -f "$mediatxt"
						else
							[[ $remote_stream != 1 ]] && echoRgb "目錄↓↓↓\n -$Backup_folder"
							REMOTE_UPLOAD_MEDIA=1
							# 只有 app_details 真的有實際內容(非初始空殼)才上傳, 避免「全部資料夾無變化跳過」
							# 時, 本地空殼覆蓋掉遠端原本正確的版本
							if [[ -f $app_details ]] && jq -e 'length > 0' "$app_details" >/dev/null 2>&1; then
								_stream_upload "Media/app_details.json" < "$app_details"
								[[ -f $mediatxt ]] && _stream_upload "mediaList.txt" < "$mediatxt"
								echoRgb "Media 清單已上傳遠端" "1"
							else
								echoRgb "Media 本輪全部資料夾無變化, 跳過json上傳(避免覆蓋遠端正確版本)" "2"
							fi
						fi
					elif [[ -d $Backup_folder ]] && ! find "$Backup_folder" -maxdepth 1 -name "*.tar*" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -q .; then
						echoRgb "Media 無實際備份內容, 清除空目錄與 mediaList.txt" "0"
						rm -rf "$Backup_folder"
						[[ -f $mediatxt ]] && [[ ! -s $mediatxt || $(grep -vc "^#" "$mediatxt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) = 0 ]] && rm -f "$mediatxt"
					else
						echoRgb "目錄↓↓↓\n -$Backup_folder"
						[[ -n $remote_type ]] && REMOTE_UPLOAD_MEDIA=1
					fi
					notification_progress "102" "$B" "$B" "Media備份完成 $(endtime 1 "自定義備份")"
					endtime 1 "自定義備份"
				else
					echoRgb "自定義路徑為空 無法備份" "0"
				fi
			fi
		fi
		unset _restore_force_play_session _restore_force_play_marker
		let i++ en++ nskg++
	done
	# 流式模式: wifi 也存 TMPDIR 暫存區 (不碰本地 $Backup)
	if [[ $remote_stream = 1 && -n $remote_type ]]; then
		backup_wifi "$TMPDIR/.stream_stage/wifi"
	else
		backup_wifi "$Backup/wifi"
	fi
	[[ -n $remote_type ]] && REMOTE_UPLOAD_WIFI=1
	Set_screen_pause_seconds off
	[[ $user != 0 ]] && am stop-user "$user" >/dev/null 2>&1
	# 流式模式: 本地無備份檔 (數據在遠端), 跳過本地大小統計; 遠端統計在 remote_cleanup 結尾顯示
	[[ $remote_stream != 1 ]] && Calculate_size "$Backup"
	_stream_failed_report
	echoRgb "批量備份完成"
	echoRgb "備份結束時間$(date +"%Y-%m-%d %H:%M:%S")"
	starttime1="$TIME"
	endtime 1 "批量備份開始到結束"
	notification_progress "105" 100 100 "備份完成 $(endtime 1 "批量備份開始到結束")"
	verify_backup_manifest
	[[ -f $txt_path ]] && chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt_path"
	[[ -f $txt_path2 ]] && chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$txt_path2"
	# 備份完成後針對本次有變動的應用做 json 健全度檢查 (結構+欄位一併驗證)
	# 流式模式: json 在遠端 (本地 staging 已刪), 跳過本地驗證 (上傳時已即時驗證)。
	# 遠端非流式且本輪無實際備份變更時，本地 app_details 可能只補到權限/通知等增量欄位；
	# 此時應以上傳後遠端 app_details 驗證為準，避免誤報缺 PackageName/apk_version。
	local _skip_local_json_health=0
	if [[ -n $remote_type && $remote_stream != 1 && ${backup_has_changes:-0} = 0 ]]; then
		_skip_local_json_health=1
		_speed_debug_log "POST_JSON_LOCAL_HEALTH_SKIP reason=remote_nonstream_no_payload_change"
	fi
	if [[ $remote_stream != 1 && $_skip_local_json_health != 1 && -s $TMPDIR/.changed_apps ]]; then
		echoRgb "—————— 備份後 JSON 結構驗證 ——————" "3"
		local _jchk_sorted="$TMPDIR/.post_json_apps"
		sort -u "$TMPDIR/.changed_apps" > "$_jchk_sorted"
		local _jchk_total _jchk_i=1
		_jchk_total="$(wc -l < "$_jchk_sorted")"
		while read -r _japp; do
			local _jf="$Backup/$_japp/app_details.json"
			echoRgb "[$_jchk_i/$_jchk_total] $_japp" "3"
			_json_health_check "$_jf" "$_japp"
			let _jchk_i++
		done < "$_jchk_sorted"
		echoRgb "檢查完成 $((_jchk_i-1))/$_jchk_total" "1"
		rm -f "$_jchk_sorted"
	fi
	_json_health_report
	REMOTE_TRIGGER=1
	# subshell 環境下 trap EXIT 在主 shell 不會觸發, 這裡直接呼叫
	remote_cleanup
	if ! cleanup_tmpdir_contents; then
		_speed_debug_pack 1
		exit 1
	fi
	# 正常備份完成點主動建立 final 包並刪除 run_xxx。
	# 仍會先建 snapshot；若 EXIT trap 在單獨入口 / pipeline subshell 未觸發，也不會留下 run 目錄。
	_speed_debug_normal_finish_pack 0
	exit 0
}
# 增量備份: 只備份版本號有更新的 app
# 對照 app_details.json 內舊版本, 沒變動的跳過
backup_update_apk() {
	Update_backup='true'
	backup
}
# 重新生成應用列表的 app 名稱欄位 (恢復模式選單用)
dumpname() {
	get_name "Apkname"
}
# 轉換 app 資料夾名稱 (舊格式 → 新格式)
convert() {
	get_name "convert"
}
# 對整個備份目錄做壓縮檔完整性檢查 (Check_archive 的批次入口)
check_file() {
	Check_archive "$MODDIR"
}
# 驗證所有 app_details.json 結構完整性 (jq 解析)
# 主選單「JSON結構檢查」呼叫
Check_json() {
	starttime1="$(date -u "+%s")"
	local error_log="$TMPDIR/json_error_log"
	rm -rf "$error_log"
	local r i=1
	r="$(find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | wc -l)"
	[[ $r -eq 0 ]] && { echoRgb "找不到任何 app_details.json" "0"; return; }
	find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sort | while read -r; do
		local dir="${REPLY%/*}"
		echoRgb "檢查第$i/$r個 剩下$((r - i))個" "3"
		echoRgb "檢查:${dir##*/}"
		if jq empty "$REPLY" >/dev/null 2>&1; then
			echoRgb "JSON結構正常" "1"
		else
			echoRgb "JSON結構損壞或格式錯誤" "0"
			echo "$REPLY">>"$error_log"
		fi
		echoRgb "$(safe_percent "$i" "$r")% $(progress_bar $(safe_percent "$i" "$r"))"
		let i++
	done
	endtime 1
	if [[ -f $error_log ]]; then
		echoRgb "以下 JSON 檔損壞:\n $(cat "$error_log")" "0"
	else
		echoRgb "恭喜~~全數 JSON 結構正常" "1"
	fi
	rm -rf "$error_log"
}

# app_details.json 重新生成更新：像正常備份 metadata 一樣用目前 Dex AppState 重新產生新 JSON。
# 安全契約：舊 JSON 只作為「目標識別 + 保護欄位來源」，不拿舊 permissions/appops 結構轉換。
# 不重新計算、不覆蓋 Size / Backup time / apk_version / versionCode；不重打包任何 payload。
_json_refresh_protected_signature() {
	local _file="$1"
	# 只鎖定「備份判斷用」欄位：root Backup time 與 app entry 直層 Size/版本欄位。
	# 不掃整份 JSON 的所有 versionCode，避免新 Dex AppState 內的 package/installDiagnostics
	# versionCode 被誤判成舊備份 APK 版本遭更新。
	jq -c '
		. as $root |
		def pick_entry($o):
			reduce ["Size","size","apk_size","data_size","obb_size","media_size","origin_size","apk_version","versionCode"][] as $k
			({}; if (($o|type)=="object" and ($o|has($k))) then .[$k]=$o[$k] else . end);
		def is_payload_entry($o):
			(($o|type)=="object") and (
				($o|has("Size")) or ($o|has("size")) or ($o|has("path")) or ($o|has("keystore")) or
				($o|has("apk_size")) or ($o|has("data_size")) or ($o|has("obb_size")) or
				($o|has("media_size")) or ($o|has("origin_size"))
			);
		def backup_entries:
			to_entries[] |
			select(.value|type=="object") |
			select(.key != "Backup time") |
			select(.value.PackageName != null or .value.app_state.packageName != null) |
			{key:.key, packageName:(.value.PackageName // .value.app_state.packageName // ""), protected:(pick_entry(.value) + (if ((.value.app_state.ssaid // .value.Ssaid // null) != null) then {ssaid:(.value.app_state.ssaid // .value.Ssaid)} else {} end))};
		def payload_entries:
			to_entries[] |
			select(.value|type=="object") |
			select(.key != "Backup time") |
			select((.value.PackageName == null) and (.value.app_state.packageName == null)) |
			select(is_payload_entry(.value)) |
			{key:.key, protected:pick_entry(.value)};
		{backup_time:($root["Backup time"] // null), entries:[backup_entries], payloads:[payload_entries]}
	' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}
_json_refresh_entry_pkg() {
	local _file="$1"
	jq -r 'try (to_entries[] |
		select(.value|type=="object") |
		select(.key != "Backup time") |
		select(.value.PackageName != null or .value.app_state.packageName != null) |
		[.key, (.value.PackageName // .value.app_state.packageName // "")] | @tsv) catch empty' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | head -n 1
}
_json_refresh_scan_root() {
	local _scan_dir
	if [[ $Output_path != "" ]]; then
		local _op="$Output_path"
		[[ ${_op: -1} = / ]] && _op="${_op%?}"
		if [[ ${_op:0:1} != / ]]; then
			_scan_dir="$MODDIR/$_op/$(get_backup_dirname)"
		else
			_scan_dir="$_op/$(get_backup_dirname)"
		fi
	else
		_scan_dir="$MODDIR/$(get_backup_dirname)"
	fi
	[[ ! -d $_scan_dir ]] && _scan_dir="$MODDIR"
	printf '%s\n' "$_scan_dir"
}
_json_refresh_collect_local_pkgs() {
	local _root="$1" _tmp="$2" _line _pkg
	: > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	find "$_root" -maxdepth 2 -name "app_details.json" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _jf; do
		_line="$(_json_refresh_entry_pkg "$_jf")"
		_pkg="$(printf '%s\n' "$_line" | awk -F'\t' '{print $2}')"
		[[ -n $_pkg ]] && printf '%s\n' "$_pkg"
	done | sort -u > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}
_json_refresh_prescan_pkgs() {
	local _pkg_file="$1" _pkgs
	[[ -s $_pkg_file ]] || return 1
	_pkgs="$(paste -sd' ' "$_pkg_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	[[ -n $_pkgs ]] || return 1
	prepare_app_state_prescan_batch $_pkgs >/dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}
_json_refresh_regenerate_one_file() {
	local _file="$1" _label="$2" _tmp _state_tmp _out _line _entry _pkg _state _old_sig _new_sig
	[[ -s $_file ]] || { echoRgb "跳過空 JSON: $_label" "0"; return 1; }
	jq -e . "$_file" >/dev/null 2>&1 || { echoRgb "跳過損壞 JSON: $_label" "0"; return 1; }
	_line="$(_json_refresh_entry_pkg "$_file")"
	_entry="$(printf '%s\n' "$_line" | awk -F'\t' '{print $1}')"
	_pkg="$(printf '%s\n' "$_line" | awk -F'\t' '{print $2}')"
	[[ -n $_entry && -n $_pkg ]] || { echoRgb "跳過無 PackageName 的 JSON: $_label" "0"; return 1; }
	_tmp="$TMPDIR/.json_regen_${$}_$RANDOM"
	_state_tmp="$_tmp.state"
	_out="$_tmp.out"
	_old_sig="$(_json_refresh_protected_signature "$_file")"
	_state="$(_kv_file_get "$TMPDIR/.pkg_appstate" "$_pkg")"
	if ! printf '%s\n' "$_state" | jq -e 'type=="object" and .schemaVersion==2 and .recordType=="snapshot"' >/dev/null 2>&1; then
		rm -f "$_tmp"* 2>/dev/null
		echoRgb "跳過: $_label ($_pkg) 目前裝置無法產生 Dex AppState 快照" "0"
		_speed_debug_log "JSON_REGENERATE_SKIP_NO_DEX_STATE label=$_label package=$_pkg file=$_file"
		return 1
	fi
	_state="$(printf '%s\n' "$_state" | _appstate_persist_compact)"
	if [[ -z $_state ]] || ! printf '%s\n' "$_state" | jq -e 'type=="object" and .schemaVersion==2 and .recordType=="snapshot"' >/dev/null 2>&1; then
		rm -f "$_tmp"* 2>/dev/null
		echoRgb "跳過: $_label ($_pkg) AppState持久化裁剪失敗" "0"
		_speed_debug_log "JSON_REGENERATE_SKIP_COMPACT_FAILED label=$_label package=$_pkg file=$_file"
		return 1
	fi
	printf '%s\n' "$_state" > "$_state_tmp"
	# 重新生成新 JSON，只把必要保護欄位從舊 JSON 疊回。
	# 這不是舊 schema 轉換；舊 permissions/appops/special_access 等不會被沿用。
	# data/obb/media/user_de 等 payload entry 沒有 PackageName/app_state，但其 Size 是增量判斷依據，必須保留。
	jq --arg e "$_entry" --arg p "$_pkg" --slurpfile state "$_state_tmp" '
		. as $old |
		($old[$e] // {}) as $oe |
		def pick_entry($o):
			reduce ["Size","size","apk_size","data_size","obb_size","media_size","origin_size","path","keystore","apk_version","versionCode"][] as $k
			({}; if (($o|type)=="object" and ($o|has($k))) then .[$k]=$o[$k] else . end);
		def is_payload_entry($o):
			(($o|type)=="object") and (
				($o|has("Size")) or ($o|has("size")) or ($o|has("path")) or ($o|has("keystore")) or
				($o|has("apk_size")) or ($o|has("data_size")) or ($o|has("obb_size")) or
				($o|has("media_size")) or ($o|has("origin_size"))
			);
		def old_ssaid($o): ($o.app_state.ssaid // $o.Ssaid // null);
		def preserve_ssaid($state; $old_entry):
			if (old_ssaid($old_entry) != null and (old_ssaid($old_entry)|tostring) != "" and (old_ssaid($old_entry)|tostring) != "null")
			then ($state | .ssaid = old_ssaid($old_entry))
			else ($state | del(.ssaid)) end;
		({} + (if ($old|has("Backup time")) then {"Backup time": $old["Backup time"]} else {} end)) |
		reduce ($old|to_entries[]) as $it (.;
			if ($it.key == "Backup time" or $it.key == $e) then .
			elif is_payload_entry($it.value) then .[$it.key] = pick_entry($it.value)
			else . end) |
		.[$e] = (
			pick_entry($oe) +
			{
				PackageName: ($oe.PackageName // $p),
				app_state: preserve_ssaid($state[0]; $oe)
			}
		)
	' "$_file" > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || { rm -f "$_tmp"* 2>/dev/null; echoRgb "重新生成失敗: $_label" "0"; return 1; }
	if ! _app_details_normalize_restore_profile_file "$_out"; then
		rm -f "$_tmp"* 2>/dev/null
		echoRgb "重新生成 canonical profile 失敗: $_label" "0"
		_speed_debug_log "JSON_REGENERATE_CANONICAL_PROFILE_FAIL label=$_label package=$_pkg file=$_file"
		return 1
	fi
	_new_sig="$(_json_refresh_protected_signature "$_out")"
	if [[ $_old_sig != "$_new_sig" ]]; then
		rm -f "$_tmp"* 2>/dev/null
		echoRgb "安全中止: $_label 的 Size/apk版本/備份時間被改動，未覆蓋" "0"
		_speed_debug_log "JSON_REGENERATE_PROTECT_GUARD_FAIL label=$_label package=$_pkg file=$_file"
		return 1
	fi
	# 373 起 _json_cat_replace() 內部已在 TMPDIR 建立回復備份；
	# 不再把 app_details.json.pre360.bak 留在備份目錄。
	rm -f "$_file.pre360.bak" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_json_cat_replace "$_out" "$_file" || { rm -f "$_tmp"* 2>/dev/null; echoRgb "覆蓋失敗: $_label" "0"; return 1; }
	rm -f "$_file.pre360.bak" "$_tmp"* 2>/dev/null
	_speed_debug_log "JSON_REGENERATE_OK label=$_label entry=$_entry package=$_pkg protected_preserved=1 ssaid_preserved=1 source=current_dex_appstate profile=canonical_restore_profile"
	echoRgb "重生JSON: $_label ($_pkg, Size/apk版本/備份時間/SSAID未更新)" "1"
	return 0
}
Json_refresh_local() {
	starttime1="$(date -u "+%s")"
	local _root _pkgs _jsons _total _ok=0 _fail=0 _i=0 _label
	_root="$(_json_refresh_scan_root)"
	_jsons="$TMPDIR/.json_regen_files_$$"
	_pkgs="$TMPDIR/.json_regen_pkgs_$$"
	find "$_root" -maxdepth 2 -name "app_details.json" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sort > "$_jsons"
	_total="$(grep -vc '^$' "$_jsons" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	[[ $_total = 0 ]] && { echoRgb "找不到本地 app_details.json (搜尋: $_root)" "0"; rm -f "$_jsons" "$_pkgs"; return 1; }
	_json_refresh_collect_local_pkgs "$_root" "$_pkgs"
	_json_refresh_prescan_pkgs "$_pkgs" || { echoRgb "Dex AppState預掃不可用，無法重新生成 JSON" "0"; rm -f "$_jsons" "$_pkgs"; return 1; }
	while read -r _jf; do
		[[ -z $_jf ]] && continue
		let _i++
		_label="${_jf%/*}"; _label="${_label##*/}"
		echoRgb "[$_i/$_total] $_label" "3"
		if _json_refresh_regenerate_one_file "$_jf" "$_label"; then let _ok++; else let _fail++; fi
	done < "$_jsons"
	rm -f "$_jsons" "$_pkgs"
	endtime 1
	echoRgb "本地JSON重生完成: 成功=$_ok 失敗=$_fail，所有 Size/apk版本/備份時間/SSAID未更新" "1"
}
Json_refresh_remote() {
	starttime1="$(date -u "+%s")"
	show_conf remote
	remote_enabled || { echoRgb "remote_type 未設定" "0"; return 1; }
	_BACKUP_DIRNAME_CACHED="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	local _list="$MODDIR/appList_network.txt" _apps _pkgs _dl _ok=0 _fail=0 _i=0 _total _raw _rk _out _line _pkg
	[[ -f $_list ]] || { echoRgb "找不到 appList_network.txt，請先執行『列出遠端備份』" "0"; return 1; }
	_apps="$TMPDIR/.json_regen_remote_apps_$$"
	_pkgs="$TMPDIR/.json_regen_remote_pkgs_$$"
	_dl="$TMPDIR/.json_regen_remote_dl_$$"
	rm -rf "$_dl" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; mkdir -p "$_dl" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	grep -v '^#' "$_list" | sed '/^$/d' | while read -r _raw; do
		case $_raw in wifi|Media|tools|start.sh|restore_settings.conf) continue ;; esac
		printf '%s\n' "$_raw"
	done > "$_apps"
	_total="$(grep -vc '^$' "$_apps" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	[[ $_total = 0 ]] && { echoRgb "appList_network.txt 內沒有可更新的 app" "0"; rm -rf "$_apps" "$_pkgs" "$_dl"; return 1; }
	: > "$_pkgs"
	while read -r _raw; do
		_rk="${_raw%% *}"; [[ -z $_rk ]] && _rk="$_raw"
		_out="$_dl/$_rk.json"
		if _get_remote_appdetails "$_rk" "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && [[ -s $_out ]]; then
			_line="$(_json_refresh_entry_pkg "$_out")"
			_pkg="$(printf '%s\n' "$_line" | awk -F'\t' '{print $2}')"
			[[ -n $_pkg ]] && printf '%s\n' "$_pkg" >> "$_pkgs"
		fi
	done < "$_apps"
	sort -u "$_pkgs" -o "$_pkgs" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_json_refresh_prescan_pkgs "$_pkgs" || { echoRgb "Dex AppState預掃不可用，無法重新生成遠端 JSON" "0"; rm -rf "$_apps" "$_pkgs" "$_dl"; return 1; }
	while read -r _raw; do
		[[ -z $_raw ]] && continue
		let _i++
		_rk="${_raw%% *}"; [[ -z $_rk ]] && _rk="$_raw"
		_out="$_dl/$_rk.json"
		echoRgb "[$_i/$_total] 遠端 $_rk" "3"
		if [[ ! -s $_out ]]; then
			echoRgb "下載失敗或不存在: $_rk/app_details.json" "0"; let _fail++; continue
		fi
		if _json_refresh_regenerate_one_file "$_out" "$_rk(遠端)" && _stream_upload "$_rk/app_details.json" < "$_out"; then
			let _ok++
		else
			let _fail++
		fi
	done < "$_apps"
	rm -rf "$_apps" "$_pkgs" "$_dl"
	endtime 1
	echoRgb "遠端JSON重生完成: 成功=$_ok 失敗=$_fail，所有 Size/apk版本/備份時間/SSAID未更新" "1"
}
Json_refresh_menu() {
	echoRgb "此功能會像備份流程一樣重新生成 app_details.json 的目前格式/AppState；但不更新 Size、apk版本、備份時間、SSAID，也不重打包資料" "3"
	ask_yn_indep "選擇更新目標" "本地JSON" "遠端JSON"
	if [[ $branch = true ]]; then
		Json_refresh_local
	else
		Json_refresh_remote
	fi
}
# 目前本地備份統計總覽: 應用/媒體數量、檔案數、總大小、含SSAID應用數、json有效率

# roundtrip.sh 已在 v24.20.14-7.48 移除；不得恢復父子 recover→backup 測試入口，避免防重複執行誤判。
Backup_Stats() {
	starttime1="$(date -u "+%s")"
	echoRgb "—————— 目前備份統計 ——————" "3"
	local _jsons _total_json=0 _valid_json=0 _ssaid_cnt=0 _app_cnt=0 _media_cnt=0
	# 唯讀算出備份目錄 (不呼叫 backup_path(), 避免其 mkdir/隨身碟詢問等副作用)
	local _scan_dir
	if [[ $Output_path != "" ]]; then
		local _op="$Output_path"
		[[ ${_op: -1} = / ]] && _op="${_op%?}"
		if [[ ${_op:0:1} != / ]]; then
			_scan_dir="$MODDIR/$_op/$(get_backup_dirname)"
		else
			_scan_dir="$_op/$(get_backup_dirname)"
		fi
	else
		_scan_dir="$MODDIR/$(get_backup_dirname)"
	fi
	[[ ! -d $_scan_dir ]] && _scan_dir="$MODDIR"
	_jsons="$(find "$_scan_dir" -maxdepth 2 -name "app_details.json" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	if [[ -z $_jsons ]]; then
		echoRgb "找不到任何備份 (無 app_details.json, 已搜尋: $_scan_dir)" "0"
		return
	fi
	_total_json="$(echo "$_jsons" | grep -vc '^$')"
	while read -r _jf; do
		[[ -z $_jf ]] && continue
		local _dirname="${_jf%/*}"
		_dirname="${_dirname##*/}"
		if [[ $_dirname = Media ]]; then
			let _media_cnt++
		else
			let _app_cnt++
		fi
		if jq -e . "$_jf" >/dev/null 2>&1; then
			let _valid_json++
			local _has_ssaid
			_has_ssaid="$(jq -r 'try ([.[] | objects | select((.app_state.ssaid // .Ssaid) != null)] | length) catch 0' "$_jf" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
			[[ ${_has_ssaid:-0} -gt 0 ]] && let _ssaid_cnt++
		fi
	done <<EOF5
$_jsons
EOF5
	# 檔案數與總大小: 用既有 calc_dir_size 邏輯量整個 Backup 目錄, 對應電腦端「大小」算法
	local _filecount _totalsize
	_filecount="$(find "$_scan_dir" -maxdepth 3 -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -vc '^$')"
	_totalsize="$(calc_dir_size "$_scan_dir" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	echoRgb "應用數量: $_app_cnt 個" "2"
	[[ $_media_cnt -gt 0 ]] && echoRgb "媒體/自訂資料夾: $_media_cnt 個" "2"
	echoRgb "檔案總數: ${_filecount:-0} 個" "2"
	echoRgb "備份總大小: $(size "${_totalsize:-0}")" "2"
	echoRgb "含SSAID的應用: $_ssaid_cnt 個" "2"
	if [[ $_valid_json -eq $_total_json ]]; then
		echoRgb "JSON有效率: $_valid_json/$_total_json (全數正常)" "1"
	else
		echoRgb "JSON有效率: $_valid_json/$_total_json (有 $((_total_json - _valid_json)) 個損壞)" "0"
	fi
	endtime 1 "統計用時"
}
# 統計分派: conf 有設定遠端就用遠端統計, 沒有就本地統計
Stats_Dispatch() {
	if [[ -n $remote_type ]]; then
		Remote_Backup_Stats
	else
		Backup_Stats
	fi
}
# 遠端備份統計總覽: 應用數量、檔案數、總大小、含SSAID應用數、json有效率 (遠端版)
Remote_Backup_Stats() {
	show_conf remote
	[[ -z $remote_type ]] && { echoRgb "remote_type 未設定" "0"; return 1; }
	case $remote_type in
	smb|webdav) ;;
	*) echoRgb "統計功能僅支援 smb / webdav (目前 remote_type=$remote_type)" "0"; return 1 ;;
	esac
	starttime1="$(date -u "+%s")"
	local target_dir="$(get_backup_dirname)"
	echoRgb "目標遠端目錄: $target_dir" "3"
	remote_parse_endpoint
	if ! remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		return 1
	fi
	[[ $remote_type = smb ]] && remote_parse_smb_url
	echoRgb "連線到 $remote_type://$REMOTE_HOST:$REMOTE_PORT" "1"
	echoRgb "—————— 遠端備份統計 ——————" "3"
	echoRgb "正在掃描遠端檔案列表 (單次連線)..." "3"
	local _filelist="$TMPDIR/.remote_stats_files"
	remote_list_files "$target_dir" > "$_filelist" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [[ ! -s $_filelist ]]; then
		echoRgb "遠端目錄不存在或無檔案: $target_dir" "0"
		rm -f "$_filelist"
		return 1
	fi
	local _filecount _app_cnt=0 _media_cnt=0 _apps="$TMPDIR/.remote_stats_apps"
	_filecount="$(grep -vc '^$' "$_filelist")"
	# 過濾出 app_details.json 所在的子目錄名 (即 app 名/Media)
	grep -E '/app_details\.json$|^app_details\.json$' "$_filelist" | sed 's|/app_details\.json$||' | sort -u > "$_apps"
	if [[ ! -s $_apps ]]; then
		echoRgb "找不到任何 app_details.json" "0"
		rm -f "$_filelist" "$_apps"
		return 1
	fi
	local _total_json _ra
	# Media/app_details.json 是自訂資料夾 metadata，不是應用 app_details；
	# 遠端 JSON 有效率只統計真正 app，Media 只列入「媒體/自訂資料夾」數量。
	_total_json="$(awk '$0!="Media"{c++} END{print c+0}' "$_apps" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	while read -r _ra; do
		[[ -z $_ra ]] && continue
		if [[ $_ra = Media ]]; then
			let _media_cnt++
		else
			let _app_cnt++
		fi
	done < "$_apps"
	echoRgb "正在計算遠端總大小..." "3"
	local _totalsize
	_totalsize="$(remote_dir_size "$target_dir")"
	# 並發下載逐一驗證 json 有效性 + 統計 SSAID (沿用健全度檢查的並發下載模式)
	echoRgb "正在下載驗證 $_total_json 個app的json..." "3"
	rm -rf "$TMPDIR/.remote_stats_dl" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	mkdir -p "$TMPDIR/.remote_stats_dl" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	local _running=0 _i=0 _rj_pids=""
	while read -r _ra; do
		[[ -z $_ra || $_ra = Media ]] && continue
		let _i++
		printf '\r -下載中 %d/%d' "$_i" "$_total_json" >&2
		( remote_download_single_file "$_ra/app_details.json" "$TMPDIR/.remote_stats_dl/$_ra.json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} ) &
		_rj_pids="$_rj_pids $!"
		let _running++
		if [[ $_running -ge 8 ]]; then _event_wait_pid_list "$_rj_pids" remote_stats_json_batch; _rj_pids=""; _running=0; fi
	done < "$_apps"
	_event_wait_pid_list "$_rj_pids" remote_stats_json_final
	echo >&2
	local _valid_json=0 _ssaid_cnt=0 _bad_json_list="$TMPDIR/.remote_stats_json_bad"
	: > "$_bad_json_list"
	while read -r _ra; do
		[[ -z $_ra || $_ra = Media ]] && continue
		local _jf="$TMPDIR/.remote_stats_dl/$_ra.json"
		if [[ ! -s $_jf ]]; then
			echo "$_ra: app_details.json 無法下載或為空" >> "$_bad_json_list"
			continue
		fi
		if ! jq -e . "$_jf" >/dev/null 2>&1; then
			echo "$_ra: json 格式損壞或無法解析" >> "$_bad_json_list"
			continue
		fi
		local _has_required
		_has_required="$(jq -r 'try ([.[] | objects | select(.PackageName != null and .apk_version != null)] | length) catch 0' "$_jf" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		if [[ ${_has_required:-0} -le 0 ]]; then
			echo "$_ra: 缺 PackageName 或 apk_version" >> "$_bad_json_list"
			continue
		fi
		let _valid_json++
		local _has_ssaid
		_has_ssaid="$(jq -r 'try ([.[] | objects | select((.app_state.ssaid // .Ssaid) != null)] | length) catch 0' "$_jf" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		[[ ${_has_ssaid:-0} -gt 0 ]] && let _ssaid_cnt++
	done < "$_apps"
	echoRgb "應用數量: $_app_cnt 個" "2"
	[[ $_media_cnt -gt 0 ]] && echoRgb "媒體/自訂資料夾: $_media_cnt 個" "2"
	echoRgb "檔案總數: ${_filecount:-0} 個" "2"
	echoRgb "備份總大小: $(size "${_totalsize:-0}")" "2"
	echoRgb "含SSAID的應用: $_ssaid_cnt 個" "2"
	if [[ $_total_json -le 0 ]]; then
		echoRgb "JSON有效率: 0/0 (沒有應用 JSON，僅媒體/自訂資料夾 metadata)" "2"
	elif [[ $_valid_json -eq $_total_json ]]; then
		echoRgb "JSON有效率: $_valid_json/$_total_json (全數正常)" "1"
	else
		echoRgb "JSON有效率: $_valid_json/$_total_json (有 $((_total_json - _valid_json)) 個損壞或無法下載)" "0"
		if [[ -s $_bad_json_list ]]; then
			echoRgb "遠端 JSON 異常清單:" "0"
			local _bj_i=1
			while read -r _bj; do
				[[ -n $_bj ]] && echoRgb "$_bj_i. $_bj" "0"
				let _bj_i++
			done < "$_bad_json_list"
		fi
	fi
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d ${SPEED_DEBUG_RUN_DIR:-} && -s $_bad_json_list ]] && cp "$_bad_json_list" "$SPEED_DEBUG_RUN_DIR/remote_stats_json_bad.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	rm -rf "$TMPDIR/.remote_stats_dl" "$_filelist" "$_apps" "$_bad_json_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	endtime 1 "統計用時"
}
# ======================================================
# Restore() 主函數
# ======================================================
# 主恢復函數 - 安裝 apk + 恢復 data + 還原 SSAID/權限
# ssaid_mode=true 時只恢復含 SSAID 的 app
# 從遠端流式恢復: 讀 appList_network.txt, 逐 app 流式拉回解壓 (不佔本機)
# 復用 Restore 的全部邏輯 (uid/selinux/權限/ssaid), 只是資料來源改為遠端流式
remote_stream_restore() {
	show_conf remote
	[[ -z $remote_type ]] && { echoRgb "remote_type 未設定" "0"; return 1; }
	case $remote_type in
	smb|webdav) ;;
	*) echoRgb "流式恢復僅支援 smb / webdav (目前 remote_type=$remote_type)" "0"; return 1 ;;
	esac
	local list="$MODDIR/appList_network.txt"
	if [[ ! -f $list ]]; then
		echoRgb "找不到 $list" "0"
		echoRgb "請先執行 '列出遠端備份' 產生清單, 編輯後再來流式恢復" "3"
		return 1
	fi
	# 連線預檢 + 解析 SMB 路徑 (流式 _stream_download 需要 SMB_SHARE/SMB_REM_PATH)
	remote_parse_endpoint
	[[ $remote_type = smb ]] && remote_parse_smb_url
	if ! remote_precheck "$REMOTE_HOST" "$REMOTE_PORT"; then
		echoRgb "遠端連線失敗: $REMOTE_HOST:$REMOTE_PORT" "0"
		return 1
	fi
	# TCP port open 不代表共享/帳密/路徑正確；Restore() 前必須做協議層硬預檢。
	_RESTORE_SUBDIR="$(get_backup_dirname)"
	if ! _remote_stream_source_precheck "$_RESTORE_SUBDIR"; then
		_speed_debug_log "REMOTE_STREAM_RESTORE_ABORT source_precheck_failed type=$remote_type host=$REMOTE_HOST port=$REMOTE_PORT subdir=$_RESTORE_SUBDIR"
		return 1
	fi
	echoRgb "流式恢復來源: $remote_type://$REMOTE_HOST/ ($_RESTORE_SUBDIR)" "3"
	echoRgb "清單: $list" "2"
	# 設流式恢復旗標, 復用 Restore 全流程。先清前一輪中斷殘留 staging。
	_RESTORE_STREAM=1
	rm -rf "$TMPDIR/.restore_stage" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	mkdir -p "$TMPDIR/.restore_stage" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	Restore
	# 清理 staging (只有 json, 數據從未落地)
	rm -rf "$TMPDIR/.restore_stage" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_RESTORE_STREAM=0
}
# 流式恢復時本地不會有 $MODDIR/Media，也不會先下載 mediaList.txt。
# 這裡只下載恢復 Media 必需的 metadata；真正的壓縮包仍由 Release_data() 經 _STREAM_SRC 邊下邊解。
_restore_stream_prepare_media() {
	_RESTORE_STREAM_MEDIA_READY=0
	unset _RESTORE_STREAM_MEDIA_LIST
	[[ ${_RESTORE_STREAM:-0} = 1 ]] || return 1
	local _list="$MODDIR/appList_network.txt"
	[[ -s $_list ]] || return 1
	if ! grep -Ev '^[[:space:]]*[#＃]|^[[:space:]]*$' "$_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -qx 'Media'; then
		return 1
	fi
	local _mstage="$TMPDIR/.restore_stage/Media" _mlist="$TMPDIR/.restore_stage/mediaList.txt"
	mkdir -p "$_mstage" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_stream_download "$_RESTORE_SUBDIR/Media/app_details.json" > "$_mstage/app_details.json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_stream_download "$_RESTORE_SUBDIR/mediaList.txt" > "$_mlist" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [[ ! -s "$_mstage/app_details.json" ]] || ! jq empty "$_mstage/app_details.json" >/dev/null 2>&1; then
		echoRgb "Media/app_details.json 下載失敗或內容損毀，跳過流式 Media 恢復" "0"
		{
			echo "===== BAD_STREAM_MEDIA_APP_DETAILS rel=$_RESTORE_SUBDIR/Media/app_details.json ====="
			echo "size=$(wc -c < "$_mstage/app_details.json" 2>/dev/null)"
			head -c 300 "$_mstage/app_details.json" 2>/dev/null | sed 's/^/  content: /'
			echo
		} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/bad_media_restore.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 1
	fi
	if [[ ! -s "$_mlist" ]] || ! grep -Ev '^[[:space:]]*[#＃]|^[[:space:]]*$' "$_mlist" >/dev/null 2>&1; then
		echoRgb "mediaList.txt 下載失敗或沒有有效項目，跳過流式 Media 恢復" "0"
		{
			echo "===== BAD_STREAM_MEDIA_LIST rel=$_RESTORE_SUBDIR/mediaList.txt ====="
			echo "size=$(wc -c < "$_mlist" 2>/dev/null)"
			head -c 300 "$_mlist" 2>/dev/null | sed 's/^/  content: /'
			echo
		} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/bad_media_restore.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 1
	fi
	Backup_folder2="$_mstage"
	_RESTORE_STREAM_MEDIA_LIST="$_mlist"
	_RESTORE_STREAM_MEDIA_READY=1
	echoRgb "流式 Media metadata 已下載，將可恢復自定義資料夾壓縮包" "1"
	return 0
}

# ============================================================
# SpeedBackup single-file section: sb_70_restore_menu_entry.sh
# ============================================================
Restore() {
	self_test
	if ! _appstate_capabilities_check; then
		echoRgb "Dex/AppState 核心能力不完整或 tools/Dex 版本不匹配，已中止應用恢復" "0"
		echoRgb "需要 Dex v2.6.61、AppState AF_UNIX daemon、HiddenApi forceStopPackageBatch daemon bodyfix、runtime UID AppOps、真實 package mode、canonical snapshot/restore/verify、foreground state-simple/list-simple-json + WebDAV daemon opt + buffer v3 + WebDAV hang guard、hot CLI removed、shared daemon bootstrap / sequential guard / Google snapshot、WEBR5、123pan managed direct、daemon hardening/watchdog、Device_List HttpUtil 分片能力" "3"
		_speed_debug_normal_finish_pack 2
		exit 2
	fi
	disable_verify
	[[ ! -d $path2 ]] && echoRgb "設備不存在user目錄" "0" && exit 1
	# 預掃資料 (取代主迴圈內每 app fork)
	_prepare_timed prepare_pkg_uid_map
	_prepare_timed prepare_pkg_ver_map
	prepare_installed_pkgs_map
	# v24.20.14-7.6：恢復主迴圈期間必須保留 session maps。
	# Release_data() 會在每個 tar 解壓後呼叫 cleanup_tmpdir_contents()；
	# 若此 flag 沒有開啟，第 1 個 app 後 .installed_pkgs/.pkg_ver/.pkg_uid 會被刪除，
	# 第 2 個 app 起就會誤判為未安裝並重跑 APK 安裝。
	_RESTORE_KEEP_SESSION_MAPS=1
	_speed_debug_log "RESTORE_SESSION_MAP_KEEP_BEGIN keep=$_RESTORE_KEEP_SESSION_MAPS installed=$(wc -l < "$TMPDIR/.installed_pkgs" 2>/dev/null) pkg_ver=$(wc -l < "$TMPDIR/.pkg_ver" 2>/dev/null) pkg_uid=$(wc -l < "$TMPDIR/.pkg_uid" 2>/dev/null)"
	if [[ ! -f ${0%/*}/app_details.json ]]; then
		echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊$MODDIR_NAME/start.sh選擇終止腳本\n -否則腳本將繼續執行直到結束" "0"
		echoRgb "如果大量提示找不到資料夾請執行$MODDIR_NAME/start.sh選擇轉換資料夾名稱"
		txt="$MODDIR/appList.txt"
		# 流式恢復: 改用 appList_network.txt (功能8 產生), 過濾掉註解與特殊項(wifi/Media), 只留 app 行
		if [[ $_RESTORE_STREAM = 1 ]]; then
			grep -Ev '^[[:space:]]*[#＃]|^[[:space:]]*$' "$MODDIR/appList_network.txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} \
				| grep -Evx '[[:space:]]*(wifi|Media)[[:space:]]*' > "$TMPDIR/.stream_restore_list"
			txt="$TMPDIR/.stream_restore_list"
			if _restore_list_has_play_markers "$txt"; then
				_speed_debug_log "STREAM_RESTORE_PLAY_MARKER_SUPPORT list=$txt marker=1"
			fi
		fi
		[[ ! -f $txt ]] && echoRgb "請執行start.sh獲取應用列表再來恢復" "0" && exit 2
		sort -u "$txt" -o "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		i=1
		r="$(awk '!/[#＃]/ && NF{count++} END{print count}' "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		[[ $r = "" ]] && echoRgb "appList.txt包名為空或是被注釋了\n -請執行start.sh獲取應用列表再來恢復" "0" && exit 1
		if _restore_list_has_play_markers "$txt"; then
			if _restore_has_play_store; then
				echoRgb "檢測到 !Play 恢復標記，Google Play 商店可用，將走 Play UID hybrid session" "3"
				_speed_debug_log "PLAY_MARKER_LIST_CHECK result=ok stream=${_RESTORE_STREAM:-0} list=$txt"
			else
				echoRgb "檢測到 !Play 恢復標記，但 Google Play 商店不可用，對應 App 會回退原生 pm 安裝" "0"
				_speed_debug_log "PLAY_MARKER_LIST_CHECK result=fail stream=${_RESTORE_STREAM:-0} list=$txt fallback=pm"
			fi
		fi
		Backup_folder2="$MODDIR/Media"
		if [[ $_RESTORE_STREAM = 1 ]]; then
			_restore_stream_prepare_media || true
		fi
		#校驗選填是否正確
		[[ $recovery_mode != "" ]] && isBoolean "$recovery_mode" "recovery_mode" && recovery_mode="$nsx" || {
		echoRgb "選擇應用恢復模式\n -音量上僅恢復未安裝，下全恢復"
		get_version "恢復未安裝" "全恢復" && recovery_mode="$branch"
		}
		[[ $setDisplayPowerMode != "" ]] && isBoolean "$setDisplayPowerMode" "setDisplayPowerMode" && setDisplayPowerMode="$nsx" || {
		echoRgb "應用恢復時關閉螢幕\n -音量上關閉，下不關閉"
		get_version "關閉" "不關閉" && setDisplayPowerMode="$branch"
		}
		if [[ $_RESTORE_STREAM = 1 ]]; then
			Get_user="$(get_backup_dirname | grep -Eo '[0-9]+$')"
		else
			Get_user="$(echo "$MODDIR" | rev | cut -d '/' -f1 | cut -d '_' -f1 | rev | grep -Eo '[0-9]+')"
		fi
		if [[ $Get_user != $user ]]; then
			echoRgb "檢測當前用戶$user與恢復資料夾用戶:$Get_user不同，音量上繼續恢復，下不恢復並離開腳本"
			get_version "恢復安裝" "不恢復安裝" && recovery_mode2="$branch"
		fi
		if [[ -d $Backup_folder2 || $_RESTORE_STREAM_MEDIA_READY = 1 ]]; then
			[[ $media_recovery != "" ]] && isBoolean "$media_recovery" "media_recovery" && media_recovery="$nsx" || {
			echoRgb "是否恢復多媒體數據\n -音量上恢復，音量下不恢復" "2"
			get_version "恢復媒體數據" "跳過恢復媒體數據" && media_recovery="$branch"
			}
		fi
		[[ $Background_apps_ignore != "" ]] && isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx" || {
		echoRgb "存在進程忽略恢復\n -音量上忽略，音量下恢復" "2"
		get_version "忽略" "恢復" && Background_apps_ignore="$branch"
		}
		[[ $recovery_mode2 = false ]] && exit 2
		if [[ $recovery_mode = true && $ssaid_mode != true && $_RESTORE_STREAM != 1 ]]; then
			echoRgb "獲取未安裝應用中"
			Apk_info="$(pm list packages --user "$user" | cut -f2 -d ':' | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
			if [[ $Apk_info != "" ]]; then
				[[ $Apk_info = *"Failure calling service package"* ]] && Apk_info="$(appinfo "user|system" "pkgName" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
			else
				Apk_info="$(appinfo "user|system" "pkgName" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -Ev 'ice.message|com.topjohnwu.magisk' | sort -u)"
			fi
			[[ $Apk_info = "" ]] && echoRgb "Apk_info變量為空" "0" && exit
			while read -r ; do
				local _reply_line _apk_pkg
				_reply_line="$(echo "$REPLY" | sed 's/^[ \t]*//')"
				if [[ $_reply_line != \#* ]]; then
					case "$_reply_line" in
					!play[[:space:]]*|！play[[:space:]]*)
						_reply_line="${_reply_line#*!play}"
						_reply_line="${_reply_line#*！play}"
						_reply_line="$(printf '%s\n' "$_reply_line" | sed 's/^[ \t]*//')"
						;;
					![[:space:]]*|！[[:space:]]*|!*)
						_reply_line="${_reply_line#!}"
						_reply_line="${_reply_line#！}"
						_reply_line="$(printf '%s\n' "$_reply_line" | sed 's/^[ \t]*//')"
						;;
				esac
					_list_name="${_reply_line%% *}"
					_apk_pkg="${_reply_line#* }"
					_apk_pkg="${_apk_pkg%% *}"
					if [[ $_list_name != "" && $_apk_pkg != "" && $_apk_pkg != "$_reply_line" ]]; then
						[[ $(echo "$Apk_info" | awk -v pkg="$_apk_pkg" '$1 == pkg {print $1}') = "" ]] && Tmplist="$Tmplist\n$REPLY"
					fi
				fi
			done < "$txt"
			if [[ $(echo "$Tmplist" | awk 'NF != 0 { count++ } END { print count }') != "" ]]; then
				echoRgb "獲取完成 預計安裝$(echo "$Tmplist" | awk 'NF != 0 { count++ } END { print count }')個應用"
				txt="$Tmplist"
				echoRgb "未安裝應用列表\n$txt" "1"
				if ! ask_yn "確認恢復?" "恢復安裝" "退出腳本"; then
					exit
				fi
			else
				echoRgb "獲取完成 但備份內應用都已安裝....正在退出腳本" "0" && exit 0
			fi
		fi
		if [[ $ssaid_mode = true ]]; then
			# 改 here-string 為暫存檔 (mksh 不支援 <<<)
			# 用暫存檔取代 ssaid_name 字串拼接 (O(N²) → O(N))
			local _find_tmp="$TMPDIR/.find_ssaid_$$"
			local _ssaid_tmp="$TMPDIR/.ssaid_list_$$"
			find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sort > "$_find_tmp"
			: > "$_ssaid_tmp"
			while read -r; do
				if [[ $(jq -r 'try ([.[]|objects|((.app_state.ssaid // .Ssaid) // empty)]|.[0]) catch ""' "$REPLY" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) != "" ]]; then
					ChineseName="$(jq -r 'try (([.[] | objects | select(.PackageName != null)] | length) as $n | if $n > 0 then (to_entries[] | select(.value.PackageName != null).key) else (to_entries[] | select(.key != null).key) end) catch ""' "$REPLY" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | head -n 1)"
					PackageName="$(jq -r 'try (.[] | select(.PackageName != null).PackageName) catch ""' "$REPLY" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
					echo "$ChineseName $PackageName" >> "$_ssaid_tmp"
				fi
			done < "$_find_tmp"
			[[ -s $_ssaid_tmp ]] && ssaid_name="$(cat "$_ssaid_tmp")"
			rm -f "$_find_tmp" "$_ssaid_tmp"
			[[ $ssaid_name != "" ]] && txt="$ssaid_name"
		fi
		if [[ ! -f $txt ]]; then
			[[ -n $txt ]] && txt="$(echo "$txt" | sed -e '/^$/d')"
		else
			txt="$(grep -Ev '#|＃' "$txt" | sed -e '/^$/d')"
		fi
		r="$(echo "$txt" | awk 'NF != 0 { count++ } END { print count }')"
		DX="批量恢復"
	else
		i=1
		r=1
		Backup_folder="$MODDIR"
		app_details="$Backup_folder/app_details.json"
		if [[ ! -f $app_details ]]; then
			echoRgb "$app_details遺失，無法獲取包名" "0" && exit 1
		else
			ChineseName="$(jq -r 'try ((([.[] | objects | select(.PackageName != null)] | length) as $n | if $n > 0 then (to_entries[] | select(.value.PackageName != null).key) else (to_entries[] | select(.key != null).key) end) // "") catch ""' "$app_details" | head -n 1)"
			PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$app_details")"
			apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
		fi
		name1="$ChineseName"
		name1="${name1:="${Backup_folder##*/}"}"
		[[ $name1 = "" ]] && echoRgb "應用名獲取失敗" "0" && exit 2
		name2="$PackageName"
		[[ $name2 = "" ]] && echoRgb "包名獲取失敗" "0" && exit 2
		DX="單獨恢復"
		[[ $Background_apps_ignore != "" ]] && isBoolean "$Background_apps_ignore" "Background_apps_ignore" && Background_apps_ignore="$nsx" || {
		echoRgb "存在進程忽略恢復\n -音量上忽略，音量下恢復" "2"
		get_version "忽略" "恢復" && Background_apps_ignore="$branch"
		}
	fi
	#開始循環$txt內的資料進行恢復
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	TIME="$starttime1"
	Set_screen_pause_seconds on
	en=118
	notification_progress "105" "$r" 0 "開始恢復app"
	# 啟用AppState批量模式: 迴圈內 restore_appstate 只收集到暫存檔, 迴圈結束後 flush 一次沖刷；單 app/外部呼叫會自動臨時 batch+flush
	# 此迴圈同時服務批量恢復(N個app)與單獨恢復(1個app); 單獨恢復時收集1組→flush設1組, 等價立即執行
	_batch_appstate_mode=1
	_RESTORE_PRESERVE_BATCH_QUEUE=1
	# 清空本輪批量恢復暫存，installer/電池也一併清，避免同一 shell session 內殘留
: > "$TMPDIR/.batch_appstate_ndjson" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# APK 安裝維持逐 app 流程：每個 app 解壓成功後立即安裝，再恢復 data/appstate。
	# 預設使用備份 installer 條件式 hybrid_installer_pm；installer 不存在/無 UID 就退回原生 pm，不做無效來源偽裝。
	# 需要 packageSource=STORE 的個別 app 才能在 appList.txt 行首加 !play 走慢速 Play session。
	# 若本輪偵測到 hybrid_installer_pm 真正安裝失敗，後續 app 直接回退原生 pm，避免重複嘗試同一失敗路線。
	_restore_hybrid_installer_pm_disabled=0
	while [[ $i -le $r ]]; do
		[[ $en -ge 229 ]] && en=118
		if [[ ! -f ${0%/*}/app_details.json ]]; then
			echoRgb "恢復第$i/$r個應用 剩下$((r - i))個" "3"
			notification_progress "105" "$r" "$((i - 1))" "恢復第$i/$r個應用 剩下$((r - i))個
恢復 $name1"
			# 一次 sed 抓行, 用 parameter expansion 拆欄位
			_line="$(echo "$txt" | sed -n "${i}p")"
			_restore_force_play_session=0
			_restore_force_play_marker=""
			case "$_line" in
			!play[[:space:]]*|！play[[:space:]]*)
				_restore_force_play_session=1
				_restore_force_play_marker="!play"
				_line="${_line#*!play}"
				_line="${_line#*！play}"
				_line="$(printf '%s\n' "$_line" | sed 's/^[ \t]*//')"
				;;
			![[:space:]]*|！[[:space:]]*|!*)
				_restore_force_play_session=1
				_restore_force_play_marker="!"
				_line="${_line#!}"
				_line="${_line#！}"
				_line="$(printf '%s\n' "$_line" | sed 's/^[ \t]*//')"
				;;
			esac
			[[ $_RESTORE_STREAM = 1 && ${_restore_force_play_session:-0} = 1 ]] && _speed_debug_log "STREAM_RESTORE_PLAY_MARKER_APPLY marker=${_restore_force_play_marker:-!} app=${_line%% *}"
			name1="${_line%% *}"
			name2="${_line#* }"
			name2="${name2%% *}"
			unset _line
			unset No_backupdata apk_version
			if [[ $name1 = *! || $name1 = *！ ]]; then
				name1="${name1//!/}"
				name1="${name1//！/}"
				echoRgb "跳過恢復$name1 所有數據" "0"
				No_backupdata=1
			fi
			Backup_folder="$MODDIR/$name1"
			# 流式恢復: 本地無備份, 從遠端拉 app_details.json 到 TMPDIR staging
			if [[ $_RESTORE_STREAM = 1 ]]; then
				Backup_folder="$TMPDIR/.restore_stage/$name1"
				mkdir -p "$Backup_folder" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				_stream_download "$_RESTORE_SUBDIR/$name1/app_details.json" > "$Backup_folder/app_details.json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				# 下載內容可能為空/非合法 json (遠端檔案不存在、傳輸中斷等), 先驗證再解析,
				# 避免 jq parse error 把 name2 弄成空值後整輪 exit 1 砍掉還沒處理的其餘 app。
				if [[ ! -s "$Backup_folder/app_details.json" ]] || ! jq empty "$Backup_folder/app_details.json" >/dev/null 2>&1; then
					if grep -Eq 'NT_STATUS_OBJECT_NAME_NOT_FOUND|NT_STATUS_OBJECT_PATH_NOT_FOUND|does not exist' "$Backup_folder/app_details.json" 2>/dev/null; then
						echoRgb "$name1 遠端不存在 (清單可能未更新), 跳過此應用" "0"
					else
						echoRgb "$name1 的 app_details.json 下載失敗或內容損毀, 跳過此應用" "0"
					fi
					{
						echo "===== BAD_APP_DETAILS $name1 rel=$_RESTORE_SUBDIR/$name1/app_details.json ====="
						echo "size=$(wc -c < "$Backup_folder/app_details.json" 2>/dev/null)"
						head -c 300 "$Backup_folder/app_details.json" 2>/dev/null | sed 's/^/  content: /'
						echo
					} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/bad_app_details.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					rm -rf "$Backup_folder" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					unset _restore_force_play_session _restore_force_play_marker
					let i++ en++ nskg++
					continue
				fi
			fi
			if [[ -f "$Backup_folder/app_details.json" ]]; then
				app_details="$Backup_folder/app_details.json"
				apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details" 2>/dev/null)"
				# 流式: 列表(appList_network.txt)只有資料夾名, 包名 name2 從 json 的 PackageName 取
				if [[ $_RESTORE_STREAM = 1 ]]; then
					name2="$(jq -r '.[] | select(.PackageName != null).PackageName' "$app_details" 2>/dev/null)"
				fi
			else
				echoRgb "$Backup_folder/app_details.json不存在" "0"
			fi
			if [[ $name2 = "" ]]; then
				echoRgb "$name1 應用包名獲取失敗, 跳過此應用" "0"
				if [[ $_RESTORE_STREAM = 1 ]]; then
					rm -rf "$Backup_folder" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					unset _restore_force_play_session _restore_force_play_marker
					let i++ en++ nskg++
					continue
				else
					exit 1
				fi
			fi
		fi
		# 流式恢復: Backup_folder 是 staging (只有 json), 視為存在以進入恢復流程
		if [[ -d $Backup_folder ]] || [[ $_RESTORE_STREAM = 1 ]]; then
			echoRgb "恢復$name1" "2"
			Background_application_list
			restore="true"
			if [[ $Backstage != "" ]] && printf '%s
' "$Backstage" | awk -v p="$name2" '$0==p{found=1} END{exit !found}'; then
				echoRgb "$name1存在前台/後台，忽略恢復" "0"
				restore="false"
			fi
			[[ $restore = true ]] && {
			starttime2="$(date -u "+%s")"
			# 用預掃的 .installed_pkgs 查 (取代 fork pm 3 次)
			# 注意: installapk 後 app 已裝, 再裝完用 grep 重查
			# v24.20.14-7.3：讀取前再保底建立，避免中途 cleanup 或異常路徑刪掉後 awk 噴 No such file。
			[[ -f "$TMPDIR/.installed_pkgs" ]] || : > "$TMPDIR/.installed_pkgs" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			local _is_installed
			_is_installed=$(awk -v p="$name2" '$0==p{f=1} END{exit !f}' "$TMPDIR/.installed_pkgs" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && echo 1)
			# v24.20.14-7.11：流式恢復時若預掃 installed map 沒命中，再用 pm path 做一次低成本保底。
			# 避免遠端流式恢復因 map 內容/時序異常，把已安裝同版 app 誤判為全新安裝而重跑 APK install。
			if [[ $_RESTORE_STREAM = 1 && -z $_is_installed && -n $name2 ]]; then
				if pm path --user "${user:-0}" "$name2" >/dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
					_is_installed=1
					printf '%s\n' "$name2" >> "$TMPDIR/.installed_pkgs"
					_speed_debug_log "STREAM_RESTORE_INSTALLED_FALLBACK_HIT package=$name2"
				else
					_speed_debug_log "STREAM_RESTORE_INSTALLED_FALLBACK_MISS package=$name2"
				fi
			fi
			# 流式: 設定 apk 遠端來源 (installapk 會用)
			# 流式: 設定 apk 遠端來源 (依壓縮方式決定後綴)
			if [[ $_RESTORE_STREAM = 1 ]]; then
				case $Compression_method in
				tar|Tar|TAR) _STREAM_APK_SRC="$_RESTORE_SUBDIR/$name1/apk.tar" ;;
				*) _STREAM_APK_SRC="$_RESTORE_SUBDIR/$name1/apk.tar.zst" ;;
				esac
			fi
			local _was_installed="$_is_installed"
			if [[ -z $_is_installed ]]; then
				installapk
				# installapk 內部會用 echo_log 設 $result
				if [[ $result = 0 ]]; then
					echo "$name2" >> "$TMPDIR/.installed_pkgs"
					_is_installed=1
					case $apk_version in ''|null|NULL|*[!0-9]*) echoRgb "全新安裝完成" "1" ;; *) echoRgb "全新安裝版本>$apk_version" "1" ;; esac
				else
					_is_installed=0
				fi
			else
				# 已裝, 比版本決定要不要 reinstall。
				# v24.20.14-7.4：map 命中失敗不可再當 0，避免已安裝同版 app 被誤判成「全新安裝」。
				local _cur_ver
				_cur_ver="$(_kv_file_get "$TMPDIR/.pkg_ver" "$name2" | tr -d ' \t\r\n')"
				[[ -z $_cur_ver ]] && _cur_ver="$(get_current_apk_version_code "$name2")"
				case $apk_version in ''|null|NULL|*[!0-9]*)
					# 備份版本不是純數字時不能安全比較；既然已安裝，就跳過 APK 安裝，只恢復 data/appstate。
					echoRgb "已安裝，備份版本不可比對，跳過APK安裝" "2"
					;;
				*)
					case $_cur_ver in ''|null|NULL|*[!0-9]*)
						# 已安裝但目前版本讀不到：安全策略是跳過，而不是把空值當 0 觸發安裝。
						echoRgb "已安裝，當前版本讀取失敗，跳過APK安裝" "0"
						SpeedDebug_log "WARN: installed_version_map_miss package=$name2 backupVersion=$apk_version skip_apk_install=1"
						;;
					*)
						if [[ $apk_version -gt $_cur_ver ]]; then
							if installapk; then
								echoRgb "版本提升${_cur_ver}>$apk_version" "1"
								# 更新本輪版本 map，避免同一輪後續判斷仍讀到舊值。
								awk -v pkg="$name2" '$1 != pkg' "$TMPDIR/.pkg_ver" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} > "$TMPDIR/.pkg_ver.tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
								mv -f "$TMPDIR/.pkg_ver.tmp" "$TMPDIR/.pkg_ver" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
								printf '%s\t%s\n' "$name2" "$apk_version" >> "$TMPDIR/.pkg_ver"
							fi
						else
							echoRgb "已安裝版本$_cur_ver，跳過APK安裝" "2"
						fi
						;;
					esac
					;;
				esac
			fi
			# 流式 + 僅恢復未安裝模式: 已裝的 app 跳過數據恢復 (流式無預篩, 在此落實 recovery_mode 語義)
			if [[ $_RESTORE_STREAM = 1 && $recovery_mode = true && -n $_was_installed ]]; then
				echoRgb "$name1 已安裝, 僅恢復未安裝模式下跳過數據恢復" "2"
			elif [[ $_is_installed = 1 ]]; then
				if [[ $No_backupdata = "" ]]; then
					[[ $name2 != *mt* ]] && {
					kill_app
					if [[ $_RESTORE_STREAM = 1 ]]; then
						# 流式: 枚舉資料類型, 設 _STREAM_SRC 遠端路徑, 逐個流式解壓
						local _dt
						# 流式恢復納入 thanox/hma 專屬系統配置。
						for _dt in user data obb user_de thanox hma; do
							# 只恢復遠端 json 有記錄的資料 (Size 存在表示有備份)
							local _has
							if [[ -s $app_details ]]; then
								_has="$(jq -r --arg k "$_dt" 'try (.[$k].Size // "") catch ""' "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
							else
								_has=""
							fi
							[[ -z $_has || $_has = null ]] && continue
							case $Compression_method in
							tar|Tar|TAR) _STREAM_SRC="$_RESTORE_SUBDIR/$name1/$_dt.tar" ;;
							*) _STREAM_SRC="$_RESTORE_SUBDIR/$name1/$_dt.tar.zst" ;;
							esac
							Release_data "$Backup_folder/${_STREAM_SRC##*/}"
						done
						unset _STREAM_SRC
					else
					find "$Backup_folder" -maxdepth 1 ! -name "apk.*" ! -name "speed_debug_*.tar" ! -name "speed_debug_*.tar.zst" -name "*.tar*" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sort | while read -r; do
						Release_data "$REPLY"
					done
					fi
					unset G
					if ! restore_appstate; then
						_speed_debug_log "RESTORE_APPSTATE_SKIPPED package=${name2:-} reason=canonical_record_invalid"
					fi
					}
				fi
			else
				[[ $No_backupdata = "" ]]&& echoRgb "$name1沒有安裝無法恢復數據" "0"
			fi
			endtime 2 "$name1恢復" "2" && echoRgb "完成$(safe_percent "$i" "$r")% $(progress_bar $(safe_percent "$i" "$r"))" "3"
			notification_progress "105" "$r" "$i" "恢復進度 $i/$r $(safe_percent "$i" "$r")%"
			rgb_d="$rgb_a"
			rgb_a=188
			echoRgb "_________________$(endtime 1 "已經")___________________"
			rgb_a="$rgb_d"
			}
		else
			echoRgb "$Backup_folder資料夾遺失，無法恢復" "0"
		fi
		if [[ $i = $r ]]; then
			endtime 1 "應用安裝/資料迴圈" "2"
			# 應用迴圈結束後立刻批量寫入權限/AppOps/電池設定。
			# 不可拖到 Media/自訂資料夾恢復之後；大檔流式 Media 可能被使用者中斷，
			# 若此時尚未 flush，整批應用權限就會停留在暫存佇列，實際沒有套用。
			echoRgb "開始批量恢復權限/AppOps/電池設定" "3"
			flush_batch_appstate
			_RESTORE_PRESERVE_BATCH_QUEUE=0
			_batch_appstate_mode=0
			notification_progress "105" "$r" "$r" "app恢復完成 $(endtime 1 "應用恢復" "2")"
			[[ ! -f ${0%/*}/app_details.json ]] && {
			if [[ $media_recovery = true ]]; then
				starttime1="$(date -u "+%s")"
				app_details="$Backup_folder2/app_details.json"
				if [[ $_RESTORE_STREAM = 1 ]]; then
					txt="${_RESTORE_STREAM_MEDIA_LIST:-$TMPDIR/.restore_stage/mediaList.txt}"
				else
					txt="$MODDIR/mediaList.txt"
				fi
				if [[ -f "$txt" ]]; then
					sort -u "$txt" -o "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				else
					echoRgb "mediaList.txt 遺失，無法恢復 Media 壓縮包" "0"
				fi
				A=1
				B="$(awk '!/[#＃]/ && NF{count++} END{print count}' "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
				[[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行start.sh獲取列表再來恢復" "0" && B=0
				notification_progress "106" "$B" 0 "Media恢復開始"
				while [[ $A -le $B ]]; do
					name1="$(awk -v n=$A '!/[#＃]/ && NF{c++} c==n{print $1; exit}' "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
					starttime2="$(date -u "+%s")"
					echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
					if [[ $_RESTORE_STREAM = 1 ]]; then
						_STREAM_SRC="$_RESTORE_SUBDIR/Media/$name1"
					fi
					Release_data "$Backup_folder2/$name1"
					unset _STREAM_SRC
					endtime 2 "$FILE_NAME2恢復" "2" && echoRgb "完成$(safe_percent "$A" "$B")% $(progress_bar $(safe_percent "$A" "$B"))" "3"
					notification_progress "106" "$B" "$A" "Media恢復進度 $A/$B $(safe_percent "$A" "$B")%"
					echoRgb "____________________________________" && let A++
				done
				endtime 1 "自定義恢復" "2"
				notification_progress "106" "$B" "$B" "Media恢復完成 $(endtime 1 "Media恢復" "2")"
			fi
			[[ $_RESTORE_STREAM != 1 ]] && recover_wifi "$MODDIR/wifi"
			}
		fi
		unset _restore_force_play_session _restore_force_play_marker
		let i++ en++ nskg++
	done
	# 保底復位：正常情況已在 app 迴圈結束瞬間 flush；這裡只防舊分支或異常路徑漏掉。
	flush_batch_appstate
	# 復位: 確保批量模式不外溢；非迴圈直接呼叫 restore_appstate 時函式內會自動臨時 batch+flush
	_RESTORE_PRESERVE_BATCH_QUEUE=0
	_batch_appstate_mode=0
	Set_screen_pause_seconds off
	[[ $user != 0 ]] && am stop-user "$user" >/dev/null 2>&1
	starttime1="$TIME"
	echoRgb "$DX完成" && endtime 1 "$DX總流程"
	notification_progress "109" 100 100 "恢復完成 $(endtime 1 "$DX總流程")"
	_RESTORE_KEEP_SESSION_MAPS=0
	_speed_debug_log "RESTORE_SESSION_MAP_KEEP_END keep=$_RESTORE_KEEP_SESSION_MAPS"
	cleanup_tmpdir_contents || exit 1
	# 正常恢復完成點主動建立 final 包並刪除 run_xxx。
	# 避免單獨入口 / tee pipeline 的 EXIT trap 提前打包，造成 speed_debug_*.tar 與幕後 run 目錄內容不一致。
	_speed_debug_normal_finish_pack 0
}
# 恢復自定義資料夾 (Media 等)
Restore3() {
	self_test
	echoRgb "點錯了?這是恢復自定義資料夾腳本 如果你是要恢復應用那你就點錯了" "2"
	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊start.sh選擇終止腳本,否則腳本將繼續執行直到結束" "0"
	if ! ask_yn "繼續恢復自定義資料夾?" "恢復自定義資料夾" "離開腳本"; then
		exit 0
	fi
	mediaDir="$MODDIR/Media"
	[[ -f "$mediaDir/app_details.json" ]] && app_details="$mediaDir/app_details.json"
	Backup_folder2="$mediaDir"
	[[ ! -d $mediaDir ]] && echoRgb "媒體資料夾不存在" "0" && exit 2
	txt="$MODDIR/mediaList.txt"
	[[ ! -f $txt ]] && echoRgb "請執行start.sh獲取媒體列表再來恢復" "0" && exit 2
	sort -u "$txt" -o "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	#記錄開始時間
	starttime1="$(date -u "+%s")"
	# 注意: 不要在這裡重新定義 echo_log()——shell 函式沒有真正的區域作用域，
	# 這樣寫會直接覆蓋第 3397 行的全域 echo_log()，導致本次呼叫之後
	# (包含這個迴圈內 Release_data() 呼叫的 echo_log，以及往後任何其他流程)
	# 全部改用這裡的簡化版，遺失 _speed_debug_log / Set_back_0 / Set_back_1 / 失敗通知。
	starttime1="$(date -u "+%s")"
	A=1
	B="$(awk '!/[#＃]/ && NF{count++} END{print count}' "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	Set_screen_pause_seconds on
	[[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行start.sh獲取列表再來恢復" "0" && exit 1
	notification_progress "108" "$B" 0 "Media恢復開始"
	while [[ $A -le $B ]]; do
		name1="$(awk -v n=$A '!/[#＃]/ && NF{c++} c==n{print $1; exit}' "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		starttime2="$(date -u "+%s")"
		echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
		Release_data "$mediaDir/$name1"
		endtime 2 "$FILE_NAME2恢復" "2" && echoRgb "完成$(safe_percent "$A" "$B")% $(progress_bar $(safe_percent "$A" "$B"))" "3"
		notification_progress "108" "$B" "$A" "Media恢復進度 $A/$B $(safe_percent "$A" "$B")%"
		echoRgb "____________________________________" && let A++
	done
	Set_screen_pause_seconds off
	endtime 1 "恢復結束"
	notification_progress "108" "$B" "$B" "Media恢復完成 $(endtime 1 "Media恢復")"
}
Restore4() {
	[[ $ssaid_mode_1 = true ]] || return 0
	local _list="$TMPDIR/.ssaid_details_list" _record="$TMPDIR/.ssaid_record_$$" _ssaid_only="$TMPDIR/.ssaid_only_$$"
	: > "$TMPDIR/.batch_appstate_ndjson" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sort > "$_list"
	while read -r app_details; do
		[[ -s $app_details ]] || continue
		name1="$(jq -r 'try (to_entries[]|select(.value.PackageName!=null).key) catch ""' "$app_details" 2>/dev/null | head -n1)"
		name2="$(jq -r 'try ([.[]|objects|select(.PackageName!=null).PackageName]|.[0]) catch ""' "$app_details" 2>/dev/null)"
		[[ -n $name1 && -n $name2 ]] || continue
		pm path --user "${user:-0}" "$name2" >/dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || continue
		_appstate_record_from_app_details "$app_details" "$name1" "$name2" "$_record" || continue
		# 只用 SSAID 篩選 App，但送入完整 canonical AppState；禁止為了單寫 SSAID 清空陣列後觸發 AppOps reset。
		jq -c 'select(.ssaid != null and (.ssaid|tostring)!="" and (.ssaid|tostring)!="null")' 			"$_record" > "$_ssaid_only" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		[[ -s $_ssaid_only ]] && cat "$_ssaid_only" >> "$TMPDIR/.batch_appstate_ndjson"
	done < "$_list"
	rm -f "$_list" "$_record" "$_ssaid_only" 2>/dev/null
	if [[ -s $TMPDIR/.batch_appstate_ndjson ]]; then
		echoRgb "開始恢復含SSAID應用的完整AppState" "2"
		_batch_appstate_mode=1
		flush_batch_appstate
		_batch_appstate_mode=0
	else
		echoRgb "SSAID無備份值，已略過" "2"
	fi
}

# ======================================================
# 生成列表 / 檢查 / backup_media / wifi
# ======================================================
# 生成應用列表 (掃描所有已安裝 user app, 輸出到 appList.txt)
# 配合 blacklist/whitelist 過濾系統 app
Getlist() {
	case $MODDIR in
	/storage/emulated/0/Android/* | /data/media/0/Android/* | /sdcard/Android/*) echoRgb "請勿在$MODDIR內生成列表" "0" && exit 2 ;;
	esac
	#校驗選填是否正確
	[[ $blacklist_mode != "" ]] && isBoolean "$blacklist_mode" "blacklist_mode" && blacklist_mode="$nsx" || {
	echoRgb "選擇黑名單模式\n -音量上不輸出，音量下輸出應用列表" "2"
	get_version "不輸出" "輸出應用列表" && blacklist_mode="$branch"
	}
	txt="$TMPDIR/appList"
	[[ -f "$MODDIR/appList.txt" ]] && cat "$MODDIR/appList.txt" >"$txt"
	[[ ! -f $txt ]] && echo '#不需要備份的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market（忽略安裝包和數據）\n#不需要備份數據的應用請在開頭使用!注釋 比如：!酷安 com.coolapk.market（僅忽略數據）' >"$txt"
	echoRgb "請勿關閉腳本，等待提示結束"
	rgb_a=118
	starttime1="$(date -u "+%s")"
	echoRgb "提示! 腳本默認會屏蔽預裝應用 如需備份請添加預裝應用白名單" "0"
	Apk_info="$(appinfo "system|user|xposed" "label|pkgName|flag" | grep -Ev 'ice.message|com.topjohnwu.magisk' | tr '/:' '_')"
	xposed_name="$(echo "$Apk_info" | awk 'index("|" $3 "|", "|xposed|") {print $2}')"
	# 系統應用白名單用 awk 精確比對包名，不再組 grep -E 正則。
	# 原本 paste -sd'|' 遇到尾端空行會產生 trailing |，toybox/busybox grep 會報 bad regex: empty (sub)expression；
	# 同時包名裡的 . 也不應被當成正則萬用字元。
	Pre_installed_apps="$(echo "$Apk_info" | awk -v syslist="$system" '
		BEGIN {
			n = split(syslist, a, /[ \t\r\n]+/)
			for (i = 1; i <= n; i++) {
				if (a[i] != "" && a[i] !~ /^[#＃]/) sys[a[i]] = 1
			}
		}
		index("|" $3 "|", "|system|") && ($2 in sys) { print $1, $2 }
	')"
	# 在 Apk_info 被收窄前, 先存全系統包名集合 (供結尾「舊註解清理」用, 省去再跑一次 pm list packages)
	echo "$Apk_info" | awk '{print $2}' | sed '/^[[:space:]]*$/d' | sort -u > "$TMPDIR/.getlist_allpkg"
	Apk_info="$(printf '%s\n%s\n' "$(echo "$Apk_info" | awk '!index("|" $3 "|", "|system|") {print $1, $2}')" "$Pre_installed_apps" | sed '/^[[:space:]]*$/d' | sort -u)"
	[[ $Apk_info = "" ]] && {
	echoRgb "appinfo輸出失敗,請截圖畫面回報作者" "0"
	exit 2 ; } || Apk_info2="$(echo "$Apk_info" | cut -d' ' -f2)"
	Apk_Quantity="$(printf "%s\n" "$Apk_info" | awk 'END{print NR}')"
	echoRgb "列出第三方應用......." "2"
	i=0; rc=0; rd=0; Q=0; Qc=0; rb=0
	# 預先收集所有「待加進 txt」的行, 用暫存檔取代 REPLY2 字串拼接 (O(N²) → O(N))
	local appended="$TMPDIR/.getlist_append"
	: > "$appended"
	# 一次 awk 把所有 app 預分類, 取代主迴圈內的多次 grep/awk fork
	# 輸出格式: <類別>\t<原行>
	# 類別: BLACK / XPOSED / WHITE / PRELOAD / NORMAL
	local classified="$TMPDIR/.getlist_class"
	# 分類 awk: 同時做「已存在判斷」與「同名不同包重命名」, 主迴圈不再 fork grep/add_entry
	# 用 FNR==NR 先吃 $txt (現有清單): 收集已存在包名集合 exist[], 以及 app名→已被佔用 namecnt[]
	# 第二檔 (Apk_info) 才做分類; 輸出格式: <類別>\t<最終label>\t<pkg>
	echo "$Apk_info" | sed 's/[\/:()\[\]\-!]//g' > "$TMPDIR/.getlist_apkinfo"
	awk -v whitelist="$whitelist" \
		-v blacklist="$blacklist" \
		-v xposed="$xposed_name" '
		BEGIN {
			n = split(whitelist, _w, /[ \t\n]+/)
			for (k in _w) if (_w[k] != "") wl[_w[k]] = 1
			n = split(blacklist, _b, /[ \t\n]+/)
			for (k in _b) if (_b[k] != "" && _b[k] !~ /^[#＃]/) bl[_b[k]] = 1
			n = split(xposed, _x, /[ \t\n]+/)
			for (k in _x) if (_x[k] != "") xp[_x[k]] = 1
			preload_re = "(oneplus|miui|xiaomi|oppo|flyme|meizu|coloros)"
			preload_exact["com.android.soundrecorder"] = 1
			preload_exact["com.mfashiongallery.emag"] = 1
			preload_exact["com.mi.health"] = 1
			preload_exact["com.duokan.phone.remotecontroller"] = 1
			preload_exact["com.android.calendar"] = 1
			preload_exact["com.android.deskclock"] = 1
			preload_exact["com.google.android.safetycore"] = 1
			preload_exact["com.google.android.contactkeys"] = 1
			preload_exact["com.google.android.apps.messaging"] = 1
			preload_exact["com.google.android.calendar"] = 1
		}
		# 第一檔: 現有 $txt — 收集已存在 pkg 與 app名已佔用情況
		FNR==NR {
			# 包名永遠是最後一欄 $NF; label 是前面所有欄位 (app 名可能含空格)
			# (註解行如 "#日曆 com.google...calendar" 也要排除該 app 重複輸出)
			if (NF < 2) next
			_cpkg = $NF
			_clabel = $1
			for (_j = 2; _j < NF; _j++) _clabel = _clabel " " $_j
			if ($0 ~ /^[#＃!]/) {
				exist_cmt[_cpkg] = 1       # 被註解(#/!)的已存在包名
			} else {
				exist[_cpkg] = 1           # 正常已存在包名
				namepkg[_clabel] = _cpkg   # 同名衝突判斷只看非註解行
				used[_clabel] = 1
			}
			next
		}
		# 第二檔: Apk_info — 分類
		{
			# 防禦: 跳過空行或缺包名的行 (避免產生空 pkg 分類, 與 Apk_Quantity 計數不一致)
			if (NF < 2) next
			# 包名永遠是最後一欄 $NF; label 是前面所有欄位 (app 名可能含空格)
			pkg = $NF
			label = $1
			for (_j = 2; _j < NF; _j++) label = label " " $_j
			# 已存在(正常) → EXIST; 已存在(被註解) → EXIST_CMT; 兩者主迴圈都只計數跳過
			if (pkg in exist)     { print "EXIST\t"     label "\t" pkg; next }
			if (pkg in exist_cmt) { print "EXIST_CMT\t" label "\t" pkg; next }
			# 同名不同包 → 加數字後綴 (與 add_entry 等價)
			final = label
			if ((label in used) && namepkg[label] != pkg) {
				c = 1
				while ((final = label "_" c) in used) c++
			}
			used[final] = 1; namepkg[final] = pkg
			if (pkg in bl)        { print "BLACK\t"      final "\t" pkg; next }
			if (pkg ~ preload_re || pkg in preload_exact) {
				if (pkg in xp)    { print "PRELOAD_XP\t" final "\t" pkg; next }
				if (pkg in wl)    { print "PRELOAD_WL\t" final "\t" pkg; next }
				print "PRELOAD\t" final "\t" pkg; next
			}
			if (pkg in xp)        { print "XPOSED\t"     final "\t" pkg; next }
			print "NORMAL\t" final "\t" pkg
		}' "$txt" "$TMPDIR/.getlist_apkinfo" > "$classified"
	rm -f "$TMPDIR/.getlist_apkinfo"
	[[ -n "$(echo "$blacklist" | grep -Ev '#|＃')" ]] && NZK=1
	# 主迴圈: 從分類結果讀, 每行已預先標好類別
	LR=1
	local _seen=0   # 核對1: 迴圈實際處理的 app 數, 應 == Apk_Quantity
	# 分類 awk 已算好最終 label 與已存在判斷, 迴圈內不再 fork (grep/cat/add_entry 全消除)
	while IFS=$'\t' read -r kind app_label app_pkg; do
		[[ -z $app_pkg ]] && continue
		let _seen++
		[[ $rgb_a -ge 229 ]] && rgb_a=118
		app_name="$app_label"
		REPLY="$app_label $app_pkg"
		case $kind in
		EXIST)
			let Q++
			let LR++; let rgb_a++
			continue
			;;
		EXIST_CMT)
			let Qc++
			echoRgb "$app_name 已註解 略過輸出" "0"
			let LR++; let rgb_a++
			continue
			;;
		BLACK)
			if [[ $NZK = 1 ]]; then
				if [[ $blacklist_mode = false ]]; then
					echo "$REPLY" >> "$appended"
					tmp=1
					echoRgb "$((i+1)):$app_name $app_pkg($rgb_a)"
					let i++ rb++
				else
					echoRgb "$app_label黑名單應用 不輸出" "0"
					let rb++
				fi
			fi
			let LR++; let rgb_a++
			continue
			;;
		PRELOAD_XP)
			echoRgb "$((i+1)):$app_name為Xposed模塊 進行添加" "0"
			echo "$REPLY" >> "$appended"
			tmp=1
			let i++ rd++
			;;
		PRELOAD_WL)
			echo "$REPLY" >> "$appended"
			tmp=1
			echoRgb "$((i+1)):$app_name $app_pkg($rgb_a)"
			let i++
			;;
		PRELOAD)
			echoRgb "$app_name 預裝應用 忽略輸出" "0"
			echo "#$REPLY" >> "$appended"
			tmp=1
			let rc++
			;;
		XPOSED)
			echo "$REPLY" >> "$appended"
			tmp=1
			echoRgb "$((i+1)):Xposed: $app_name $app_pkg($rgb_a)"
			let i++ rd++
			;;
		NORMAL|*)
			echo "$REPLY" >> "$appended"
			tmp=1
			echoRgb "$((i+1)):$app_name $app_pkg($rgb_a)"
			let i++
			;;
		esac
		let LR++; let rgb_a++
	done < "$classified"
	# 核對1 用: 先記錄合併前 txt 既有的有效行數 (非註解) — 須在 append 前取
	local _old_eff
	_old_eff=$(awk '/^[[:space:]]*$/{next} /^[[:space:]]*[#＃!]/{next} {c++} END{print c+0}' "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})
	local _chk_fail=0
	# ====== 數量核對1: 全員到齊 (無論有無新輸出都檢查) ======
	# 迴圈處理數 _seen 應 == 分類檔行數, 且 == 系統第三方總數 Apk_Quantity
	local _cls_lines
	_cls_lines=$(awk 'END{print NR+0}' "$classified" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})
	if [[ ${_seen:-0} -ne ${_cls_lines:-0} ]]; then
		echoRgb "⚠️ 數量核對1異常: 迴圈處理=$_seen 但分類檔行數=$_cls_lines (迴圈漏讀)" "0"
		_chk_fail=1
	elif [[ ${_seen:-0} -ne ${Apk_Quantity:-0} ]]; then
		echoRgb "⚠️ 數量核對1異常: 已分類=$_seen 但第三方總數=$Apk_Quantity (分類前後數量不符)" "0"
		_chk_fail=1
	else
		echoRgb "✅ 數量核對1: 全部 $Apk_Quantity 個 app 皆已分類處理" "1"
	fi
	# 把累積的 append 一次寫進 txt
	if [[ -s $appended ]]; then
		# 修復: txt 結尾若缺換行符, 直接 append 會與新內容第一行黏成一行 (已知問題根因)
		[[ -s $txt ]] && [[ -n "$(tail -c1 "$txt")" ]] && echo >> "$txt"
		cat "$appended" >> "$txt"
		echoRgb "已經將預裝應用輸出至appList.txt並注釋# 需要備份則去掉#" "0"
		[[ -n $tmp ]] && echoRgb "\n -第三方apk數量=\"$Apk_Quantity\"\n -已過濾=\"$rc\"\n -xposed=\"$rd\"\n -黑名單應用=\"$rb\"\n -存在列表中=\"$Q\"\n -已註解略過=\"$Qc\"\n -輸出=\"$i\""
		# ====== 數量核對2: 輸出行 (僅在有新輸出時) ======
		# 合併後有效行 應 == 合併前有效行 + 本次輸出 i
		local _eff_lines _expect _new_eff
		_eff_lines=$(awk '/^[[:space:]]*$/{next} /^[[:space:]]*[#＃!]/{next} {c++} END{print c+0}' "$txt")
		# 本次 append 的非註解有效行數 (輸出 i 含註解行, 不可全加)
		_new_eff=$(awk '/^[[:space:]]*$/{next} /^[[:space:]]*[#＃!]/{next} {c++} END{print c+0}' "$appended" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})
		_expect=$(( ${_old_eff:-0} + ${_new_eff:-0} ))
		if [[ $_eff_lines -ne $_expect ]]; then
			echoRgb "⚠️ 數量核對2異常: 列表有效行=$_eff_lines 但預期(原有$_old_eff+本次新增有效$_new_eff)=$_expect" "0"
			_chk_fail=1
		else
			echoRgb "✅ 數量核對2: 列表有效行=$_eff_lines (原有$_old_eff+本次新增有效$_new_eff)" "1"
		fi
	else
		# 無新輸出 (全部已存在/已註解): 顯示統計, 核對2 不適用
		[[ -n $tmp ]] && echoRgb "\n -第三方apk數量=\"$Apk_Quantity\"\n -已過濾=\"$rc\"\n -xposed=\"$rd\"\n -黑名單應用=\"$rb\"\n -存在列表中=\"$Q\"\n -已註解略過=\"$Qc\"\n -輸出=\"$i\""
		echoRgb "本次無新增應用 (全部已存在或已註解)" "2"
	fi
	# 任一核對失敗 → 中止, 不寫出可能有誤的列表
	if [[ $_chk_fail = 1 ]]; then
		echoRgb "\n -輸出異常 數量核對不通過 請聯繫作者解決" "0"
		rm -rf "$txt"
		rm -f "$appended" "$classified"
		exit
	fi
	rm -f "$appended" "$classified"
	# 結尾過濾: 對 txt 內的每行檢查 pkg 是否還在系統內, 不在的刪掉
	# 用一個 awk 一次處理 (取代原本 per-row fork awk)
	if [[ -f $txt ]]; then
		local pkg_set="$TMPDIR/.getlist_pkgset"
		echo "$Apk_info2" > "$pkg_set"
		# 註解行用「全系統已裝包名」判斷 (Apk_info2 僅第三方+白名單預裝, 會誤刪系統 app)
		# 直接複用開頭 appinfo 已存的全包名集合, 不再跑 pm list packages (省一次全系統查詢)
		local all_pkg_set="$TMPDIR/.getlist_allpkg"
		local _allpkg_n
		_allpkg_n="$(wc -l < "$all_pkg_set" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || echo 0)"
		local filtered="$TMPDIR/.getlist_filtered"
		# 三檔: (1)第三方清單 existing[] (2)全系統清單 allpkg[] (3)txt 逐行判斷
		awk -v allpkg_n="$_allpkg_n" '
			# 第一檔: 第三方清單
			FNR==NR { existing[$1]=1; next }
			# 第二檔: 全系統清單
			FILENAME == ALLF { allpkg[$1]=1; next }
			# 第三檔: txt
			/^[[:space:]]*$/ { print; next }
			/^[[:space:]]*[#＃!]/ {
				cpkg = $2
				if (cpkg ~ /^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$/) {
					# 合法包名的註解行: 全系統清單為空時一律保留(防 pm 失敗誤刪), 否則查全系統存在性
					if (allpkg_n == 0 || cpkg in allpkg) print
					else print "##__MISSING__\t" $0
				} else {
					print   # 說明行 / 無合法包名 → 保留
				}
				next
			}
			{
				pkg = $2
				if (pkg == "" || pkg in existing) print
				else print "##__MISSING__\t" $0
			}' ALLF="$all_pkg_set" "$pkg_set" "$all_pkg_set" "$txt" > "$filtered"
		# 印出被刪除的行 (給用戶看)
		grep '^##__MISSING__' "$filtered" | sed 's/^##__MISSING__\t//' | while read -r missing_line; do
			echoRgb "$missing_line不存在系統，從列表中刪除" "0"
		done
		# 寫回 txt (排序, 去空行)
		grep -v '^##__MISSING__' "$filtered" \
			| sed -e '/^$/d' | sort > "$txt"
		rm -f "$pkg_set" "$all_pkg_set" "$filtered"
	fi
	# ====== appList.txt 結構驗證 (類似 JSON 自動檢查) ======
	# 檢查: 非註解行欄位數=2、包名格式合法、包名無重複
	if [[ -f $txt ]]; then
		echoRgb "—————— 應用列表結構驗證 ——————" "3"
		local _lc_err="$TMPDIR/.applist_err"
		: > "$_lc_err"
		awk '
			/^[[:space:]]*$/      { next }
			/^[[:space:]]*[#＃!]/ { next }
			{
				total++
				if (NF != 2) { print "欄位數異常(" NF "欄): " $0; next }
				pkg = $2
				if (pkg !~ /^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$/) print "包名格式可疑: " $1 " " pkg
				if (pkg in seen) print "包名重複: " pkg " (與 " seen[pkg] " 重複)"
				else seen[pkg] = $1
			}
			END { print "##TOTAL##\t" total > "/dev/stderr" }
		' "$txt" 2> "$TMPDIR/.applist_cnt" >> "$_lc_err"
		local _lc_total
		_lc_total="$(awk -F'\t' '/^##TOTAL##/{print $2}' "$TMPDIR/.applist_cnt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		rm -f "$TMPDIR/.applist_cnt"
		if [[ -s $_lc_err ]]; then
			echoRgb "列表驗證發現異常:" "0"
			while read -r _el; do echoRgb "❌ $_el" "0"; done < "$_lc_err"
			echoRgb "請檢查 appList.txt 後再進行備份" "0"
		else
			echoRgb "✅ 列表結構正常 (${_lc_total:-0} 個有效應用)" "1"
		fi
		rm -f "$_lc_err"
	fi
	endtime 1
	cat "$txt">"$MODDIR/appList.txt" && rm "$txt"
	chown "$(stat -c '%u:%g' '/data/media/0/Download')" "$MODDIR/appList.txt"
	echoRgb "輸出包名結束 請查看$MODDIR/appList.txt"
}
# 備份自定義資料夾 (來自 Custom_path 設定)
# 例: Pictures / Download / DCIM / /data/adb 等
# 結尾設 REMOTE_UPLOAD_MEDIA=1 + REMOTE_TRIGGER=1
backup_media() {
	self_test
	backup_path
	show_conf media
	# 清除可能殘留的遠端json快取: backup_media 本身不會建立這個快取(只有批量備份的
	# prepare_remote_json_map 會), 但若先前跑過批量備份或中斷的測試留下舊快取,
	# _get_remote_appdetails 會一直讀到僵死的舊內容, 導致增量比對永遠用錯誤的舊資料
	rm -rf "$TMPDIR/.remote_json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# 流式上傳路徑快取: 在 Compression_method 還未被 Backup_data() 暫時污染前固定一次
	_BACKUP_DIRNAME_CACHED="$(get_backup_dirname)"
	# 快照備份前遠端大小 (backup() 主函數才有做這個快照, backup_media 是獨立函數需自己補上,
	# 否則沿用上次殘留的全域變數值, 導致結尾差異統計算出離譜的數字)
	if [[ -n $remote_type ]]; then
		_RTOTAL_BEFORE="$(remote_dir_size "$_BACKUP_DIRNAME_CACHED" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		[[ -z $_RTOTAL_BEFORE ]] && _RTOTAL_BEFORE=0
		_speed_debug_log "REMOTE_TOTAL_BEFORE subdir=$_BACKUP_DIRNAME_CACHED bytes=$_RTOTAL_BEFORE"
	fi
	echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊start.sh選擇終止腳本,否則腳本將繼續執行直到結束" "0"
	A=1
	B="$(printf "%s\n" "$Custom_path" | awk '!/[#＃]/ && NF{count++} END{print count}')"
	if [[ $B != "" ]]; then
		starttime1="$(date -u "+%s")"
		Backup_folder="$Backup/Media"
		app_details="$Backup_folder/app_details.json"
		mediatxt="$Backup/mediaList.txt"
		if [[ $remote_stream = 1 && -n $remote_type ]]; then
			_STREAM_DEST="Media"
			Backup_folder="$TMPDIR/.stream_stage/Media"
			app_details="$Backup_folder/app_details.json"
			mediatxt="$TMPDIR/.stream_stage/mediaList.txt"
			mkdir -p "$Backup_folder" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		fi
		# 延遲建立: 只有實際備份了至少一個資料夾才建立 Media/txt 等 (避免空殼)
		_media_created=0
		_ensure_media_dirs() {
			[[ $_media_created = 1 ]] && return
			if [[ $remote_stream = 1 && -n $remote_type ]]; then
				[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
			else
				[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
				[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
				[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
				[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
			fi
			[[ ! -f $app_details ]] && echo "{\n}">"$app_details"
			[[ ! -f $mediatxt ]] && echo "#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download" > "$mediatxt"
			filesize="$(calc_dir_size "$Backup_folder")"
			_media_created=1
		}
		Set_screen_pause_seconds on
		notification "109" "Media備份開始"
		echo "$Custom_path" | sed -e '/^#/d; /^$/d; s/\/$//' > "$TMPDIR/.media_custom_paths"
		while read -r; do
			echoRgb "備份第$A/$B個資料夾 剩下$((B - A))個" "3"
			starttime2="$(date -u "+%s")"
			if [[ ${REPLY##*/} = adb ]]; then
				if [[ $ksu != ksu ]]; then
					echoRgb "Magisk adb"
					_ensure_media_dirs
					Backup_data "${REPLY##*/}" "$REPLY"
				else
					echoRgb "KernelSU adb不支持備份" "0"
				fi
			else
				_ensure_media_dirs
				Backup_data "${REPLY##*/}" "$REPLY"
			fi
			endtime 2 "${REPLY##*/}備份" "1"
			echoRgb "完成$(safe_percent "$A" "$B")% $(progress_bar $(safe_percent "$A" "$B"))$(_progress_local_storage_suffix)" "2" && echoRgb "____________________________________" && let A++
		done < "$TMPDIR/.media_custom_paths"
		rm -f "$TMPDIR/.media_custom_paths"
		# 收尾: 若 Media 內無任何備份檔 (全部跳過/不支持), 清掉空殼避免上傳空目錄
		# 流式模式: .tar 壓縮完即上傳, 本機 $Backup_folder 永遠不會留有 .tar 檔 (設計如此),
		# 故改用 _media_created 旗標 (有實際處理過至少一個資料夾才會被設成1) 判斷, 不能沿用本機檔案掃描
		if [[ $remote_stream = 1 && -n $remote_type ]]; then
			if [[ $_media_created != 1 ]]; then
				echoRgb "Media 無實際備份內容, 清除 mediaList.txt" "0"
				rm -rf "$Backup_folder" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				[[ -f $mediatxt ]] && [[ ! -s $mediatxt || $(grep -vc "^#" "$mediatxt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) = 0 ]] && rm -f "$mediatxt"
			else
				REMOTE_UPLOAD_MEDIA=1
				# 只有 app_details 真的有實際內容(非初始空殼)才上傳, 避免「全部資料夾無變化跳過」
				# 時, 本地空殼覆蓋掉遠端原本正確的版本
				if [[ -f $app_details ]] && jq -e 'length > 0' "$app_details" >/dev/null 2>&1; then
					_stream_upload "Media/app_details.json" < "$app_details"
					[[ -f $mediatxt ]] && _stream_upload "mediaList.txt" < "$mediatxt"
					echoRgb "Media 清單已上傳遠端" "1"
				else
					echoRgb "Media 本輪全部資料夾無變化, 跳過json上傳(避免覆蓋遠端正確版本)" "2"
				fi
			fi
		elif [[ -d $Backup_folder ]] && ! find "$Backup_folder" -maxdepth 1 -name "*.tar*" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -q .; then
			echoRgb "Media 無實際備份內容, 清除空目錄與 mediaList.txt" "0"
			rm -rf "$Backup_folder"
			[[ -f $mediatxt ]] && [[ ! -s $mediatxt || $(grep -vc "^#" "$mediatxt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) = 0 ]] && rm -f "$mediatxt"
		else
			[[ $remote_stream != 1 ]] && Calculate_size "$Backup_folder"
			[[ -n $remote_type ]] && REMOTE_UPLOAD_MEDIA=1
		fi
		Set_screen_pause_seconds off
		endtime 1 "自定義備份"
		notification "109" "Media備份完成 $(endtime 1 "自定義備份")"
	else
		echoRgb "自定義路徑為空 無法備份" "0"
	fi
	REMOTE_TRIGGER=1
	# subshell 環境下 trap EXIT 在主 shell 不會觸發, 這裡直接呼叫
	remote_cleanup
	cleanup_tmpdir_contents || return 1
}
# HttpUtil 分片下載/解析 Device_List；避免 Android 16 app_process 單一 Dex 行程連續 HTTPS 下載時 native abort。
# 每個品牌由 Dex HttpUtil get 短行程下載，shell 只負責合併既有格式；全部失敗才 fallback 舊 shell 流程。
_device_list_httputil_sharded_download() {
	local _out="$1" _dex_log _tmp_body _ok _fail _i Brand_URL URL model
	[[ -n $_out ]] || return 1
	URL="https://raw.githubusercontent.com/KHwang9883/MobileModels/refs/heads/master/brands"
	_dex_log="$(_speed_debug_log_path device_list_dex.log)"
	_ok=0
	_fail=0
	rm -f "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	for _i in $(echo "xiaomi\nxiaomi_en\nsamsung\nsamsung_global\nasus\nBlack_Shark\nBlack_Shark_en\ngoogle\nLenovo\nMEIZU\nMEIZU_en\nMotorola\nNokia\nnothing\nnubia\nOnePlus\nOnePlus_en\nSony\nrealme\nrealme_en\nvivo\nvivo_en\noppo\noppo_en"); do
		case $_i in
		xiaomi) Brand_URL="$URL/xiaomi.md" ;;
		xiaomi_en) Brand_URL="$URL/xiaomi_en.md" ;;
		samsung) Brand_URL="$URL/samsung_cn.md" ;;
		samsung_global) Brand_URL="$URL/samsung_global_en.md" ;;
		asus) Brand_URL="$URL/asus_cn.md" ;;
		Black_Shark) Brand_URL="$URL/blackshark.md" ;;
		Black_Shark_en) Brand_URL="$URL/blackshark_en.md" ;;
		google) Brand_URL="$URL/google.md" ;;
		Lenovo) Brand_URL="$URL/lenovo_cn.md" ;;
		MEIZU) Brand_URL="$URL/meizu.md" ;;
		MEIZU_en) Brand_URL="$URL/meizu_en.md" ;;
		Motorola) Brand_URL="$URL/motorola_cn.md" ;;
		Nokia) Brand_URL="$URL/nokia_cn.md" ;;
		nothing) Brand_URL="$URL/nothing.md" ;;
		nubia) Brand_URL="$URL/nubia.md" ;;
		OnePlus) Brand_URL="$URL/oneplus.md" ;;
		OnePlus_en) Brand_URL="$URL/oneplus_en.md" ;;
		Sony) Brand_URL="$URL/sony_cn.md" ;;
		realme) Brand_URL="$URL/realme_cn.md" ;;
		realme_en) Brand_URL="$URL/realme_global_en.md" ;;
		vivo) Brand_URL="$URL/vivo_cn.md" ;;
		vivo_en) Brand_URL="$URL/vivo_global_en.md" ;;
		oppo) Brand_URL="$URL/oppo_cn.md" ;;
		oppo_en) Brand_URL="$URL/oppo_global_en.md" ;;
		*) continue ;;
		esac
		_tmp_body="${TMPDIR:-/data/local/tmp}/.device_list_dex_body_${$}_${RANDOM:-0}"
		rm -f "$_tmp_body" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		echoRgb "Dex 獲取品牌$_i"
		if _dex_exec_unfiltered com.xayah.dex.HttpUtil get "$Brand_URL" > "$_tmp_body" 2>>"$_dex_log"; then
			if [[ -s $_tmp_body ]]; then
				_ok=$((_ok+1))
				grep -oE '`[^`]+`:[^`]*' "$_tmp_body" 2>>"$_dex_log" | sed -E 's/: /:/g' | sed -E 's/`([^`]+)`:(.*)/"\1" "\2"/' | while read -r REPLY; do
					[[ -n $REPLY ]] || continue
					model="$(echo "$REPLY" | awk -F'"' '{print $2}')"
					[[ -n $model ]] || continue
					if [[ ! -e $_out ]] || [[ $(grep -Ew "$model" "$_out" 2>/dev/null | awk -F'"' '{print $2}' | head -n 1) != "$model" ]]; then
						echo "$REPLY" >> "$_out"
					fi
				done
			else
				_fail=$((_fail+1))
				echo "DEVICE_LIST_BRAND_FAIL name=$_i reason=empty_body url=$Brand_URL" >> "$_dex_log"
			fi
		else
			_fail=$((_fail+1))
			echo "DEVICE_LIST_BRAND_FAIL name=$_i reason=http_get_failed url=$Brand_URL" >> "$_dex_log"
		fi
		rm -f "$_tmp_body" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	done
	if [[ -s $_out ]]; then
		echo "DEVICE_LIST_OK mode=dex_httputil_sharded okBrands=$_ok failedBrands=$_fail size=$(stat -c%s "$_out" 2>/dev/null)" >> "$_dex_log"
		return 0
	fi
	echo "DEVICE_LIST_FAIL mode=dex_httputil_sharded okBrands=$_ok failedBrands=$_fail" >> "$_dex_log"
	return 1
}

# 從 tools/Device_List 對照表查詢設備識別資訊 (處理器型號、RAM 規格等)
Device_List() {
	URL="https://raw.githubusercontent.com/KHwang9883/MobileModels/refs/heads/master/brands"
	rm -rf "$tools_path/Device_List"
	echoRgb "使用 Dex HttpUtil 分片下載/解析機型列表" "3"
	if _device_list_httputil_sharded_download "$tools_path/Device_List"; then
		if [[ $(stat -c%s "$tools_path/Device_List" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) -gt 1 ]]; then
			[[ $shell_language = zh-TW ]] && ts_inplace "$tools_path/Device_List"
			echoRgb "已下載機型列表在$tools_path/Device_List"
			return 0
		fi
	fi
	echoRgb "Dex HttpUtil 機型列表下載失敗，回退 shell 下載流程" "2"
	_device_list_shell_log="$(_speed_debug_log_path device_list_shell.log)"
	rm -rf "$tools_path/Device_List"
	for i in $(echo "xiaomi\nxiaomi_en\nsamsung\nsamsung_global\nasus\nBlack_Shark\nBlack_Shark_en\ngoogle\nLenovo\nMEIZU\nMEIZU_en\nMotorola\nNokia\nnothing\nnubia\nOnePlus\nOnePlus_en\nSony\nrealme\nrealme_en\nvivo\nvivo_en\noppo\noppo_en"); do
		echoRgb "獲取品牌$i"
		case $i in
		xiaomi) Brand_URL="$URL/xiaomi.md" ;;
		xiaomi_en) Brand_URL="$URL/xiaomi_en.md" ;;
		samsung) Brand_URL="$URL/samsung_cn.md" ;;
		samsung_global) Brand_URL="$URL/samsung_global_en.md" ;;
		asus) Brand_URL="$URL/asus_cn.md" ;;
		Black_Shark) Brand_URL="$URL/blackshark.md" ;;
		Black_Shark_en) Brand_URL="$URL/blackshark_en.md" ;;
		google) Brand_URL="$URL/google.md" ;;
		Lenovo) Brand_URL="$URL/lenovo_cn.md" ;;
		MEIZU) Brand_URL="$URL/meizu.md" ;;
		MEIZU_en) Brand_URL="$URL/meizu_en.md" ;;
		Motorola) Brand_URL="$URL/motorola_cn.md" ;;
		Nokia) Brand_URL="$URL/nokia_cn.md" ;;
		nothing) Brand_URL="$URL/nothing.md" ;;
		nubia) Brand_URL="$URL/nubia.md" ;;
		OnePlus) Brand_URL="$URL/oneplus.md" ;;
		OnePlus_en) Brand_URL="$URL/oneplus_en.md" ;;
		Sony) Brand_URL="$URL/sony_cn.md" ;;
		realme) Brand_URL="$URL/realme_cn.md" ;;
		realme_en) Brand_URL="$URL/realme_global_en.md" ;;
		vivo) Brand_URL="$URL/vivo_cn.md" ;;
		vivo_en) Brand_URL="$URL/vivo_global_en.md" ;;
		oppo) Brand_URL="$URL/oppo_cn.md" ;;
		oppo_en) Brand_URL="$URL/oppo_global_en.md" ;;
		esac
		if [[ ! -e $tools_path/Device_List ]]; then
			down "$Brand_URL" 2>>"$_device_list_shell_log" | grep -oE '`[^`]+`:[^`]*' | sed -E 's/: /:/g' | sed -E 's/`([^`]+)`:(.*)/"\1" "\2"/'>"$tools_path/Device_List"
		else
			down "$Brand_URL" 2>>"$_device_list_shell_log" | grep -oE '`[^`]+`:[^`]*' | sed -E 's/: /:/g' | sed -E 's/`([^`]+)`:(.*)/"\1" "\2"/' | while read -r; do
				unset model
				model="$(echo "$REPLY" | awk -F'"' '{print $2}')"
				if [[ $(grep -Ew "$model" "$tools_path/Device_List" | awk -F'"' '{print $2}') != $model ]]; then
					echo "$REPLY">>"$tools_path/Device_List"
				else
					echo "$(grep -Ew "$model" "$tools_path/Device_List" | awk -F'"' '{print $2}') = $model"
				fi
			done
		fi
	done
	if [[ -e $tools_path/Device_List ]]; then
		if [[ $(stat -c%s "$tools_path/Device_List" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) -gt 1 ]]; then
			[[ $shell_language = zh-TW ]] && ts_inplace "$tools_path/Device_List"
			echoRgb "已下載機型列表在$tools_path/Device_List"
		else
			echoRgb "下載機型失敗"
		fi
	else
		echoRgb "下載機型失敗"
	fi
}
# 主選單「備份WiFi」入口
# 建立備份目錄結構 + 複製 tools/ + 生成 start.sh + 備份 wifi.json
wifi() {
	backup_path
	show_conf wifi
	[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
	[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
	[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
	backup_wifi "$Backup/wifi"
	[[ -n $remote_type ]] && REMOTE_UPLOAD_WIFI=1
}
# ======================================================
# 主選單入口
# ======================================================
if [[ $0 = *backup.sh ]]; then
	start=backup
elif [[ $0 = *upload.sh ]]; then
	# upload.sh 位於 Backup_zstd_X/<app>/upload.sh
	# MODDIR 已被入口腳本設成 Backup_zstd_X
	# 取得 app 名 = upload.sh 所在的資料夾名
	_upload_app="${0%/*}"
	_upload_app="${_upload_app##*/}"
	start="single_upload \"$_upload_app\""
else
	[[ $0 = *recover.sh ]] && start=Restore
fi
if [[ $start != "" ]]; then
	# 單獨入口由入口主線等待工作完成後統一 final 打包。
	# 避免 background_execution=1 或 tee/pipeline 場景下，EXIT trap 早於實際工作完成而刪除 run_xxx。
	_entry_bg="$(grep -o 'background_execution=.*' "$conf_path" | awk -F '=' '{print $2}')"
	case $_entry_bg in
	1)
		( eval "$start" ) &
		_entry_pid=$!
		wait "$_entry_pid"
		_entry_rc=$?
		;;
	*)
		eval "$start"
		_entry_rc=$?
		;;
	esac
	# 函數若已主動 final 打包，這裡會自動跳過；未打包的單獨 upload / media / wifi 等入口則在這裡補齊。
	_speed_debug_normal_finish_pack "${_entry_rc:-0}"
	exit "${_entry_rc:-0}"
else
	# 主選單循環: 跑完一個動作回到選單繼續
	# 備份類動作 (backup/backup_update_apk/backup_media/wifi) 跑完直接退出整個腳本
	# 其他動作 (Getlist/remote_test/list/download) 跑完回選單
	while true; do
	# 使用逐行資料取代 shell array，避免 mksh/busybox parser 差異。
	steps_data=
	commands_data=
	if [[ -f $MODDIR/backup_settings.conf ]]; then
		steps_data="$(cat <<'SPEEDBACKUP_STEPS_BACKUP'
生成應用列表
備份應用
備份已更新應用
備份自定義資料夾
備份WiFi
測試遠端連線
單獨上傳當前備份
列出遠端備份(產生 appList_network.txt)
從遠端下載備份
從遠端流式恢復(不佔本機)
目前備份統計
重生現有備份JSON(保留Size/版本/時間/SSAID)
殺死運行中腳本
SPEEDBACKUP_STEPS_BACKUP
)"
		commands_data="$(cat <<'SPEEDBACKUP_COMMANDS_BACKUP'
Getlist
backup; exit
backup_update_apk; exit
backup_media; _rc=$?; _speed_debug_normal_finish_pack $_rc; exit $_rc
wifi; _rc=$?; _speed_debug_normal_finish_pack $_rc; exit $_rc
remote_test_menu
upload_current_backup
remote_list_backups
remote_download_backup
remote_stream_restore; _rc=$?; _speed_debug_normal_finish_pack $_rc; exit $_rc
Stats_Dispatch
Json_refresh_menu
echoRgb '等待腳本停止中，請稍後.....' && echoRgb '腳本終止'; exit
SPEEDBACKUP_COMMANDS_BACKUP
)"
	elif [[ -f $MODDIR/restore_settings.conf ]]; then
		steps_data="$(cat <<'SPEEDBACKUP_STEPS_RESTORE'
重新生成應用列表
恢復備份
僅恢復包含ssaid應用(含數據)
僅恢復包含SSAID應用的App狀態(不含數據)
恢復自定義資料夾
恢復wifi
壓縮檔完整性檢查
JSON結構檢查
重生現有備份JSON(保留Size/版本/時間/SSAID)
轉換文件夾名稱
殺死運行中腳本
SPEEDBACKUP_STEPS_RESTORE
)"
		commands_data="$(cat <<'SPEEDBACKUP_COMMANDS_RESTORE'
dumpname
Restore; exit
ssaid_mode=true && Restore; exit
ssaid_mode_1=true && Restore4; _rc=$?; _speed_debug_normal_finish_pack $_rc; exit $_rc
Restore3; _rc=$?; _speed_debug_normal_finish_pack $_rc; exit $_rc
recover_wifi "$MODDIR/wifi"; _rc=$?; _speed_debug_normal_finish_pack $_rc; exit $_rc
check_file
Check_json
Json_refresh_menu
convert
echoRgb '等待腳本停止中，請稍後.....' && echoRgb '腳本終止'; exit
SPEEDBACKUP_COMMANDS_RESTORE
)"
	fi
	step_count="$(printf '%s\n' "$steps_data" | awk 'NF {n++} END {print n+0}')"
	echoRgb "請選擇要執行的操作："
	i=1
	while [[ $i -le $step_count ]]; do
		_step_label="$(printf '%s\n' "$steps_data" | sed -n "${i}p")"
		printf " -%d) %s\n" "$i" "$_step_label"
		i="$((i + 1))"
	done
	echo " -0) 離開腳本"
	echo -n " -請輸入選項編號: "
	# read 失敗 (stdin 關閉/EOF, 例如後台執行無 tty) 立刻退出,避免無限循環
	if ! read choice; then
		echoRgb "無互動 stdin, 退出" "0"
		exit 0
	fi
	case $choice in
	0)
		echoRgb "已退出腳本" "0"
		_speedbackup_lock_cleanup
		exit 0 ;;
	''|*[!0-9]*)
		echoRgb "輸入錯誤，請重新輸入有效的數字。" "0" ;;
	*)
		if [[ $choice -ge 1 && $choice -le $step_count ]]; then
			_selected_step="$(printf '%s\n' "$steps_data" | sed -n "${choice}p")"
			_selected_command="$(printf '%s\n' "$commands_data" | sed -n "${choice}p")"
			echo " -執行：$_selected_step"
			background="$(grep -o 'background_execution=.*' "$conf_path" | awk -F '=' '{print $2}')"
			if [[ "$background" = "1" ]]; then
				case $_selected_command in
				remote_test_menu*)
					# 功能 6 內部還有 SMB 掃描子選單，需要繼續讀取使用者輸入；
					# 背景 subshell 會讓子選單 read 讀到 EOF，因此這類互動診斷固定前台執行。
					eval "$_selected_command"
					;;
				*)
					# 後台執行: 用 subshell 防 exit 殺主 shell
					(eval "$_selected_command") &
					bg_pid=$!
					wait "$bg_pid"
					case $_selected_command in
					*exit*) exit 0 ;;
					esac
					;;
				esac
			else
				eval "$_selected_command"
			fi
		else
			echoRgb "超出功能選項範圍（1-$step_count）" "0"
		fi
		;;
	esac
	done
fi
