#!/system/bin/sh
# ============================================================
# SpeedBackup tools.sh
# ============================================================
# 區塊索引:
# 單檔內部分區索引:
#   00 core/conf/debug/root/version
#   10 remote/local/tar/zstd/common helpers
#   20 dex/wifi/update/selftest bridge
#   30 backup prepare/package maps/app_details
#   40 backup data/restore data/install apk
#   50 validation/appstate/restore helpers
#   60 backup main/media/statistics
#   70 restore/menu/entrypoint
# ============================================================
if [ "$(whoami)" != root ]; then
	echo "你是憨批？不給Root用你媽 爬"
	exit 1
fi
# 早期不再把 set -x 寫到 /data/cache；如需命令追蹤，請設 _dex_debug=1，會寫入 speed_debug/xtrace.log。
shell_language="zh-TW"
MODDIR_NAME="${MODDIR##*/}"
tools_path="$MODDIR/tools"
script="${0##*/}"
backup_version="202606211326"
speedbackup_patch_build="v24.20.14-7.66-201-lock-cleanup-fix-20260704"
# 7.66-163: 單檔發布，不 source sb_*.sh；162 模組化僅作重構實驗分支。

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
	_restore_defaults="restore_pm_install_with_installer=1 restore_play_install_keep_workdir=0 restore_play_install_fast_tmpdir_apk=1 restore_play_install_force_copy_apk=0 restore_play_install_verify_source=1 restore_play_install_bypass_low_target=auto restore_play_install_allow_test=1 restore_play_install_allow_downgrade=0 restore_play_install_grant_runtime_permissions=0 restore_play_install_dont_kill=0 restore_play_install_require_user_action=not_required restore_play_install_package_source=store restore_play_install_reason=user restore_play_install_location=auto restore_play_install_extra_flags= restore_play_install_human_log=0 restore_play_install_log_mode=summary"
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
		echo "pid=$$"
		echo "script=$0"
		echo "entry_script=${SPEEDBACKUP_ENTRY_SCRIPT:-}"
		echo "entry_mode=${SPEEDBACKUP_ENTRY_MODE:-}"
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
		app_state_stdin app_state_output permission_state_stdin \
		verify_app_state_stdin verify_app_state_output; do
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
		_conf_remove_internal_remote_function
		_conf_append_key diagnostic_mode 'diagnostic_mode="${diagnostic_mode:-0}"'
		_conf_append_key log_max_size_mb 'log_max_size_mb="${log_max_size_mb:-}"'
		_conf_append_key notification_enable 'notification_enable="${notification_enable:-1}"'
		_conf_append_key rgb_a 'rgb_a="${rgb_a:-220}"'
		_conf_append_key rgb_b 'rgb_b="${rgb_b:-51}"'
		_conf_append_key rgb_c 'rgb_c="${rgb_c:-213}"'
		_conf_append_key remote_type 'remote_type="${remote_type:-}"'
		_conf_append_key smb_url 'smb_url="${smb_url:-}"'
		_conf_append_key smb_remote_user 'smb_remote_user="${smb_remote_user:-}"'
		_conf_append_key smb_remote_pass 'smb_remote_pass="${smb_remote_pass:-}"'
		_conf_append_key webdav_url 'webdav_url="${webdav_url:-}"'
		_conf_append_key webdav_remote_user 'webdav_remote_user="${webdav_remote_user:-}"'
		_conf_append_key webdav_remote_pass 'webdav_remote_pass="${webdav_remote_pass:-}"'
		_conf_append_key remote_stream 'remote_stream="${remote_stream:-0}"'
		_conf_append_key remote_keep_local 'remote_keep_local="${remote_keep_local:-0}"'
		_conf_append_key remote_upload_per_app 'remote_upload_per_app="${remote_upload_per_app:-0}"'
		;;
	*restore_settings.conf)
		_conf_append_key diagnostic_mode 'diagnostic_mode="${diagnostic_mode:-0}"'
		_conf_append_key log_max_size_mb 'log_max_size_mb="${log_max_size_mb:-}"'
		_conf_append_key notification_enable 'notification_enable="${notification_enable:-1}"'
		_conf_append_key rgb_a 'rgb_a="${rgb_a:-220}"'
		_conf_append_key rgb_b 'rgb_b="${rgb_b:-51}"'
		_conf_append_key rgb_c 'rgb_c="${rgb_c:-213}"'
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

# 憑證改走檔案傳遞, 避免出現在命令行參數 (/proc/*/cmdline 任何本機進程可讀)
_SMB_AUTHFILE=""
_WEBDAV_NETRC=""
if [[ $remote_type = smb && -n $remote_user ]]; then
	_SMB_AUTHFILE="${TMPDIR:-/data/local/tmp}/.smb_authfile_$$"
	{
		printf 'username = %s\n' "$remote_user"
		printf 'password = %s\n' "$remote_pass"
	} > "$_SMB_AUTHFILE" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	chmod 0600 "$_SMB_AUTHFILE" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
elif [[ $remote_type = webdav && -n $remote_user ]]; then
	_WEBDAV_NETRC="${TMPDIR:-/data/local/tmp}/.webdav_netrc_$$"
	_webdav_host="${remote_url#*://}"
	_webdav_host="${_webdav_host%%/*}"
	_webdav_host="${_webdav_host%%:*}"
	printf 'machine %s login %s password %s\n' "$_webdav_host" "$remote_user" "$remote_pass" \
		> "$_WEBDAV_NETRC" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	chmod 0600 "$_WEBDAV_NETRC" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
fi

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

# JSON 原地更新 helper (取代 jq...>tmp...cat>...rm 模式)
# 用法: jq_inplace <檔案> <jq 表達式> [額外參數...]
# 例: jq_inplace "$app_details" --arg k "key" '.[$k] = "value"'
# 注意: 用 cat 寫回而不是 mv, 因為 Android 跨檔案系統 mv 會嘗試 setfilecon
# (sdcard 不支援會印 "Operation not supported on transport endpoint" 錯誤)
jq_inplace() {
	local file="$1"; shift
	local tmp="$TMPDIR/.jq_$$"
	if jq "$@" "$file" > "$tmp"; then
		cat "$tmp" > "$file"
		rm -f "$tmp"
	else
		rm -f "$tmp"
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
	# 純文件字節總和 (對應電腦端「大小」, 不含目錄項佔用); 單一 find 進程
	find "$1" -type f -printf '%s\n' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{s+=$1}END{print s+0}'
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
	case $_entry in user|data|obb|user_de|media) _mark_changed ;; esac
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

# json 健全度檢查: 檢查 app_details.json 是否含必要欄位
# 用法: _json_health_check <json路徑> <app顯示名>
# 必要欄位 (缺即視為異常, 會影響恢復/識別): PackageName, apk_version
# permissions/notification_settings/battery_opt/battery_settings/Ssaid 不是每個app都一定會產生 (取決於該app是否申請過runtime權限/
# 是否曾查到電池策略/是否使用裝置識別碼), 缺不代表異常, 單獨歸入弱提示
# 結果: 異常訊息 append 到 $TMPDIR/.json_health_issues, 弱提示 append 到 $TMPDIR/.json_health_hints
_json_health_check() {
	local _file="$1" _name="$2" _pkg _ver _has_perm _has_batt _has_notify _has_ssaid _issues="" _hints=""
	[[ ! -s $_file ]] && { echo "$_name: app_details.json 不存在或為空" >> "$TMPDIR/.json_health_issues"; return; }
	if ! jq -e . "$_file" >/dev/null 2>&1; then
		echo "$_name: json 格式損壞 (無法解析)" >> "$TMPDIR/.json_health_issues"
		return
	fi
	_pkg="$(jq -r 'try ([.[] | objects | select(.PackageName != null).PackageName] | .[0]) catch "" // ""' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	_ver="$(jq -r 'try ([.[] | objects | select(.apk_version != null).apk_version] | .[0]) catch "" // ""' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	_has_perm="$(jq -r 'try ([.[] | objects | select(.permissions != null)] | length) catch 0' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	_has_batt="$(jq -r 'try ([.[] | objects | select(.battery_opt != null or .battery_settings != null)] | length) catch 0' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	_has_notify="$(jq -r 'try ([.[] | objects | select(.notification_settings != null)] | length) catch 0' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	_has_ssaid="$(jq -r 'try ([.[] | objects | select(.Ssaid != null)] | length) catch 0' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	[[ -z $_pkg ]] && _issues="$_issues 缺PackageName"
	[[ -z $_ver ]] && _issues="$_issues 缺apk_version"
	# 新增欄位型態檢查：有欄位但不是 object，恢復端會讀取異常，視為嚴重問題
	if ! jq -e 'try all(.[] | objects | select(.permissions != null); (.permissions | type) == "object") catch true' "$_file" >/dev/null 2>&1; then
		_issues="$_issues permissions非object"
	fi
	if ! jq -e 'try all(.[] | objects | select(.notification_settings != null); (.notification_settings | type) == "object") catch true' "$_file" >/dev/null 2>&1; then
		_issues="$_issues notification_settings非object"
	fi
	if ! jq -e 'try all(.[] | objects | select(.battery_settings != null); (.battery_settings | type) == "object") catch true' "$_file" >/dev/null 2>&1; then
		_issues="$_issues battery_settings非object"
	fi
	# notification_settings key 格式檢查：只允許 NOTIFY_APP / NOTIFY_CHANNEL / NOTIFY_GROUP
	local _bad_notify_keys
	_bad_notify_keys="$(jq -r '
		try ([
			.[] | objects | select(.notification_settings != null)
			| .notification_settings
			| to_entries[]
			| select((.key | startswith("NOTIFY_APP:") or startswith("NOTIFY_CHANNEL:") or startswith("NOTIFY_GROUP:")) | not)
			| .key
		] | unique | join(",")) catch ""
	' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	[[ -n $_bad_notify_keys ]] && _issues="$_issues notification_settings未知key($_bad_notify_keys)"
	# battery_settings key/value 格式檢查
	# 合法 key:
	#   BATTERY:RUN_IN_BACKGROUND        "63 0 allow" 或 "0" 或 "allow"
	#   BATTERY:RUN_ANY_IN_BACKGROUND    "70 0 allow" 或 "0" 或 "allow"
	#   BATTERY:deviceidle_whitelist     true/false
	local _bad_batt_keys _bad_batt_vals
	_bad_batt_keys="$(jq -r '
		try ([
			.[] | objects | select(.battery_settings != null)
			| .battery_settings
			| to_entries[]
			| select((.key == "BATTERY:RUN_IN_BACKGROUND" or .key == "BATTERY:RUN_ANY_IN_BACKGROUND" or .key == "BATTERY:deviceidle_whitelist" or .key == "BATTERY:idle_whitelist" or .key == "BATTERY:doze_whitelist") | not)
			| .key
		] | unique | join(",")) catch ""
	' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	[[ -n $_bad_batt_keys ]] && _issues="$_issues battery_settings未知key($_bad_batt_keys)"
	_bad_batt_vals="$(jq -r '
		def batt_mode_ok:
			(type == "string") and
			(
				test("^[0-9]+( [0-9]+ [A-Za-z_]+)?$") or
				test("^(allow|allowed|ignore|ignored|deny|denied|errored|default|foreground|true|false)$"; "i")
			);
		try ([
			.[] | objects | select(.battery_settings != null)
			| .battery_settings
			| to_entries[]
			| select(
				if (.key == "BATTERY:deviceidle_whitelist" or .key == "BATTERY:idle_whitelist" or .key == "BATTERY:doze_whitelist") then
					((.value | tostring) | test("^(true|false)$"; "i") | not)
				elif (.key == "BATTERY:RUN_IN_BACKGROUND" or .key == "BATTERY:RUN_ANY_IN_BACKGROUND") then
					((.value | tostring) | batt_mode_ok | not)
				else
					false
				end
			)
			| "\(.key)=\(.value)"
		] | unique | join(",")) catch ""
	' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	[[ -n $_bad_batt_vals ]] && _issues="$_issues battery_settings值異常($_bad_batt_vals)"
	[[ -n $_issues ]] && echo "$_name:$_issues" >> "$TMPDIR/.json_health_issues"
	# 弱提示: 不視為異常，只是告知該欄位沒有紀錄
	[[ ${_has_perm:-0} -eq 0 ]] && _hints="$_hints 無permissions"
	[[ ${_has_notify:-0} -eq 0 ]] && _hints="$_hints 無notification_settings"
	[[ ${_has_batt:-0} -eq 0 ]] && _hints="$_hints 無battery_opt/battery_settings"
	[[ ${_has_ssaid:-0} -eq 0 ]] && _hints="$_hints SSAID無備份值"
	[[ -n $_hints ]] && echo "$_name:$_hints" >> "$TMPDIR/.json_health_hints"
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
		local _hcnt
		_hcnt="$(grep -vc '^$' "$TMPDIR/.json_health_hints" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		echoRgb "$_hcnt 個app有部分次要欄位未紀錄 (可能該app本來就沒有, 非異常):" "2"
		while read -r _hline; do
			[[ -n $_hline ]] && echoRgb "$_hline" "2"
		done < "$TMPDIR/.json_health_hints"
		rm -f "$TMPDIR/.json_health_hints"
	fi
	if [[ $_invalid_count -gt 0 || $_missing_count -gt 0 ]]; then
		echoRgb "⚠️ 遠端app_details無效/下載不完整 $((_invalid_count + _missing_count)) 個，已略過，不納入損壞回報" "2"
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
ln -fs "$tools_path/classes.dex" "$filepath/classes.dex"
export CLASSPATH="$filepath/classes.dex"
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
			curl)
				if [[ $remote_type = webdav ]]; then
					echoRgb "⚠️ $tools_path/$file: SHA-256 不一致，僅影響 WebDAV 遠端備份
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
		# smbclient/curl 是遠端可選工具；純本機模式不顯示遠端相關提示。
		case $file in
		smbclient)
			if [[ $remote_type = smb ]]; then
				echoRgb "⚠️ 檔案 $tools_path/$file 不存在 (僅影響 SMB 遠端備份)" "0"
			else
				_speed_debug_log "OPTIONAL_REMOTE_TOOL_MISSING file=$file remote_type=${remote_type:-none}"
			fi
			;;
		curl)
			if [[ $remote_type = webdav ]]; then
				echoRgb "⚠️ 檔案 $tools_path/$file 不存在 (僅影響 WebDAV 遠端備份)" "0"
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
zstd 9ef4b54148699c9874cfd45aaf38e5cc950e5d168afdcf2edf58a2463f5561ed
tar 882639ac310a7eb4052c68c21cea02633307700f9cc8c7c469c2dd18d734a112
classes.dex 845ebb028f0a54dcac033d7f91c1855a4965357e8024ecc108254498a4fe4172
busybox 4d60ab3f5a59ebb2ca863f2f514e6924401b581e9b64f602665c008177626651
find 7fa812e58aafa29679cf8b50fc617ecf9fec2cfb2e06ea491e0a2d6bf79b903b
jq 6bc62f25981328edd3cfcfe6fe51b073f2d7e7710d7ef7fcdac28d4e384fc3d4
keycheck 50645ee0e0d2a7d64fb4a1286446df7a4445f3d11aefd49eeeb88515b314c363
cmd 08da8ac23b6e99788fd3ce6c19c7b5a083b2ad48be35963a48d01d6ee7f3bb6d
smbclient 0fe8aa0abcf2ab81387d25dfb4a47369925e475bcf0c32acc9846753775ec35e
curl c78079c0239f0a6c44aa7e9180f97d4c3d175495d1ccf565a8854abd15f68b60
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
	local _ver_log="${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/tools_version.log" _dex_ver_line=""
	[[ -f $tools_path/classes.dex ]] && _dex_ver_line="$(get_dex_version_line)"
	SPEED_DEBUG_LAST_DEX_VERSION="$_dex_ver_line"
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
		# curl
		which curl >/dev/null 2>&1 && {
			echo "[curl]"
			curl --version 2>&1 | head -3
			echo ""
		}
		# smbclient
		which smbclient >/dev/null 2>&1 && {
			echo "[smbclient]"
			smbclient --version 2>&1 | head -1
			echo ""
		}
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
	# v24.20.14-7.23：dex 版本啟動期只允許 app_process --version 跑一次。
	# dex precheck 先取得並寫入 SPEED_DEBUG_LAST_DEX_VERSION；後續工具版本、設備資訊、show_dex_version 全部讀快取。
	if [[ -n ${SPEED_DEBUG_LAST_DEX_VERSION:-} ]]; then
		echo "$SPEED_DEBUG_LAST_DEX_VERSION"
		return 0
	fi
	[[ ! -f $tools_path/classes.dex ]] && { SPEED_DEBUG_LAST_DEX_VERSION="未找到classes.dex"; echo "$SPEED_DEBUG_LAST_DEX_VERSION"; return 0; }
	local _dex_raw _dex_line
	_dex_raw="$(CLASSPATH="$tools_path/classes.dex" app_process /system/bin com.xayah.dex.HiddenApiUtil --version 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
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
# v24.20.14-7.66-200：tmpdir-notify-residue-clean；清理 speedbackup_notify_state 與 .batch_notify_verify 殘留。
# v24.20.14-7.66-197：no-logo-no-startup-dex-version；以 7.66-194 為基底，只移除啟動第一屏與選單前 dex 版本/JVM 啟動。
# 主通知固定 TAG/ID，避免不同階段堆出多張 SpeedBackup 進度通知。
notification_enable="${notification_enable:-1}"
SPEEDBACKUP_NOTIFY_CONTROL_DIR="${SPEEDBACKUP_NOTIFY_CONTROL_DIR:-/sdcard/Android/data/com.xayah.dex/files/speedbackup_control}"
SPEEDBACKUP_NOTIFY_PAUSE_FILE="${SPEEDBACKUP_NOTIFY_PAUSE_FILE:-$SPEEDBACKUP_NOTIFY_CONTROL_DIR/.speedbackup_pause}"
SPEEDBACKUP_NOTIFY_STOP_FILE="${SPEEDBACKUP_NOTIFY_STOP_FILE:-$SPEEDBACKUP_NOTIFY_CONTROL_DIR/.speedbackup_stop}"
SPEEDBACKUP_NOTIFY_THROTTLE_MS="${SPEEDBACKUP_NOTIFY_THROTTLE_MS:-500}"
SPEEDBACKUP_NOTIFY_ACTIONS="${SPEEDBACKUP_NOTIFY_ACTIONS:-0}"
SPEEDBACKUP_NOTIFY_MAIN_TAG="${SPEEDBACKUP_NOTIFY_MAIN_TAG:-speedbackup_main}"
SPEEDBACKUP_NOTIFY_MAIN_ID="${SPEEDBACKUP_NOTIFY_MAIN_ID:-2020}"
SPEEDBACKUP_NOTIFY_ERROR_TAG="${SPEEDBACKUP_NOTIFY_ERROR_TAG:-speedbackup_error}"
SPEEDBACKUP_NOTIFY_ERROR_ID="${SPEEDBACKUP_NOTIFY_ERROR_ID:-2021}"
SPEEDBACKUP_NOTIFY_CONTROL_INIT=0
_notification_control_init() {
	[[ $SPEEDBACKUP_NOTIFY_ACTIONS != 1 ]] && return 0
	[[ $SPEEDBACKUP_NOTIFY_CONTROL_INIT = 1 ]] && return 0
	# 不主動 mkdir 外部 app 專屬目錄，避免 root 建目錄造成 companion APK 無法寫入。
	# receiver 會在第一次按暫停/停止時自行建立 speedbackup_control 目錄。
	rm -f "$SPEEDBACKUP_NOTIFY_PAUSE_FILE" "$SPEEDBACKUP_NOTIFY_STOP_FILE" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	SPEEDBACKUP_NOTIFY_CONTROL_INIT=1
}
_notification_control_check() {
	[[ $SPEEDBACKUP_NOTIFY_ACTIONS != 1 ]] && return 0
	_notification_control_init
	if [[ -f "$SPEEDBACKUP_NOTIFY_STOP_FILE" ]]; then
		echoRgb "偵測到通知欄停止指令，終止目前流程" "0"
		_speed_debug_log "notification stop requested: $SPEEDBACKUP_NOTIFY_STOP_FILE"
		exit 130
	fi
	if [[ -f "$SPEEDBACKUP_NOTIFY_PAUSE_FILE" ]]; then
		echoRgb "偵測到通知欄暫停指令，等待再次點擊暫停/繼續或刪除控制檔" "3"
		_speed_debug_log "notification pause requested: $SPEEDBACKUP_NOTIFY_PAUSE_FILE"
		while [[ -f "$SPEEDBACKUP_NOTIFY_PAUSE_FILE" ]]; do
			sleep 1
			if [[ -f "$SPEEDBACKUP_NOTIFY_STOP_FILE" ]]; then
				echoRgb "暫停期間偵測到停止指令，終止目前流程" "0"
				_speed_debug_log "notification stop requested while paused: $SPEEDBACKUP_NOTIFY_STOP_FILE"
				exit 130
			fi
		done
		_speed_debug_log "notification pause released"
	fi
	return 0
}
if [[ $notification_enable = 1 ]]; then
	_notification_control_init
	_notification_notify_batch_send() {
		local _event="$1" _channel="$2" _tag="$3" _max="$4" _progress="$5" _indeterminate="$6" _ongoing="$7" _auto_cancel="$8" _only_alert_once="$9"
		shift 9
		local _text="$*" _tmp _pkg _android_tag _android_id _event_up _channel_lc
		_notification_control_check
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
		app_process /system/bin com.xayah.dex.NotificationUtil notifyBatch --stdin < "$_tmp" >/dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		local _rc=$?
		rm -f "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
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
		backup_done backup_manifest batch_battery batch_clear_installer batch_grant batch_install_compare batch_installer \
		batch_notify batch_notify_verify batch_ops batch_opsreset batch_pflags batch_ask_access batch_revoke battery_settings battery_wl \
		changed_apps chk_folders chk_listed curl_http curl_test_err dchk_folders \
		dchk_listed decoded_listing dex_call_log dir_sizes dirs_count dirsize_work \
		dl_diff_items dl_items dns_cache getlist_allpkg getlist_apkinfo getlist_append \
		getlist_class getlist_filtered getlist_pkgset health_check_dl install_diag \
		installed_pkgs json_fetch json_health_hints json_health_issues listver_changed \
		local_apps local_sorted media_custom_paths notification_settings pkg_notify pkg_battery \
		perm_actual perm_expect pkg_installer pkg_perms pkg_uid pkg_ver play_restore_hints install_compare_hints install_method_log \
		post_json_apps precheck_list raw_wdav_listing rcollect remote_files remote_scripts \
		remote_stats_apps remote_stats_dl remote_stats_files remote_sub_listing \
		restore_ssaid rfail rlist rok screen_timeout_orig sfail slist \
		smb_batch smb_groups smb_mkdir smb_scan_results sok ssaid_apks stream_err \
		stream_failed stream_json_check_apps stream_restore_list stream_stage update_apks \
		verify_files wdav_all_files wdav_out wdav_root notify_expect notify_actual notify_mismatch notify_pending \
		battery_expect battery_actual ops_expect ops_actual listver_changed \
		batch_app_state app_state_out verify_app_state_stdin verify_app_state_out \
		appstate_all_pkgs appstate_pkg_chunk app_state_output_all verify_app_state_output_all \
		verify_appstate_all_pkgs verify_appstate_pkg_chunk \
		batch_location_access batch_media_access runtime_appops_dex_repair; do
		case "$f" in
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

	# PID/mktemp 後綴：只清本腳本專屬前綴，絕不清裸 .*
	for f in \
		app_details_read_ battery_raw_ compress_progress_ curl_cfg_ find_ssaid_ install_compare_ install_diag_one_ jq_ \
		merge_remote_ merged_app_details_ perm_ rel_jq_ remote_app_details_ \
		remote_check_ remote_health_check_ smb_dbg_ smb_dl_ ssaid_list_ ts_ \
		update_check_ wdav_scan_ json_fetch_ verify_files_ dex_stdin_ \
		play_install_session_ play_install_precheck_ play_install_source_ install_source_installer_ \
		dex_stderr_ dex_stdout_ dex_xargs_ zstd_test_ \
		curl_progress_ stream_download_err_ stream_mkcol_err_ wdav_get_err_ webdav_ad_err_ webdav_mkcol_err_ \
		notify_fastskip_ notify_filter_ smb_ls_ smb_size_ \
		speedbackup_notify_batch_ \
		ssaid_expected_ ssaid_readback_ ssaid_details_list apk_scan_list restore_stage \
		wdav_err_ wdav_propfind_ webdav_chunk_test_err_ \
		dex_probe_ appstate_filter_ appstate_chunk_ verify_appstate_chunk_ \
		hybrid_play_pm_ hybrid_play_pm_stderr_ hybrid_installer_pm_ hybrid_installer_pm_stderr_ sparse_dedupe_ play_uid_pm_probe_ play_uid_pm_probe_ok_ remote_debug_seq_ local_raw_ \
		smb_authfile_ webdav_netrc_ \
		speedbackup_wifi_save_; do
		rm -rf "$TMPDIR/.$f"* 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	done

	# 本腳本建立的暫存目錄
	rm -rf "$TMPDIR/.remote_json" "$TMPDIR/.stream_stage" "$TMPDIR/.speedbackup_play_session" "$TMPDIR/.speedbackup_apk_stage" "$TMPDIR/.speedbackup_apk_work" \
		"$TMPDIR/speedbackup_notify_state" "$TMPDIR/.speedbackup_notify_state" "$TMPDIR/.speedbackup_notify_state_"* 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# Play UID installSessionBatch 新版工作區放在集中二進制目錄；只清本腳本專用前綴。
	if [[ -n ${filepath:-} && -d "$filepath" ]]; then
		rm -rf "$filepath/.speedbackup_play_session" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	fi
}
TMPDIR="/data/local/tmp"
cleanup_tmpdir_contents || exit 1
[[ ! -d $TMPDIR ]] && mkdir "$TMPDIR"
chmod 771 "$TMPDIR"
chown '2000:2000' "$TMPDIR"

# DNS 解析: 解決部分 ARM curl 二進位檔域名解析失敗 (尤其網盤 WebDAV)
# 用法: _dns_resolve "host.example.com" → 輸出 IP 或空字串
# 快取放在 $TMPDIR/.dns_cache, 格式: <host><TAB><ip>
_dns_resolve() {
	local host="$1"
	# 若已是 IP 直接返回
	case $host in
	*[!0-9.]*) ;;
	*) echo "$host"; return 0 ;;
	esac
	# 查快取 (mksh 兼容: 用檔案而非 here-string)
	if [[ -f $TMPDIR/.dns_cache ]]; then
		local _cached
		_cached=$(awk -v h="$host" -F'\t' '$1 == h {print $2; exit}' "$TMPDIR/.dns_cache" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})
		[[ -n $_cached ]] && { echo "$_cached"; return 0; }
	fi
	# 解析: 依可用工具 fallback
	local ip=""
	if command -v nslookup >/dev/null 2>&1; then
		ip=$(nslookup "$host" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '/^(Address|Name):/ {if (NR>1 && $0 ~ /^Address/) {print $NF; exit}}')
		# 備援: 抓任何 IPv4
		[[ -z $ip ]] && ip=$(nslookup "$host" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '^127\.' | tail -1)
	fi
	if [[ -z $ip ]] && command -v ping >/dev/null 2>&1; then
		ip=$(ping -c 1 -W 1 "$host" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sed -n 's/.*(\([0-9.]*\)).*/\1/p' | head -1)
	fi
	# 寫入快取
	[[ -n $ip ]] && printf '%s\t%s\n' "$host" "$ip" >> "$TMPDIR/.dns_cache"
	echo "$ip"
}

# 覆蓋 curl: 自動透過 --resolve 繞過內建 DNS (解決 ARM curl 二進制解析失敗)
# 對 URL 內的域名先解析成 IP, 再傳 --resolve <host>:<port>:<ip> 給 curl
# 只處理 URL 參數中的域名, 純 IP 跳過
curl() {
	# mksh 不支援 args=(), 改用暫存檔記錄
	local extra_resolve="" _arg _rest _hp _host _port _ip
	for _arg in "$@"; do
		case $_arg in
		http://*|https://*|ftp://*)
			# 解出 host:port
			_rest="${_arg#*://}"
			_hp="${_rest%%/*}"
			_host="${_hp%%:*}"
			_port="${_hp#*:}"
			[[ $_port = $_hp ]] && {
				case $_arg in
				http://*)  _port=80 ;;
				https://*) _port=443 ;;
				ftp://*)   _port=21 ;;
				esac
			}
			# 僅對域名 (非純 IP) 處理
			case $_host in
			*[!0-9.]*) ;;          # 含非數字/點 → 是域名
			*) continue ;;          # 純 IP → 跳過
			esac
			# hostname 白名單: 只允許字母/數字/點/連字號, port 只允許數字, 防止注入額外 curl 參數
			case $_host in
			*[!A-Za-z0-9.-]*) continue ;;
			esac
			case $_port in
			*[!0-9]*) continue ;;
			esac
			_ip=$(_dns_resolve "$_host")
			if [[ -n $_ip && $_ip != "$_host" ]]; then
				extra_resolve="$extra_resolve --resolve $_host:$_port:$_ip"
			fi
			;;
		esac
	done
	# 用 command curl 避免遞迴, 加上預先解析的 resolve 參數
	if [[ -n $extra_resolve ]]; then
		command curl $extra_resolve "$@"
	else
		command curl "$@"
	fi
}

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
	_dex_raw /system/bin com.xayah.dex.HttpUtil get "$@"
}
ts() {
	case $SCRIPT_LANG in
	*CN* | *cn*) _dex_raw /system/bin com.xayah.dex.CCUtil t2s "$@" ;;
	*) _dex_raw /system/bin com.xayah.dex.CCUtil s2t "$@" ;;
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
# 內建 AppOps 中文補充表：只影響顯示，不參與還原/驗證。
_appops_localization_builtin() {
	# 只內建真正權限 / AppOps 類名稱與 mode / group；
	# 不再內建 AppOps App 的說明文、摘要文、控制文，避免 debug/終端混入大量非權限翻譯資源。
	case "$1" in
	'permission_group_activity_recognition') printf '%s\n' '體能活動'; return 0 ;;
	'permission_group_sensors') printf '%s\n' '傳感器'; return 0 ;;
	'permission_group_phone') printf '%s\n' '電話'; return 0 ;;
	'permission_group_sms') printf '%s\n' '簡訊'; return 0 ;;
	'permission_group_contacts') printf '%s\n' '通訊錄'; return 0 ;;
	'permission_group_camera') printf '%s\n' '相機'; return 0 ;;
	'permission_group_location') printf '%s\n' '位置'; return 0 ;;
	'permission_group_calender') printf '%s\n' '日曆'; return 0 ;;
	'permission_group_microphone') printf '%s\n' '麥克風'; return 0 ;;
	'permission_group_storage') printf '%s\n' '儲存空間'; return 0 ;;
	'permission_group_other') printf '%s\n' '其他'; return 0 ;;
	'op_mode_allow') printf '%s\n' '允許'; return 0 ;;
	'op_mode_ignore') printf '%s\n' '忽略'; return 0 ;;
	'op_mode_ignore_description_others') printf '%s\n' '應用程式會得到空資料或操作不被執行'; return 0 ;;
	'op_mode_ignore_description_runtime') printf '%s\n' '「授予」應用程式權限，但是應用程式會得到空資料或操作不會被執行'; return 0 ;;
	'op_mode_deny') printf '%s\n' '拒絕'; return 0 ;;
	'op_mode_deny_crash') printf '%s\n' '拒絕（可能讓應用程式崩潰）'; return 0 ;;
	'op_mode_default') printf '%s\n' '預設'; return 0 ;;
	'op_mode_foreground') printf '%s\n' '僅限應用程式使用期間允許'; return 0 ;;
	'op_mode_onetime') printf '%s\n' '每次都詢問'; return 0 ;;
	'op_mode_unspecified') printf '%s\n' '尚未設定'; return 0 ;;
	'op_mode_unknown') printf '%s\n' '未知 (%1$d)'; return 0 ;;
	'op_mode_default_description') printf '%s\n' '系統設定或應用程式資訊中的設定控制。]]>'; return 0 ;;
	'permission_group_clipboard') printf '%s\n' '剪貼簿'; return 0 ;;
	'permission_group_device_identifiers') printf '%s\n' '裝置識別碼'; return 0 ;;
	'op_name_QUERY_ALL_PACKAGES') printf '%s\n' '查詢所有套件'; return 0 ;;
	'op_name_MANAGE_EXTERNAL_STORAGE') printf '%s\n' '管理所有檔案'; return 0 ;;
	'op_name_ACCESS_MEDIA_LOCATION') printf '%s\n' '從媒體檔案讀取位置資訊'; return 0 ;;
	'op_name_READ_DEVICE_IDENTIFIERS') printf '%s\n' '讀取裝置識別碼'; return 0 ;;
	'op_name_WRITE_MEDIA_IMAGES') printf '%s\n' '寫入你的相片收藏'; return 0 ;;
	'op_name_READ_MEDIA_IMAGES') printf '%s\n' '讀取你的相片收藏'; return 0 ;;
	'op_name_WRITE_MEDIA_VIDEO') printf '%s\n' '寫入你的影片收藏'; return 0 ;;
	'op_name_READ_MEDIA_VIDEO') printf '%s\n' '讀取你的影片收藏'; return 0 ;;
	'op_name_WRITE_MEDIA_AUDIO') printf '%s\n' '寫入你的音樂收藏'; return 0 ;;
	'op_name_READ_MEDIA_AUDIO') printf '%s\n' '讀取你的音樂收藏'; return 0 ;;
	'op_name_SMS_FINANCIAL_TRANSACTIONS') printf '%s\n' '付費短訊權限'; return 0 ;;
	'op_name_ACTIVITY_RECOGNITION') printf '%s\n' '識別身體活動'; return 0 ;;
	'op_name_USE_BIOMETRIC') printf '%s\n' '使用生物識別硬體'; return 0 ;;
	'op_name_REQUEST_DELETE_PACKAGES') printf '%s\n' '請求刪除程式'; return 0 ;;
	'op_name_BLUETOOTH_SCAN') printf '%s\n' '藍芽掃描'; return 0 ;;
	'op_name_START_FOREGROUND') printf '%s\n' '執行前景服務'; return 0 ;;
	'op_name_MANAGE_IPSEC_TUNNELS') printf '%s\n' '建立和管理 IPsec Tunnels'; return 0 ;;
	'op_name_ACCEPT_HANDOVER') printf '%s\n' '繼續進行來自其他應用程式的通話'; return 0 ;;
	'op_name_BIND_ACCESSIBILITY_SERVICE') printf '%s\n' '使用無障礙服務'; return 0 ;;
	'op_name_ANSWER_PHONE_CALLS') printf '%s\n' '接聽電話'; return 0 ;;
	'op_name_PICTURE_IN_PICTURE') printf '%s\n' '畫中畫'; return 0 ;;
	'op_name_REQUEST_INSTALL_PACKAGES') printf '%s\n' '請求安裝程式'; return 0 ;;
	'op_name_READ_PHONE_NUMBERS') printf '%s\n' '讀取手機號碼'; return 0 ;;
	'op_name_AUDIO_ACCESSIBILITY_VOLUME') printf '%s\n' '協助工具音量'; return 0 ;;
	'op_name_LOCK_APP') printf '%s\n' '鎖定程式'; return 0 ;;
	'op_name_SU') printf '%s\n' '取得 ROOT 權限'; return 0 ;;
	'op_name_DATA_CONNECT_CHANGE') printf '%s\n' '切換移動數據'; return 0 ;;
	'op_name_NFC_CHANGE') printf '%s\n' '切換 NFC'; return 0 ;;
	'op_name_BOOT_COMPLETED') printf '%s\n' '開機時執行'; return 0 ;;
	'op_name_BLUETOOTH_CHANGE') printf '%s\n' '開啟藍牙'; return 0 ;;
	'op_name_WIFI_CHANGE') printf '%s\n' '更改 Wi-Fi 狀態'; return 0 ;;
	'op_name_RUN_IN_BACKGROUND') printf '%s\n' '在背景執行'; return 0 ;;
	'op_name_GET_ACCOUNTS') printf '%s\n' '取得帳號'; return 0 ;;
	'op_name_TURN_ON_SCREEN') printf '%s\n' '開啟螢幕'; return 0 ;;
	'op_name_WRITE_EXTERNAL_STORAGE') printf '%s\n' '寫入儲存空間'; return 0 ;;
	'op_name_READ_EXTERNAL_STORAGE') printf '%s\n' '讀取儲存空間'; return 0 ;;
	'op_name_MOCK_LOCATION') printf '%s\n' '模擬位置'; return 0 ;;
	'op_name_READ_CELL_BROADCASTS') printf '%s\n' '讀取小區廣播'; return 0 ;;
	'op_name_BODY_SENSORS') printf '%s\n' '身體傳感器'; return 0 ;;
	'op_name_USE_FINGERPRINT') printf '%s\n' '指紋'; return 0 ;;
	'op_name_PROCESS_OUTGOING_CALLS') printf '%s\n' '處理撥出電話'; return 0 ;;
	'op_name_USE_SIP') printf '%s\n' '使用 SIP'; return 0 ;;
	'op_name_ADD_VOICEMAIL') printf '%s\n' '新增語音郵件'; return 0 ;;
	'op_name_READ_PHONE_STATE') printf '%s\n' '讀取手機狀態'; return 0 ;;
	'op_name_ASSIST_SCREENSHOT') printf '%s\n' '輔助螢幕截圖'; return 0 ;;
	'op_name_ASSIST_STRUCTURE') printf '%s\n' '輔助結構'; return 0 ;;
	'op_name_WRITE_WALLPAPER') printf '%s\n' '寫入壁紙'; return 0 ;;
	'op_name_ACTIVATE_VPN') printf '%s\n' '激活 VPN'; return 0 ;;
	'op_name_PROJECT_MEDIA') printf '%s\n' '投影媒體'; return 0 ;;
	'op_name_TOAST_WINDOW') printf '%s\n' '顯示 Toast'; return 0 ;;
	'op_name_MUTE_MICROPHONE') printf '%s\n' '將麥克風靜音或取消靜音'; return 0 ;;
	'op_name_GET_USAGE_STATS') printf '%s\n' '取得使用情況統計資訊'; return 0 ;;
	'op_name_MONITOR_HIGH_POWER_LOCATION') printf '%s\n' '監控高耗電位置資訊服務'; return 0 ;;
	'op_name_MONITOR_LOCATION') printf '%s\n' '監測位置'; return 0 ;;
	'op_name_WAKE_LOCK') printf '%s\n' '保持喚醒狀態'; return 0 ;;
	'op_name_AUDIO_BLUETOOTH_VOLUME') printf '%s\n' '藍牙音量'; return 0 ;;
	'op_name_AUDIO_NOTIFICATION_VOLUME') printf '%s\n' '通知音量'; return 0 ;;
	'op_name_AUDIO_ALARM_VOLUME') printf '%s\n' '鬧鐘音量'; return 0 ;;
	'op_name_AUDIO_MEDIA_VOLUME') printf '%s\n' '媒體音量'; return 0 ;;
	'op_name_AUDIO_RING_VOLUME') printf '%s\n' '鈴聲音量'; return 0 ;;
	'op_name_AUDIO_VOICE_VOLUME') printf '%s\n' '語音音量'; return 0 ;;
	'op_name_AUDIO_MASTER_VOLUME') printf '%s\n' '主音量'; return 0 ;;
	'op_name_TAKE_AUDIO_FOCUS') printf '%s\n' '音訊焦點'; return 0 ;;
	'op_name_TAKE_MEDIA_BUTTONS') printf '%s\n' '媒體按鈕'; return 0 ;;
	'op_name_WRITE_CLIPBOARD') printf '%s\n' '修改剪貼簿內容'; return 0 ;;
	'op_name_READ_CLIPBOARD') printf '%s\n' '讀取剪貼簿內容'; return 0 ;;
	'op_name_PLAY_AUDIO') printf '%s\n' '播放音訊'; return 0 ;;
	'op_name_RECORD_AUDIO') printf '%s\n' '錄制音訊'; return 0 ;;
	'op_name_CAMERA') printf '%s\n' '相機'; return 0 ;;
	'op_name_ACCESS_NOTIFICATIONS') printf '%s\n' '存取通知'; return 0 ;;
	'op_name_SYSTEM_ALERT_WINDOW') printf '%s\n' '顯示在其他應用程式上層'; return 0 ;;
	'op_name_WRITE_SETTINGS') printf '%s\n' '修改系統設定'; return 0 ;;
	'op_name_WRITE_ICC_SMS') printf '%s\n' '寫入 ICC 簡訊'; return 0 ;;
	'op_name_READ_ICC_SMS') printf '%s\n' '讀取 ICC 簡訊'; return 0 ;;
	'op_name_SEND_SMS') printf '%s\n' '發送簡訊'; return 0 ;;
	'op_name_RECEIVE_WAP_PUSH') printf '%s\n' '接收 WAP PUSH 消息'; return 0 ;;
	'op_name_RECEIVE_MMS') printf '%s\n' '接收多媒體簡訊'; return 0 ;;
	'op_name_RECEIVE_EMERGECY_SMS') printf '%s\n' '接收緊急簡訊'; return 0 ;;
	'op_name_RECEIVE_SMS') printf '%s\n' '接收文字簡訊'; return 0 ;;
	'op_name_WRITE_SMS') printf '%s\n' '編寫簡訊'; return 0 ;;
	'op_name_READ_SMS') printf '%s\n' '讀取簡訊'; return 0 ;;
	'op_name_CALL_PHONE') printf '%s\n' '撥打電話'; return 0 ;;
	'op_name_NEIGHBORING_CELLS') printf '%s\n' '手機網路掃描'; return 0 ;;
	'op_name_POST_NOTIFICATION') printf '%s\n' '通知'; return 0 ;;
	'op_name_WIFI_SCAN') printf '%s\n' 'Wi-Fi掃描'; return 0 ;;
	'op_name_WRITE_CALENDAR') printf '%s\n' '修改日曆'; return 0 ;;
	'op_name_READ_CALENDAR') printf '%s\n' '讀取日曆'; return 0 ;;
	'op_name_WRITE_CALL_LOG') printf '%s\n' '修改通話記錄'; return 0 ;;
	'op_name_READ_CALL_LOG') printf '%s\n' '讀取通話記錄'; return 0 ;;
	'op_name_WRITE_CONTACTS') printf '%s\n' '修改連絡人'; return 0 ;;
	'op_name_READ_CONTACTS') printf '%s\n' '讀取連絡人'; return 0 ;;
	'op_name_VIBRATE') printf '%s\n' '振動'; return 0 ;;
	'op_name_GPS') printf '%s\n' 'GPS'; return 0 ;;
	'op_name_FINE_LOCATION') printf '%s\n' '精凖位置'; return 0 ;;
	'op_name_COARSE_LOCATION') printf '%s\n' '粗略位置'; return 0 ;;
	'op_name_LOCATION') printf '%s\n' '使用位置'; return 0 ;;
	'op_name_special_SENSORS') printf '%s\n' '傳感器'; return 0 ;;
	esac
	return 1
}
_appops_localization_lookup_one() {
	local _key="$1" _file _val
	[[ -z $_key ]] && return 1
	for _file in "$tools_path/appops-localization.tsv" "$filepath/appops-localization.tsv"; do
		[[ -s $_file ]] || continue
		_val="$(awk -F'\t' -v k="$_key" '$1==k && $2!="" {print $2; exit}' "$_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		[[ -n $_val ]] && { echo "$_val"; return 0; }
	done
	_appops_localization_builtin "$_key" && return 0
	return 1
}

_appops_localization_lookup() {
	local _key="$1" _base _upper _lower _try _seen
	[[ -z $_key ]] && return 1

	# 先精確查詢，避免外部表自訂 key 被別名覆蓋。
	_appops_localization_lookup_one "$_key" && return 0

	_base="$_key"
	case "$_base" in
		android.permission.*) _base="${_base#android.permission.}" ;;
		android:*) _base="${_base#android:}" ;;
		OP_*) _base="${_base#OP_}" ;;
		op_name_*) _base="${_base#op_name_}" ;;
	esac

	_upper="$(printf '%s' "$_base" | tr '[:lower:]' '[:upper:]')"
	_lower="$(printf '%s' "$_base" | tr '[:upper:]' '[:lower:]')"

	_seen=" $_key "
	for _try in \
		"$_base" \
		"$_upper" \
		"op_name_$_upper" \
		"OP_$_upper" \
		"android.permission.$_upper" \
		"android:$_lower" \
		"permission_group_$_lower" \
		"op_mode_$_lower"
	do
		[[ -n $_try ]] || continue
		case "$_seen" in *" $_try "*) continue ;; esac
		_seen="$_seen$_try "
		_appops_localization_lookup_one "$_try" && return 0
	done

	return 1
}

# 權限全名 → 中文名稱對照 (用於權限變更顯示更易讀)
# 用法: _perm_cn android.permission.CAMERA → 相機權限 (查不到則回傳原始全名)
_perm_cn() {
	local _localized
	_localized="$(_appops_localization_lookup "$1")"
	[[ -n $_localized ]] && { echo "$_localized"; return; }
	case $1 in
	android.permission.READ_EXTERNAL_STORAGE) echo "讀取外部存儲" ;;
	android.permission.WRITE_EXTERNAL_STORAGE) echo "寫入外部存儲" ;;
	android.permission.CAMERA) echo "相機權限" ;;
	android.permission.RECORD_AUDIO) echo "麥克風權限" ;;
	android.permission.ACCESS_FINE_LOCATION) echo "精確定位" ;;
	android.permission.ACCESS_COARSE_LOCATION) echo "粗略定位" ;;
	android.permission.ACCESS_MEDIA_LOCATION) echo "媒體位置訪問" ;;
	android.permission.READ_PHONE_STATE) echo "讀取手機狀態" ;;
	android.permission.CALL_PHONE) echo "直接撥打電話" ;;
	android.permission.READ_CONTACTS) echo "讀取聯絡人" ;;
	android.permission.WRITE_CONTACTS) echo "寫入聯絡人" ;;
	android.permission.READ_CALL_LOG) echo "讀取通話記錄" ;;
	android.permission.WRITE_CALL_LOG) echo "寫入通話記錄" ;;
	android.permission.SEND_SMS) echo "發送短信" ;;
	android.permission.READ_SMS) echo "讀取短信" ;;
	android.permission.READ_MEDIA_IMAGES) echo "讀取圖片" ;;
	android.permission.READ_MEDIA_VIDEO) echo "讀取視頻" ;;
	android.permission.READ_MEDIA_AUDIO) echo "讀取音頻" ;;
	android.permission.READ_MEDIA_VISUAL_USER_SELECTED) echo "讀取用戶選擇的媒體" ;;
	android.permission.READ_CALENDAR) echo "讀取日曆" ;;
	android.permission.WRITE_CALENDAR) echo "寫入日曆" ;;
	android.permission.BODY_SENSORS) echo "身體傳感器" ;;
	android.permission.ACTIVITY_RECOGNITION) echo "活動識別" ;;
	android.permission.GET_ACCOUNTS) echo "獲取帳戶列表" ;;
	android.permission.MANAGE_ACCOUNTS) echo "管理帳戶" ;;
	android.permission.USE_CREDENTIALS) echo "使用憑據" ;;
	android.permission.AUTHENTICATE_ACCOUNTS) echo "驗證帳戶" ;;
	android.permission.SYSTEM_ALERT_WINDOW) echo "懸浮窗權限" ;;
	android.permission.WRITE_SETTINGS) echo "寫入系統設置" ;;
	android.permission.REQUEST_INSTALL_PACKAGES) echo "安裝應用" ;;
	android.permission.QUERY_ALL_PACKAGES) echo "查詢所有應用" ;;
	android.permission.READ_PRIVILEGED_PHONE_STATE) echo "讀取特權手機狀態" ;;
	android.permission.BLUETOOTH) echo "使用藍牙" ;;
	android.permission.BLUETOOTH_ADMIN) echo "藍牙管理" ;;
	android.permission.BLUETOOTH_CONNECT) echo "藍牙連接" ;;
	android.permission.BLUETOOTH_SCAN) echo "藍牙掃描" ;;
	android.permission.BLUETOOTH_ADVERTISE) echo "藍牙廣播" ;;
	android.permission.INTERNET) echo "訪問網絡" ;;
	android.permission.ACCESS_NETWORK_STATE) echo "查看網絡狀態" ;;
	android.permission.ACCESS_WIFI_STATE) echo "查看WiFi狀態" ;;
	android.permission.CHANGE_WIFI_STATE) echo "修改WiFi狀態" ;;
	android.permission.CHANGE_NETWORK_STATE) echo "修改網絡狀態" ;;
	android.permission.CHANGE_WIFI_MULTICAST_STATE) echo "修改WiFi多播狀態" ;;
	android.permission.POST_NOTIFICATIONS) echo "發送通知" ;;
	android.permission.RECEIVE_BOOT_COMPLETED) echo "開機啟動" ;;
	android.permission.RECEIVE_USER_PRESENT) echo "用戶解鎖設備" ;;
	android.permission.WAKE_LOCK) echo "保持喚醒" ;;
	android.permission.VIBRATE) echo "振動權限" ;;
	android.permission.FLASHLIGHT) echo "手電筒" ;;
	android.permission.DISABLE_KEYGUARD) echo "禁用鎖屏" ;;
	android.permission.EXPAND_STATUS_BAR) echo "展開狀態欄" ;;
	android.permission.MODIFY_AUDIO_SETTINGS) echo "修改音頻設置" ;;
	android.permission.USE_FINGERPRINT) echo "使用指紋" ;;
	android.permission.USE_BIOMETRIC) echo "使用生物識別" ;;
	android.permission.USE_FACERECOGNITION) echo "使用面部識別" ;;
	android.permission.BIND_NFC_SERVICE) echo "NFC服務綁定" ;;
	android.permission.BIND_NOTIFICATION_LISTENER_SERVICE) echo "通知監聽服務綁定" ;;
	android.permission.BIND_QUICK_ACCESS_WALLET_SERVICE) echo "快捷錢包服務綁定" ;;
	android.permission.BIND_ACCESSIBILITY_SERVICE) echo "無障礙服務綁定" ;;
	android.permission.BIND_WALLPAPER) echo "壁紙服務綁定" ;;
	android.permission.FOREGROUND_SERVICE) echo "前台服務" ;;
	android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS) echo "忽略電池優化" ;;
	android.permission.SCHEDULE_EXACT_ALARM) echo "精確鬧鐘" ;;
	android.permission.GET_TASKS) echo "獲取任務" ;;
	android.permission.REORDER_TASKS) echo "重新排序任務" ;;
	android.permission.BROADCAST_STICKY) echo "粘性廣播" ;;
	android.permission.DUMP) echo "系統信息轉儲" ;;
	android.permission.NFC) echo "NFC權限" ;;
	android.permission.SMARTCARD) echo "智能卡權限" ;;
	# ---- Android 13 新增 ----
	android.permission.NEARBY_WIFI_DEVICES) echo "鄰近WiFi設備" ;;
	# ---- Android 11+ 儲存全部管理 ----
	android.permission.MANAGE_EXTERNAL_STORAGE) echo "管理所有檔案" ;;
	# ---- 短信補充 ----
	android.permission.WRITE_SMS) echo "寫入短信" ;;
	android.permission.RECEIVE_SMS) echo "接收短信" ;;
	android.permission.RECEIVE_MMS) echo "接收彩信" ;;
	android.permission.RECEIVE_WAP_PUSH) echo "接收WAP推送" ;;
	android.permission.READ_CELL_BROADCASTS) echo "讀取緊急廣播" ;;
	# ---- 電話補充 ----
	android.permission.READ_PHONE_NUMBERS) echo "讀取電話號碼" ;;
	android.permission.ANSWER_PHONE_CALLS) echo "接聽電話" ;;
	android.permission.PROCESS_OUTGOING_CALLS) echo "處理撥出電話" ;;
	android.permission.ADD_VOICEMAIL) echo "新增語音信箱" ;;
	android.permission.USE_SIP) echo "使用SIP通話" ;;
	android.permission.ACCEPT_HANDOVER) echo "接管通話" ;;
	# ---- 位置補充 ----
	android.permission.ACCESS_BACKGROUND_LOCATION) echo "背景定位" ;;
	# ---- 通知補充 ----
	android.permission.USE_FULL_SCREEN_INTENT) echo "全螢幕通知" ;;
	android.permission.ACCESS_NOTIFICATION_POLICY) echo "勿擾模式存取" ;;
	android:picture_in_picture) echo "子母畫面" ;;
	android:system_alert_window) echo "懸浮窗權限(AppOps)" ;;
	android:use_full_screen_intent) echo "全螢幕通知(AppOps)" ;;
	android:write_settings) echo "寫入系統設置(AppOps)" ;;
	android:request_install_packages) echo "安裝未知應用(AppOps)" ;;
	android:get_usage_stats) echo "使用情況存取(AppOps)" ;;
	android:manage_external_storage) echo "管理所有檔案(AppOps)" ;;
	android:schedule_exact_alarm) echo "精確鬧鐘(AppOps)" ;;
	android:access_notification_policy) echo "勿擾模式存取(AppOps)" ;;

	# ---- AppOps 額外名稱對照 ----
	android:coarse_location) echo "粗略定位(AppOps)" ;;
	android:fine_location) echo "精確定位(AppOps)" ;;
	android:gps) echo "GPS定位(AppOps)" ;;
	android:vibrate) echo "振動(AppOps)" ;;
	android:read_contacts) echo "讀取聯絡人(AppOps)" ;;
	android:write_contacts) echo "寫入聯絡人(AppOps)" ;;
	android:read_call_log) echo "讀取通話記錄(AppOps)" ;;
	android:write_call_log) echo "寫入通話記錄(AppOps)" ;;
	android:read_calendar) echo "讀取日曆(AppOps)" ;;
	android:write_calendar) echo "寫入日曆(AppOps)" ;;
	android:wifi_scan) echo "WiFi掃描(AppOps)" ;;
	android:post_notification) echo "發送通知(AppOps)" ;;
	android:neighboring_cells) echo "鄰近基地台(AppOps)" ;;
	android:call_phone) echo "直接撥打電話(AppOps)" ;;
	android:read_sms) echo "讀取短信(AppOps)" ;;
	android:write_sms) echo "寫入短信(AppOps)" ;;
	android:receive_sms) echo "接收短信(AppOps)" ;;
	android:receive_emergency_broadcast) echo "接收緊急廣播(AppOps)" ;;
	android:receive_mms) echo "接收彩信(AppOps)" ;;
	android:receive_wap_push) echo "接收WAP推送(AppOps)" ;;
	android:send_sms) echo "發送短信(AppOps)" ;;
	android:read_icc_sms) echo "讀取SIM短信(AppOps)" ;;
	android:write_icc_sms) echo "寫入SIM短信(AppOps)" ;;
	android:access_notifications) echo "通知存取(AppOps)" ;;
	android:camera) echo "相機(AppOps)" ;;
	android:record_audio) echo "麥克風(AppOps)" ;;
	android:play_audio) echo "播放音訊(AppOps)" ;;
	android:read_clipboard) echo "讀取剪貼板(AppOps)" ;;
	android:write_clipboard) echo "寫入剪貼板(AppOps)" ;;
	android:take_media_buttons) echo "接收媒體按鍵(AppOps)" ;;
	android:take_audio_focus) echo "取得音訊焦點(AppOps)" ;;
	android:audio_master_volume) echo "主音量控制(AppOps)" ;;
	android:audio_voice_volume) echo "通話音量控制(AppOps)" ;;
	android:audio_ring_volume) echo "鈴聲音量控制(AppOps)" ;;
	android:audio_media_volume) echo "媒體音量控制(AppOps)" ;;
	android:audio_alarm_volume) echo "鬧鐘音量控制(AppOps)" ;;
	android:audio_notification_volume) echo "通知音量控制(AppOps)" ;;
	android:audio_bluetooth_volume) echo "藍牙音量控制(AppOps)" ;;
	android:wake_lock) echo "保持喚醒(AppOps)" ;;
	android:monitor_location) echo "監控定位(AppOps)" ;;
	android:monitor_high_power_location) echo "高功耗定位監控(AppOps)" ;;
	android:mute_microphone) echo "靜音麥克風(AppOps)" ;;
	android:toast_window) echo "Toast視窗(AppOps)" ;;
	android:project_media) echo "媒體投放/投影(AppOps)" ;;
	android:activate_vpn) echo "啟用VPN(AppOps)" ;;
	android:write_wallpaper) echo "修改壁紙(AppOps)" ;;
	android:assist_structure) echo "輔助結構存取(AppOps)" ;;
	android:assist_screenshot) echo "輔助截圖存取(AppOps)" ;;
	android:read_phone_state) echo "讀取手機狀態(AppOps)" ;;
	android:add_voicemail) echo "新增語音信箱(AppOps)" ;;
	android:use_sip) echo "使用SIP通話(AppOps)" ;;
	android:process_outgoing_calls) echo "處理撥出電話(AppOps)" ;;
	android:use_fingerprint) echo "使用指紋(AppOps)" ;;
	android:body_sensors) echo "身體傳感器(AppOps)" ;;
	android:read_cell_broadcasts) echo "讀取緊急廣播(AppOps)" ;;
	android:mock_location) echo "模擬位置(AppOps)" ;;
	android:read_external_storage) echo "讀取外部存儲(AppOps)" ;;
	android:write_external_storage) echo "寫入外部存儲(AppOps)" ;;
	android:turn_screen_on) echo "喚醒螢幕(AppOps)" ;;
	android:get_accounts) echo "獲取帳戶列表(AppOps)" ;;
	android:run_in_background) echo "背景執行(AppOps)" ;;
	android:audio_accessibility_volume) echo "無障礙音量控制(AppOps)" ;;
	android:read_phone_numbers) echo "讀取電話號碼(AppOps)" ;;
	android:instant_app_start_foreground) echo "即時應用啟動前台服務(AppOps)" ;;
	android:answer_phone_calls) echo "接聽電話(AppOps)" ;;
	android:run_any_in_background) echo "任意背景執行(AppOps)" ;;
	android:change_wifi_state) echo "修改WiFi狀態(AppOps)" ;;
	android:request_delete_packages) echo "刪除應用(AppOps)" ;;
	android:bind_accessibility_service) echo "綁定無障礙服務(AppOps)" ;;
	android:accept_handover) echo "接管通話(AppOps)" ;;
	android:manage_ipsec_tunnels) echo "管理IPSec通道(AppOps)" ;;
	android:start_foreground) echo "啟動前台服務(AppOps)" ;;
	android:bluetooth_scan) echo "藍牙掃描(AppOps)" ;;
	android:use_biometric) echo "使用生物識別(AppOps)" ;;
	android:activity_recognition) echo "活動識別(AppOps)" ;;
	android:sms_financial_transactions) echo "金融短信交易(AppOps)" ;;
	android:read_media_audio) echo "讀取音頻(AppOps)" ;;
	android:write_media_audio) echo "寫入音頻(AppOps)" ;;
	android:read_media_video) echo "讀取視頻(AppOps)" ;;
	android:write_media_video) echo "寫入視頻(AppOps)" ;;
	android:read_media_images) echo "讀取圖片(AppOps)" ;;
	android:write_media_images) echo "寫入圖片(AppOps)" ;;
	android:legacy_storage) echo "舊版儲存模式(AppOps)" ;;
	android:access_accessibility) echo "無障礙存取(AppOps)" ;;
	android:read_device_identifiers) echo "讀取裝置識別碼(AppOps)" ;;
	android:access_media_location) echo "媒體位置存取(AppOps)" ;;
	android:query_all_packages) echo "查詢所有應用(AppOps)" ;;
	android:interact_across_profiles) echo "跨設定檔互動(AppOps)" ;;
	android:activate_platform_vpn) echo "啟用平台VPN(AppOps)" ;;
	android:loader_usage_stats) echo "載入器使用情況(AppOps)" ;;
	android:auto_revoke_permissions_if_unused) echo "未使用自動撤銷權限(AppOps)" ;;
	android:auto_revoke_managed_by_installer) echo "安裝器管理自動撤銷(AppOps)" ;;
	android:no_isolated_storage) echo "停用隔離儲存(AppOps)" ;;
	android:phone_call_microphone) echo "通話麥克風(AppOps)" ;;
	android:phone_call_camera) echo "通話相機(AppOps)" ;;
	android:record_audio_hotword) echo "熱詞錄音(AppOps)" ;;
	android:manage_ongoing_calls) echo "管理進行中通話(AppOps)" ;;
	android:manage_credentials) echo "管理憑證(AppOps)" ;;
	android:use_icc_auth_with_device_identifier) echo "SIM認證使用裝置識別碼(AppOps)" ;;
	android:record_audio_output) echo "錄製系統音訊輸出(AppOps)" ;;
	android:fine_location_source) echo "精確定位來源(AppOps)" ;;
	android:coarse_location_source) echo "粗略定位來源(AppOps)" ;;
	android:manage_media) echo "管理媒體(AppOps)" ;;
	android:bluetooth_connect) echo "藍牙連接(AppOps)" ;;
	android:uwb_ranging) echo "超寬頻測距(AppOps)" ;;
	android:activity_recognition_source) echo "活動識別來源(AppOps)" ;;
	android:bluetooth_advertise) echo "藍牙廣播(AppOps)" ;;
	android:record_incoming_phone_audio) echo "錄製來電音訊(AppOps)" ;;
	android:nearby_wifi_devices) echo "鄰近WiFi設備(AppOps)" ;;
	android:establish_vpn_service) echo "建立VPN服務(AppOps)" ;;
	android:establish_vpn_manager) echo "建立VPN管理器(AppOps)" ;;
	android:access_restricted_settings) echo "存取受限設定(AppOps)" ;;
	android:receive_soundtrigger_audio) echo "接收聲音觸發音訊(AppOps)" ;;
	android:receive_explicit_user_interaction_audio) echo "接收明確互動音訊(AppOps)" ;;
	android:run_user_initiated_jobs) echo "執行使用者發起工作(AppOps)" ;;
	android:read_media_visual_user_selected) echo "讀取使用者選擇媒體(AppOps)" ;;
	android:system_exempt_from_suspension) echo "系統豁免暫停(AppOps)" ;;
	android:system_exempt_from_dismissible_notifications) echo "系統豁免可清除通知(AppOps)" ;;
	android:read_write_health_data) echo "讀寫健康資料(AppOps)" ;;
	android:foreground_service_special_use) echo "前台服務特殊用途(AppOps)" ;;
	android:camera_sandboxed) echo "沙盒相機(AppOps)" ;;
	android:record_audio_sandboxed) echo "沙盒錄音(AppOps)" ;;
	android:receive_sandbox_trigger_audio) echo "接收沙盒觸發音訊(AppOps)" ;;
	android:system_exempt_from_power_restrictions) echo "系統豁免電源限制(AppOps)" ;;
	android:system_exempt_from_hibernation) echo "系統豁免休眠(AppOps)" ;;
	android:system_exempt_from_activity_bg_start_restriction) echo "系統豁免背景啟動限制(AppOps)" ;;
	android:capture_consentless_bugreport_on_userdebug_build) echo "擷取無同意錯誤報告(AppOps)" ;;
	# ---- 系統/背景執行補充 ----
	android.permission.RUN_IN_BACKGROUND) echo "在背景執行" ;;
	android.permission.RUN_ANY_IN_BACKGROUND) echo "任意背景執行" ;;
	android.permission.START_FOREGROUND) echo "啟動前台服務" ;;
	android.permission.FOREGROUND_SERVICE_LOCATION) echo "前台服務-定位" ;;
	android.permission.FOREGROUND_SERVICE_CAMERA) echo "前台服務-相機" ;;
	android.permission.FOREGROUND_SERVICE_MICROPHONE) echo "前台服務-麥克風" ;;
	android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK) echo "前台服務-媒體播放" ;;
	android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION) echo "前台服務-畫面錄製" ;;
	android.permission.FOREGROUND_SERVICE_PHONE_CALL) echo "前台服務-通話" ;;
	android.permission.FOREGROUND_SERVICE_DATA_SYNC) echo "前台服務-數據同步" ;;
	android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE) echo "前台服務-連接設備" ;;
	android.permission.FOREGROUND_SERVICE_HEALTH) echo "前台服務-健康" ;;
	android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING) echo "前台服務-遠程消息" ;;
	android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED) echo "前台服務-系統豁免" ;;
	android.permission.FOREGROUND_SERVICE_SPECIAL_USE) echo "前台服務-特殊用途" ;;
	android.permission.REQUEST_DELETE_PACKAGES) echo "刪除應用" ;;
	android.permission.PACKAGE_USAGE_STATS) echo "使用情況存取" ;;
	android.permission.GET_USAGE_STATS) echo "獲取使用情況統計" ;;
	android.permission.READ_CLIPBOARD) echo "讀取剪貼板" ;;
	android.permission.WRITE_CLIPBOARD) echo "寫入剪貼板" ;;
	android.permission.MUTE_MICROPHONE) echo "靜音麥克風" ;;
	android.permission.LEGACY_STORAGE) echo "舊版儲存模式" ;;
	android.permission.HIGH_SAMPLING_RATE_SENSORS) echo "高採樣率傳感器" ;;
	android.permission.UWB_RANGING) echo "超寬頻測距" ;;
	android.permission.BIND_VPN_SERVICE) echo "VPN服務綁定" ;;
	android.permission.INTERACT_ACROSS_USERS) echo "跨用戶互動" ;;
	android.permission.MANAGE_OWN_CALLS) echo "管理自有通話" ;;
	android.permission.CALL_COMPANION_APP) echo "車機配對通話" ;;
	# ---- Android 16 健康權限 (health.* 命名空間, 取代舊版 BODY_SENSORS) ----
	android.permission.health.READ_HEART_RATE) echo "讀取心率" ;;
	android.permission.health.READ_STEPS) echo "讀取步數" ;;
	android.permission.health.READ_SLEEP) echo "讀取睡眠數據" ;;
	android.permission.health.READ_OXYGEN_SATURATION) echo "讀取血氧" ;;
	android.permission.health.READ_BODY_TEMPERATURE) echo "讀取體溫" ;;
	android.permission.health.READ_BLOOD_PRESSURE) echo "讀取血壓" ;;
	android.permission.health.READ_BLOOD_GLUCOSE) echo "讀取血糖" ;;
	android.permission.health.READ_EXERCISE) echo "讀取運動記錄" ;;
	android.permission.health.READ_NUTRITION) echo "讀取營養記錄" ;;
	android.permission.health.READ_WEIGHT) echo "讀取體重" ;;
	android.permission.health.READ_MEDICAL_DATA_IMMUNIZATION) echo "讀取疫苗醫療記錄" ;;
	android.permission.health.WRITE_MEDICAL_DATA) echo "寫入醫療記錄" ;;
	android:op_*) echo "未知AppOps(${1#android:op_})" ;;
	*) echo "$1" ;;
	esac
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
    _cleanup_tmp_files() {
    	# EXIT 收尾必須做完整清理，不保留恢復主迴圈的 session maps。
    	_RESTORE_KEEP_SESSION_MAPS=0
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
# 預連線測試 (避免後續操作卡住)
# 用法: remote_precheck <host> <port>
# 三層 fallback: nc → /dev/tcp → curl, 失敗會寫 speed_debug/remote_precheck.log
remote_precheck() {
	local host="$1" port="$2"
	[[ -z $host ]] && { echoRgb "remote_precheck: host為空" "0"; return 1; }
	local dbg
	dbg="$(_speed_debug_log_path remote_precheck.log)"
	_speed_debug_append_file "$dbg" \
		"===== precheck $(date '+%Y-%m-%d %H:%M:%S') =====" \
		"host=$host port=$port"
	# 1. nc
	if command -v nc >/dev/null 2>&1; then
		nc -z -w 3 "$host" "$port" >/dev/null 2>&1 && {
			_speed_debug_append_file "$dbg" "[OK] nc passed"
			return 0
		}
		_speed_debug_append_file "$dbg" "[FAIL] nc -z -w 3 $host $port → 失敗"
	fi
	# 2. /dev/tcp
	if command -v timeout >/dev/null 2>&1; then
		timeout 3 sh -c "echo > /dev/tcp/$host/$port" >/dev/null 2>&1 && {
			_speed_debug_append_file "$dbg" "[OK] /dev/tcp passed"
			return 0
		}
		_speed_debug_append_file "$dbg" "[FAIL] timeout 3 /dev/tcp/$host/$port → 失敗"
	fi
	# 3. curl --connect-timeout (對 https 通常更可靠, 也能用 --resolve)
	if command -v curl >/dev/null 2>&1; then
		# 構造 url; 不知 https/http 直接試 telnet 風格
		local _scheme=http
		[[ $port = 443 || $port = 30 ]] && _scheme=https
		local curl_err
		curl_err=$(curl -sS --connect-timeout 3 -o /dev/null -w '%{http_code}' "$_scheme://$host:$port/" 2>&1)
		case $curl_err in
		[0-9][0-9][0-9])
			_speed_debug_append_file "$dbg" "[OK] curl returned HTTP $curl_err"
			return 0 ;;
		*)
			_speed_debug_append_file "$dbg" "[FAIL] curl err: $curl_err"
			;;
		esac
	fi
	# 詳細失敗原因已寫入 speed_debug 包內 remote_precheck.log；此函數本身不刷終端，交由呼叫端顯示摘要。
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

# URL 編碼 (處理 UTF-8 多 byte, 保留 / 不編碼以保持路徑結構)
# 用法: url_encode_path <string>
url_encode_path() {
	local s="$1"
	# 用 od 把每個 byte 印成 hex, awk 處理 hex 字串轉換
	# 避免 strtonum (busybox awk 不支援)
	printf '%s' "$s" | od -An -tx1 -v | tr -s ' \n' ' ' | awk '
	BEGIN {
		# 建立 hex → dec 對照表
		for (i=0; i<10; i++) hex2int[sprintf("%d",i)] = i
		hex2int["a"]=10; hex2int["b"]=11; hex2int["c"]=12
		hex2int["d"]=13; hex2int["e"]=14; hex2int["f"]=15
	}
	{
		n = split($0, a, " ")
		for (i=1; i<=n; i++) {
			h = a[i]
			if (h == "") continue
			# 把兩個 hex 字元轉成 dec
			val = hex2int[substr(h,1,1)] * 16 + hex2int[substr(h,2,1)]
			# 不編碼: A-Z a-z 0-9 - _ . ~ /
			if ((val>=48 && val<=57) || (val>=65 && val<=90) || (val>=97 && val<=122) \
				|| val==45 || val==95 || val==46 || val==126 || val==47) {
				printf "%c", val
			} else {
				printf "%%%s", toupper(h)
			}
		}
	}'
}

# URL 解碼 (處理 %XX, 含 UTF-8 多 byte)
url_decode_path() {
	local s="$1"
	local converted
	converted=$(echo "$s" | sed 's/%\([0-9a-fA-F][0-9a-fA-F]\)/\\x\1/g')
	printf '%b' "$converted"
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
	[[ -z $my_ip ]] && { echoRgb "無法取得本機 IP" "0"; return 1; }
	SMB_SCAN_SUBNET="${my_ip%.*}"
	if ! command -v nc >/dev/null 2>&1; then
		echoRgb "未找到 nc 命令,無法掃描" "0"; return 1
	fi
	echoRgb "本機 IP: $my_ip" "2"
	echoRgb "掃描 $SMB_SCAN_SUBNET.0/24 上的 SMB 主機 (445 port)..." "3"
	local results="$TMPDIR/.smb_scan_results"; : > "$results"
	local i pids=""
	for i in $(seq 1 254); do
		( nc -z -w 1 "$SMB_SCAN_SUBNET.$i" 445 >/dev/null 2>&1 && echo "$SMB_SCAN_SUBNET.$i" >> "$results" ) &
		pids="$pids $!"
		if [[ $((i % 20)) -eq 0 ]]; then
			wait $pids 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; pids=""
			printf '\r -掃描 %d/254 %s' "$i" "$(progress_bar $((i * 100 / 254)))" >&2
		fi
	done
	wait $pids 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
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
	if [[ -n $remote_user ]]; then _auth="-A $_SMB_AUTHFILE"; else _auth="-N"; fi
	local target share
	while read -r target; do
		echoRgb "發現 SMB: $target" "1"
		share="$(command smbclient -L "//$target" $_auth -t 5 -s /dev/null -m SMB3 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} \
			| awk '/Disk/ && $1!~/\$$/ {print $1; exit}')"
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
	if [[ -n $remote_user ]]; then _auth="-A $_SMB_AUTHFILE"; else _auth="-N"; fi
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
		command smbclient -L "//$target" $_auth -t 3 -s /dev/null -m SMB3 2>>"$_scan_raw" \
			| awk '/Disk/ {print "  共享: "$1}' \
			| while read -r line; do echoRgb "$line" "2"; done
	done < "$TMPDIR/.smb_scan_results"
	rm -f "$TMPDIR/.smb_scan_results"
}
# SMB 上傳實作 (使用 smbclient)
# 流程: 解析 URL → 預檢 → 收集檔案 → 按目錄分組 → 每組一次 smbclient 批次傳輸
# 跟 upload_remote 的差別: SMB 用獨立的 smbclient 二進制, 不走 curl
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
	#   -s /dev/null    : 跳過讀取 smb.conf (避免手動編譯版找不到 conf 噴警告)
	#   -p <port>       : 指定 SMB 端口 (預設 445, 由 remote_parse_endpoint 設定)
	#   -m SMB3         : client max protocol = SMB3, 表示最高用到 SMB3.1.1
	#                     min 維持 smbclient 預設 (SMB2_02), 故拒絕 SMB1 但允許協商到 SMB2.x ~ SMB3.x
	local SMB_OPTS="-t 10 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
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
		_mkdir_out="$(smbclient "$share" -A "$_SMB_AUTHFILE" $SMB_OPTS < "$mkdir_script" 2>&1)"
		_mkdir_rc=$?
		remote_raw_log "remote_smb_upload_raw.log" "MKDIR rc=$_mkdir_rc script=$mkdir_script"
		printf '%s\n' "$_mkdir_out" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_smb_upload_raw.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		printf '%s\n' "$_mkdir_out" | grep -Ev '^Domain=|^OS=|NT_STATUS_OBJECT_NAME_COLLISION|^Try "help"|^dos charset|^Can.t load' >&2
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
		smb_out="$(smbclient "$share" -A "$_SMB_AUTHFILE" $SMB_OPTS < "$batch" 2>&1)"
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
		local _smb_err_lines
		_smb_err_lines="$(printf '%s\n' "$smb_out" | grep -E 'NT_STATUS|does not exist|ERR' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		while read -r f; do
			let idx++
			local rel="${f#$Backup/}"
			local fname="${f##*/}"
			case "$_smb_err_lines" in
				*"$fname"*)
					echo "$rel" >> "$fail_list"
					echoRgb "[$idx/$total] ✗ $rel" "0"
					remote_log "FAIL SMB $rel"
					;;
				*)
					echo "$f" >> "$ok_list"
					echoRgb "[$idx/$total] ✓ $rel" "1"
					;;
			esac
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
		if [[ ! -s $fail_list ]]; then
			let idx++
			local _ad_rel="${REMOTE_APPDETAILS_FILE#$Backup/}"
			local _ad_dir="$(dirname "$REMOTE_APPDETAILS_FILE")"
			local _ad_fname="$(basename "$REMOTE_APPDETAILS_FILE")"
			local _ad_smb_out _ad_smb_rc _ad_tag
			_ad_tag="$(_remote_debug_seq smb_upload)"
			_ad_smb_out="$(smbclient "$share" -A "$_SMB_AUTHFILE" -t 10 -s /dev/null \
				-D "${rem_path:+$rem_path/}$(dirname "$_ad_rel")" \
				-c "lcd $_ad_dir; put $_ad_fname; exit" 2>&1)"
			_ad_smb_rc=$?
			remote_raw_log "remote_smb_upload_raw.log" "APP_DETAILS tag=$_ad_tag rc=$_ad_smb_rc rel=$_ad_rel dir=$_ad_dir"
			{
				echo "===== SMB_UPLOAD_APP_DETAILS $_ad_tag rel=$_ad_rel rc=$_ad_smb_rc ====="
				printf '%s\n' "$_ad_smb_out"
			} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_smb_upload_${_ad_tag}.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			if echo "$_ad_smb_out" | grep -F "$_ad_fname" | grep -qE 'NT_STATUS|does not exist|ERR'; then
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
# WebDAV: 用 curl 逐檔 PUT, 預先 MKCOL 建好目錄結構
upload_remote() {
	local proto="$1"
	[[ $proto = smb ]] && { upload_smb; return $?; }
	[[ -z $remote_url ]] && { echoRgb "remote_url未設置" "0"; return 1; }
	UPLOAD_START_TS=$(date +%s)
	local base_url
	case $proto in
	webdav)
		base_url="${remote_url%/}"
		[[ $base_url != http://* && $base_url != https://* ]] && { echoRgb "WebDAV地址格式錯誤: $remote_url" "0"; return 1; }
		;;
	*) echoRgb "未支援的協議: $proto" "0"; return 1 ;;
	esac
	# 自動加上備份目錄前綴 (跟本地結構一致)
	local backup_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	base_url="$base_url/$backup_subdir"
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
	[[ $REMOTE_QUIET != 1 ]] && echoRgb "使用: $filepath/curl" "2"
	local list_file="$TMPDIR/.rlist"
	local ok_list="$TMPDIR/.rok"
	local fail_list="$TMPDIR/.rfail"
	: > "$ok_list"; : > "$fail_list"
	[[ -z $Backup ]] && { echoRgb "Backup路徑為空" "0"; return 1; }
	remote_collect_targets "$list_file"
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
	# WebDAV: 先建初始目錄 (Backup_zstd_X 自己)
	local _mkcol_http _mkcol_rc _mkcol_err="$TMPDIR/.webdav_mkcol_err_$$"
	_mkcol_http="$(curl -sS -L --http1.1 -X MKCOL --netrc-file "$_WEBDAV_NETRC" "$base_url" -o /dev/null -w '%{http_code}' 2>"$_mkcol_err")"
	_mkcol_rc=$?
	remote_raw_log "remote_webdav_upload_raw.log" "MKCOL root rc=$_mkcol_rc http=$_mkcol_http url=$base_url"
	remote_raw_cat "remote_webdav_upload_raw.log" "$_mkcol_err" "[MKCOL root stderr]"
	rm -f "$_mkcol_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# WebDAV: 創建遠程子目錄 (MKCOL)
	while read -r f; do
		local d="${f#$Backup/}"
		d="${d%/*}"
		[[ -n $d && $d != "${f#$Backup/}" ]] && echo "$d"
	done < "$list_file" | sort -u | while read -r d; do
		local enc_d="$(url_encode_path "$d")"
		local cur="$base_url"
		local IFS='/'
		set -- $enc_d
		for seg; do
			cur="$cur/$seg"
			local _sub_mk_err="$TMPDIR/.webdav_mkcol_err_$$" _sub_mk_http _sub_mk_rc
			_sub_mk_http="$(curl -sS -L --http1.1 -X MKCOL --netrc-file "$_WEBDAV_NETRC" "$cur" -o /dev/null -w '%{http_code}' 2>"$_sub_mk_err")"
			_sub_mk_rc=$?
			remote_raw_log "remote_webdav_upload_raw.log" "MKCOL dir rc=$_sub_mk_rc http=$_sub_mk_http url=$cur"
			remote_raw_cat "remote_webdav_upload_raw.log" "$_sub_mk_err" "[MKCOL dir stderr]"
			rm -f "$_sub_mk_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		done
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
			local enc_rel="$(url_encode_path "$rel")"
			target_url="$base_url/$enc_rel"
		else
			target_url="$base_url/$rel"
		fi
		local http_code curl_exit
		# 顯示上傳百分比: curl -# 進度 → awk 過濾只留百分比 → 同行刷新
		local _sz_human
		_sz_human=$(awk "BEGIN{s=${_sz:-0};if(s>=1073741824)printf\"%.2fGB\",s/1073741824;else if(s>=1048576)printf\"%.1fMB\",s/1048576;else if(s>=1024)printf\"%.0fKB\",s/1024;else printf\"%dB\",s}")
		local _curl_progress="$TMPDIR/.curl_progress_$$" _curl_tag
		_curl_tag="$(_remote_debug_seq webdav_upload)"
		curl -# -S -L --http1.1 --retry 2 --retry-delay 3 --connect-timeout 10 \
			-T "$f" --netrc-file "$_WEBDAV_NETRC" -w '%{http_code}' \
			-o /dev/null "$target_url" > "$TMPDIR/.curl_http" 2>"$_curl_progress"
		curl_exit=$?
		cat "$_curl_progress" | awk -v idx="$idx" -v total="$total" -v rel="$rel" -v sz="$_sz_human" '
			BEGIN{RS="\r"; last_pct=""}
			/[0-9]+%/{
				match($0,/[0-9]+\.?[0-9]*%/)
				pct=substr($0,RSTART,RLENGTH)
				# curl -# 對小檔常連續吐兩次 100.0%，終端會看到同一行重複兩遍。
				# 同一檔案內相同百分比只刷新一次，不影響 raw log / HTTP 判定。
				if(pct==last_pct) next
				last_pct=pct
				spd=""
				for(i=1;i<=NF;i++) if(index($i,"/s")) spd=$i
				printf "\r\033[38;5;51m [%d/%d] %s (%s) %s",idx,total,rel,sz,pct
				if(spd!="") printf " %s",spd
				printf "\033[0m "
				fflush()
			}' > /dev/tty
		http_code="$(cat "$TMPDIR/.curl_http" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		remote_raw_log "remote_webdav_upload_raw.log" "PUT tag=$_curl_tag rc=$curl_exit http=$http_code bytes=${_sz:-0} rel=$rel url=$target_url"
		remote_raw_cat "remote_webdav_upload_${_curl_tag}.log" "$_curl_progress" "===== WEBDAV_PUT $_curl_tag rel=$rel rc=$curl_exit http=$http_code ====="
		cat "$_curl_progress" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_webdav_upload_raw.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		rm -f "$_curl_progress" "$TMPDIR/.curl_http" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
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
			remote_log "FAIL $proto $rel HTTP=$http_code curl_exit=$curl_exit"
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
		if [[ ! -s $fail_list ]]; then
			let idx++
			local _ad_rel="${REMOTE_APPDETAILS_FILE#$Backup/}"
			local _ad_url="$base_url/$(url_encode_path "$_ad_rel")"
			local _ad_http _ad_curl_rc _ad_curl_err="$TMPDIR/.webdav_ad_err_$$" _ad_tag
			_ad_tag="$(_remote_debug_seq webdav_upload)"
			_ad_http="$(curl -sS -L --http1.1 --retry 2 --retry-delay 3 --connect-timeout 10 \
				-T "$REMOTE_APPDETAILS_FILE" --netrc-file "$_WEBDAV_NETRC" -w '%{http_code}' \
				-o /dev/null "$_ad_url" 2>"$_ad_curl_err")"
			_ad_curl_rc=$?
			remote_raw_log "remote_webdav_upload_raw.log" "APP_DETAILS tag=$_ad_tag rc=$_ad_curl_rc http=$_ad_http rel=$_ad_rel url=$_ad_url"
			remote_raw_cat "remote_webdav_upload_${_ad_tag}.log" "$_ad_curl_err" "===== WEBDAV_APP_DETAILS $_ad_tag rel=$_ad_rel rc=$_ad_curl_rc http=$_ad_http ====="
			rm -f "$_ad_curl_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
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
# 依 remote_type 分發 smbclient(recurse ls) / curl(PROPFIND)
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
		if [[ -n $remote_user ]]; then _auth="-A $_SMB_AUTHFILE"; else _auth="-N"; fi
		local SMB_OPTS="-t 300 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _pref="$SMB_REM_PATH/$_path"; _pref="${_pref#/}"
		local _p="$_pref"; _p="${_p//\//\\}"
		# recurse ls: stderr 只進 raw log；CP850/橫幅噪音不寫入 stderr.log。
		local _smb_ls_out="$TMPDIR/.smb_ls_out_$$" _smb_ls_err="$TMPDIR/.smb_ls_err_$$"
		command smbclient "$SMB_SHARE" $_auth $SMB_OPTS \
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
		awk -v pref="$_pref/" '
			/^\\/ { dir=$0; sub(/^\\/,"",dir); gsub(/\\/,"/",dir); next }
			{
				for (i=2; i<=NF; i++) {
					if ($i ~ /^[AHSRN]+$/ && $(i+1) ~ /^[0-9]+$/) {
						name=$1
						for (j=2; j<i; j++) name=name" "$j
						if (dir=="") { print name }
						else {
							full=dir"/"name
							if (index(full, pref)==1) print substr(full, length(pref)+1)
						}
						break
					}
				}
			}' "$_smb_ls_out"
		rm -f "$_smb_ls_out" "$_smb_ls_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		;;
	webdav)
		local _wauth=""
		[[ -n $remote_user ]] && _wauth="--netrc-file $_WEBDAV_NETRC"
		local _wurl="${remote_url%/}/$_path"
		# v24.20.14-7.12：PROPFIND 404/空目錄屬於可預期情境，不污染 stderr.log；完整 stderr 進 raw log。
		local _wd_prop="$TMPDIR/.wdav_propfind_list_$$" _wd_err="$TMPDIR/.wdav_propfind_list_err_$$" _wd_rc
		curl -fsS $_wauth -X PROPFIND -H "Depth: infinity" "$_wurl/" > "$_wd_prop" 2>"$_wd_err"
		_wd_rc=$?
		remote_raw_log "remote_webdav_propfind_raw.log" "LIST path=$_path rc=$_wd_rc url=$_wurl/"
		remote_raw_cat "remote_webdav_propfind_raw.log" "$_wd_err" "[WEBDAV_LIST stderr path=$_path]"
		if [[ $_wd_rc != 0 ]]; then
			_speed_debug_log "REMOTE_WEBDAV_LIST_MISSING_OR_FAIL path=$_path rc=$_wd_rc"
			rm -f "$_wd_prop" "$_wd_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			return 0
		fi
		# href 解碼後去掉 base 前綴, 過濾目錄 (以 / 結尾)
		sed 's/</\n</g' "$_wd_prop" | sed -n 's|<[^>]*href[^>]*>\([^<]*\).*|\1|p' \
			| awk -v base="$_path" '
				BEGIN { for (i=0;i<256;i++) hex[sprintf("%02X",i)]=sprintf("%c",i) }
				function urldec(s,  out,k,h) {
					out=""
					while ((k=index(s,"%"))>0) {
						h=toupper(substr(s,k+1,2))
						if (h in hex) { out=out substr(s,1,k-1) hex[h]; s=substr(s,k+3) }
						else { out=out substr(s,1,k); s=substr(s,k+1) }
					}
					return out s
				}
				{
					$0=urldec($0)
					if ($0 ~ /\/$/) next
					idx=index($0, base"/")
					if (idx==0) next
					print substr($0, idx+length(base)+1)
				}'
		rm -f "$_wd_prop" "$_wd_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
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
		if [[ -n $remote_user ]]; then _auth="-A $_SMB_AUTHFILE"; else _auth="-N"; fi
		local SMB_OPTS="-t 300 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _pref="$SMB_REM_PATH/$_path"; _pref="${_pref#/}"
		local _p="$_pref"; _p="${_p//\//\\}"
		# recurse ls 累加檔案大小；stderr 只進 raw log，避免 CP850 噪音污染 stderr.log。
		local _smb_size_out="$TMPDIR/.smb_size_out_$$" _smb_size_err="$TMPDIR/.smb_size_err_$$"
		command smbclient "$SMB_SHARE" $_auth $SMB_OPTS \
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
		awk -v pref="$_pref" '
			/^\\/ { dir=$0; sub(/^\\/,"",dir); gsub(/\\/,"/",dir); ok=(index(dir,pref)==1); next }
			ok || dir=="" {
				for (i=2; i<=NF; i++) {
					if ($i ~ /^[AHSRN]+$/ && $(i+1) ~ /^[0-9]+$/) { s += $(i+1); break }
				}
			}
			END { print s+0 }' "$_smb_size_out"
		rm -f "$_smb_size_out" "$_smb_size_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		;;
	webdav)
		local _wauth=""
		[[ -n $remote_user ]] && _wauth="--netrc-file $_WEBDAV_NETRC"
		local _wurl="${remote_url%/}/$_path"
		# v24.20.14-7.12：PROPFIND 404/空目錄回 0，stderr 只進 raw log。
		local _wd_prop="$TMPDIR/.wdav_propfind_size_$$" _wd_err="$TMPDIR/.wdav_propfind_size_err_$$" _wd_rc
		curl -fsS $_wauth -X PROPFIND -H "Depth: infinity" "$_wurl" > "$_wd_prop" 2>"$_wd_err"
		_wd_rc=$?
		remote_raw_log "remote_webdav_propfind_raw.log" "SIZE path=$_path rc=$_wd_rc url=$_wurl"
		remote_raw_cat "remote_webdav_propfind_raw.log" "$_wd_err" "[WEBDAV_SIZE stderr path=$_path]"
		if [[ $_wd_rc != 0 ]]; then
			_speed_debug_log "REMOTE_WEBDAV_SIZE_MISSING_OR_FAIL path=$_path rc=$_wd_rc before=0"
			echo 0
			rm -f "$_wd_prop" "$_wd_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			return 0
		fi
		# PROPFIND Depth: infinity 遞迴, 抓所有 getcontentlength 數值累加
		sed 's/</\n</g' "$_wd_prop" \
			| sed -n 's|.*getcontentlength[^>]*>\([0-9]\{1,\}\).*|\1|p' \
			| awk '{s+=$1} END{print s+0}'
		rm -f "$_wd_prop" "$_wd_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		;;
	*)
		echo 0
		;;
	esac
}
# 流式模式: 上傳恢復必要的基礎設施到遠端 (tools/ 目錄、start.sh、restore_settings.conf)
# 讓遠端備份能獨立恢復 (功能8 檢查這些, 功能10 流式恢復需要)
# tools/ 較大(數十 MB 二進制), 遠端已有就跳過; start.sh/conf 小, 每次重傳確保最新
stream_upload_infra() {
	stream_enabled || { _speed_debug_log "STREAM_INFRA_SKIP reason=remote_disabled"; return 0; }
	local _stage="$TMPDIR/.stream_stage/.infra"
	mkdir -p "$_stage" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	# 1. start.sh (恢復模式入口, touch_shell "2")
	touch_shell "2" "$_stage/start.sh"
	_stream_upload "start.sh" < "$_stage/start.sh" && echoRgb "start.sh 已上傳遠端" "1" || echoRgb "start.sh 上傳失敗" "0"
	# 2. restore_settings.conf
	update_Restore_settings_conf > "$_stage/restore_settings.conf"
	_stream_upload "restore_settings.conf" < "$_stage/restore_settings.conf" && echoRgb "restore_settings.conf 已上傳遠端" "1" || echoRgb "restore_settings.conf 上傳失敗" "0"
	# 3. appList.txt (功能8/恢復需要應用清單)
	if [[ -f $MODDIR/appList.txt ]]; then
		_stream_upload "appList.txt" < "$MODDIR/appList.txt" && echoRgb "appList.txt 已上傳遠端" "1" || echoRgb "appList.txt 上傳失敗" "0"
	fi
	# 3b. MT管理器.apk (恢復時安裝用, 對齊非流式上傳清單)
	if [[ -f $Backup/MT管理器.apk ]]; then
		_stream_upload "MT管理器.apk" < "$Backup/MT管理器.apk" && echoRgb "MT管理器.apk 已上傳遠端" "1" || echoRgb "MT管理器.apk 上傳失敗" "0"
	fi
	# 4. tools/ 目錄: 遠端已有就跳過. 下載 tools/tools.sh 開頭, 必須是真 shell 腳本 (#!) 才算存在
	# (smbclient get 不存在檔可能輸出錯誤訊息到 stdout, 故須驗證內容是腳本而非錯誤)
	local _toolschk
	_toolschk="$(_stream_download "${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}/tools/tools.sh" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | head -c 30)"
	case $_toolschk in
	'#!'*|*'system/bin'*)
		echoRgb "遠端已有 tools/ (跳過, 省流量)" "2" ;;
	*)
		echoRgb "遠端缺 tools/, 上傳工具目錄 (首次, 約數十 MB)..." "3"
		local _tf _rel
		find "$MODDIR/tools" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while read -r _tf; do
			_rel="tools/${_tf#$MODDIR/tools/}"
			_stream_upload "$_rel" < "$_tf"
		done
		echoRgb "tools/ 已上傳遠端" "1"
		;;
	esac
	rm -rf "$_stage" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

# 通用流式上傳: 從 stdin 讀資料, 上傳到遠端 (相對遠端根的) 路徑
# 依 remote_type 分發到 smbclient / curl(webdav) / ssh
# 用法: <資料來源> | _stream_upload "相對路徑/file.tar.zst"
# 回傳: 0=成功
_stream_upload() {
	local _rel="$1"
	remote_enabled || { remote_log "STREAM_UPLOAD_SKIP remote_disabled rel=$_rel"; return 1; }
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
		if [[ -n $remote_user ]]; then _auth="-A $_SMB_AUTHFILE"; else _auth="-N"; fi
		local SMB_OPTS="-t 300 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
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
			_mk_out="$(printf '%sexit\n' "$_mk" | command smbclient "$SMB_SHARE" $_auth $SMB_OPTS 2>&1 >/dev/null)"
			_mk_rc=$?
			remote_raw_log "stream_upload.log" "SMB_MKDIR tag=$_stream_tag rc=$_mk_rc dir=$_smbdir"
			printf '%s\n' "$_mk_out" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/stream_upload_${_stream_tag}.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		fi
		# 2. 流式 put -: 用 -c 傳命令 (不佔 stdin!), stdin 留給 put - 讀管道資料
		#    (之前用 printf|smbclient 喂命令會佔住 stdin, 導致 put - 讀不到資料寫出 0KB)
		local _cddir="${_smbdir//\//\\}"
		local _out _cmd_rc
		_out="$(command smbclient "$SMB_SHARE" $_auth $SMB_OPTS \
			-c "cd \"$_cddir\"; put - \"$_file\"" 2>&1)"
		_cmd_rc=$?
		# smbclient 退出碼不可靠, 改看輸出有無錯誤關鍵字
		local _rc=0
		echo "$_out" | grep -qE 'NT_STATUS|does not exist|ERRbadpath|Server (stopped|exited)|Connection.*refused|tree connect failed' && _rc=1
		local _elapsed=$(( $(date +%s) - _stream_start ))
		remote_raw_log "stream_upload.log" "END tag=$_stream_tag type=smb rc=$_rc cmd_rc=$_cmd_rc elapsed=${_elapsed}s rel=$_rel dir=$_cddir file=$_file"
		{
			echo "===== STREAM_UPLOAD_SMB $_stream_tag rel=$_rel rc=$_rc cmd_rc=$_cmd_rc elapsed=${_elapsed}s ====="
			printf '%s\n' "$_out"
		} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/stream_upload_${_stream_tag}.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		if [[ $_rc != 0 ]]; then
			echoRgb "[SMB流式失敗] dir=$_cddir file=$_file" "0" >&2
			echo "$_out" | sed -E 's#://[^/@[:space:]]+:[^/@[:space:]]+@#://[REDACTED]@#g; s/(password[[:space:]]*=[[:space:]]*).*/\1[REDACTED]/I; s/^/  /' >&2
		fi
		return $_rc
		;;
	webdav)
		# WebDAV: 先 MKCOL 逐層建父目錄，再 curl -T - 上傳
		local _wbase="${remote_url%/}"
		local _wauth=""
		[[ -n $remote_user ]] && _wauth="--netrc-file $_WEBDAV_NETRC"
		# 逐層建目錄
		local _wdir="${_rel%/*}"
		if [[ $_wdir != $_rel ]]; then
			local _IFS_old="$IFS"; IFS='/'; local _wp="" _wseg
			for _wseg in $_wdir; do
				_wp="$_wp$_wseg/"
				local _su_mk_err="$TMPDIR/.stream_mkcol_err_$$" _su_mk_http _su_mk_rc
				_su_mk_http="$(curl -sS $_wauth -X MKCOL "$_wbase/${_wp%/}" -o /dev/null -w '%{http_code}' 2>"$_su_mk_err")"
				_su_mk_rc=$?
				remote_raw_log "stream_upload.log" "WEBDAV_MKCOL tag=$_stream_tag rc=$_su_mk_rc http=$_su_mk_http url=$_wbase/${_wp%/}"
				remote_raw_cat "stream_upload_${_stream_tag}.log" "$_su_mk_err" "[STREAM_UPLOAD_WEBDAV_MKCOL stderr]"
				rm -f "$_su_mk_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			done
			IFS="$_IFS_old"
		fi
		local _httpcode _stream_err="$TMPDIR/.stream_err"
		_httpcode="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 30 --speed-time 300 --speed-limit 512 $_wauth -T - "$_wbase/$_rel" 2>"$_stream_err")"
		local _rc=$?
		[[ $_rc = 0 && $_httpcode -ge 400 ]] && _rc=22
		local _elapsed=$(( $(date +%s) - _stream_start ))
		remote_raw_log "stream_upload.log" "END tag=$_stream_tag type=webdav rc=$_rc http=$_httpcode elapsed=${_elapsed}s rel=$_rel url=$_wbase/$_rel"
		remote_raw_cat "stream_upload_${_stream_tag}.log" "$_stream_err" "===== STREAM_UPLOAD_WEBDAV $_stream_tag rel=$_rel rc=$_rc http=$_httpcode elapsed=${_elapsed}s ====="
		if [[ $_rc != 0 ]]; then
			echoRgb "[WebDAV流式失敗 rc=$_rc http=$_httpcode] url=$_wbase/$_rel" "0" >&2
			sed -E 's#://[^/@[:space:]]+:[^/@[:space:]]+@#://[REDACTED]@#g; s/(password[[:space:]]*=[[:space:]]*).*/\1[REDACTED]/I; s/^/  /' "$_stream_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} >&2
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
# 依 remote_type 分發 smbclient(get -) / curl. 配合管道解壓: _stream_download "路徑" | zstd -d | tar -x
_stream_download() {
	local _rel="$1"
	local _stream_tag _stream_start
	_stream_tag="$(_remote_debug_seq stream_download)"
	_stream_start=$(date +%s)
	remote_raw_log "stream_download.log" "BEGIN tag=$_stream_tag type=$remote_type rel=$_rel"
	case $remote_type in
	smb)
		local _auth
		if [[ -n $remote_user ]]; then _auth="-A $_SMB_AUTHFILE"; else _auth="-N"; fi
		local SMB_OPTS="-t 300 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _smbpath="$SMB_REM_PATH/$_rel"; _smbpath="${_smbpath#/}"
		local _smbdir="${_smbpath%/*}" _file="${_smbpath##*/}"
		local _cddir="${_smbdir//\//\\}"
		# get "檔" - : 輸出到 stdout；stderr 另存 raw log 後再轉回 stderr，避免污染資料流。
		local _sd_err="$TMPDIR/.stream_download_err_$$" _sd_rc _sd_elapsed
		command smbclient "$SMB_SHARE" $_auth $SMB_OPTS \
			-c "cd \"$_cddir\"; get \"$_file\" -" 2>"$_sd_err"
		_sd_rc=$?
		_sd_elapsed=$(( $(date +%s) - _stream_start ))
		remote_raw_log "stream_download.log" "END tag=$_stream_tag type=smb rc=$_sd_rc elapsed=${_sd_elapsed}s rel=$_rel dir=$_cddir file=$_file"
		remote_raw_cat "stream_download_${_stream_tag}.log" "$_sd_err" "===== STREAM_DOWNLOAD_SMB $_stream_tag rel=$_rel rc=$_sd_rc elapsed=${_sd_elapsed}s ====="
		grep -Ev '^dos charset|^Can.t load|^Domain=|^OS=|^Try "help"|^getting file |^putting file |^$' "$_sd_err" >&2 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		rm -f "$_sd_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return $_sd_rc
		;;
	webdav)
		local _wauth=""
		[[ -n $remote_user ]] && _wauth="--netrc-file $_WEBDAV_NETRC"
		local _wd_err="$TMPDIR/.stream_download_err_$$" _wd_rc _wd_elapsed
		curl -fsS --connect-timeout 30 --speed-time 300 --speed-limit 512 $_wauth "${remote_url%/}/$_rel" 2>"$_wd_err"
		_wd_rc=$?
		_wd_elapsed=$(( $(date +%s) - _stream_start ))
		remote_raw_log "stream_download.log" "END tag=$_stream_tag type=webdav rc=$_wd_rc elapsed=${_wd_elapsed}s rel=$_rel url=${remote_url%/}/$_rel"
		remote_raw_cat "stream_download_${_stream_tag}.log" "$_wd_err" "===== STREAM_DOWNLOAD_WEBDAV $_stream_tag rel=$_rel rc=$_wd_rc elapsed=${_wd_elapsed}s ====="
		# v24.20.14-7.12：
		# - app_details 不存在/半截回應在增量預掃中是可預期 missing，不污染 stderr。
		# - head -c 探測 tools/tools.sh 會讓 curl 遇到 SIGPIPE/rc=23，也不視為真錯誤。
		# 其他 WebDAV 下載錯誤仍轉出 stderr。
		if [[ $_wd_rc != 0 ]]; then
			# v24.20.14-7.14：
			# WebDAV 的 curl rc=18/22/23 在本工具內常見於：
			#   1) 遠端 app_details 不存在 / 被伺服器回半截，用於增量預掃時應視為 missing；
			#   2) tools/tools.sh 探測被 head 提前關管線；
			#   3) WebDAV 伺服器對不存在檔回錯誤但仍輸出部分內容。
			# 這些都已完整寫入 stream_download_*.log，不再轉出到 stderr.log。
			case $_wd_rc in
			18|22|23)
				_speed_debug_log "WEBDAV_STREAM_DOWNLOAD_EXPECTED_NONFATAL rel=$_rel rc=$_wd_rc"
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

# 從遠端下載單個文件 (用於備份前對比 app_details.json)
# 用法: remote_download_single_file <遠端相對路徑> <本地目標路徑>
# 回傳: 0=成功, 1=失敗
remote_download_single_file() {
	local remote_rel="$1" local_dest="$2"
	[[ -z $remote_type || -z $remote_url ]] && return 1
	local backup_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
	case $remote_type in
	webdav)
		local base_url="${remote_url%/}/$backup_subdir"
		local enc_rel="$(url_encode_path "$remote_rel")"
		local target_url="$base_url/$enc_rel"
		local _tmp="${local_dest}.part.$$" _err="$TMPDIR/.wdav_get_err_$$" _rc _bytes
		# v24.20.14-7.66-16: 暫存錯誤檔可能已被其他清理流程移除；不要讓 rm 噪音污染 stderr.log。
		rm -f "$local_dest" "$_tmp" "$_err" 2>/dev/null
		if [[ -n $remote_user ]]; then
			curl -sS -L --http1.1 --connect-timeout 10 --netrc-file "$_WEBDAV_NETRC" \
				-o "$_tmp" "$target_url" 2>"$_err"
		else
			curl -sS -L --http1.1 --connect-timeout 10 \
				-o "$_tmp" "$target_url" 2>"$_err"
		fi
		_rc=$?
		_bytes="$(_local_file_size_debug "$_tmp")"
		remote_raw_log "remote_download_raw.log" "WEBDAV_SINGLE_GET rc=$_rc bytes=${_bytes:-0} rel=$remote_rel url=$target_url"
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
		smbclient "$share" -A "$_SMB_AUTHFILE" -t 10 -s /dev/null \
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
		if [[ $remote_stream = 1 ]]; then
			echoRgb "流式上傳模式 (邊壓邊傳, 不佔本機空間)" "3"
			# WebDAV 流式需伺服器支援 chunked PUT (Synology 等 Apache WebDAV 常不支援, 回 411)
			if [[ $remote_type = webdav ]]; then
				local _wauth_t=""
				[[ -n $remote_user ]] && _wauth_t="--netrc-file $_WEBDAV_NETRC"
				local _chunk_err
				_chunk_err="$TMPDIR/.webdav_chunk_test_err_$$"
				if ! echo "chunked_test" | curl -fsS -o /dev/null --connect-timeout 15 $_wauth_t -T - "${remote_url%/}/.stream_chunk_test" 2>"$_chunk_err"; then
					remote_raw_cat "remote_webdav_stream_probe_raw.log" "$_chunk_err" "[chunked PUT test stderr]"
					rm -f "$_chunk_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					echoRgb "此 WebDAV 伺服器不支援串流上傳 (chunked PUT, 如 Synology 內建 WebDAV)" "0"
					echoRgb "流式模式無法使用, 請改用 SMB 或設 remote_stream=0" "3"
					exit 1
				fi
				rm -f "$_chunk_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				curl -fsS $_wauth_t -X DELETE "${remote_url%/}/.stream_chunk_test" >/dev/null 2>&1
			fi
		elif [[ $remote_keep_local = true ]]; then
			echoRgb "備份完成後將自動上傳到遠端 (保留本地檔案)" "3"
		else
			echoRgb "備份完成後將自動上傳到遠端 (上傳成功後刪除本地檔案)" "3"
		fi
	else
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
	scan_smb
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
		local out
		out="$(smbclient "$share" -A "$_SMB_AUTHFILE" -t 10 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3 \
			-c "cd ${rem_path:-/}; ls; exit" 2>&1)"
		out="$(smb_filter_noise "$out")"
		if echo "$out" | grep -qE 'NT_STATUS_LOGON_FAILURE'; then
			echoRgb "認證失敗 (帳號或密碼錯誤)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_ACCESS_DENIED'; then
			echoRgb "存取被拒 (帳號權限不足)" "0"
			return 1
		elif echo "$out" | grep -qE 'NT_STATUS_BAD_NETWORK_NAME'; then
			echoRgb "share 名稱錯誤: $share_name (請檢查伺服器是否有此分享)" "0"
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
			# 抓實際協商出的 SMB 協議版本
			# 不同 Samba 版本輸出格式不同, 先把 debug 輸出存檔再多路徑抓取
			local _dbg="$TMPDIR/.smb_dbg_$$"
			smbclient "$share" -A "$_SMB_AUTHFILE" -t 5 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3 -d 5 \
				-c 'exit' >"$_dbg" 2>&1
			local _proto
			# 試多種關鍵字 (依不同 Samba 版本)
			_proto="$(grep -oiE 'protocol negotiation: server.*\[(SMB[0-9_]+|NT[0-9]*)\]|Selected protocol \[?(SMB[0-9_]+|NT[0-9]*)|Negotiated dialect \[?(SMB[0-9_]+|NT[0-9]*)|protocol \[(SMB[0-9_]+|NT[0-9]*)\] negotiated|dialect.*(SMB[0-9_]+|NT[0-9]*)' "$_dbg" | grep -oE '(SMB[0-9_]+|NT[0-9]*)' | head -1)"
			if [[ -n $_proto ]]; then
				echoRgb "協議版本: $_proto" "1"
			else
				# fallback: 抓出所有看似協議版本的字串
				_proto="$(grep -oiE 'SMB[123]_[0-9]{2}' "$_dbg" | sort -u | tail -1)"
				[[ -n $_proto ]] && echoRgb "協議版本: $_proto (推測)" "1"
				# 若仍抓不到, 保留 debug 輸出供排查
				[[ -z $_proto ]] && {
					echoRgb "無法解析協議版本, debug 輸出留在: $_dbg" "2"
					return 0
				}
			fi
			rm -f "$_dbg"
		fi
		;;
	webdav)
		local base_url="${remote_url%/}"
		local code curl_err
		# stderr 寫到檔案, 別污染 http_code
		code="$(curl -sS -L --http1.1 --connect-timeout 10 --netrc-file "$_WEBDAV_NETRC" \
			-X PROPFIND -H "Depth: 0" -w '%{http_code}' -o /dev/null "$base_url" 2>"$TMPDIR/.curl_test_err")"
		curl_err="$(cat "$TMPDIR/.curl_test_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		rm -f "$TMPDIR/.curl_test_err"
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
		3*) echoRgb "未處理的重定向 (HTTP $code, curl -L 已展開但仍失敗, 可能跳到非 WebDAV 端點)" "0"; return 1 ;;
		000)
			# curl 連 HTTP 都還沒走到, 看 stderr 判斷具體原因
			echoRgb "curl 無法完成請求" "0"
			case $curl_err in
			*WRONG_VERSION_NUMBER*|*wrong\ version\ number*)
				echoRgb "原因: 協議跟端口不匹配 (URL 寫 https 但伺服器是 http, 或反過來)" "0"
				case $remote_url in
				https://*) echoRgb "建議: 把 remote_url 改成 http://$REMOTE_HOST:$REMOTE_PORT/..." "3" ;;
				http://*) echoRgb "建議: 把 remote_url 改成 https://$REMOTE_HOST:$REMOTE_PORT/..." "3" ;;
				esac ;;
			*"Could not resolve host"*|*"Couldn't resolve host"*)
				echoRgb "原因: DNS 解析失敗 (域名不存在或 DNS 服務問題)" "0" ;;
			*"Connection refused"*)
				echoRgb "原因: 連線被拒 (端口未開或防火牆攔截)" "0" ;;
			*"Connection timed out"*|*"timed out"*)
				echoRgb "原因: 連線逾時 (網路或防火牆問題)" "0" ;;
			*"SSL certificate"*|*"certificate verify"*|*"server certificate verification failed"*)
				echoRgb "原因: SSL 證書驗證失敗 (自簽證書或過期)" "0"
				echoRgb "建議: 若是自簽證書, 改用 http://, 或在 curl 加 -k (需改腳本)" "3" ;;
			*"SSL_ERROR_SYSCALL"*|*"SSL connect error"*)
				echoRgb "原因: SSL 握手失敗 (TLS 版本不相容 / 伺服器斷線)" "0" ;;
			*"server certificate verification failed"*)
				echoRgb "原因: 伺服器證書驗證失敗" "0"
				echoRgb "建議: 若是自簽證書, 用 http:// 或在 curl 加 -k (需改腳本)" "3" ;;
			*"Host requires authentication"*|*"401 Unauthorized"*)
				echoRgb "原因: 需要認證但帳密為空或錯誤" "0" ;;
			*"Operation too slow"*)
				echoRgb "原因: 傳輸過慢被中斷" "0" ;;
			*"Empty reply from server"*)
				echoRgb "原因: 伺服器收到請求但沒回應 (服務未啟動 / 配置錯誤)" "0" ;;
			*) echoRgb "詳細: $curl_err" "0" ;;
			esac
			return 1 ;;
		*)   echoRgb "WebDAV 異常 (HTTP $code)" "0"
			[[ -n $curl_err ]] && echoRgb "詳細: $curl_err" "0"
			return 1 ;;
		esac
		;;
	esac
	echoRgb "========================================" "3"
	echoRgb "全部測試通過, 可以開始備份" "1"
	return 0
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
		smb_out=$(smbclient "$share" -A "$_SMB_AUTHFILE" -t 10 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3 \
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
		# 格式: "D dirname" 或 "N filename"
		echo "$smb_out" | awk 'NF>=5 && $1 != "." && $1 != ".." {print $2, $1}' > "$sub_listing"
	elif [[ $remote_type = webdav ]]; then
		local base_url="${remote_url%/}"
		local http_code _wdav_err
		_wdav_err="$TMPDIR/.wdav_err_$$"
		: > "$TMPDIR/.wdav_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		http_code=$(curl -sS -L --http1.1 --connect-timeout 10 --netrc-file "$_WEBDAV_NETRC" \
			-X PROPFIND -H "Depth: 1" -w '%{http_code}' -o "$TMPDIR/.wdav_out" \
			"$base_url/$target_dir/" 2>"$_wdav_err")
		# debug: 把 PROPFIND 原始回應與 curl stderr 寫到 log 供除錯；不可污染 stderr.log。
		local dbg_log
		dbg_log="$(_speed_debug_log_path webdav_debug.log)"
		{
			echo "===== WebDAV PROPFIND $(date '+%Y-%m-%d %H:%M:%S') ====="
			echo "URL: $base_url/$target_dir/"
			echo "HTTP code: $http_code"
			if [[ -s "$_wdav_err" ]]; then
				echo "----- curl stderr -----"
				cat "$_wdav_err" 2>/dev/null
			fi
			echo "----- Raw XML response -----"
			[[ -f "$TMPDIR/.wdav_out" ]] && cat "$TMPDIR/.wdav_out" 2>/dev/null
			echo ""
			echo "----- End -----"
		} | while IFS= read -r _dbg_line; do _speed_debug_append_file "$dbg_log" "$_dbg_line"; done
		case $http_code in
		2*) ;;
		404)
			echoRgb "遠端目錄不存在: $target_dir (HTTP 404)" "0"
			echoRgb "請確認遠端有此備份,或備份過至少一次" "3"
			# PROPFIND 根目錄看實際有什麼, 幫用戶確認路徑名
			local root_code root_xml="$TMPDIR/.wdav_root"
			local _root_err="$TMPDIR/.wdav_root_err_$$"
			root_code=$(curl -sS -L --http1.1 --connect-timeout 10 --netrc-file "$_WEBDAV_NETRC" \
				-X PROPFIND -H "Depth: 1" -w '%{http_code}' -o "$root_xml" \
				"$base_url/" 2>"$_root_err")
			{
				echo ""
				echo "----- 根目錄探測 PROPFIND $base_url/ -----"
				echo "HTTP code: $root_code"
				if [[ -s "$_root_err" ]]; then
					echo "----- root curl stderr -----"
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
		# 解析每個 response, 過濾掉「目錄自己」(href 跟 base 同名)
		# 收集成 "D|encoded_name" 或 "N|encoded_name"
		# 兼容 WebDAV XML：d:/D: 名前綴、無前綴、tag 帶屬性、單行 XML。
		# 堅果雲會輸出小寫 d:multistatus / d:response / d:href；舊 parser 只去 D:，導致遠端選單解析為空。
		local raw_listing="$TMPDIR/.raw_wdav_listing"
		echo "$propfind_out" | tr '><' '\n' | awk '
			{
				tag = $1
				# 去掉 XML namespace 前綴，大小寫都支援：d:href / D:href / /d:response / /D:response。
				sub(/^d:/, "", tag)
				sub(/^D:/, "", tag)
				sub(/^\/d:/, "/", tag)
				sub(/^\/D:/, "/", tag)
				# 去掉自關閉尾斜線，例如 resourcetype/、collection/。
				sub(/\/$/, "", tag)
			}
			tag == "response" { in_resp=1; href=""; is_dir=0; next }
			tag == "/response" {
				if (in_resp && href != "") {
					n = split(href, a, "/")
					name = a[n]
					if (name == "" && n > 1) name = a[n-1]
					if (name != "" && name != "/") {
						print (is_dir ? "D" : "N") "|" name
					}
				}
				in_resp=0
				next
			}
			tag == "href" { getline href; next }
			tag == "collection" { is_dir=1 }
		' > "$raw_listing"
		# 過濾掉目錄自己 (encoded 或非 encoded 都比對)
		# target_dir 是 "Backup_zstd_0" 純 ASCII,不需要編碼
		grep -vE "\|${target_dir}\$" "$raw_listing" > "$sub_listing"
		rm -f "$raw_listing"
		# URL 解碼 (支援 UTF-8 中文)
		# 用 printf 將 %XX 轉成實際字元
		local decoded="$TMPDIR/.decoded_listing"
		: > "$decoded"
		while IFS='|' read -r typ name; do
			[[ -z $name ]] && continue
			# printf '%b' 不認 %XX, 要先轉成 \xXX
			local converted
			converted=$(echo "$name" | sed 's/%\([0-9a-fA-F][0-9a-fA-F]\)/\\x\1/g')
			# 用 printf 把 \xXX 還原成真實字元
			local real
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
		local _ra _jchk_total _jchk_i=0 _running=0 _jok=0 _jinvalid=0 _jmissing=0
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
			let _running++
			if [[ $_running -ge 8 ]]; then wait; _running=0; fi
		done < "$TMPDIR/.apps_sorted_keep"
		wait
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
					rm -f "$TMPDIR/.health_check_dl/$_rk.json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				fi
			else
				let _jmissing++
				_speed_debug_log "REMOTE_HEALTH_APPDETAILS_MISSING app=$_ra key=$_rk"
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
	local SMB_OPTS="-t 300 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
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
		out=$(smbclient "$share" -A "$_SMB_AUTHFILE" $SMB_OPTS \
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
	tools_out=$(smbclient "$share" -A "$_SMB_AUTHFILE" $SMB_OPTS \
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
	fix_out=$(smbclient "$share" -A "$_SMB_AUTHFILE" $SMB_OPTS \
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

# WebDAV 下載實作 (並行模式: 先遞迴掃出所有檔案 url, 再 curl -Z 並行下載)
_remote_download_webdav() {
	local chosen="$1" dest="$2" items_file="$3"
	local base_url="${remote_url%/}/$chosen"
	remote_raw_log "remote_download_raw.log" "WEBDAV_BEGIN base_url=$base_url dest=$dest items_file=$items_file"
	local total_items
	total_items=$(wc -l < "$items_file")
	local fail_total=0
	# 遞迴掃描 WebDAV 路徑, 把所有檔案 (含子目錄內) 寫入清單檔
	# 清單格式: <遠端編碼URL>\t<本地完整路徑>
	# $1=遠端 base url (已編碼), $2=本地目錄, $3=清單檔
	_webdav_scan_files() {
		local r_url="$1" l_dir="$2" out_list="$3"
		mkdir -p "$l_dir" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		local out _scan_err="$TMPDIR/.wdav_scan_err_$$" _scan_rc _scan_tag
		_scan_tag="$(_remote_debug_seq webdav_scan)"
		out=$(curl -sS -L --http1.1 --connect-timeout 10 --netrc-file "$_WEBDAV_NETRC" \
			-X PROPFIND -H "Depth: 1" "$r_url/" 2>"$_scan_err")
		_scan_rc=$?
		remote_raw_log "remote_download_raw.log" "WEBDAV_SCAN tag=$_scan_tag rc=$_scan_rc url=$r_url/ local=$l_dir"
		remote_raw_cat "remote_download_webdav_scan_${_scan_tag}.log" "$_scan_err" "===== WEBDAV_SCAN $_scan_tag url=$r_url/ rc=$_scan_rc ====="
		rm -f "$_scan_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		# 用 mktemp 避免遞迴呼叫時不同層級共用同個檔案造成資料覆蓋
		local parsed
		parsed=$(mktemp "$TMPDIR/.wdav_scan_XXXXXX")
		echo "$out" | tr '><' '\n' | awk '
			{
				tag = $1
				sub(/^D:/, "", tag)
				sub(/^\/D:/, "/", tag)
				sub(/\/$/, "", tag)
			}
			tag == "response" { in_resp=1; href=""; is_dir=0; next }
			tag == "/response" {
				if (in_resp && href != "") {
					print (is_dir ? "D" : "F") "	" href
				}
				in_resp=0
				next
			}
			tag == "href" { getline href; next }
			tag == "collection" { is_dir=1 }
		' > "$parsed"
		local r_url_basename_encoded r_url_basename
		r_url_basename_encoded="$(echo "$r_url" | sed 's|/$||; s|.*/||')"
		r_url_basename=$(url_decode_path "$r_url_basename_encoded")
		local rc=0
		while IFS=$'	' read -r typ href; do
			[[ -z $href ]] && continue
			local encoded_name name
			encoded_name="$(echo "$href" | sed 's|/$||; s|.*/||')"
			name=$(url_decode_path "$encoded_name")
			[[ -z $name ]] && continue
			[[ $name = "$r_url_basename" ]] && continue
			if [[ $typ = D ]]; then
				_webdav_scan_files "$r_url/$encoded_name" "$l_dir/$name" "$out_list" || rc=1
			else
				# 寫入清單: URL	本地路徑
				echo -e "$r_url/$encoded_name	$l_dir/$name" >> "$out_list"
			fi
		done < "$parsed"
		rm -f "$parsed"
		return $rc
	}
	# 用 curl -Z (--parallel) 批次下載清單內的所有檔案
	# 每行 "url\tlocal_path", 並行度預設 4
	_webdav_parallel_get() {
		local list="$1"
		[[ ! -s $list ]] && return 0
		# 組裝 curl --config 格式: url + output 一對一
		local cfg="$TMPDIR/.curl_cfg_$$"
		: > "$cfg"
		while IFS=$'	' read -r url lpath; do
			# curl config 格式: 每組 url + output
			# 路徑要用引號避開空白
			echo "url = \"$url\"" >> "$cfg"
			echo "output = \"$lpath\"" >> "$cfg"
		done < "$list"
		local _get_err="$TMPDIR/.wdav_get_err_$$" _get_tag
		_get_tag="$(_remote_debug_seq webdav_get)"
		curl -sS -L --http1.1 --connect-timeout 10 --retry 2 -Z --parallel-max 4 \
			--netrc-file "$_WEBDAV_NETRC" -K "$cfg" 2>"$_get_err"
		local rc=$?
		remote_raw_log "remote_download_raw.log" "WEBDAV_GET tag=$_get_tag rc=$rc cfg=$cfg list=$list"
		{
			echo "===== WEBDAV_PARALLEL_GET $_get_tag rc=$rc cfg=$cfg ====="
			echo "[config]"
			cat "$cfg"
			echo "[stderr]"
			cat "$_get_err" 2>/dev/null
		} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/remote_download_webdav_get_${_get_tag}.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		# v24.20.14-7.66-17: WebDAV parallel GET 清理暫存檔時完全靜默，避免偶發 rm 噪音污染 stderr.log。
		rm -f "$cfg" "$_get_err" 2>/dev/null
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
		local encoded_item
		encoded_item=$(url_encode_path "$item")
		[[ -z $encoded_item ]] && encoded_item="$item"
		echoRgb "[$idx/$total_items] $(progress_bar $((idx * 100 / total_items))) 掃描 $item" "3"
		if ! _webdav_scan_files "$base_url/$encoded_item" "$dest/$item" "$all_files"; then
			echoRgb "✗ 掃描失敗: $item" "0"
			scan_fail=1
			let fail_total++
		fi
	done < "$items_file"
	# 1b. 固定項目 tools/
	echoRgb "掃描固定項目: tools/" "3"
	if ! _webdav_scan_files "$base_url/tools" "$dest/tools" "$all_files"; then
		echoRgb "✗ 掃描失敗: tools/" "0"
		scan_fail=1
		let fail_total++
	fi
	# 1c. 固定檔案 start.sh / restore_settings.conf 直接加進清單
	for f in start.sh restore_settings.conf; do
		echo -e "$base_url/$f\t$dest/$f" >> "$all_files"
	done
	# 2. 並行下載
	local total_files
	total_files=$(wc -l < "$all_files")
	echoRgb "並行下載 $total_files 個檔案 (4 路同時)" "3"
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
	# 只有在 backup / backup_media / backup_update_apk 跑完後才上傳
	# 其他功能 (測試連線、生成列表、檢查壓縮等) 不觸發上傳
	[[ $REMOTE_TRIGGER != 1 ]] && return 0
	# 純本機模式：完全不進入遠端收尾，避免「已上傳/只上傳依賴文件」等提示殘留。
	remote_ui_allowed || return 0
	# 防雙重觸發 (backup 內直接呼叫 + trap EXIT 都可能呼叫)
	[[ $REMOTE_DONE = 1 ]] && return 0
	REMOTE_DONE=1
	# 流式模式: 應用數據與 json 已在備份過程中逐個流式傳走, 此處只補傳結尾的 wifi (若有)
	if [[ $remote_stream = 1 && -n $remote_type ]]; then
		local _wifidir="$TMPDIR/.stream_stage/wifi"
		if [[ $REMOTE_UPLOAD_WIFI = 1 && -d $_wifidir ]]; then
			local _wf
			for _wf in "$_wifidir"/*; do
				[[ -f $_wf ]] && _stream_upload "wifi/${_wf##*/}" < "$_wf"
			done
			echoRgb "wifi 設定已上傳遠端" "1"
		fi
		echoRgb "流式上傳完成 (數據未佔用本機空間)" "1"
		# 上傳恢復必要檔案到遠端 (tools/ start.sh restore_settings.conf), 讓遠端備份可獨立恢復 (功能8/10 需要)
		stream_upload_infra
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
					fi
				else
					let _jmissing++
					_speed_debug_log "REMOTE_HEALTH_APPDETAILS_MISSING app=$_ra key=$_rk"
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
	*) return 0 ;;
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
Manager_version="$(su -v 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
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
_dex_expected_permission_skip() {
	case "$1" in
	android.permission.FOREGROUND_SERVICE|android.permission.FOREGROUND_SERVICE_*|android.permission.SCHEDULE_EXACT_ALARM|android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS|android.permission.WRITE_SETTINGS|android.permission.REQUEST_INSTALL_PACKAGES)
		return 0 ;;
	esac
	return 1
}
_dex_expected_permission_note() {
	local _perm="$1"
	case "$_perm" in
	android.permission.FOREGROUND_SERVICE|android.permission.FOREGROUND_SERVICE_*)
		echo "略過前台服務宣告權限 ${_perm}：此類權限不是可直接 grant/revoke 的 runtime 權限；若備份含 op=76，會由 AppOps 恢復前台服務狀態" ;;
	android.permission.SCHEDULE_EXACT_ALARM)
		echo "略過精確鬧鐘 ${_perm}：這是特殊權限/AppOps 類狀態，不是可直接 grant/revoke 的 runtime 權限" ;;
	android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
		echo "略過忽略電池優化請求權限 ${_perm}：實際狀態由電池白名單/背景設定恢復與驗證" ;;
	android.permission.WRITE_SETTINGS)
		echo "略過寫入系統設定 ${_perm}：實際狀態由 AppOps 恢復與驗證" ;;
	android.permission.REQUEST_INSTALL_PACKAGES)
		echo "略過安裝未知應用 ${_perm}：實際狀態由 AppOps 恢復與驗證" ;;
	*)
		echo "略過系統不可直接 grant/revoke 的權限 ${_perm}" ;;
	esac
}
_dex_expected_installer_skip() {
	case "$1" in
	*'Unknown calling UID'*|*'calling UID'*) return 0 ;;
	esac
	return 1
}
_dex_expected_notification_skip() {
	case "$1" in
	NOTIFY_APP:importance|NOTIFY_CHANNEL:*:deleted) return 0 ;;
	esac
	return 1
}
_dex_translate_failed_skip() {
	local _line="$1" _key _pkg _reason _perm _op _mode _k _val _installer _msg
	_key="${_line%% *}"
	_pkg="$(_dex_kv_get "$_line" package)"
	_reason="$(_dex_kv_get "$_line" reason)"
	_perm="$(_dex_kv_get "$_line" permission)"
	_op="$(_dex_kv_get "$_line" op)"
	_mode="$(_dex_kv_get "$_line" mode)"
	_k="$(_dex_kv_get "$_line" key)"
	_val="$(_dex_kv_get "$_line" value)"
	_installer="$(_dex_kv_get "$_line" installer)"
	_msg="$(_dex_reason_zh "$_reason")"
	case $_key in
		PACKAGE_UID_FAILED_SKIP) _dex_human_emit "$_pkg" "讀取 UID 失敗：$_msg" ;;
		PACKAGE_LABEL_FAILED_SKIP) _dex_human_emit "$_pkg" "讀取應用名稱失敗：$_msg" ;;
		INSTALLER_FAILED_SKIP) _dex_human_emit "$_pkg" "讀取 installer 失敗：$_msg" ;;
		INSTALLER_SET_FAILED_SKIP)
			if _dex_expected_installer_skip "$_reason $_msg"; then
				_dex_human_emit "$_pkg" "略過事後 installer 設定：系統不允許目前 UID 直接 setInstaller；若 Play 來源驗證已通過，這不影響恢復結果"
			else
				_dex_human_emit "$_pkg" "設定 installer=${_installer:-未知} 失敗：$_msg"
			fi ;;
		INSTALLER_CLEAR_FAILED_SKIP) _dex_human_emit "$_pkg" "清除 installer 失敗：$_msg" ;;
		INSTALL_SOURCE_FAILED_SKIP) _dex_human_emit "$_pkg" "讀取安裝來源診斷失敗：$_msg" ;;
		INSTALL_COMPARE_FAILED_SKIP) _dex_human_emit "$_pkg" "比對安裝診斷失敗：$_msg" ;;
		PERMISSION_QUERY_FAILED_SKIP) _dex_human_emit "$_pkg" "讀取權限狀態失敗：$_msg" ;;
		PERMISSION_GRANT_FAILED_SKIP)
			if _dex_expected_permission_skip "$_perm"; then
				_dex_human_emit "$_pkg" "$(_dex_expected_permission_note "$_perm")"
			else
				_dex_human_emit "$_pkg" "授予權限 ${_perm:-未知} 失敗：$_msg"
			fi ;;
		PERMISSION_REVOKE_FAILED_SKIP)
			if _dex_expected_permission_skip "$_perm"; then
				_dex_human_emit "$_pkg" "$(_dex_expected_permission_note "$_perm")"
			else
				_dex_human_emit "$_pkg" "撤銷權限 ${_perm:-未知} 失敗：$_msg"
			fi ;;
		APP_OPS_RESET_FAILED_SKIP) _dex_human_emit "$_pkg" "AppOps package-scoped reset 不支援，已安全略過：$_msg" ;;
		APP_OPS_RESET_FALLBACK_OP_FAILED_SKIP) _dex_human_emit "$_pkg" "AppOps reset fallback 單一 op 失敗：op=${_op:-?}" ;;
		APP_OPS_RESET_FALLBACK_PACKAGE_FAILED_SKIP) _dex_human_emit "$_pkg" "AppOps reset fallback 套件讀取失敗：$_msg" ;;
		APP_OP_FAILED_SKIP) _dex_human_emit "$_pkg" "設定 AppOps op=${_op:-?} mode=${_mode:-?} 失敗：$_msg" ;;
		APP_OP_PACKAGE_FAILED_SKIP) _dex_human_emit "$_pkg" "處理 AppOps 批次失敗：$_msg" ;;
		ASK_MODE_FAILED_SKIP) _dex_human_emit "$_pkg" "每次詢問模式還原失敗/略過：${_perm:-未知}，原因=$_msg" ;;
		MEDIA_MODE_FAILED_SKIP) _dex_human_emit "$_pkg" "媒體權限語意模式還原失敗/略過：$(_dex_kv_get "$_line" mode)，原因=$_msg" ;;
		MEDIA_MODE_PACKAGE_FAILED_SKIP) _dex_human_emit "$_pkg" "讀取媒體權限套件失敗：$_msg" ;;
		LOCATION_MODE_FAILED_SKIP) _dex_human_emit "$_pkg" "定位權限語意模式還原失敗/略過：$(_dex_kv_get "$_line" mode)，原因=$_msg" ;;
		LOCATION_MODE_PACKAGE_FAILED_SKIP) _dex_human_emit "$_pkg" "讀取定位權限套件失敗：$_msg" ;;
		PERMISSION_FLAGS_FAILED_SKIP) _dex_human_emit "$_pkg" "權限 flags 還原失敗/略過：${_perm:-未知}，原因=$_msg" ;;
		PERMISSION_STATE_PACKAGE_FAILED_SKIP) _dex_human_emit "$_pkg" "權限狀態套件讀取失敗：$_msg" ;;
		PERMISSION_PACKAGE_FAILED_SKIP) _dex_human_emit "$_pkg" "權限套件讀取失敗：$_msg" ;;
		RUNTIME_APPOP_PACKAGE_FAILED_SKIP) _dex_human_emit "$_pkg" "runtime AppOps 修正套件讀取失敗：$_msg" ;;
		RUNTIME_APPOP_ALLOW_FAILED_SKIP|RUNTIME_APPOP_FIX_FAILED_SKIP|SEMANTIC_APPOP_ALLOW_FAILED_SKIP) _dex_human_emit "$_pkg" "runtime 權限 AppOps 修正失敗/略過：${_perm:-未知}，原因=$_msg" ;;
		SEMANTIC_GRANT_FAILED_SKIP) _dex_human_emit "$_pkg" "語意權限 grant 失敗/略過：${_perm:-未知}，原因=$_msg" ;;
		SEMANTIC_REVOKE_FAILED_SKIP) _dex_human_emit "$_pkg" "語意權限 revoke 失敗/略過：${_perm:-未知}，原因=$_msg" ;;
		BATTERY_QUERY_FAILED_SKIP) _dex_human_emit "$_pkg" "讀取電池/背景設定失敗：$_msg" ;;
		BATTERY_SET_FAILED_SKIP) _dex_human_emit "$_pkg" "設定電池/背景項目 ${_k:-?}=${_val:-?} 失敗：$_msg" ;;
		BATTERY_PACKAGE_FAILED_SKIP) _dex_human_emit "$_pkg" "處理電池/背景批次失敗：$_msg" ;;
		NOTIFICATION_QUERY_FAILED_SKIP) _dex_human_emit "$_pkg" "讀取通知設定失敗：$_msg" ;;
		NOTIFICATION_SET_FAILED_SKIP)
			if _dex_expected_notification_skip "$_k"; then
				_dex_human_emit "$_pkg" "略過不支援的通知細項 ${_k:-?}：不同 Android/ROM 可能不能直接寫入此欄位；後續通知驗證通過即可"
			else
				_dex_human_emit "$_pkg" "設定通知項目 ${_k:-?}=${_val:-?} 失敗：$_msg"
			fi ;;
		NOTIFICATION_PACKAGE_FAILED_SKIP) _dex_human_emit "$_pkg" "處理通知設定批次失敗：$_msg" ;;
		*) _dex_human_emit "${_pkg:-dex}" "dex 操作略過：$_key ${_reason:+原因=$(_dex_reason_zh "$_reason")}" ;;
	esac
}

_verify_mismatch_log() {
	local _title="$1"
	shift
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d "$SPEED_DEBUG_RUN_DIR" ]] || return 0
	{
		printf '[%s] %s\n' "$(date '+%H:%M:%S' 2>/dev/null)" "$_title"
		printf '%s\n' "$*"
	} >> "$SPEED_DEBUG_RUN_DIR/verify_mismatch.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_runtime_semantic_report() {
	local _expect="$1" _actual="$2" _media="$3" _location="$4" _pflags="$5" _ask="$6" _out
	[ -n "${SPEED_DEBUG_RUN_DIR:-}" ] && [ -d "$SPEED_DEBUG_RUN_DIR" ] && [ -s "$_expect" ] && [ -s "$_actual" ] || return 0
	_out="$SPEED_DEBUG_RUN_DIR/permission_semantic_verify.log"
	awk -F'\t' -v media="$_media" -v location="$_location" -v pflags="$_pflags" -v ask="$_ask" '
		function modezh(m){ if(m=="0")return "允許"; if(m=="1")return "忽略/不允許"; if(m=="2")return "拒絕/錯誤"; if(m=="3")return "預設"; if(m=="4")return "僅前台"; if(m=="" || m=="?") return "未知"; return m }
		function declarative_runtime_skip(p){ return (p=="android.permission.FOREGROUND_SERVICE" || p ~ /^android\.permission\.FOREGROUND_SERVICE_/) }
		function groupzh(p){
			if(p=="android.permission.CAMERA") return "相機";
			if(p=="android.permission.RECORD_AUDIO") return "麥克風";
			if(p=="android.permission.ACCESS_FINE_LOCATION") return "精確位置";
			if(p=="android.permission.ACCESS_COARSE_LOCATION") return "大概位置";
			if(p=="android.permission.ACCESS_BACKGROUND_LOCATION") return "背景定位";
			if(p=="android.permission.READ_MEDIA_IMAGES") return "相片";
			if(p=="android.permission.READ_MEDIA_VIDEO") return "影片";
			if(p=="android.permission.READ_MEDIA_AUDIO") return "音訊";
			if(p=="android.permission.READ_MEDIA_VISUAL_USER_SELECTED") return "選取相片/影片";
			if(p=="android.permission.POST_NOTIFICATIONS") return "通知";
			return p;
		}
		function pfnum(v){ gsub(/^pflags=/,"",v); if(v=="" || v=="?") return 0; return v+0 }
		function hasbit(n,b){ return (int(n / b) % 2) == 1 }
		function askflag(g,pf){ return (g!="true" && (hasbit(pfnum(pf),65536) || hasbit(pfnum(pf),131072) || hasbit(pfnum(pf),16384))) }
		function loc_detail_from_value(v,p){
			if(v=="ask_every_time") return "每次詢問";
			if(p=="android.permission.ACCESS_FINE_LOCATION"){
				if(v=="precise" || v=="background") return "精確位置/使用期間";
				if(v=="approximate" || v=="denied") return "精確位置未授予";
			}
			if(p=="android.permission.ACCESS_COARSE_LOCATION"){
				if(v=="precise" || v=="approximate" || v=="background") return "大概位置/使用期間";
				if(v=="denied") return "大概位置未授予";
			}
			if(p=="android.permission.ACCESS_BACKGROUND_LOCATION"){
				if(v=="background") return "背景允許";
				if(v=="precise" || v=="approximate" || v=="denied") return "背景未授予";
			}
			return loczh(v);
		}
		function sem(g,mode,pf,p){
			if(askflag(g,pf)) return "每次詢問";
			if(g!="true"){
				if(p=="android.permission.ACCESS_FINE_LOCATION") return "精確位置未授予";
				if(p=="android.permission.ACCESS_COARSE_LOCATION") return "大概位置未授予";
				if(p=="android.permission.ACCESS_BACKGROUND_LOCATION") return "背景未授予";
				return "不允許";
			}
			if(mode=="1" || mode=="2"){
				if(p=="android.permission.ACCESS_FINE_LOCATION") return "精確位置未授予";
				if(p=="android.permission.ACCESS_COARSE_LOCATION") return "大概位置未授予";
				if(p=="android.permission.ACCESS_BACKGROUND_LOCATION") return "背景未授予";
				return "不允許(AppOps=" modezh(mode) ")";
			}
			if(p=="android.permission.ACCESS_BACKGROUND_LOCATION") return "背景允許";
			if(p=="android.permission.ACCESS_FINE_LOCATION") return "精確位置/使用期間";
			if(p=="android.permission.ACCESS_COARSE_LOCATION") return "大概位置/使用期間";
			if(mode=="4") return "僅前台/使用期間";
			if(p=="android.permission.READ_MEDIA_VISUAL_USER_SELECTED") return "選取相片/影片";
			return "允許";
		}
		function loczh(v){ if(v=="ask_every_time")return "每次詢問"; if(v=="background")return "背景允許"; if(v=="precise")return "精確位置/使用期間"; if(v=="approximate")return "大概位置/使用期間"; if(v=="denied")return "不允許"; if(v=="")return "未設定"; return v }
		function mediazh(v){ if(v=="selected")return "選取相片/影片"; if(v=="full")return "全部相片/影片"; if(v=="denied")return "不允許"; if(v=="")return "未設定"; return v }
		function read_brackets(file, kind,    line,n,a,i,seg,m,pkg){
			if(file=="") return;
			while((getline line < file) > 0){
				n=split(line,a,"]");
				for(i=1;i<=n;i++){
					seg=a[i]; gsub(/^[[:space:]\[]+/,"",seg); gsub(/[[:space:]]+$/,"",seg); if(seg=="") continue;
					m=split(seg,b,/ +/); if(m<2) continue; pkg=b[1]; pkgs[pkg]=1;
					if(kind=="media") expMedia[pkg]=b[2];
					else if(kind=="location") expLoc[pkg]=b[2];
					else if(kind=="ask") { for(j=2;j<=m;j++) expAsk[pkg SUBSEP b[j]]=1; }
					else if(kind=="pflags") { for(j=2;j+1<=m;j+=2) expPf[pkg SUBSEP b[j]]=b[j+1]; }
					else if(kind=="ops") { for(j=2;j+1<=m;j+=2) expOpMode[pkg SUBSEP b[j]]=b[j+1]; }
				}
			}
			close(file);
		}
		function permop(p){
			if(p=="android.permission.ACCESS_COARSE_LOCATION") return "0";
			if(p=="android.permission.ACCESS_FINE_LOCATION") return "1";
			if(p=="android.permission.READ_CONTACTS") return "4";
			if(p=="android.permission.WRITE_CONTACTS") return "5";
			if(p=="android.permission.POST_NOTIFICATIONS") return "11";
			if(p=="android.permission.CAMERA") return "26";
			if(p=="android.permission.RECORD_AUDIO") return "27";
			if(p=="android.permission.READ_PHONE_STATE") return "51";
			if(p=="android.permission.GET_ACCOUNTS") return "62";
			if(p=="android.permission.READ_PHONE_NUMBERS") return "65";
			if(p=="android.permission.READ_MEDIA_AUDIO") return "81";
			if(p=="android.permission.READ_MEDIA_VIDEO") return "83";
			if(p=="android.permission.READ_MEDIA_IMAGES") return "85";
			if(p=="android.permission.ACCESS_MEDIA_LOCATION") return "90";
			if(p=="android.permission.BLUETOOTH_CONNECT") return "111";
			if(p=="android.permission.READ_MEDIA_VISUAL_USER_SELECTED") return "123";
			return "";
		}
		function grant_exp(pkg,perm,    k){ k=pkg SUBSEP perm; return ((k in expv) ? expv[k] : "") }
		function exp_mode(pkg,perm,    po,k){ po=permop(perm); if(po=="") return ""; k=pkg SUBSEP po; return ((k in expOpMode) ? expOpMode[k] : "") }
		function exp_known(pkg,perm,    k,po,ok){
			k=pkg SUBSEP perm; if(k in expv || k in expAsk || k in expPf) return 1;
			po=permop(perm); if(po!=""){ ok=pkg SUBSEP po; if(ok in expOpMode) return 1; }
			return 0;
		}
		function act_known(pkg,perm,    k){ k=pkg SUBSEP perm; return (k in act); }
		function exp_perm_sem(pkg,perm,eg,    k,em){
			k=pkg SUBSEP perm;
			if(k in expAsk) return "每次詢問";
			if((perm=="android.permission.ACCESS_FINE_LOCATION" || perm=="android.permission.ACCESS_COARSE_LOCATION" || perm=="android.permission.ACCESS_BACKGROUND_LOCATION") && (pkg in expLoc)) return loc_detail_from_value(expLoc[pkg],perm);
			if(perm=="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" && (pkg in expMedia)) return mediazh(expMedia[pkg]);
			if(!exp_known(pkg,perm)) return "未要求";
			em=exp_mode(pkg,perm);
			# Android 12+ 相機/麥克風在系統 UI 屬於「使用期間」語意；備份佇列只有 runtime grant 時，
			# 不應把 expect 顯示成無限制「允許」，否則會和實際 AppOps mode=4 形成假 mismatch。
			if((perm=="android.permission.CAMERA" || perm=="android.permission.RECORD_AUDIO") && eg=="true" && (em=="" || em=="3" || em=="4")) return "僅前台/使用期間";
			return sem(eg,em,((k in expPf)?expPf[k]:"0"),perm);
		}
		function expected_location(pkg,    kf,kc,kb,fg,cg,bg){
			if(pkg in expLoc) return loczh(expLoc[pkg]);
			kf=pkg SUBSEP "android.permission.ACCESS_FINE_LOCATION"; kc=pkg SUBSEP "android.permission.ACCESS_COARSE_LOCATION"; kb=pkg SUBSEP "android.permission.ACCESS_BACKGROUND_LOCATION";
			if((kf in expAsk) || (kc in expAsk)) return "每次詢問";
			fg=((kf in expv)?expv[kf]:""); cg=((kc in expv)?expv[kc]:""); bg=((kb in expv)?expv[kb]:"");
			if(bg=="true") return "背景允許";
			if(fg=="true") return "精確位置/使用期間";
			if(cg=="true") return "大概位置/使用期間";
			if((kf in expv) || (kc in expv) || (kb in expv)) return "不允許";
			return "未設定";
		}
		function actual_location(pkg,    kf,kc,kb,fg,cg,bg,fpf,cpf){
			kf=pkg SUBSEP "android.permission.ACCESS_FINE_LOCATION"; kc=pkg SUBSEP "android.permission.ACCESS_COARSE_LOCATION"; kb=pkg SUBSEP "android.permission.ACCESS_BACKGROUND_LOCATION";
			fg=((kf in act)?act[kf]:""); cg=((kc in act)?act[kc]:""); bg=((kb in act)?act[kb]:""); fpf=((kf in pf)?pf[kf]:"0"); cpf=((kc in pf)?pf[kc]:"0");
			if(askflag(fg,fpf) || askflag(cg,cpf)) return "每次詢問";
			if(bg=="true") return "背景允許";
			if(fg=="true") return "精確位置/使用期間";
			if(cg=="true") return "大概位置/使用期間";
			if((kf in act) || (kc in act) || (kb in act)) return "不允許";
			return "未讀到";
		}
		function expected_media(pkg,    ki,kv,ks,ig,vg,sg){
			if(pkg in expMedia) return mediazh(expMedia[pkg]);
			ki=pkg SUBSEP "android.permission.READ_MEDIA_IMAGES"; kv=pkg SUBSEP "android.permission.READ_MEDIA_VIDEO"; ks=pkg SUBSEP "android.permission.READ_MEDIA_VISUAL_USER_SELECTED";
			ig=((ki in expv)?expv[ki]:""); vg=((kv in expv)?expv[kv]:""); sg=((ks in expv)?expv[ks]:"");
			if(sg=="true" && ig!="true" && vg!="true") return "選取相片/影片";
			if(ig=="true" && vg=="true") return "全部相片/影片";
			if(ig=="true") return "相片允許";
			if(vg=="true") return "影片允許";
			if((ki in expv) || (kv in expv) || (ks in expv)) return "不允許";
			return "未設定";
		}
		function actual_media(pkg,    ki,kv,ks,ig,vg,sg){
			ki=pkg SUBSEP "android.permission.READ_MEDIA_IMAGES"; kv=pkg SUBSEP "android.permission.READ_MEDIA_VIDEO"; ks=pkg SUBSEP "android.permission.READ_MEDIA_VISUAL_USER_SELECTED";
			ig=((ki in act)?act[ki]:""); vg=((kv in act)?act[kv]:""); sg=((ks in act)?act[ks]:"");
			if(sg=="true" && ig!="true" && vg!="true") return "選取相片/影片";
			if(ig=="true" && vg=="true") return "全部相片/影片";
			if(ig=="true") return "相片允許";
			if(vg=="true") return "影片允許";
			if((ki in act) || (kv in act) || (ks in act)) return "不允許";
			return "未讀到";
		}
		function one_sem(pkg,perm,    k){ k=pkg SUBSEP perm; if(k in act) return sem(act[k],mode[k],pf[k],perm); return (exp_known(pkg,perm) ? "未讀到" : "未要求"); }
		BEGIN {
			read_brackets(media,"media"); read_brackets(location,"location"); read_brackets(pflags,"pflags"); read_brackets(ask,"ask"); read_brackets(ops,"ops");
			print "# permission semantic detail";
		}
		NR==FNR { k=$1 SUBSEP $2; act[k]=$3; op[k]=$4; mode[k]=$5; pfv=$6; sub(/^pflags=/,"",pfv); pf[k]=(pfv==""?"0":pfv); pkgs[$1]=1; next }
		{
			k=$1 SUBSEP $2; expv[k]=$3; pkgs[$1]=1;
			a=(k in act?act[k]:"未讀到"); m=(k in mode?mode[k]:"?"); o=(k in op?op[k]:"?"); p=(k in pf?pf[k]:"0");
			if(declarative_runtime_skip($2)){
				printf "%s\t%s\t%s\texpect=宣告型權限，略過 runtime 判定\tactual=宣告型權限，略過 runtime 判定\top=%s\tmode=%s(%s)\tpflags=%s\tnote=此類前台服務權限不是可 grant/revoke 的 runtime 權限；相關狀態由 AppOps/系統語意驗證\n", $1, groupzh($2), $2, o, m, modezh(m), p;
				next;
			}
			printf "%s\t%s\t%s\texpect=%s\tactual=%s\top=%s\tmode=%s(%s)\tpflags=%s\n", $1, groupzh($2), $2, exp_perm_sem($1,$2,$3), sem(a,m,p,$2), o, m, modezh(m), p;
		}
		END {
			print "# permission semantic snapshot";
			for(pkg in pkgs){
				printf "%s\t相機\texpect=%s\tactual=%s\n", pkg, exp_perm_sem(pkg,"android.permission.CAMERA",grant_exp(pkg,"android.permission.CAMERA")), one_sem(pkg,"android.permission.CAMERA");
				printf "%s\t麥克風\texpect=%s\tactual=%s\n", pkg, exp_perm_sem(pkg,"android.permission.RECORD_AUDIO",grant_exp(pkg,"android.permission.RECORD_AUDIO")), one_sem(pkg,"android.permission.RECORD_AUDIO");
				printf "%s\t定位\texpect=%s\tactual=%s\n", pkg, expected_location(pkg), actual_location(pkg);
				printf "%s\t相片與影片\texpect=%s\tactual=%s\n", pkg, expected_media(pkg), actual_media(pkg);
				printf "%s\t音訊\texpect=%s\tactual=%s\n", pkg, exp_perm_sem(pkg,"android.permission.READ_MEDIA_AUDIO",grant_exp(pkg,"android.permission.READ_MEDIA_AUDIO")), one_sem(pkg,"android.permission.READ_MEDIA_AUDIO");
				printf "%s\t通知\texpect=%s\tactual=%s\n", pkg, exp_perm_sem(pkg,"android.permission.POST_NOTIFICATIONS",grant_exp(pkg,"android.permission.POST_NOTIFICATIONS")), one_sem(pkg,"android.permission.POST_NOTIFICATIONS");
			}
		}
	' "$_actual" "$_expect" > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
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
	# __OPS__ 通常不含 CAMERA/RECORD_AUDIO/LOCATION 這些 runtime op；
	# 從 dex verify actual 補進來，才能診斷「每次詢問」相關 package/uid 雙狀態。
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
		_dex_raw /system/bin com.xayah.dex.HiddenApiUtil appOpsScopeDetail "${USER_ID:-0}" "$_scope_args" > "$_dex_scope" 2>>"$_raw"
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
_appops_semantic_report() {
	local _expect="$1" _actual="$2" _out
	[ -n "${SPEED_DEBUG_RUN_DIR:-}" ] && [ -d "$SPEED_DEBUG_RUN_DIR" ] && [ -s "$_expect" ] && [ -s "$_actual" ] || return 0
	_out="$SPEED_DEBUG_RUN_DIR/appops_semantic_verify.log"
	awk -F'\t' '
		function modezh(m){ if(m=="0")return "允許"; if(m=="1")return "忽略/不允許"; if(m=="2")return "拒絕/錯誤"; if(m=="3")return "預設"; if(m=="4")return "僅前台"; if(m=="" || m=="?")return "未知"; return m }
		function opname(op){
			if(op=="0") return "粗略定位"; if(op=="1") return "精確定位"; if(op=="11") return "通知";
			if(op=="24") return "懸浮窗"; if(op=="26") return "相機"; if(op=="27") return "麥克風";
			if(op=="66") return "安裝未知應用"; if(op=="67") return "子母畫面"; if(op=="76") return "前台服務";
			if(op=="81") return "讀取音訊"; if(op=="83") return "讀取影片"; if(op=="85") return "讀取圖片"; if(op=="89") return "讀取裝置識別碼";
			if(op=="90") return "媒體位置"; if(op=="92") return "管理所有檔案"; if(op=="107") return "精確鬧鐘";
			if(op=="119") return "受限設定存取"; if(op=="123") return "選取相片/影片"; if(op=="133") return "全螢幕通知";
			if(op=="154") return "相機來源"; if(op=="155") return "麥克風來源";
			return "op_" op;
		}
		function scopehint(op){
			if(op=="0" || op=="1" || op=="26" || op=="27" || op=="81" || op=="83" || op=="85" || op=="123" || op=="154" || op=="155") return "runtime/uid-sensitive";
			if(op=="24" || op=="66" || op=="67" || op=="76" || op=="89" || op=="92" || op=="107" || op=="119" || op=="133") return "package-special";
			return "package";
		}
		function warn(op,e,a){
			if(a=="未讀到") return "未讀到";
			if(e==a) return "OK";
			if((op=="0" || op=="1" || op=="26" || op=="27") && e=="4" && a=="0") return "注意:可能缺 uid 前台語意";
			if((op=="0" || op=="1" || op=="26" || op=="27") && e=="0" && a=="4") return "注意:實際為僅前台";
			return "MISMATCH";
		}
		NR==FNR { act[$1"\t"$2]=$3; next }
		BEGIN { print "# appops semantic verify"; print "# scope_hint 只是目前 tools.sh 可用資料的分層提示；actual 仍是 dex 讀回的合併 mode，不代表已完成 uidMode/packageMode 拆讀。" }
		{
			k=$1"\t"$2; a=(k in act?act[k]:"未讀到");
			printf "%s\top=%s\tname=%s\tscope_hint=%s\texpect=%s(%s)\tactual=%s(%s)\t%s\n", $1, $2, opname($2), scopehint($2), $3, modezh($3), a, modezh(a), warn($2,$3,a)
		}
	' "$_actual" "$_expect" > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_permission_policy_v2_runtime_report() {
	local _expect="$1" _actual="$2" _out
	[ -n "${SPEED_DEBUG_RUN_DIR:-}" ] && [ -d "$SPEED_DEBUG_RUN_DIR" ] && [ -s "$_expect" ] && [ -s "$_actual" ] || return 0
	_out="$SPEED_DEBUG_RUN_DIR/permission_policy_v2_verify.log"
	awk -F'\t' '
		function modezh(m){ if(m=="0")return "允許"; if(m=="1")return "忽略/不允許"; if(m=="2")return "拒絕/錯誤"; if(m=="3")return "預設"; if(m=="4")return "僅前台"; if(m==""||m=="?")return "未知"; return m }
		function hasbit(n,b){ return (int(n / b) % 2) == 1 }
		function flags(pf, s){ pf+=0; s=""; if(hasbit(pf,1))s=s"USER_SET,"; if(hasbit(pf,2))s=s"USER_FIXED,"; if(hasbit(pf,4))s=s"POLICY_FIXED,"; if(hasbit(pf,64))s=s"SYSTEM_FIXED,"; if(hasbit(pf,128))s=s"GRANTED_BY_DEFAULT,"; if(hasbit(pf,256))s=s"USER_SENSITIVE_WHEN_GRANTED,"; if(hasbit(pf,512))s=s"USER_SENSITIVE_WHEN_DENIED,"; if(hasbit(pf,2048))s=s"RESTRICTION_INSTALLER_EXEMPT,"; if(hasbit(pf,16384))s=s"ONE_TIME,"; if(hasbit(pf,65536))s=s"AUTO_REVOKED,"; if(hasbit(pf,131072))s=s"USER_SELECTED_REVOKE,"; sub(/,$/,"",s); return s }
		function special(p){ return (p=="android.permission.SYSTEM_ALERT_WINDOW"||p=="android.permission.WRITE_SETTINGS"||p=="android.permission.SCHEDULE_EXACT_ALARM"||p=="android.permission.REQUEST_INSTALL_PACKAGES"||p=="android.permission.MANAGE_EXTERNAL_STORAGE") }
		function ptype(p){ if(p ~ /^android\.permission\.FOREGROUND_SERVICE/) return "DECLARATIVE_PERMISSION"; if(special(p)) return "SPECIAL_PERMISSION_APPOP_CONTROLLED"; if(p=="android.permission.ACCESS_FINE_LOCATION"||p=="android.permission.ACCESS_COARSE_LOCATION"||p=="android.permission.ACCESS_BACKGROUND_LOCATION") return "LOCATION_RUNTIME_APPOP"; if(p ~ /^android\.permission\.READ_MEDIA_/ || p=="android.permission.READ_EXTERNAL_STORAGE" || p=="android.permission.WRITE_EXTERNAL_STORAGE") return "MEDIA_RUNTIME_APPOP"; if(p=="android.permission.CAMERA"||p=="android.permission.RECORD_AUDIO"||p=="android.permission.POST_NOTIFICATIONS") return "RUNTIME_USER_APPOP"; if(p ~ /^android\.permission\./) return "RUNTIME_OR_MANIFEST_PERMISSION"; return "CUSTOM_OR_SIGNATURE_PERMISSION" }
		function route(p,e){ t=ptype(p); if(t=="DECLARATIVE_PERMISSION") return "manifest_declared_skip_runtime_grant"; if(t=="SPECIAL_PERMISSION_APPOP_CONTROLLED") return "restoreAppStateBatch.__OPS__"; if(t=="LOCATION_RUNTIME_APPOP") return "__GRANT__/__REVOKE__ + __LOCATION__/__ASK__/__PFLAGS__"; if(t=="MEDIA_RUNTIME_APPOP") return "__GRANT__/__REVOKE__ + __MEDIA__/__PFLAGS__"; return (e=="true"?"restoreAppStateBatch.__GRANT__":"restoreAppStateBatch.__REVOKE__") }
		function source(p,pf){ if(p ~ /^android\.permission\.FOREGROUND_SERVICE/) return "ANDROID_FRAMEWORK_MANIFEST_DECLARATION"; if(special(p)) return "APP_OPS_SERVICE + SETTINGS_UI_POLICY"; if(hasbit(pf,4))return "DEVICE_OR_SYSTEM_POLICY_FIXED"; if(hasbit(pf,64))return "ANDROID_SYSTEM_FIXED"; if(hasbit(pf,2048))return "INSTALLER_POLICY_EXEMPT"; if(hasbit(pf,128))return "ANDROID_DEFAULT_GRANT"; if(hasbit(pf,1))return "USER_OR_RESTORE_SNAPSHOT"; return "ANDROID_PERMISSION_MANAGER" }
		BEGIN{ print "# permission policy v2 verify"; print "# columns: package permission type expect actual op mode pflags source_hint restore_route status" }
		NR==FNR { act[$1"\t"$2]=$3; op[$1"\t"$2]=$4; mode[$1"\t"$2]=$5; pf[$1"\t"$2]=$6; next }
		{ k=$1"\t"$2; a=(k in act?act[k]:"未讀到"); o=(k in op?op[k]:"?"); m=(k in mode?mode[k]:"?"); f=(k in pf?pf[k]:"0"); st=(ptype($2)=="DECLARATIVE_PERMISSION"?"DECLARATIVE_SKIP":(a==$3?"OK":"MISMATCH")); printf "%s\t%s\ttype=%s\texpect=%s\tactual=%s\top=%s\tmode=%s(%s)\tpflags=%s[%s]\tsource_hint=%s\trestore_route=%s\tstatus=%s\n", $1,$2,ptype($2),$3,a,o,m,modezh(m),f,flags(f),source($2,f),route($2,$3),st }
	' "$_actual" "$_expect" > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_permission_policy_v2_appops_report() {
	local _expect="$1" _actual="$2" _out _hist _src
	[ -n "${SPEED_DEBUG_RUN_DIR:-}" ] && [ -d "$SPEED_DEBUG_RUN_DIR" ] && [ -s "$_expect" ] && [ -s "$_actual" ] || return 0
	_out="$SPEED_DEBUG_RUN_DIR/appops_policy_v2_verify.log"
	_hist="$SPEED_DEBUG_RUN_DIR/appops_history_diff.log"
	_src="$SPEED_DEBUG_RUN_DIR/enforce_source_v2.log"
	awk -F'\t' '
		function modezh(m){ if(m=="0")return "允許"; if(m=="1")return "忽略/不允許"; if(m=="2")return "拒絕/錯誤"; if(m=="3")return "預設"; if(m=="4")return "僅前台"; if(m==""||m=="?")return "未知"; return m }
		function opname(op){ if(op=="0")return "粗略定位"; if(op=="1")return "精確定位"; if(op=="11")return "通知"; if(op=="24")return "懸浮窗"; if(op=="26")return "相機"; if(op=="27")return "麥克風"; if(op=="66")return "安裝未知應用"; if(op=="76")return "前台服務"; if(op=="81")return "讀取音訊"; if(op=="83")return "讀取影片"; if(op=="85")return "讀取圖片"; if(op=="92")return "管理所有檔案"; if(op=="107")return "精確鬧鐘"; if(op=="119")return "受限設定存取"; if(op=="123")return "選取相片/影片"; if(op=="133")return "全螢幕通知"; return "op_"op }
		function scope(op){ if(op=="0"||op=="1"||op=="26"||op=="27"||op=="81"||op=="83"||op=="85"||op=="123") return "runtime/uid-sensitive"; if(op=="24"||op=="66"||op=="76"||op=="92"||op=="107"||op=="119"||op=="133") return "package-special"; return "package" }
		function src(op){ if(scope(op)=="runtime/uid-sensitive") return "APP_OPS_SERVICE + PERMISSION_MANAGER"; if(op=="66"||op=="92"||op=="107"||op=="119") return "APP_OPS_SERVICE + SETTINGS_UI_POLICY"; if(op=="76") return "APP_OPS_SERVICE + FOREGROUND_SERVICE_POLICY"; return "APP_OPS_SERVICE" }
		BEGIN{ print "# appops policy v2 verify"; print "# package op name scope expect actual source_hint status" }
		NR==FNR { act[$1"\t"$2]=$3; next }
		{ k=$1"\t"$2; a=(k in act?act[k]:"未讀到"); st=(a==$3?"OK":(a=="未讀到"?"MISSING":"MISMATCH")); printf "%s\top=%s\tname=%s\tscope=%s\texpect=%s(%s)\tactual=%s(%s)\tsource_hint=%s\tstatus=%s\n", $1,$2,opname($2),scope($2),$3,modezh($3),a,modezh(a),src($2),st }
	' "$_actual" "$_expect" > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	awk -F'\t' '
		function modezh(m){ if(m=="0")return "允許"; if(m=="1")return "忽略/不允許"; if(m=="2")return "拒絕/錯誤"; if(m=="3")return "預設"; if(m=="4")return "僅前台"; if(m==""||m=="?")return "未知"; return m }
		BEGIN{ print "# appops history diff"; print "# transaction=backup_snapshot -> restore_actual；這不是系統全歷史，只是本次恢復交易差異。" }
		NR==FNR { act[$1"\t"$2]=$3; next }
		{ k=$1"\t"$2; a=(k in act?act[k]:"未讀到"); st=(a==$3?"unchanged_after_restore":"changed_or_missing_after_restore"); printf "%s\top=%s\tbackup_snapshot=%s(%s)\trestore_actual=%s(%s)\ttransition=%s->%s\tstatus=%s\n", $1,$2,$3,modezh($3),a,modezh(a),$3,a,st }
	' "$_actual" "$_expect" > "$_hist" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	awk -F'\t' '
		function source(op){ if(op=="66"||op=="92"||op=="107"||op=="119") return "system_settings_policy"; if(op=="76") return "foreground_service_policy"; if(op=="0"||op=="1"||op=="26"||op=="27"||op=="81"||op=="83"||op=="85"||op=="123") return "permission_manager+appops_uid_scope"; return "appops_service" }
		BEGIN{ print "# enforce source v2"; print "# source_hint 是根據 op 類型、scope 與 flags 的判斷，不代表系統提供了唯一 owner。" }
		NR==FNR { act[$1"\t"$2]=$3; next }
		{ k=$1"\t"$2; a=(k in act?act[k]:"未讀到"); printf "%s\top=%s\texpect=%s\tactual=%s\tsource_hint=%s\tconfidence=%s\n", $1,$2,$3,a,source($2),(a=="未讀到"?"low":"medium") }
	' "$_actual" "$_expect" > "$_src" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_notification_deep_verify_report() {
	# v24.20.14-7.56：通知 channel/group 深度欄位 verify 報告。
	# 只做診斷報告，不改既有 restore/verify 判定；缺失 channel/group 仍分級為 pending，不當硬錯。
	local _expect="$1" _actual="$2" _out
	[ -n "${SPEED_DEBUG_RUN_DIR:-}" ] && [ -d "$SPEED_DEBUG_RUN_DIR" ] && [ -s "$_expect" ] && [ -s "$_actual" ] || return 0
	_out="$SPEED_DEBUG_RUN_DIR/notification_channel_deep_verify.log"
	awk -F'\t' '
		function field_label(f){
			if(f=="importance") return "重要性";
			if(f=="sound") return "音效";
			if(f=="vibration") return "震動";
			if(f=="lights") return "燈號";
			if(f=="bypassDnd") return "略過勿擾";
			if(f=="lockscreenVisibility") return "鎖定畫面顯示";
			if(f=="showBadge") return "通知圓點";
			if(f=="allowBubbles" || f=="canBubble") return "泡泡通知";
			if(f=="importantConversation") return "重要對話";
			if(f=="demoted") return "降低對話優先級";
			if(f=="parentChannelId") return "父分類";
			if(f=="conversationId") return "對話ID";
			if(f=="blocked") return "群組封鎖";
			return f;
		}
		function baseof(k){
			n=split(k,p,":");
			if(n>=2 && (p[1]=="NOTIFY_CHANNEL" || p[1]=="NOTIFY_GROUP")) return p[1]":"p[2];
			return k;
		}
		function fieldof(k){
			n=split(k,p,":");
			if(n>=3) return p[3];
			return "";
		}
		function is_deep_field(f){
			return (f=="importance" || f=="sound" || f=="vibration" || f=="lights" || f=="bypassDnd" || f=="lockscreenVisibility" || f=="showBadge" || f=="allowBubbles" || f=="canBubble" || f=="importantConversation" || f=="demoted" || f=="parentChannelId" || f=="conversationId" || f=="blocked");
		}
		BEGIN {
			print "# notification channel/group deep verify";
			print "# 已存在 channel/group 才逐欄位比對；尚未建立者列 pending，不視為恢復錯誤。";
			print "# app-level NOTIFY_APP 仍由原本通知設定驗證判定。";
		}
		NR==FNR {
			ak=$1"\t"$2; aval[ak]=$3;
			if($2 ~ /^NOTIFY_CHANNEL:/ || $2 ~ /^NOTIFY_GROUP:/) abase[$1"\t"baseof($2)]=1;
			next;
		}
		{
			if($2 !~ /^NOTIFY_CHANNEL:/ && $2 !~ /^NOTIFY_GROUP:/) next;
			b=baseof($2); f=fieldof($2); k=$1"\t"$2; bk=$1"\t"b;
			if(!(bk in abase)) {
				if(!pend_seen[bk]++) { pending++; print "PENDING\t"$1"\t"b"\t尚未建立/未讀到"; }
				next;
			}
			if(!is_deep_field(f)) next;
			if(k in aval) {
				if(aval[k] == $3) { ok++; print "OK\t"$1"\t"b"\t"field_label(f)"\texpect="$3"\tactual="aval[k]; }
				else { mismatch++; print "MISMATCH\t"$1"\t"b"\t"field_label(f)"\texpect="$3"\tactual="aval[k]; }
			} else {
				mismatch++; print "MISMATCH\t"$1"\t"b"\t"field_label(f)"\texpect="$3"\tactual=未讀到";
			}
		}
		END { print "# summary ok="ok+0" mismatch="mismatch+0" pending="pending+0; }
	' "$_actual" "$_expect" > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_notify_filter_readonly_fields() {
	# 移除 NotificationChannel 唯讀/診斷欄位，避免 restore 時 IllegalArgumentException；verify 也不把它當可恢復項。
	local _f="$1" _tmp
	[ -s "$_f" ] || return 0
	_tmp="$TMPDIR/.notify_filter_${_f##*/}_$$"
	awk 'BEGIN{RS="]"; ORS=""}
	{
		gsub(/^[[:space:]\[]+/,""); gsub(/[[:space:]]+$/,"",$0);
		if($0=="") next;
		n=split($0,a,/ +/); if(n<3){ printf "[%s] ",$0; next }
		out=a[1]; kept=0;
		for(i=2;i+1<=n;i+=2){
			key=a[i]; val=a[i+1];
			if(key ~ /^NOTIFY_CHANNEL:.*:deleted$/) continue;
			out=out" "key" "val; kept=1;
		}
		if(kept) printf "[%s] ",out;
	}' "$_f" > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	cat "$_tmp" > "$_f" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	rm -f "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_notify_fast_skip_missing_channel_groups() {
	# v24.20.14-7.49：卸載後首次恢復時，app 尚未建立 NotificationChannel/Group。
	# 先讀目前已存在的分類/群組，restore 只送已存在項目；不存在項目留給 verify 分級摘要，不逐欄位打 dex。
	# 注意：此函式定義早於 alias 區，單獨 recover.sh 入口也只載入 tools.sh；因此這裡必須直呼 _dex，不能呼叫 get_Notifications alias。
	local _f="$1" _pkglist _actual _tmp _missing _summary _ch _gr
	[ -s "$_f" ] || return 0
	_pkglist="$TMPDIR/.notify_fastskip_pkgs_$$"
	_actual="$TMPDIR/.notify_fastskip_actual_$$"
	_tmp="$TMPDIR/.notify_fastskip_filtered_$$"
	_missing="$TMPDIR/.notify_fastskip_missing_$$"
	_summary="$TMPDIR/.notify_fastskip_summary_$$"
	: > "$_missing" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	awk 'BEGIN{RS="]"; ORS="\n"}
	{
		gsub(/^[[:space:]\[]+/,""); gsub(/[[:space:]]+$/,"",$0);
		if($0=="") next;
		n=split($0,a,/ +/); if(a[1] ~ /\./ && !seen[a[1]]++) print a[1];
	}' "$_f" > "$_pkglist" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [ ! -s "$_pkglist" ]; then
		rm -f "$_pkglist" "$_actual" "$_tmp" "$_missing" "$_summary" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 0
	fi
	_dex /system/bin com.xayah.dex.HiddenApiUtil getNotificationSettings "$USER_ID" $(cat "$_pkglist") 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} > "$_actual"
	awk -v actual="$_actual" -v miss="$_missing" 'BEGIN{
		FS=" "; ORS="";
		while ((getline line < actual) > 0) {
			n=split(line,a,/ +/);
			if(n < 2) continue;
			key=a[2];
			if(key ~ /^NOTIFY_CHANNEL:/ || key ~ /^NOTIFY_GROUP:/) {
				split(key,p,":");
				if(length(p[1]) && length(p[2])) present[a[1]"\t"p[1]":"p[2]]=1;
			}
		}
		close(actual);
		RS="]";
	}
	{
		gsub(/^[[:space:]\[]+/,""); gsub(/[[:space:]]+$/,"",$0);
		if($0=="") next;
		n=split($0,a,/ +/); if(n < 3) { printf "[%s] ",$0; next }
		pkg=a[1]; out=pkg; kept=0;
		for(i=2;i+1<=n;i+=2) {
			key=a[i]; val=a[i+1];
			if(key ~ /^NOTIFY_CHANNEL:/ || key ~ /^NOTIFY_GROUP:/) {
				split(key,p,":"); base=p[1]":"p[2];
				if(!(pkg"\t"base in present)) {
					if(!missed[pkg"\t"base]++) printf "%s\t%s\n", pkg, base >> miss;
					continue;
				}
			}
			out=out" "key" "val; kept=1;
		}
		if(kept) printf "[%s] ",out;
	}' "$_f" > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	cat "$_tmp" > "$_f" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [ -s "$_missing" ]; then
		awk -F'\t' '
			$2 ~ /^NOTIFY_CHANNEL:/ {ch[$1"\t"$2]=1; next}
			$2 ~ /^NOTIFY_GROUP:/ {gr[$1"\t"$2]=1; next}
			END {for(k in ch)c++; for(k in gr)g++; print c+0" "g+0}
		' "$_missing" > "$_summary" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		read -r _ch _gr < "$_summary"
		{
			printf '[%s] notification missing channel/group fast-skip: channel=%s group=%s\n' "$(date '+%H:%M:%S' 2>/dev/null)" "${_ch:-0}" "${_gr:-0}"
			cat "$_missing"
		} >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/notification_missing_fast_skip.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		{
			printf '[%s] 通知分類/群組尚未建立，恢復前快速略過：channel=%s group=%s\n' "$(date '+%H:%M:%S' 2>/dev/null)" "${_ch:-0}" "${_gr:-0}"
		} >> "${SPEED_DEBUG_CMD_LOG:-/dev/null}" 2>/dev/null
	fi
	rm -f "$_pkglist" "$_actual" "$_tmp" "$_missing" "$_summary" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_dex_translate_line() {
	local _line="$1" _ctx="$2" _pkg _tag _ev _key _val _msg _b _c _status _source _op _mode _perm
	[[ -n $_line ]] || return 0
	case $_line in
		*FAILED_SKIP*) _dex_translate_failed_skip "$_line"; return 0 ;;
		PERMISSION_STATE_BATCH_OK*) _dex_human_emit "dex" "權限批量還原完成：${_line#PERMISSION_STATE_BATCH_OK }"; return 0 ;;
		APP_STATE_BATCH_OK*) _dex_human_emit "dex" "權限/安裝來源/通知/電池批量還原完成：${_line#APP_STATE_BATCH_OK }"; return 0 ;;
		VERIFY_APP_STATE_BATCH_OK*) _dex_human_emit "dex" "安裝完整性/權限/AppOps/通知/電池批量驗證讀回完成：${_line#VERIFY_APP_STATE_BATCH_OK }"; return 0 ;;
		APP_OPS_RESET_OK*) _pkg="$(_dex_kv_get "$_line" package)"; _dex_human_emit "$_pkg" "AppOps package-scoped reset 完成"; return 0 ;;
		APP_OPS_RESET_FALLBACK_OK*) _pkg="$(_dex_kv_get "$_line" package)"; _dex_human_emit "$_pkg" "AppOps reset fallback 完成：已將本次 payload 內已知 op 重設為 default"; return 0 ;;
		APP_OPS_RESET_FALLBACK_SUMMARY*) _pkg="$(_dex_kv_get "$_line" package)"; _dex_human_emit "$_pkg" "AppOps reset fallback 摘要：ok=$(_dex_kv_get "$_line" ok) fail=$(_dex_kv_get "$_line" fail) total=$(_dex_kv_get "$_line" total)"; return 0 ;;
		APPOPS_SCOPE_DETAIL_OK*) _dex_human_emit "dex" "AppOps scope detail 批量讀取完成：${_line#APPOPS_SCOPE_DETAIL_OK }"; return 0 ;;
		APP_OP_RUNTIME_BACKED_SKIP*) _pkg="$(_dex_kv_get "$_line" package)"; _op="$(_dex_kv_get "$_line" op)"; _mode="$(_dex_kv_get "$_line" mode)"; _dex_human_emit "$_pkg" "略過 runtime-backed AppOps：op=${_op:-?} mode=${_mode:-?}，由 runtime permission/flags/uid mode 處理"; return 0 ;;
		ASK_MODE_RESTORE_OK*) _pkg="$(_dex_kv_get "$_line" package)"; _perm="$(_dex_kv_get "$_line" permission)"; _dex_human_emit "$_pkg" "每次詢問模式還原完成：${_perm:-未知}"; return 0 ;;
		MEDIA_MODE_RESTORE_OK*) _pkg="$(_dex_kv_get "$_line" package)"; _mode="$(_dex_kv_get "$_line" mode)"; _dex_human_emit "$_pkg" "媒體權限語意模式還原完成：${_mode:-未知}"; return 0 ;;
		LOCATION_MODE_RESTORE_OK*) _pkg="$(_dex_kv_get "$_line" package)"; _mode="$(_dex_kv_get "$_line" mode)"; _dex_human_emit "$_pkg" "定位權限語意模式還原完成：${_mode:-未知}"; return 0 ;;
		PERMISSION_FLAGS_RESTORE_OK*) _pkg="$(_dex_kv_get "$_line" package)"; _perm="$(_dex_kv_get "$_line" permission)"; _dex_human_emit "$_pkg" "權限 flags 還原完成：${_perm:-未知}"; return 0 ;;
		RUNTIME_APPOP_ALLOW_OK*|RUNTIME_APPOP_FIX_OK*|SEMANTIC_APPOP_ALLOW_OK*) _pkg="$(_dex_kv_get "$_line" package)"; _perm="$(_dex_kv_get "$_line" permission)"; _op="$(_dex_kv_get "$_line" op)"; _mode="$(_dex_kv_get "$_line" mode)"; _dex_human_emit "$_pkg" "runtime 權限 AppOps 修正完成：${_perm:-未知} op=${_op:-?} mode=${_mode:-?}"; return 0 ;;
		RUNTIME_APPOP_ALLOW_NO_OP*|RUNTIME_APPOP_FIX_NO_OP*|SEMANTIC_APPOP_ALLOW_NO_OP*) _pkg="$(_dex_kv_get "$_line" package)"; _perm="$(_dex_kv_get "$_line" permission)"; _dex_human_emit "$_pkg" "權限無對應 AppOps，略過修正：${_perm:-未知}"; return 0 ;;
		INSTALL_METHOD\ *)
			set -- $_line; _pkg="$2"; _ev="$3"
			case $_ev in
				dex_play_session) _msg="安裝方式：Play 完整來源安裝（慢速）" ;;
				dex_play_session_success) _msg="Play 完整來源安裝成功" ;;
				dex_play_session_failed) _msg="Play 完整來源安裝失敗" ;;
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
		INSTALL_COMPARE)
			_key="$3"; _b="$4"; _c="$5"; _status="$6"
			case $_status in MATCH|OK|same) _msg="一致" ;; *) _msg="不一致" ;; esac
			_dex_human_emit "$_pkg" "安裝診斷比對：$_key 備份=$_b 目前=$_c，結果=$_msg" ;;
		INSTALL_RISK)
			_dex_human_emit "$_pkg" "Play 恢復風險：$3，建議：$4" ;;
		INSTALLER)
			_dex_human_emit "$_pkg" "目前 installer=${3:-null}" ;;
		BATTERY:*)
			_key="${_tag#BATTERY:}"; _val="$5"
			[[ $_key = deviceidle_whitelist ]] && _val="$3"
			_dex_human_emit "$_pkg" "電池/背景設定：$_key=${_val:-${3:-unknown}}" ;;
		*)
			case $_ctx in
				SsaidUtil:get) if [[ $# -ge 2 ]]; then _dex_human_emit "$_pkg" "SSAID=${2}"; fi ;;
				SsaidUtil:set) if [[ $# -ge 1 ]]; then _dex_human_emit "$_pkg" "SSAID 設定輸出：${_line}"; fi ;;
				HiddenApiUtil:getRuntimePermissions) if [[ $# -ge 5 ]]; then _dex_human_emit "$_pkg" "權限狀態：$2=$3 op=$4 mode=$5"; fi ;;
				HiddenApiUtil:getNotificationSettings) if [[ $# -ge 3 ]]; then _dex_human_emit "$_pkg" "通知設定：$2=$3"; fi ;;
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

_dex_raw() {
	# 給 JSON / zip / 純文字 payload 使用：不翻譯、不過濾、不暫存，只保留原始 stdout。
	# stderr 先過濾 HUMAN，再收進 speed_debug，避免預期中文提示污染 stderr.log。
	local _dex_err="${TMPDIR:-/data/local/tmp}/.dex_stderr_${$}_$RANDOM" _dex_rc
	command app_process "$@" 2>"$_dex_err"
	_dex_rc=$?
	_dex_append_nonhuman_stderr "$_dex_err"
	rm -f "$_dex_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	return $_dex_rc
}

_dex() {
	[[ $_dex_debug = 1 ]] && {
		local _c
		for _c in "$@"; do case $_c in
			getRuntime*|getInstalled*|getPackage*|setDisplay*|getNotification*|getBattery*|restoreAppState*|verifyAppState*|appOpsResetBatch|fixRuntimeAppOpsAllow|getInstaller|getInstallSourceInfo|diagnosePlayRestore|compareInstallDiagnostics|installSessionBatch|precheckInstallApks|get|set) echo "$_c" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/dex_call.log"; break ;;
		esac; done
	}
	local _dex_out _dex_err _dex_rc _dex_ctx
	_dex_ctx="$(_dex_context_from_args "$@")"
	_dex_out="${TMPDIR:-/data/local/tmp}/.dex_stdout_${$}_$RANDOM"
	_dex_err="${TMPDIR:-/data/local/tmp}/.dex_stderr_${$}_$RANDOM"
	command app_process "$@" > "$_dex_out" 2>"$_dex_err"
	_dex_rc=$?
	_dex_append_nonhuman_stderr "$_dex_err"
	_dex_translate_file "$_dex_out" "$_dex_ctx"
	_dex_filter_human_stdout < "$_dex_out"
	rm -f "$_dex_out" "$_dex_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	return $_dex_rc
}

# 批量 dex 調用 wrapper：xargs 不能直接使用 alias / shell function，
# 所以批量恢復統一集中到這裡，避免 _flush_batch_permissions 內散落多段 xargs app_process。
# 用法: _dex_xargs <HiddenApiUtil方法> <輸入檔> [輸出檔]
_dex_xargs() {
	local _method="$1" _in="$2" _out="$3" _tmp _rc
	[[ -n $_method && -s $_in ]] || return 0
	_tmp="${TMPDIR:-/data/local/tmp}/.dex_xargs_${_method}_${$}_$RANDOM"
	local _xerr="${TMPDIR:-/data/local/tmp}/.dex_xargs_stderr_${_method}_${$}_$RANDOM"
	xargs app_process /system/bin com.xayah.dex.HiddenApiUtil "$_method" "$USER_ID" < "$_in" > "$_tmp" 2>"$_xerr"
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

# 單次 JVM + stdin 版 dex 批量呼叫。用於 appOpsResetBatch / restoreAppStateBatch / verifyAppStateBatch，避免 xargs 依 ARG_MAX 分割成多次 JVM。
_dex_stdin() {
	local _method="$1" _in="$2" _out="$3" _tmp _rc
	[[ -n $_method && -s $_in ]] || return 0
	_tmp="${TMPDIR:-/data/local/tmp}/.dex_stdin_${_method}_${$}_$RANDOM"
	local _xerr="${TMPDIR:-/data/local/tmp}/.dex_stdin_stderr_${_method}_${$}_$RANDOM"
	app_process /system/bin com.xayah.dex.HiddenApiUtil "$_method" "$USER_ID" --stdin < "$_in" > "$_tmp" 2>"$_xerr"
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
alias appinfo="_dex /system/bin com.xayah.dex.HiddenApiUtil getInstalledPackagesAsUser $USER_ID $@"
alias appinfo2="_dex /system/bin com.xayah.dex.HiddenApiUtil getPackageLabel $USER_ID $@"
alias appinfo3="_dex /system/bin com.xayah.dex.HiddenApiUtil getPackageArchiveInfo $@"
alias get_ssaid="_dex /system/bin com.xayah.dex.SsaidUtil get $USER_ID $@"
alias set_ssaid="_dex /system/bin com.xayah.dex.SsaidUtil set $USER_ID $@"
alias get_uid="_dex /system/bin com.xayah.dex.HiddenApiUtil getPackageUid $USER_ID $@"
alias get_Permissions="_dex /system/bin com.xayah.dex.HiddenApiUtil getRuntimePermissions $USER_ID $@"
alias Fix_Runtime_AppOps="_dex /system/bin com.xayah.dex.HiddenApiUtil fixRuntimeAppOpsAllow $USER_ID $@"
# DEX16_DIRECT_APPOPS_RESET_BATCH: AppOps reset 只走公開批量入口 appOpsResetBatch；不再保留單包公開入口，也不再把 reset 包塞進 restoreAppStateBatch 的 __RESET__ 區段。
alias get_Installer="_dex /system/bin com.xayah.dex.HiddenApiUtil getInstaller $USER_ID $@"
alias get_Install_Source_Info="_dex /system/bin com.xayah.dex.HiddenApiUtil getInstallSourceInfo $USER_ID $@"
alias get_Install_Diagnostics="_dex /system/bin com.xayah.dex.HiddenApiUtil diagnosePlayRestore $USER_ID $@"
alias Compare_Install_Diagnostics="_dex /system/bin com.xayah.dex.HiddenApiUtil compareInstallDiagnostics $USER_ID $@"
alias get_Notifications="_dex /system/bin com.xayah.dex.HiddenApiUtil getNotificationSettings $USER_ID $@"
alias get_Battery_Settings="_dex /system/bin com.xayah.dex.HiddenApiUtil getBatterySettings $USER_ID $@"
alias setDisplay="_dex /system/bin com.xayah.dex.HiddenApiUtil setDisplayPowerMode $@"

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
	[ -f "$_p" ] && { printf '%s
' "$_p"; return 0; }
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
	return 0
}

_speed_debug_dex_full_test
find_tools_path="$(find "$path_hierarchy"/* -maxdepth 1 -name "tools" -type d ! -path "$path_hierarchy/tools" | grep -v "/Backup_[^/]*/tools$")"
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
		command app_process /system/bin com.xayah.dex.NetworkUtil saveNetworks >"$_wifi_tmp" 2>"$_wifi_err" &
		_wifi_pid=$!
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
		if [[ -z $_wifi_rc ]]; then
			wait "$_wifi_pid" 2>/dev/null
			_wifi_rc=$?
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
			_dex /system/bin com.xayah.dex.NetworkUtil restoreNetworks "$1/wifi.json"
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
	echo "#!/system/bin/sh
if [ -f \"$MODDIR_Path/tools/tools.sh\" ]; then
	MODDIR=\"$MODDIR_Path1\"
	conf_path=\"$conf_path\"
	[ ! -f \"$conf_path\" ] && . \"$MODDIR_Path/tools/tools.sh\"
else
	echo \"$MODDIR_Path/tools/tools.sh遺失\"
fi
# 入口腳本自己的 log 目錄必須自行建立；不能引用 tools.sh 上一次 run 的 speed_debug 路徑。
_log_dir=\"\${0%/*}/log\"
mkdir -p \"\$_log_dir\" 2>/dev/null || _log_dir=\"/data/local/tmp\"
logfile=\"\$_log_dir/log_\$(date +%Y-%m-%d_%H-%M).txt\"
: > \"\$logfile\" 2>/dev/null || logfile=\"/dev/null\"
# 由入口腳本啟動時，trap 收尾訊息只寫 speed_debug，不刷終端，避免單獨恢復開頭出現 trap 訊息。
export SPEEDBACKUP_ENTRY_QUIET_TRAP=1
export SPEEDBACKUP_ENTRY_MODE="$1"
export SPEEDBACKUP_ENTRY_SCRIPT="\$0"
# 防止舊入口腳本 / 父 shell 殘留上一輪 speed_debug run_xxx 變數，導致單獨腳本誤寫已被 final 刪除的 main.log/stderr.log。
unset SPEED_DEBUG_RUN_DIR SPEED_DEBUG_MAIN_LOG SPEED_DEBUG_PENDING_ERR_LOG SPEED_DEBUG_CMD_LOG SPEED_DEBUG_INFO_LOG SPEED_DEBUG_DEX_HUMAN_LOG SPEED_DEBUG_ARCHIVE SPEED_DEBUG_PACKED SPEED_DEBUG_SNAPSHOT_DONE SPEED_DEBUG_RUN_DIR_REMOVED SPEED_DEBUG_ERR_LOG
set -o pipefail 2>/dev/null || true
. "$MODDIR_Path/tools/tools.sh" 2>&1 | tee "\$logfile"
_entry_rc=\$?
if [ "\$logfile" != "/dev/null" ] && [ -f "\$logfile" ]; then
	sed -i \"\$(printf 's/\033\\[[0-9;]*m//g')\" \"\$logfile\" 2>/dev/null || true
fi
exit "\$_entry_rc"" > "$2"
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
						exit
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
# 兩個來源都嘗試 (Download 有無關 zip 時不該擋住 QQ 的更新包)
_dl_zip="$(ls -t /storage/emulated/0/Download/*.zip 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | head -1)"
_qq_zip="$(ls -t /storage/emulated/0/Android/data/com.tencent.mobileqq/Tencent/QQfile_recv/*.zip 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | head -1)"
for _try_zip in "$_dl_zip" "$_qq_zip"; do
	[[ -z $_try_zip ]] && continue
	# 只有「含 backup_settings.conf 的更新包」才傳入; 普通 zip 略過不處理
	if unzip -l "$_try_zip" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -q "backup_settings\.conf$"; then
		echoRgb "偵測到更新包: ${_try_zip##*/}" "2"
		update_script "$_try_zip"
	fi
done
unset _dl_zip _qq_zip _try_zip
# APK 安裝統一走 installapk() 內部函數。
# Play 來源 app 可優先使用 Play UID + HiddenApiUtil installSessionBatch 建立真正 Play 安裝 session；
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
				    echo "$MODDIR"
				    exit
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
						wait
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
	[[ ! -d $Backup ]] && mkdir -p "$Backup"
	# 分區詳細：df 統計使用實際 Backup 路徑；_resolve_real_mount 只作 df fallback，不再拿 /data 拼假路徑。
	_df_target="$(_backup_df_target "$Backup")"
	_real_suffix="$(_backup_mount_display_suffix "$Backup" "$_df_target")"
	remote_setup
	# 一致性保護: remote_stream=1 但 remote_type 無效/空 → runtime 關閉流式。
	# 不反寫 conf；只有遠端預檢失敗才提示。
	if [[ $remote_stream = 1 && -z $remote_type ]]; then
		[[ -n $_remote_type_orig ]] && echoRgb "遠端不可用，已停用流式上傳，改為純本機備份" "2"
		remote_stream=0
	fi
	# 分區統計移到 remote_setup/一致性保護之後:
	# 連線失敗自動轉純本機備份時, 也能正確顯示本地資訊; 流式 (數據不落地) 才不顯示
	if [[ $remote_stream != 1 ]]; then
		echoRgb "${hx}備份資料夾所使用分區統計如下↓\n -$(_backup_partition_summary "$_df_target")\n -備份目錄輸出位置↓\n -$Backup${_real_suffix:+\n$_real_suffix}"
		echoRgb "$outshow" "2"
	fi
	# 快照備份前遠端大小 (結尾算差異, 對齊本地備份的整體資料夾差異統計)
	if [[ -n $remote_type ]]; then
		_RTOTAL_BEFORE="$(remote_dir_size "$(get_backup_dirname)" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		[[ -z $_RTOTAL_BEFORE ]] && _RTOTAL_BEFORE=0
		_speed_debug_log "REMOTE_TOTAL_BEFORE subdir=$(get_backup_dirname) bytes=$_RTOTAL_BEFORE"
	fi
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

# 預掃 pkg → installer (安裝來源) map
# 寫到 $TMPDIR/.pkg_installer 格式: pkg<TAB>installer
# pm list packages -i 輸出: package:<pkg>  installer=<installer>
prepare_pkg_installer_map() {
	: > "$TMPDIR/.pkg_installer"
	local _list _src_tmp _legacy_tmp
	if [[ -n $1 ]]; then
		_list="$*"
	else
		_list="$(echo "$txt" | awk '{print $2}' | grep -v '^$')"
	fi
	[[ -z $_list ]] && return

	# 優先用 getInstallSourceInfo：它同時讀 installer 與 installingPackageName。
	# 某些系統 getInstallerPackageName 可能回 null，但 InstallSourceInfo.installing 仍有 com.android.vending；
	# 這種情況若只用 getInstaller，備份會顯示安裝來源空，恢復時也無法 setInstaller。
	_src_tmp="$TMPDIR/.install_source_installer_$$"
	get_Install_Source_Info $_list 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '
		$2 == "INSTALL_DIAG" && $3 == "installer" {
			if ($4 != "" && $4 != "null") installer[$1] = $4
			next
		}
		$2 == "INSTALL_DIAG" && $3 == "installing" {
			if ($4 != "" && $4 != "null") installing[$1] = $4
			next
		}
		END {
			for (p in installer) print p "\t" installer[p]
			for (p in installing) if (!(p in installer)) print p "\t" installing[p]
		}
	' > "$_src_tmp"
	[[ -s $_src_tmp ]] && cat "$_src_tmp" > "$TMPDIR/.pkg_installer"
	rm -f "$_src_tmp"

	# fallback：舊 dex 或 getInstallSourceInfo 失敗時才回退 getInstaller。
	if [[ ! -s $TMPDIR/.pkg_installer ]]; then
		_legacy_tmp="$TMPDIR/.pkg_installer_legacy_$$"
		get_Installer $_list 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '$2=="INSTALLER" && $1!="" && $3!="" && $3!="null" {print $1"\t"$3}' > "$_legacy_tmp"
		[[ -s $_legacy_tmp ]] && cat "$_legacy_tmp" > "$TMPDIR/.pkg_installer"
		rm -f "$_legacy_tmp"
	fi
}

# 預掃 pkg → install_diagnostics map
# 寫到 $TMPDIR/.install_diag 格式: pkg<TAB>json
# 內容包含 installer/install source/update owner/version/signature/split/Play 環境與風險碼。
prepare_install_diagnostics_map() {
	: > "$TMPDIR/.install_diag"
	local _list
	if [[ -n $1 ]]; then
		_list="$1"
	else
		_list="$(echo "$txt" | awk '{print $2}' | grep -v '^$')"
	fi
	[[ -z $_list ]] && return
	get_Install_Diagnostics $_list 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | jq -nRc -r '
		[inputs | select(length > 0) | split(" ") | select(length >= 4)
		 | if .[1] == "INSTALL_DIAG" then
			{pkg: .[0], key: .[2], val: (.[3:] | join(" "))}
		   elif .[1] == "INSTALL_RISK" then
			{pkg: .[0], key: ("risk_" + .[2]), val: (.[3:] | join(" "))}
		   else empty end]
		| group_by(.pkg)[]
		| [.[0].pkg, (map({(.key): .val}) | add | tojson)]
		| @tsv
	' > "$TMPDIR/.install_diag"
}

# 預掃各 app 的電池/背景設定（dex v12: RUN_IN_BACKGROUND / RUN_ANY_IN_BACKGROUND / deviceidle whitelist）
# 寫到 $TMPDIR/.pkg_battery, 格式: pkg<TAB>json
# dex 輸出每行: packageName BATTERY:xxx value...
prepare_battery_settings_map() {
	local _battery_tmp="$TMPDIR/.pkg_battery"
	: > "$_battery_tmp"
	local _all_pkgs
	if [[ -n $1 ]]; then
		_all_pkgs="$1"
	else
		_all_pkgs="$(echo "$txt" | awk '{print $2}' | grep -v '^$' | paste -sd' ' -)"
	fi
	[[ -z $_all_pkgs ]] && return
	echoRgb "預掃電池/背景設定中..." "2"
	get_Battery_Settings $_all_pkgs 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '
		NF>=3 && $0 != "null" {
			pkg=$1; key=$2
			val=$3; for(i=4;i<=NF;i++) val=val" "$i
			gsub(/\\/, "\\\\", key); gsub(/"/, "\\\"", key)
			gsub(/\\/, "\\\\", val); gsub(/"/, "\\\"", val)
			if (seen[pkg]) entry[pkg]=entry[pkg]","
			entry[pkg]=entry[pkg] "\"" key "\":\"" val "\""
			seen[pkg]=1
		}
		END { for (p in entry) print p "\t{" entry[p] "}" }
	' >> "$_battery_tmp"
}

# 預掃各 app 的後台運行狀態 (appops RUN_ANY_IN_BACKGROUND)
# 預掃各 app 的後台運行狀態 (appops RUN_ANY_IN_BACKGROUND)
# 對應系統設定「允許在背景使用 / 無限制 / 最佳化」
# 用法: prepare_battery_whitelist [單一包名]  — 不傳則掃 $txt 全部
# 寫到 $TMPDIR/.battery_wl 格式: pkg<TAB>mode (mode = allow/ignore/deny/default)
# 只記錄「有明確設定」的 (RUN_ANY_IN_BACKGROUND: xxx), 系統預設(Default mode)不記錄
prepare_battery_whitelist() {
	: > "$TMPDIR/.battery_wl"
	# dex v12 已經批量讀到 RUN_ANY_IN_BACKGROUND 時，直接從 .pkg_battery 轉出舊 battery_opt，避免逐 app appops get 變慢
	if [[ -s "$TMPDIR/.pkg_battery" ]]; then
		jq -Rr '
			split("	") as $x |
			select(($x|length) >= 2) |
			($x[1] | fromjson? // {}) as $j |
			($j["BATTERY:RUN_ANY_IN_BACKGROUND"] // "" | split(" ") | last) as $m |
			select($m != null and $m != "") |
			"\($x[0])	\($m)"
		' "$TMPDIR/.pkg_battery" > "$TMPDIR/.battery_wl" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		[[ -s "$TMPDIR/.battery_wl" ]] && return
	fi
	local _list
	if [[ -n $1 ]]; then
		_list="$1"
	else
		_list="$(echo "$txt" | awk '{print $2}' | grep -v '^$')"
	fi
	local _total _i=0
	_total="$(echo "$_list" | grep -vc '^$')"
	echo "$_list" | while read -r _pkg; do
		[[ -z $_pkg ]] && continue
		let _i++
		printf '\r -預掃後台運行 %d/%d %s' "$_i" "$_total" "$(progress_bar $((_i * 100 / _total)))" >&2
		# appops 導向 </dev/null 避免吃掉迴圈 stdin
		_ops="$(appops get "$_pkg" RUN_ANY_IN_BACKGROUND </dev/null 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		# 兼容兩種輸出格式:
		#   舊/部分裝置: "RUN_ANY_IN_BACKGROUND: allow"
		#   新/部分裝置: "Default mode: allow"
		_mode="$(echo "$_ops" | sed -n -e 's/^RUN_ANY_IN_BACKGROUND: \([a-z]*\).*/\1/p' -e 's/^Default mode: \([a-z]*\).*/\1/p' | head -1)"
		[[ -n $_mode ]] && printf '%s\t%s\n' "$_pkg" "$_mode" >> "$TMPDIR/.battery_wl"
	done
	echo >&2
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
	local _total _i=0 _running=0 _par=8
	_total="$(echo "$_list" | grep -vc '^$')"
	# 用 here-string 餵 while, 避免管道把迴圈丟進子 shell (子 shell 內背景任務的變數作用域問題)
	local _pkg _typ _dp
	while read -r _pkg; do
		[[ -z $_pkg ]] && continue
		let _i++
		printf '\r -預掃數據大小 %d/%d %s' "$_i" "$_total" "$(progress_bar $((_i * 100 / _total)))" >&2
		for _typ in user user_de data obb; do
			case $_typ in
				user)    _dp="$path2/$_pkg" ;;
				user_de) _dp="$path3/$_pkg" ;;
				data)    _dp="$path/data/$_pkg" ;;
				obb)     _dp="$path/obb/$_pkg" ;;
			esac
			[[ ! -d $_dp ]] && continue
			# 背景並行算大小, 各寫獨立檔 (無共享寫入, 安全); 背景內再確認 workdir 存在防競態
			{ [[ -d $_workdir ]] && printf '%s\t%s\t%s\n' "$_pkg" "$_typ" "$(find "$_dp" -type f -printf '%s\n' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '{s+=$1}END{print s+0}')" > "$_workdir/${_pkg}.${_typ}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; } &
			_running=$((_running+1))
			[[ $_running -ge $_par ]] && { wait; _running=0; }
		done
	done <<EOF
$_list
EOF
	wait
	echo >&2
	cat "$_workdir"/* 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} > "$_map"
	rm -rf "$_workdir"
}

# 遠端模式: 並發預掃所有 app 的遠端 app_details.json 到本地快取
# 主迴圈 apk/data 增量比對直接讀快取, 免每 app 多次遠端往返
prepare_remote_json_map() {
	local _cache="$TMPDIR/.remote_json"
	rm -rf "$_cache"; mkdir -p "$_cache"
	[[ -z $remote_type ]] && return
	local _list
	_list="$(echo "$txt" | awk '{sub(/[[:space:]]+[^[:space:]]+$/,""); print}' | grep -v '^$')"
	[[ -z $_list ]] && { touch "$_cache/.done"; return; }
	local _subdir
	_subdir="${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}"
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
		if [[ -n $remote_user ]]; then _auth="-A $_SMB_AUTHFILE"; else _auth="-N"; fi
		SMB_OPTS="-t 300 -s /dev/null${REMOTE_PORT:+ -p $REMOTE_PORT} -m SMB3"
		local _base="$SMB_REM_PATH/$_subdir"; _base="${_base#/}"; _base="${_base//\//\\}"
		while read -r _app; do
			[[ -z $_app ]] && continue
			let _i++ _n++
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
		# v24.20.14-7.66-15：部分 WebDAV 服務在 _stream_download 預掃小 JSON 時會回 curl rc=18，
		# 但同一路徑用 remote_download_single_file/WEBDAV_SINGLE_GET 可成功。
		# 因此這裡直接走已驗證較穩的單檔 GET，避免遠端已有 app_details 卻 seed 失敗後不必要重備份。
		local _running=0 _app
		while read -r _app; do
			[[ -z $_app ]] && continue
			let _i++
			printf '\r -預掃遠端清單 %d/%d' "$_i" "$_total" >&2
			(
				local _tmp_json="$_cache/$_app.json.part" _final_json="$_cache/$_app.json" _ok=0 _try=1
				rm -f "$_tmp_json" "$_final_json" 2>/dev/null
				# v24.20.14-7.66-16: WebDAV 小 JSON GET 偶發 curl rc=18；seed app_details 最多試 2 次。
				while [[ $_try -le 2 ]]; do
					if remote_download_single_file "$_app/app_details.json" "$_tmp_json"; then
						_ok=1
						break
					fi
					_speed_debug_log "WEBDAV_REMOTE_APPDETAILS_RETRY app=$_app try=$_try"
					rm -f "$_tmp_json" 2>/dev/null
					let _try++
					[[ $_try -le 2 ]] && sleep 1
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
			let _running++
			if [[ $_running -ge 8 ]]; then wait; _running=0; fi
		done < "$TMPDIR/.json_fetch"
		wait
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
	[[ -z $remote_type ]] && return
	echoRgb "預掃遠端檔案列表 (單次連線)..." "3"
	remote_list_files "${_BACKUP_DIRNAME_CACHED:-$(get_backup_dirname)}" > "$TMPDIR/.remote_files" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
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

# 預掃所有 app 的 runtime permissions (取代 Backup_Permissions 內每個 app 各 fork dex)
# 寫到 $TMPDIR/.pkg_perms, 格式: pkg<TAB>json (json = getRuntimePermissions 輸出轉成的 object)
# Backup_Permissions 直接 awk 查, 不再呼叫 get_Permissions
prepare_permissions_map() {
	local _perms_tmp="$TMPDIR/.pkg_perms"
	: > "$_perms_tmp"
	# 一次取得所有 app 的包名 (空白分隔)。可傳入單一/多個包名，供單獨備份共用同一套解析邏輯。
	local _all_pkgs
	if [[ -n $1 ]]; then
		_all_pkgs="$*"
	else
		_all_pkgs="$(echo "$txt" | awk '{print $2}' | grep -v '^$' | paste -sd' ' -)"
	fi
	[[ -z $_all_pkgs ]] && return
	echoRgb "預掃應用權限中..." "2"
	# 一次 get_Permissions 讀回所有 app (dex 只啟動 1 次, 取代逐 app N 次)
	# 輸出每行: 包名 權限名 true/false op mode → awk 按包名分組直接生成 json
	get_Permissions $_all_pkgs 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '
		NF>=3 && $0 != "null" {
			pkg=$1; perm=$2
			if (perm == "EXTRA_OP" && NF >= 4) {
				# 舊/未知 AppOps 輸出格式: pkg EXTRA_OP op mode
				# JSON key 必須唯一, 否則多個 EXTRA_OP 會互相覆蓋
				perm="EXTRA_OP_" $3
				val=$3 " " $4
			} else {
				# 一般格式: pkg permissionOrAppOp true/false op mode
				val=$3; for(i=4;i<=NF;i++) val=val" "$i
			}
			if (seen[pkg]) entry[pkg]=entry[pkg]","
			# json 跳脫: 包名/權限名/值皆為安全字元(字母數字點底線冒號空白), 直接包引號
			entry[pkg]=entry[pkg] "\"" perm "\":\"" val "\""
			seen[pkg]=1
		}
		END { for (p in entry) print p "\t{" entry[p] "}" }
	' >> "$_perms_tmp"
}

# 預掃所有 app 的通知設定（NotificationManager / NotificationChannel）
# 寫到 $TMPDIR/.pkg_notify, 格式: pkg<TAB>json
# dex 輸出每行: packageName NOTIFY_xxx value
prepare_notifications_map() {
	local _notify_tmp="$TMPDIR/.pkg_notify"
	: > "$_notify_tmp"
	local _all_pkgs
	if [[ -n $1 ]]; then
		_all_pkgs="$*"
	else
		_all_pkgs="$(echo "$txt" | awk '{print $2}' | grep -v '^$' | paste -sd' ' -)"
	fi
	[[ -z $_all_pkgs ]] && return
	echoRgb "預掃應用通知設定中..." "2"
	get_Notifications $_all_pkgs 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '
		NF>=3 && $0 != "null" {
			pkg=$1; key=$2
			val=$3; for(i=4;i<=NF;i++) val=val" "$i
			# JSON escape: backslash first, then double quote
			gsub(/\\/, "\\\\", key); gsub(/"/, "\\\"", key)
			gsub(/\\/, "\\\\", val); gsub(/"/, "\\\"", val)
			if (seen[pkg]) entry[pkg]=entry[pkg]","
			entry[pkg]=entry[pkg] "\"" key "\":\"" val "\""
			seen[pkg]=1
		}
		END { for (p in entry) print p "\t{" entry[p] "}" }
	' >> "$_notify_tmp"
}
# 用法: app_details_read <檔案路徑>
# 設定全域變數: APK_VER / SSAID_OLD / PERMS_OLD / NOTIFY_OLD / BATTERY_SETTINGS_OLD / INSTALL_DIAG_OLD / PKG_NAME / BACKUP_TIME
#              SIZE_user / SIZE_data / SIZE_obb / SIZE_user_de / SIZE_media (各類型大小)
#              INSTALLER_OLD / BATTERY_OLD
app_details_read() {
	local file="$1"
	APK_VER=""; SSAID_OLD=""; PERMS_OLD=""; NOTIFY_OLD=""; BATTERY_SETTINGS_OLD=""; INSTALL_DIAG_OLD=""; PKG_NAME=""; BACKUP_TIME=""
	SIZE_user=""; SIZE_data=""; SIZE_obb=""; SIZE_user_de=""; SIZE_media=""
	INSTALLER_OLD=""; BATTERY_OLD=""
	[[ ! -f $file ]] && return
	# jq 把各值各印一行到暫存檔
	# 用 try ... catch "" 確保每個 expression 不論成敗都輸出一行 (即使空字串)
	# 避免某行 error 導致整個輸出位移
	local tmpf="$TMPDIR/.app_details_read_$$"
	jq -r '
		(try ([.[] | objects | select(.apk_version != null).apk_version] | .[0]) catch "" // ""),
		(try ([.[] | objects | select(.Ssaid != null).Ssaid] | .[0]) catch "" // ""),
		(try ([.[] | objects | select(.permissions != null).permissions | tojson] | .[0]) catch "" // ""),
		(try ([.[] | objects | select(.notification_settings != null).notification_settings | tojson] | .[0]) catch "" // ""),
		(try ([.[] | objects | select(.battery_settings != null).battery_settings | tojson] | .[0]) catch "" // ""),
		(try ([.[] | objects | select(.install_diagnostics != null).install_diagnostics | tojson] | .[0]) catch "" // ""),
		(try ([.[] | objects | select(.PackageName != null).PackageName] | .[0]) catch "" // ""),
		(try (.["Backup time"].date) catch "" // ""),
		(try (.user.Size) catch "" // ""),
		(try (.data.Size) catch "" // ""),
		(try (.obb.Size) catch "" // ""),
		(try (.user_de.Size) catch "" // ""),
		(try (.media.Size) catch "" // ""),
		(try ([.[] | objects | select(.installer != null).installer] | .[0]) catch "" // ""),
		(try ([.[] | objects | select(.battery_opt != null).battery_opt] | .[0]) catch "" // "")
	' "$file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} > "$tmpf"
	# 用 FD 逐行讀 (mksh 相容)
	exec 3< "$tmpf"
	read -r APK_VER <&3
	read -r SSAID_OLD <&3
	read -r PERMS_OLD <&3
	read -r NOTIFY_OLD <&3
	read -r BATTERY_SETTINGS_OLD <&3
	read -r INSTALL_DIAG_OLD <&3
	read -r PKG_NAME <&3
	read -r BACKUP_TIME <&3
	read -r SIZE_user <&3
	read -r SIZE_data <&3
	read -r SIZE_obb <&3
	read -r SIZE_user_de <&3
	read -r SIZE_media <&3
	read -r INSTALLER_OLD <&3
	read -r BATTERY_OLD <&3
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
		(try .[$e].Size catch "" // ""),
		(try ([.[] | objects | select(.keystore != null).keystore] | .[0]) catch "" // ""),
		(try .[$e].path catch "" // "")
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
# 取得指定 app 的後台運行 PID (用於跳過正在運行的 app)
Process_Information() {
	dumpsys activity processes 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk -v key="$1" -v user="$user" '
	function getUserFromUid(uid){return int(uid/100000)}
	# 進程塊起點: ProcessRecord{hash PID:name/uid} → 抓 pid (兼容無獨立 pid= 行的新格式)
	/ProcessRecord\{/ {tmp=$0; sub(/^.*ProcessRecord\{[^ ]+ /,"",tmp); sub(/:.*/,"",tmp); pid=tmp; uid=""; pkg=""; next}
	/^ *user #[0-9]+ uid=/ {if($0 ~ /ISOLATED uid=[0-9]+/){uid="";next} tmp=$0; sub(/^.*uid=/,"",tmp); sub(/ .*/,"",tmp); uid=tmp}
	/packageList=\{/ {tmp=$0; sub(/^.*packageList=\{/,"",tmp); sub(/\}.*/,"",tmp); pkg=tmp; if(pkg!="" && uid!="" && pid!=""){if((key=="" || pkg==key) && (user=="" || getUserFromUid(uid)==user)) print pid}}
	'
}
# 強制終止指定 app (am force-stop + pkill 雙保險)
kill_app() {
	process_Information="$(Process_Information "$name2")"
	if [[ $name2 != bin.mt.plus && $name2 != com.termux && $name2 != bin.mt.plus.canary ]]; then
		if [[ $process_Information != "" ]]; then
			am force-stop --user "$user" "$name2" &>/dev/null
			# force-stop 後 PID 可能已消失，這是正常競態；不寫 stderr.log。
			printf '%s\n' "$process_Information" | while read -r _kp; do
				case $_kp in ''|*[!0-9]*) continue ;; esac
				kill -0 "$_kp" 2>/dev/null && kill -9 "$_kp" 2>/dev/null
			done
			pkill -9 -f "$name2$|$name2[:/_]" 2>/dev/null
			#killall -9 "$name2" &>/dev/null
			#am kill "$name2" &>/dev/null
			echoRgb "殺死$name1進程"
		fi
	fi
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
	if [[ -z $_v ]]; then
		_v="$(get_Install_Diagnostics "$_pkg" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} 			| awk '$2=="INSTALL_DIAG" && $3=="versionCode" {print $4; exit}' 			| tr -d ' \t\r\n')"
	fi
	echo "$_v"
}

# 備份核心函數 (Backup_apk / Backup_data / ssaid / 權限)
# ======================================================
# 備份 app 的 apk 檔 (含 split apk, 用 tar/zstd 打包)
Backup_apk() {
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
				remote_apk_ver=$(jq -r --arg name "$name1" 'try .[$name].apk_version catch "" // ""' "$remote_app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})
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
						# 否則本地 app_details 只是新建的 {}，後續 Backup_metadata_once 會誤判 permissions/notification/installer/battery 全部缺失，
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
		if [[ $nobackup = false ]]; then
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
		else
			let osj++
			rm -rf "$Backup_folder"
		fi
	fi
	[[ $name2 = bin.mt.plus && ! -f $Backup/$name1.apk ]] && cp -r "$apk_path" "$Backup/$name1.apk"
}
# 備份 app 的 SSAID (應用識別碼)
# 用 classes.dex 透過 app_process 讀 /data/system/users/$user/settings_ssaid.xml
# 沒備份 SSAID 恢復後遊戲帳號會被當新裝置
Backup_ssaid() {
	# Ssaid (舊值) 已由 app_details_read 載入到 SSAID_OLD
	Ssaid="$SSAID_OLD"
	ssaid="$(printf "%s\n" "$ssaid_info" | awk -v pkg="$name2" '$1 == pkg {print $2}')"
	[[ $ssaid != null && $ssaid != "" ]] && echoRgb "SSAID:$ssaid"
	if [[ $ssaid != null && $ssaid != "" ]]; then
		if [[ $ssaid != $Ssaid ]] || ! app_details_has_key "$app_details" "$name1" "Ssaid"; then
			if [[ $ssaid != $Ssaid ]]; then
				echoRgb "備份ssaid"
				echoRgb "$Ssaid>$ssaid"
				# 用暫存檔取代字串拼接
				echo "$name1 \"$name2\"" >> "$TMPDIR/.ssaid_apks"
			else
				echoRgb "補寫ssaid" "2"
			fi
			jq_inplace "$app_details" --arg entry "$name1" --arg new_value "$ssaid" '.[$entry].Ssaid |= $new_value'
			echo_log "備份ssaid"
			[[ $result = 0 ]] && _mark_changed
		fi
	fi
	[[ $ssaid = null ]] && ssaid=
}
# 備份 app 的 runtime permissions (運行時權限)
# 恢復時可一鍵還原所有授權, 不用再手動點
Backup_Permissions() {
	# 從預掃 map 讀取當前系統權限
	eval "Get_Permissions=\${_pp_${name2//[!a-zA-Z0-9]/_}}"
	# 上次備份的舊值 (由 app_details_read 載入到 PERMS_OLD)
	local perms_old="$PERMS_OLD"
	[[ $_perm_diag = 1 ]] && echoRgb "[診斷] $name1 PERMS_OLD長度=${#perms_old} app_details=$app_details 種子存在=$([[ -s $TMPDIR/.remote_json/$name1.json ]] && echo Y || echo N)" "0" >&2
	if [[ -n $Get_Permissions ]] && [[ $Get_Permissions = *true* || $Get_Permissions = *false* ]]; then
		local perms_missing=0
		app_details_has_key "$app_details" "$name1" "permissions" || perms_missing=1
		if [[ $perms_old = "" || $perms_missing = 1 ]]; then
			[[ $perms_missing = 1 && -n $perms_old ]] && echoRgb "補寫權限" "2" || echoRgb "備份權限"
			jq_inplace "$app_details" --arg packageName "$name1" --argjson permissions "$Get_Permissions" '.[$packageName].permissions |= $permissions'
			echo_log "備份權限"
			[[ $result = 0 ]] && _mark_changed
		else
			if [[ $perms_old = *true* || $perms_old = *false* ]]; then
				if [[ $perms_old != $Get_Permissions ]]; then
					# v24.4 起 getRuntimePermissions 會在 value 尾端追加 pflags=...
					# 舊 app_details 沒有 pflags 時，整個 JSON 字串會不同，但終端若只顯示 true/op/mode 會看起來「一模一樣」。
					# 因此這裡把差異分成：
					#   VISIBLE = granted/op/mode 真正變更，顯示為「權限變更」
					#   PFLAGS  = 只有 permission flags 補全/變更，終端只顯示摘要，細節寫 dex_human.log
					local _perm_diff="$TMPDIR/.perm_diff_$$"
					jq -n --argjson old "$perms_old" --argjson new "$Get_Permissions" \
						'
						def parts: tostring | split(" ");
						def flag: parts[0];
						def opmode:
						  parts as $v |
						  if ($v|length) >= 3 then " op=" + $v[1] + " mode=" + $v[2]
						  elif ($v|length) >= 2 then " op=" + $v[0] + " mode=" + $v[1]
						  else "" end;
						def pflags:
						  (parts | map(select(startswith("pflags="))) | .[0] // "pflags=0");
						def visible_key:
						  parts as $v |
						  if ($v|length) >= 3 then ($v[0] + " " + $v[1] + " " + $v[2])
						  elif ($v|length) >= 2 then ($v[0] + " " + $v[1])
						  elif ($v|length) >= 1 then $v[0]
						  else "" end;
						def shown:
						  flag + opmode + (if pflags != "pflags=0" then " " + pflags else "" end);
						$new
						| to_entries[]
						| select(.key as $k | $old[$k] == null or $old[$k] != .value)
						| .key as $k
						| if ($old[$k] == null) then
							"VISIBLE|\($k)|新增→" + (.value|shown)
						  elif (($old[$k]|visible_key) != (.value|visible_key)) then
							"VISIBLE|\($k)|" + ($old[$k]|flag) + "→" + (.value|flag) + "  " + ($old[$k]|opmode) + " →" + (.value|opmode) +
							(if (($old[$k]|pflags) != (.value|pflags)) then "  " + ($old[$k]|pflags) + " → " + (.value|pflags) else "" end)
						  elif (($old[$k]|pflags) != (.value|pflags)) then
							"PFLAGS|\($k)|" + ($old[$k]|pflags) + " → " + (.value|pflags)
						  else empty end
						' \
						-r > "$_perm_diff" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					local _visible_cnt _pflags_cnt
					_visible_cnt="$(grep -c '^VISIBLE|' "$_perm_diff" 2>/dev/null)"
					_pflags_cnt="$(grep -c '^PFLAGS|' "$_perm_diff" 2>/dev/null)"
					[[ -z $_visible_cnt ]] && _visible_cnt=0
					[[ -z $_pflags_cnt ]] && _pflags_cnt=0
					if [[ $_visible_cnt -gt 0 ]]; then
						echoRgb "權限變更"
						grep '^VISIBLE|' "$_perm_diff" 2>/dev/null | while IFS='|' read -r _kind _pname _pchange; do
							echoRgb "$(_perm_cn "$_pname"): $_pchange"
						done
						if [[ $_pflags_cnt -gt 0 ]]; then
							echoRgb "另有 $_pflags_cnt 項權限旗標更新，細節已寫入 debug log" "2"
						fi
					elif [[ $_pflags_cnt -gt 0 ]]; then
						echoRgb "權限旗標補全/更新 $_pflags_cnt 項（權限開關與 AppOps 未變）" "2"
					fi
					if [[ $_pflags_cnt -gt 0 && -n ${SPEED_DEBUG_DEX_HUMAN_LOG:-} ]]; then
						grep '^PFLAGS|' "$_perm_diff" 2>/dev/null | while IFS='|' read -r _kind _pname _pchange; do
							echo "[$(date '+%H:%M:%S' 2>/dev/null)] ${name2} 權限旗標更新：${_pname} ${_pchange}" >> "$SPEED_DEBUG_DEX_HUMAN_LOG" 2>/dev/null
						done
					fi
					rm -f "$_perm_diff" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					jq_inplace "$app_details" --arg packageName "$name1" --argjson permissions "$Get_Permissions" '.[$packageName] |= . + {permissions: $permissions}'
					echo_log "備份權限"
					[[ $result = 0 ]] && _mark_changed
				fi
			fi
		fi
	else
		[[ $Get_Permissions != "" ]] && echoRgb "備份權限失敗" "0"
	fi
}
# 備份通知設定（NotificationManager / NotificationChannel）
# 恢復時可還原通知總開關、通知圓點、對話/泡泡、channel 重要性等可寫欄位
Backup_Notifications() {
	# 從預掃 map 讀取當前系統通知設定
	eval "Get_Notifications=\${_pn_${name2//[!a-zA-Z0-9]/_}}"
	local notify_old="$NOTIFY_OLD"
	[[ -z $Get_Notifications ]] && return
	local notify_missing=0
	app_details_has_key "$app_details" "$name1" "notification_settings" || notify_missing=1
	if [[ $notify_old = "" || $notify_missing = 1 ]]; then
		[[ $notify_missing = 1 && -n $notify_old ]] && echoRgb "補寫通知設定" "2" || echoRgb "備份通知設定"
		jq_inplace "$app_details" --arg packageName "$name1" --argjson notification_settings "$Get_Notifications" '.[$packageName].notification_settings |= $notification_settings'
		echo_log "備份通知設定"
		[[ $result = 0 ]] && _mark_changed
	else
		if [[ $notify_old != "$Get_Notifications" ]]; then
			echoRgb "通知設定變更"
			jq -n --argjson old "$notify_old" --argjson new "$Get_Notifications" '
				$new
				| to_entries
				| map(select(.key as $k | $old[$k] == null or $old[$k] != .value)
				  | "\(.key)|\(if ($old[.key] == null) then "新增→" + .value else $old[.key] + "→" + .value end)")
				| .[]
			' -r 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while IFS='|' read -r _nkey _nchange; do
				echoRgb "$(_notify_cn "$_nkey"): $_nchange"
			done
			jq_inplace "$app_details" --arg packageName "$name1" --argjson notification_settings "$Get_Notifications" '.[$packageName] |= . + {notification_settings: $notification_settings}'
			echo_log "備份通知設定"
			[[ $result = 0 ]] && _mark_changed
		fi
	fi
}

# 通知設定 key → 中文顯示
_notify_cn() {
	case $1 in
		NOTIFY_APP:enabled) echo "通知總開關" ;;
		NOTIFY_APP:importance) echo "通知重要性" ;;
		NOTIFY_APP:showBadge) echo "允許使用通知圓點" ;;
		NOTIFY_APP:bubblePreference|NOTIFY_APP:allowBubbles) echo "對話區/泡泡通知" ;;
		NOTIFY_CHANNEL:*:showBadge) echo "允許使用通知圓點" ;;
		NOTIFY_CHANNEL:*:importance) echo "通知分類重要性" ;;
		NOTIFY_CHANNEL:*:allowBubbles|NOTIFY_CHANNEL:*:canBubble) echo "對話區/泡泡通知" ;;
		NOTIFY_CHANNEL:*:importantConversation) echo "重要對話" ;;
		NOTIFY_CHANNEL:*:demoted) echo "降低對話優先級" ;;
		NOTIFY_CHANNEL:*:vibration) echo "通知分類震動" ;;
		NOTIFY_CHANNEL:*:lights) echo "通知分類燈號" ;;
		NOTIFY_CHANNEL:*:deleted) echo "通知分類已刪除" ;;
		NOTIFY_GROUP:*:blocked) echo "通知分類群組封鎖" ;;
		*) echo "$1" ;;
	esac

}

# 電池/背景設定 key → 中文顯示
_battery_cn() {
	case $1 in
		BATTERY:RUN_IN_BACKGROUND) echo "背景執行" ;;
		BATTERY:RUN_ANY_IN_BACKGROUND) echo "任意背景執行" ;;
		BATTERY:deviceidle_whitelist) echo "Doze白名單" ;;
		*) echo "$1" ;;
	esac
}

# 備份額外 metadata: installer (安裝來源) 與 battery_opt/battery_settings (電池/背景設定)
# 從預掃 map 讀取, 不額外 fork; 變更時寫入 app_details.json
Backup_extra() {
	# installer name
	local installer
	eval "installer=\${_pi_${name2//[!a-zA-Z0-9]/_}}"
	local installer_missing=0
	app_details_has_key "$app_details" "$name1" "installer" || installer_missing=1
	if [[ -n $installer ]] && [[ $installer != $INSTALLER_OLD || $installer_missing = 1 ]]; then
		jq_inplace "$app_details" --arg entry "$name1" --arg v "$installer" '.[$entry].installer |= $v'
		echo_log "備份installer"
		[[ $result = 0 && $installer != $INSTALLER_OLD ]] && echoRgb "安裝來源:$installer" "2"
		[[ $result = 0 && $installer = $INSTALLER_OLD && $installer_missing = 1 ]] && echoRgb "補寫安裝來源:$installer" "2"
		[[ $result = 0 ]] && _mark_changed
	fi
	# install_diagnostics: Play 跳轉風險診斷，僅提示/比對用，不直接恢復
	local install_diag
	eval "install_diag=\${_id_${name2//[!a-zA-Z0-9]/_}}"
	local install_diag_missing=0
	app_details_has_key "$app_details" "$name1" "install_diagnostics" || install_diag_missing=1
	if [[ -n $install_diag ]] && [[ $install_diag != $INSTALL_DIAG_OLD || $install_diag_missing = 1 ]]; then
		jq_inplace "$app_details" --arg entry "$name1" --argjson v "$install_diag" '.[$entry].install_diagnostics |= $v'
		echo_log "備份install_diagnostics"
		[[ $result = 0 && $install_diag != $INSTALL_DIAG_OLD ]] && echoRgb "安裝診斷已記錄" "2"
		[[ $result = 0 && $install_diag = $INSTALL_DIAG_OLD && $install_diag_missing = 1 ]] && echoRgb "補寫安裝診斷" "2"
		[[ $result = 0 ]] && _mark_changed
	fi

	# battery_settings: dex v12 批量後台/電池設定（RUN_IN_BACKGROUND / RUN_ANY_IN_BACKGROUND / deviceidle whitelist）
	local batt_settings
	eval "batt_settings=\${_bs_${name2//[!a-zA-Z0-9]/_}}"
	local batt_settings_missing=0
	app_details_has_key "$app_details" "$name1" "battery_settings" || batt_settings_missing=1
	if [[ -n $batt_settings ]] && [[ $batt_settings != "$BATTERY_SETTINGS_OLD" || $batt_settings_missing = 1 ]]; then
		if [[ $BATTERY_SETTINGS_OLD != "" && $batt_settings != "$BATTERY_SETTINGS_OLD" ]]; then
			echoRgb "電池/背景設定變更" "2"
			jq -n --argjson old "$BATTERY_SETTINGS_OLD" --argjson new "$batt_settings" '
				$new
				| to_entries
				| map(select(.key as $k | $old[$k] == null or $old[$k] != .value)
				  | "\(.key)|\(if ($old[.key] == null) then "新增→" + .value else $old[.key] + "→" + .value end)")
				| .[]
			' -r 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | while IFS='|' read -r _bkey _bchange; do
				echoRgb "$(_battery_cn "$_bkey"): $_bchange"
			done
		else
			[[ $batt_settings_missing = 1 && -n $BATTERY_SETTINGS_OLD ]] && echoRgb "補寫電池/背景設定" "2" || echoRgb "備份電池/背景設定" "2"
		fi
		jq_inplace "$app_details" --arg entry "$name1" --argjson v "$batt_settings" '.[$entry].battery_settings |= $v'
		echo_log "備份battery_settings"
		[[ $result = 0 ]] && _mark_changed
	fi
	# battery_opt: 舊版相容（RUN_ANY_IN_BACKGROUND 單一 mode）
	local batt
	eval "batt=\${_bw_${name2//[!a-zA-Z0-9]/_}}"
	local batt_missing=0
	app_details_has_key "$app_details" "$name1" "battery_opt" || batt_missing=1
	if [[ -n $batt ]] && [[ $batt != $BATTERY_OLD || $batt_missing = 1 ]]; then
		jq_inplace "$app_details" --arg entry "$name1" --arg v "$batt" '.[$entry].battery_opt |= $v'
		echo_log "備份battery_opt"
		[[ $result = 0 && $batt != $BATTERY_OLD ]] && echoRgb "後台運行設定:$batt" "2"
		[[ $result = 0 && $batt = $BATTERY_OLD && $batt_missing = 1 ]] && echoRgb "補寫後台運行設定:$batt" "2"
		[[ $result = 0 ]] && _mark_changed
	fi
}

# 權限政策語意引擎 v2：把 raw permissions/AppOps 轉成可解釋 schema。
# 這不是恢復主路線；只是把「granted/op/mode/pflags」補上 policy_type / restore_route / enforcer_hint / history_diff。
Backup_PermissionPolicyV2() {
	# v24.20.14-7.66-194：主 app_details.json 不再保存完整 policy per-permission 物件。
	# 原因：完整語意層可由 permissions / AppOps 原始資料重新推導；寫入 JSON 會讓單包 app_details 膨脹數倍。
	# 現在 JSON 僅保留 compact summary + derived marker；完整分類/來源/差異仍輸出到 speed_debug：
	#   permission_policy_v2_verify.log / appops_policy_v2_verify.log / enforce_source_v2.log / appops_history_diff.log
	local _entry="$name1" _pkg="$name2" _before _after
	[[ -s $app_details && -n $_entry && -n $_pkg ]] || return 0
	app_details_has_key "$app_details" "$_entry" "permissions" || return 0
	_before="$(jq -c --arg e "$_entry" 'try (.[$e].permission_policy_v2 // null) catch null' "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	jq_inplace "$app_details" --arg entry "$_entry" --arg pkg "$_pkg" --arg engine "v24.20.14-7.66-194-json-compact-fast-menu" '
		def parts($v): ($v|tostring|split(" "));
		def pflags($v): ((parts($v) | map(select(startswith("pflags="))) | .[0] // "pflags=0") | sub("^pflags="; ""));
		def n($x): ($x|tonumber? // 0);
		def special_perm($k):
			($k=="android.permission.SYSTEM_ALERT_WINDOW" or $k=="android.permission.WRITE_SETTINGS" or $k=="android.permission.SCHEDULE_EXACT_ALARM" or $k=="android.permission.REQUEST_INSTALL_PACKAGES" or $k=="android.permission.MANAGE_EXTERNAL_STORAGE");
		(.[$entry].permissions // {}) as $perms |
		.[$entry].permission_policy_v2 = {
			schema: "speedbackup.permission_policy.v2",
			engine: $engine,
			package: $pkg,
			storage: "compact_json_full_debug_only",
			derived_from: ["permissions", "notification_settings", "battery_settings", "install_diagnostics", "post_restore_verify_logs"],
			note: "此欄僅保留 compact 語意摘要，完整 per-permission policy 由 tools.sh 在恢復/驗證時即時計算並寫入 speed_debug；原始可恢復資料仍以 permissions / notification_settings / battery_settings / install_diagnostics 為準。",
			policy_summary: {
				total: ($perms | length),
				runtime_or_manifest: ($perms | to_entries | map(select((.key|startswith("android.permission.")) and ((.key|startswith("android.permission.FOREGROUND_SERVICE"))|not))) | length),
				declarative_permissions: ($perms | to_entries | map(select(.key|startswith("android.permission.FOREGROUND_SERVICE"))) | length),
				special_appops: ($perms | to_entries | map(select((.key|startswith("android:")) or special_perm(.key) or (.key|startswith("EXTRA_OP_")))) | length),
				with_pflags: ($perms | to_entries | map(select(n(pflags(.value)) != 0)) | length)
			}
		}
	' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 0
	_after="$(jq -c --arg e "$_entry" 'try (.[$e].permission_policy_v2 // null) catch null' "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	if [[ $_before != "$_after" ]]; then
		echoRgb "補寫權限政策語意v2摘要" "2"
		echo_log "備份權限政策語意v2摘要"
		[[ $result = 0 ]] && _mark_changed
	fi
}

# 每個 app 的 metadata 固定備份一次。
# 目的：APK-only / Backup_user_data=0 / user 目錄不存在時，也能寫入 permissions、notification、battery、installer、install_diagnostics、SSAID。
# 既有 user data 流程也呼叫此函數，靠 per-package guard 避免重複輸出。
Backup_metadata_once() {
	local _md_vn="_md_${name2//[!a-zA-Z0-9]/_}" _md_done
	eval "_md_done=\${$_md_vn:-0}"
	[[ $_md_done = 1 ]] && return 0
	[[ -f $app_details ]] || return 0
	Backup_ssaid
	Backup_Permissions
	Backup_Notifications
	Backup_extra
	Backup_PermissionPolicyV2
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
		[[ -f $app_details ]] && Size="$(jq -r --arg entry "$1" 'try .[$entry].Size catch "" // ""' "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
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
		[[ $1 != thanox ]] && local _comp_override=tar
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
		user|data|obb|user_de|media) _remote_lookup_name="$name1" ;;
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
				remote_size=$(jq -r --arg entry "$1" 'try .[$entry].Size catch "" // ""' "$remote_app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})
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
						user|data|obb|user_de|media)
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
	_v="$(jq -r 'try ([.[] | objects | select(.installer != null).installer] | .[0]) catch "" // ""' "$_json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	case $_v in null|NULL) _v="" ;; esac
	if [[ -z $_v ]]; then
		_v="$(jq -r 'try ([.[] | objects | select(.install_diagnostics != null).install_diagnostics | (.installer // .installing // "")] | .[0]) catch "" // "" | select(. != "null")' "$_json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
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
		_uid="$(CLASSPATH="$tools_path/classes.dex" app_process /system/bin com.xayah.dex.HiddenApiUtil getPackageUid "$USER_ID" "$_pkg" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '/^[0-9]+$/ {print; exit}')"
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
		_uid="$(CLASSPATH="$tools_path/classes.dex" app_process /system/bin com.xayah.dex.HiddenApiUtil getPackageUid "$USER_ID" com.android.vending 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk '/^[0-9]+$/ {print; exit}')"
	fi
	echo "$_uid"
}

_restore_has_play_store() {
	pm path --user "$user" com.android.vending >/dev/null 2>&1 && return 0
	pm list packages --user "$user" com.android.vending 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | grep -q '^package:com.android.vending$'
}

_restore_play_work_root() {
	# 使用集中二進制目錄下的專用子目錄，避免寫入或污染 Google Play 私有資料目錄。
	# /data/backup_tools 是目前所有二進制集中位置；子目錄改由 Play UID 持有，讓 uidexec 後的 Play 進程可讀 dex/APK。
	echo "$filepath/.speedbackup_play_session/u$user"
}

_restore_prepare_play_dex() {
	local _play_uid="$1" _root _art_dir _dex_dst
	[[ -n $_play_uid && -f $tools_path/classes.dex ]] || return 1
	_root="$(_restore_play_work_root)"
	_art_dir="$_root/art"
	_dex_dst="$_art_dir/classes.dex"
	mkdir -p "$_art_dir/tmp" "$_art_dir/dalvik-cache" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	chown -R "$_play_uid:$_play_uid" "$_root" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	chmod 700 "$_root" "$_art_dir" "$_art_dir/tmp" "$_art_dir/dalvik-cache" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	cp -f "$tools_path/classes.dex" "$_dex_dst" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
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

_restore_prepare_play_apks_fast_tmpdir() {
	local _play_uid="$1" _pkg="$2" _src_dir="$3" _root _work
	[[ ${restore_play_install_fast_tmpdir_apk:-1} = 1 ]] || return 1
	_restore_bool_enabled "${restore_play_install_force_copy_apk:-0}" && return 1
	[[ -n $_play_uid && -n $_pkg && -d $_src_dir ]] || return 1
	case "$_src_dir" in
	"$TMPDIR/.speedbackup_apk_stage"/*) ;;
	*) _speed_debug_log "Play APK fast path 拒絕非專用 APK stage: $_src_dir"; return 1 ;;
	esac
	if ! ls "$_src_dir"/*.apk >/dev/null 2>&1; then
		return 1
	fi
	_root="$(_restore_apk_stage_root)"
	_work="$_src_dir"
	# APK 不是 ART 要載入的 dex；這裡讓 Play UID / pm fallback 都能依已知路徑讀取，省掉二次複製。
	chown -R "$_play_uid:$_play_uid" "$_work" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	chmod 711 "$_root" "$_work" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	chmod 444 "$_work"/*.apk 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	restorecon -R "$_root" 2>>${SPEED_DEBUG_CMD_LOG:-/dev/null}
	_restore_log_install_stage "$_pkg" "READY" "mode=tmpdir_fast dir=$_work apkCount=$(_restore_count_stage_apks "$_work") bytes=$(_restore_sum_stage_apk_bytes "$_work")"
	echo "$_work"
}

_restore_prepare_play_apks_copy() {
	local _play_uid="$1" _pkg="$2" _src_dir="$3" _root _install_root _work _a
	[[ -n $_play_uid && -n $_pkg && -d $_src_dir ]] || return 1
	_root="$(_restore_play_work_root)"
	_install_root="$_root/install"
	_work="$_install_root/$_pkg"
	rm -rf "$_work" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	mkdir -p "$_work" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	chown -R "$_play_uid:$_play_uid" "$_root" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	chmod 700 "$_root" "$_install_root" "$_work" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	for _a in "$_src_dir"/*.apk; do
		[[ -f $_a ]] || continue
		[[ ${_a##*/} = nmsl.apk ]] && continue
		[[ -f $_work/${_a##*/} ]] && continue
		cp -f "$_a" "$_work/${_a##*/}" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} || return 1
	done
	if ! ls "$_work"/*.apk >/dev/null 2>&1; then
		rm -rf "$_work" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 1
	fi
	chown -R "$_play_uid:$_play_uid" "$_install_root" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	chmod 700 "$_install_root" "$_work" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	chmod 400 "$_work"/*.apk 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	restorecon -R "$_root" 2>>${SPEED_DEBUG_CMD_LOG:-/dev/null}
	_restore_log_install_stage "$_pkg" "READY" "mode=copy_fallback dir=$_work apkCount=$(_restore_count_stage_apks "$_work") bytes=$(_restore_sum_stage_apk_bytes "$_work")"
	echo "$_work"
}

_restore_prepare_play_apks() {
	local _play_uid="$1" _pkg="$2" _src_dir="$3" _work
	[[ -n $_src_dir ]] || _src_dir="$TMPDIR"
	if _work="$(_restore_prepare_play_apks_fast_tmpdir "$_play_uid" "$_pkg" "$_src_dir")"; then
		_restore_log_install_method "$_pkg" "dex_play_session_apk_source" "mode=tmpdir_fast dir=$_work"
		echo "$_work"
		return 0
	fi
	_work="$(_restore_prepare_play_apks_copy "$_play_uid" "$_pkg" "$_src_dir")" || return 1
	_restore_log_install_method "$_pkg" "dex_play_session_apk_source" "mode=copy_fallback dir=$_work"
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
	echo "$_pkg Play來源驗證未完全通過 installer=${_installer:-null} installing=${_installing:-null} initiating=${_initiating:-null} source=${_source:-null}" >> "$TMPDIR/.play_restore_hints"
	return 0
}

_restore_verify_play_install_source() {
	local _pkg="$1" _diag _installer _installing _initiating _source
	[[ ${restore_play_install_verify_source:-1} = 1 ]] || return 0
	[[ -n $_pkg ]] || return 1
	_diag="$TMPDIR/.play_install_source_${_pkg//[!a-zA-Z0-9]/_}"
	local _diag_err
	_diag_err="${TMPDIR:-/data/local/tmp}/.play_install_source_stderr_${_pkg//[!a-zA-Z0-9]/_}_$$"
	CLASSPATH="$tools_path/classes.dex" app_process /system/bin com.xayah.dex.HiddenApiUtil getInstallSourceInfo "$USER_ID" "$_pkg" 2>"$_diag_err" | _dex_filter_human_stdout > "$_diag"
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
	echo "$_pkg Play來源驗證未完全通過 installer=${_installer:-null} installing=${_installing:-null} initiating=${_initiating:-null} source=${_source:-null}" >> "$TMPDIR/.play_restore_hints"
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

_restore_run_play_precheck_once() {
	local _pkg="$1" _apk_work="$2" _out="$3" _err _rc _t0
	[[ -n $_pkg && -n $_apk_work && -d $_apk_work ]] || return 1
	_err="${TMPDIR:-/data/local/tmp}/.play_install_precheck_stderr_${_pkg//[!a-zA-Z0-9]/_}_$$"
	rm -f "$_out" "$_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_t0="$(_restore_now_ms)"
	CLASSPATH="$tools_path/classes.dex" app_process /system/bin com.xayah.dex.HiddenApiUtil precheckInstallApks "$_pkg" "$_apk_work" 2>"$_err" | _dex_filter_human_stdout > "$_out"
	_rc=$?
	_restore_log_install_timing "$_pkg" "play_precheck" "$_t0"
	_dex_append_nonhuman_stderr "$_err"
	rm -f "$_err" 2>/dev/null
	_dex_translate_file "$_out" "HiddenApiUtil:precheckInstallApks"
	_restore_save_play_session_raw_log "$_pkg" "$_out"
	if [[ $_rc != 0 ]]; then
		_restore_log_install_method "$_pkg" "dex_play_precheck_failed" "rc=$_rc"
		_restore_print_play_session_output "$_out"
		return $_rc
	fi
	_restore_log_install_method "$_pkg" "dex_play_precheck_ok" "rc=0"
	return 0
}

_restore_run_play_session_once() {
	local _pkg="$1" _play_uid="$2" _art_dir="$3" _dex_dst="$4" _apk_work="$5" _session_opts="$6" _out="$7" _sess_err _rc _t0
	_sess_err="${TMPDIR:-/data/local/tmp}/.play_install_session_stderr_${_pkg//[!a-zA-Z0-9]/_}_$$"
	rm -f "$_out" "$_sess_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_t0="$(_restore_now_ms)"
	# !play/STORE 路線使用 dex installSessionBatch，即使目前每次只餵一個 package，
	# 也能共用 Java 端批量子系統與目錄展開邏輯，避免 installSessionBatch 變成死路徑。
	# shellcheck disable=SC2086
	uidexec "$_play_uid" "$_play_uid" "$_art_dir" "$_dex_dst" \
		/system/bin/app_process /system/bin com.xayah.dex.HiddenApiUtil installSessionBatch "$USER_ID" $_session_opts --pkg "$_pkg" "$_apk_work" 2>"$_sess_err" | _dex_filter_human_stdout > "$_out"
	_rc=$?
	_restore_log_install_timing "$_pkg" "session_batch" "$_t0"
	_dex_append_nonhuman_stderr "$_sess_err"
	rm -f "$_sess_err" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_dex_translate_file "$_out" "HiddenApiUtil:installSessionBatch"
	_restore_save_play_session_raw_log "$_pkg" "$_out"
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
			echo_log "split Apk安裝"
		else
			echo_log "Apk安裝"
		fi
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
	local _pkg="$1" _apk_src="$2" _play_uid _dex_dst _apk_work _out _rc _art_dir _session_opts _used_fast=0 _t_prepare
	[[ -n $_pkg ]] || return 1
	_restore_has_play_store || { echoRgb "未找到 Google Play 商店，跳過 Play UID 安裝流程" "2"; return 1; }
	_play_uid="$(_restore_play_uid)"
	case $_play_uid in ""|*[!0-9]*) echoRgb "無法取得 Google Play UID，跳過 Play UID 安裝流程" "0"; return 1 ;; esac
	_t_prepare="$(_restore_now_ms)"
	_dex_dst="$(_restore_prepare_play_dex "$_play_uid")" || { echoRgb "準備 Play 私有 dex 失敗，跳過 Play UID 安裝流程" "0"; _restore_cleanup_play_session "$_pkg"; return 1; }
	_apk_work="$(_restore_prepare_play_apks "$_play_uid" "$_pkg" "$_apk_src")" || { echoRgb "準備 Play 可讀 APK 失敗，跳過 Play UID 安裝流程" "0"; _restore_cleanup_play_session "$_pkg"; return 1; }
	_restore_log_install_timing "$_pkg" "prepare" "$_t_prepare"
	case "$_apk_work" in "$TMPDIR/.speedbackup_apk_stage"/*) _used_fast=1 ;; esac
	_art_dir="$(_restore_play_work_root)/art"
	_out="$TMPDIR/.play_install_session_${_pkg//[!a-zA-Z0-9]/_}"
	_restore_log_install_method "$_pkg" "dex_play_session" "installer=com.android.vending uid=$_play_uid uidexec=uidexec"
	echoRgb "使用 Google Play 來源安裝 APK..." "3"
	_session_opts="$(_restore_play_install_options)"
	_restore_log_install_method "$_pkg" "dex_play_session_options" "flags=${restore_play_install_extra_flags:-default} downgrade=${restore_play_install_allow_downgrade:-0} test=${restore_play_install_allow_test:-1} source=${restore_play_install_package_source:-store} logMode=${restore_play_install_log_mode:-summary} humanLog=${restore_play_install_human_log:-0} conservative=1 fastSourceVerify=1 apkFastTmpdir=${restore_play_install_fast_tmpdir_apk:-1} forceCopy=${restore_play_install_force_copy_apk:-0}"
	# !play 慢速 STORE 路線先做 dex APK 預檢；失敗時不建立 PackageInstaller session，直接回退原生 pm。
	if ! _restore_run_play_precheck_once "$_pkg" "$_apk_work" "${TMPDIR}/.play_install_precheck_${_pkg//[!a-zA-Z0-9]/_}"; then
		echoRgb "Play UID installSessionBatch 預檢失敗" "0"
		_restore_cleanup_play_session "$_pkg"
		return 1
	fi
	_restore_run_play_session_once "$_pkg" "$_play_uid" "$_art_dir" "$_dex_dst" "$_apk_work" "$_session_opts" "$_out"
	_rc=$?
	# TMPDIR fast path 若被 ROM/SELinux 拒讀，先退回舊的 copy_fallback 工作區再重試一次 Play session，不直接掉 pm。
	if [[ $_rc != 0 && $_used_fast = 1 ]]; then
		_restore_log_install_method "$_pkg" "dex_play_session_retry_copy" "reason=tmpdir_fast_failed"
		_apk_work="$(_restore_prepare_play_apks_copy "$_play_uid" "$_pkg" "$_apk_src")"
		if [[ -n $_apk_work ]]; then
			_restore_run_play_session_once "$_pkg" "$_play_uid" "$_art_dir" "$_dex_dst" "$_apk_work" "$_session_opts" "$_out"
			_rc=$?
		fi
	fi
	if [[ $_rc = 0 ]] && grep -q "$_pkg INSTALL_SESSION packageFound" "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; then
		echoRgb "Play UID installSessionBatch 安裝成功" "1"
		_restore_log_install_method "$_pkg" "dex_play_session_success" "installer=com.android.vending"
		_restore_verify_play_install_source_from_file "$_pkg" "$_out" || _restore_verify_play_install_source "$_pkg"
		_restore_cleanup_play_session "$_pkg"
		rm -f "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 0
	fi
	echoRgb "Play UID installSessionBatch 安裝失敗" "0"
	_restore_log_install_method "$_pkg" "dex_play_session_failed" "installer=com.android.vending"
	_restore_cleanup_play_session "$_pkg"
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
	local _apk="$1" _installer="$2" _iarg _bypass=""
	[[ -f $_apk ]] || return 1
	_iarg="$(_pm_installer_arg "$_installer")"
	[[ $sdk -gt 33 ]] && _bypass="--bypass-low-target-sdk-block"
	# shellcheck disable=SC2086
	pm install -r $_bypass --user "$user" -t $_iarg "$_apk" >/dev/null
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
			echoRgb "!play 標記：使用 Play 完整來源安裝（三欄 Play + STORE，較慢）" "3"
			_restore_log_install_method "$name2" "play_session_requested_by_appList" "marker=!play installerBackup=${_installer_raw:-null} validatedInstaller=${_installer:-null} fallback=pm packageSource=STORE"
			if _restore_install_with_play_session "$name2" "$_apk_stage"; then
				_used_play_session=1
				result=0
				Set_back_0
			else
				echoRgb "Play 完整來源安裝失敗，回退原生 pm" "3"
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
			ChineseName="$(jq -r 'try (([.[] | objects | select(.PackageName != null)] | length) as $n | if $n > 0 then (to_entries[] | select(.value.PackageName != null).key) else (to_entries[] | select(.key != null).key) end) catch "" // ""' "$Folder/app_details.json" | head -n 1)"
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
						app=($DUMPAPK $DUMPAPK)
						PackageName="${app[1]}"
						ChineseName="${app[2]}"
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
restore_permissions () {
	echoRgb "加入權限/通知/電池恢復佇列"
	local _restore_perm_autoflush=0
	# v24.20.14-7.66-184：restore_permissions 只支援批量資料路線。
	# 單獨恢復 1 個 app 也會自動開一個臨時 batch，立刻 flush；不再提示或依賴已移除的單項公開入口。
	if [[ ${_batch_perm_mode:-0} != 1 ]]; then
		_restore_perm_autoflush=1
		_batch_perm_mode=1
		for _rp_batch_file in 			"$TMPDIR/.batch_grant" "$TMPDIR/.batch_revoke" "$TMPDIR/.batch_ops" "$TMPDIR/.batch_opsreset" 			"$TMPDIR/.batch_media_access" "$TMPDIR/.batch_location_access" "$TMPDIR/.batch_pflags" "$TMPDIR/.batch_ask_access" 			"$TMPDIR/.batch_notify" "$TMPDIR/.batch_notify_verify" "$TMPDIR/.batch_battery" "$TMPDIR/.batch_install_compare"; do
			: > "$_rp_batch_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		done
		unset _rp_batch_file
		_speed_debug_log "RESTORE_PERMISSIONS_AUTO_BATCH_ON package=${name2:-}"
	fi
	# v24.20.14-1 conservative sparse reset：AppOps reset 不再每個 app 無條件送。
	# 但 media/location/ask/pflags 也會影響權限語意，不能只看 Set_Ops_permissions。
	# 純 runtime / notify / battery 不送 opsreset，避免 restoreAppStateBatch 做無效工作。
	# 一次 jq 抓全部需要的欄位 (runtime true/false + AppOps mode + installer + battery + Ssaid)
	# AppOps/android:xxx 統一寫入批量 __OPS__；android.permission.* runtime 權限只走 __GRANT__/__REVOKE__。
	# 重要：不要把 runtime 權限內附帶的 op/mode 再還原到 AppOps，避免 grant=true 後被 mode=ignored 蓋掉。
	# 取代原本多個 jq fork; 批量恢復時每個 app 省下數次 jq, 累積可觀
	local tmpf="$TMPDIR/.perm_$$"
	jq -r '
		def special_perm(k):
			# 這些是 android.permission.* 形式，但實際 UI/狀態由 AppOps 或特殊系統設定控制；
			# 不可丟進 grant/revoke，必須以備份值內的 op/mode 還原。
			(k == "android.permission.SYSTEM_ALERT_WINDOW") or
			(k == "android.permission.FOREGROUND_SERVICE") or
			(k == "android.permission.WRITE_SETTINGS") or
			(k == "android.permission.REQUEST_INSTALL_PACKAGES") or
			(k == "android.permission.PACKAGE_USAGE_STATS") or
			(k == "android.permission.GET_USAGE_STATS") or
			(k == "android.permission.SCHEDULE_EXACT_ALARM") or
			(k == "android.permission.MANAGE_EXTERNAL_STORAGE") or
			(k == "android.permission.USE_FULL_SCREEN_INTENT") or
			(k == "android.permission.ACCESS_NOTIFICATION_POLICY");
		def non_runtime_manifest_perm(k):
			special_perm(k) or
			(k == "android.permission.FOREGROUND_SERVICE") or
			(k == "android.permission.BATTERY_STATS");
		def pfnum(v):
			(try ((v | tostring | split(" ") | map(select(startswith("pflags="))) | .[0] // "pflags=0") | sub("^pflags="; "") | tonumber) catch 0);
		def hasbit(n; b): (((n / b) | floor) % 2) == 1;
		def ask_perm(k; v):
			((k == "android.permission.CAMERA") or (k == "android.permission.RECORD_AUDIO") or (k == "android.permission.ACCESS_FINE_LOCATION") or (k == "android.permission.ACCESS_COARSE_LOCATION"))
			and ((v | tostring | startswith("true")) | not)
			and (hasbit(pfnum(v); 65536) or hasbit(pfnum(v); 131072) or hasbit(pfnum(v); 16384));
		(try (to_entries[] | select(.value.permissions != null) | .value.permissions | to_entries | map(select((.value | startswith("true")) and ((.key | startswith("android:")) | not) and (non_runtime_manifest_perm(.key) | not) and ((ask_perm(.key; .value)) | not)) | .key) | join(" ")) catch "" // ""),
		(try (to_entries[] | select(.value.permissions != null) | .value.permissions | to_entries | map(select((.value | startswith("false")) and ((.key | startswith("android:")) | not) and (non_runtime_manifest_perm(.key) | not) and ((ask_perm(.key; .value)) | not)) | .key) | join(" ")) catch "" // ""),
		(try (.[] | select(.permissions != null).permissions | to_entries | map(
			# 純 AppOps 類 key 走批量 __OPS__。
			# 另外 SYSTEM_ALERT_WINDOW / WRITE_SETTINGS / REQUEST_INSTALL_PACKAGES / SCHEDULE_EXACT_ALARM
			# 這類 android.permission.* 不是可 grant/revoke 的 runtime 權限，
			# 但備份值內的 op/mode 才是系統 UI 真正狀態，必須還原。
			# 其他 android.permission.* runtime 權限仍禁止丟進 __OPS__，避免 mode=ignored 覆蓋 grant。
			select((.key | startswith("android:")) or (.key | startswith("EXTRA_OP_")) or special_perm(.key)) |
			(.value | split(" ")) as $v |
			if ((.key | startswith("android:")) or special_perm(.key)) and (($v | length) >= 3 and $v[1] != "-1") then
				"\($v[1]) \($v[2])"
			elif (.key | startswith("EXTRA_OP_")) and (($v | length) >= 2) then
				"\($v[0]) \($v[1])"
			else
				empty
			end
		) | join(" ")) catch "" // ""),
		(try (.[] | select(.notification_settings != null).notification_settings | to_entries | map(select(.key != "NOTIFY_APP:importance") | "\(.key) \(.value)") | join(" ")) catch "" // ""),
		(try (.[] | select(.battery_settings != null).battery_settings | to_entries | map(
			(.value | split(" ")) as $v |
			if (.key == "BATTERY:deviceidle_whitelist") then
				"\(.key) \(.value)"
			elif (($v | length) >= 2) then
				"\(.key) \($v[1])"
			elif (($v | length) >= 1) then
				"\(.key) \($v[0])"
			else
				empty
			end
		) | join(" ")) catch "" // ""),
		(try (([.[] | select(.permissions != null).permissions] | .[0]) as $p |
			def b(k): (($p[k] // "") | tostring | startswith("true"));
			# v24.20.14-7.45 media permission semantic split:
			# __MEDIA__ 只用於 Android 14+「選取相片/影片」語意修正。
			# READ_MEDIA_AUDIO 是獨立 runtime/AppOps 權限，不能因「相片/影片 full」被 __MEDIA__ full 重新 grant。
			# full/denied 交給 __GRANT__/__REVOKE__ 逐項處理，避免把音訊權限混入視覺媒體語意。
			if $p == null then ""
			elif b("android.permission.READ_MEDIA_VISUAL_USER_SELECTED") and ((b("android.permission.READ_MEDIA_IMAGES") or b("android.permission.READ_MEDIA_VIDEO")) | not) then "selected"
			else "" end) catch "" // ""),
		(try (([.[] | select(.permissions != null).permissions] | .[0]) as $p |
			def b(k): (($p[k] // "") | tostring | startswith("true"));
			def ask(k): ($p[k] != null and ask_perm(k; ($p[k] | tostring)));
			if $p == null then ""
			elif ask("android.permission.ACCESS_FINE_LOCATION") or ask("android.permission.ACCESS_COARSE_LOCATION") then "ask_every_time"
			elif b("android.permission.ACCESS_BACKGROUND_LOCATION") then "background"
			elif b("android.permission.ACCESS_FINE_LOCATION") then "precise"
			elif b("android.permission.ACCESS_COARSE_LOCATION") then "approximate"
			elif ($p | has("android.permission.ACCESS_FINE_LOCATION") or has("android.permission.ACCESS_COARSE_LOCATION") or has("android.permission.ACCESS_BACKGROUND_LOCATION")) then "denied"
			else "" end) catch "" // ""),
		(try (.[] | select(.permissions != null).permissions | to_entries | map(
			select(.key | startswith("android.permission.")) |
			(.value | split(" ")) as $v |
			($v[] | select(startswith("pflags=")) | sub("^pflags="; "")) as $pf |
			select($pf != "" and $pf != "0") |
			"\(.key) \($pf)"
		) | join(" ")) catch "" // ""),
		(try (.[] | select(.permissions != null).permissions | to_entries | map(select(ask_perm(.key; .value)) | .key) | join(" ")) catch "" // ""),
		(try (.[] | select(.installer != null).installer) catch "" // ""),
		(try (.[] | select(.install_diagnostics != null).install_diagnostics | tojson) catch "" // ""),
		(try (.[] | select(.battery_opt != null).battery_opt) catch "" // ""),
		(try (.[] | select(.Ssaid != null).Ssaid) catch "" // "")
	' "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} > "$tmpf"
	local _installer _install_diag _battery _media_access_mode _location_access_mode _ask_permissions
	exec 3< "$tmpf"
	read -r true_permissions <&3
	read -r false_permissions <&3
	read -r Set_Ops_permissions <&3
	read -r Set_Notify_settings <&3
	read -r Set_Battery_settings <&3
	read -r _media_access_mode <&3
	read -r _location_access_mode <&3
	read -r _permission_flags <&3
	read -r _ask_permissions <&3
	read -r _installer <&3
	read -r _install_diag <&3
	read -r _battery <&3
	read -r _rp_ssaid <&3
	exec 3<&-
	rm -f "$tmpf"
	# 若舊備份沒有 .installer，但 install_diagnostics 內有 installer / installing，從診斷資料補回。
	# 優先 installer，其次 installingPackageName；避免恢復後因備份 installer 空而完全不寫安裝來源。
	if [[ -z $_installer && -n $_install_diag ]]; then
		_installer="$(echo "$_install_diag" | jq -r 'try (.installer // .installing // "") catch "" | select(. != "null")' 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	fi
	# 權限恢復只寫入批量暫存；單 app 恢復由本函式自動開臨時 batch 並立即 flush。
	[[ $true_permissions != "" ]] && printf '[%s %s] ' "$name2" "$true_permissions" >> "$TMPDIR/.batch_grant"
	[[ $false_permissions != "" ]] && printf '[%s %s] ' "$name2" "$false_permissions" >> "$TMPDIR/.batch_revoke"
	# v24.20.14-1 conservative sparse reset：
	# 不恢復每 app 無條件 __RESET__，但只看 Set_Ops_permissions 又太窄。
	# media/location/ask/pflags 都可能牽涉 AppOps 或權限 flags 語意，故任一存在就保守送一次 reset。
	# 通知/電池/純 runtime 不送 reset，避免 restoreAppStateBatch 做無效工作。
	local _need_opsreset=0
	[[ -n $Set_Ops_permissions ]] && _need_opsreset=1
	[[ -n $_media_access_mode ]] && _need_opsreset=1
	[[ -n $_location_access_mode ]] && _need_opsreset=1
	[[ -n $_permission_flags ]] && _need_opsreset=1
	[[ -n $_ask_permissions ]] && _need_opsreset=1
	if [[ $_need_opsreset = 1 ]]; then
		printf '[%s] ' "$name2" >> "$TMPDIR/.batch_opsreset"
	fi
	[[ $Set_Ops_permissions != "" ]] && printf '[%s %s] ' "$name2" "$Set_Ops_permissions" >> "$TMPDIR/.batch_ops"
	[[ $Set_Notify_settings != "" ]] && printf '[%s %s] ' "$name2" "$Set_Notify_settings" >> "$TMPDIR/.batch_notify"
	[[ $Set_Battery_settings != "" ]] && printf '[%s %s] ' "$name2" "$Set_Battery_settings" >> "$TMPDIR/.batch_battery"
	[[ -n $_media_access_mode ]] && {
		# v24.20.14-7.45: 這裡只會送 selected，不再送 full/denied。
		# READ_MEDIA_AUDIO / IMAGES / VIDEO 的 true/false 由 grant/revoke 精準收斂。
		printf '[%s %s] ' "$name2" "$_media_access_mode" >> "$TMPDIR/.batch_media_access"
	}
	[[ -n $_location_access_mode ]] && printf '[%s %s] ' "$name2" "$_location_access_mode" >> "$TMPDIR/.batch_location_access"
	[[ -n $_permission_flags ]] && printf '[%s %s] ' "$name2" "$_permission_flags" >> "$TMPDIR/.batch_pflags"
	[[ -n $_ask_permissions ]] && printf '[%s %s] ' "$name2" "$_ask_permissions" >> "$TMPDIR/.batch_ask_access"
	# APK 安裝階段已由 hybrid_installer_pm / pm -i 處理 installer；不再把 installer 放進 restoreAppStateBatch，避免 dex 額外嘗試改寫 installer。
	_play_restore_hint_from_json "$name2" "$name1" "$_install_diag"
	_append_install_compare_batch "$name2" "$_install_diag"
	# 舊版 battery_opt 相容: 只有在沒有 battery_settings 時才套用, 避免覆蓋 dex v12 的完整設定
	if [[ -z $Set_Battery_settings ]]; then
		case $_battery in
		allow|ignore|deny|default)
			appops set "$name2" RUN_ANY_IN_BACKGROUND "$_battery" &>/dev/null
			# allow(無限制)時一併加入 doze 白名單豁免
			[[ $_battery = allow ]] && dumpsys deviceidle whitelist "+$name2" &>/dev/null
			echoRgb "恢復後台運行設定:$_battery" "2"
			;;
		esac
	fi
	if [[ $_restore_perm_autoflush = 1 ]]; then
		flush_batch_permissions
		_batch_perm_mode=0
		for _rp_batch_file in 			"$TMPDIR/.batch_grant" "$TMPDIR/.batch_revoke" "$TMPDIR/.batch_ops" "$TMPDIR/.batch_opsreset" 			"$TMPDIR/.batch_media_access" "$TMPDIR/.batch_location_access" "$TMPDIR/.batch_pflags" "$TMPDIR/.batch_ask_access" 			"$TMPDIR/.batch_notify" "$TMPDIR/.batch_notify_verify" "$TMPDIR/.batch_battery" "$TMPDIR/.batch_install_compare"; do
			rm -f "$_rp_batch_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		done
		unset _rp_batch_file
		_speed_debug_log "RESTORE_PERMISSIONS_AUTO_BATCH_FLUSHED package=${name2:-}"
	fi
}
# 根據備份時的 install_diagnostics 產生恢復提示：只提示，不中斷恢復。
_play_restore_hint_from_json() {
	local _pkg="$1" _app_label="$2" _json="$3" _show
	[[ -z $_pkg || -z $_app_label || -z $_json ]] && return
	_show="$_app_label"
	local _tmp="$TMPDIR/.install_diag_one_$$" _jqerr="$TMPDIR/.install_diag_one_jq_$$.err"
	# install_diagnostics 只允許 JSON object 進入 jq；舊備份/截斷值若不是 JSON，只記到 command.log，避免 stderr.log 出現 jq parse error。
	if ! printf '%s\n' "$_json" | jq -e 'type == "object"' >/dev/null 2>"$_jqerr"; then
		{
			echo "[$(date '+%H:%M:%S' 2>/dev/null)] $_pkg install_diagnostics 非 JSON object，已略過 Play 提示解析"
			[[ -s $_jqerr ]] && sed 's/^/[jq] /' "$_jqerr"
		} >> "${SPEED_DEBUG_CMD_LOG:-/dev/null}" 2>/dev/null
		rm -f "$_jqerr" "$_tmp" 2>/dev/null
		return 0
	fi
	rm -f "$_jqerr" 2>/dev/null
	printf '%s\n' "$_json" | jq -r '
		[ (.installer // ""), (.updateOwner // ""), (.updateOwnerApi // ""),
		  (.packageSource // ""), (.packageSourceName // ""), (.splitCount // "0" | tostring),
		  (.playStore // ""), (.playStoreEnabledState // ""), (.playStoreUid // ""), (.playStoreVersionCode // ""), (.playStoreRunAnyInBackgroundMode // ""),
		  (.playServices // ""), (.playServicesEnabledState // ""), (.playServicesUid // ""), (.playServicesVersionCode // ""), (.playServicesRunAnyInBackgroundMode // ""),
		  (.risk_INSTALLER_NOT_PLAY // .risk_INSTALLER_NULL // ""), (.risk_UPDATE_OWNER_PLAY_API34_PLUS // ""), (.risk_HAS_SPLITS // "")
		] | @tsv' 2>>${SPEED_DEBUG_CMD_LOG:-/dev/null} > "$_tmp"
	local _installer _update_owner _update_owner_api _pkg_src _pkg_src_name _split_count
	local _play_store _play_store_enabled _play_store_uid _play_store_ver _play_store_runany
	local _play_services _play_services_enabled _play_services_uid _play_services_ver _play_services_runany
	local _risk_installer _risk_update _risk_split
	IFS='	' read -r _installer _update_owner _update_owner_api _pkg_src _pkg_src_name _split_count \
		_play_store _play_store_enabled _play_store_uid _play_store_ver _play_store_runany \
		_play_services _play_services_enabled _play_services_uid _play_services_ver _play_services_runany \
		_risk_installer _risk_update _risk_split < "$_tmp"
	rm -f "$_tmp"
	# 終端只提示真正需要用戶處理的 Play 風險；installer/packageSource/splitCount 等正常資訊只保留在 debug log。
	[[ -n $_risk_update ]] && echo "$_show 設置擁有者為Play store，若版本過舊可能要求通過play store更新" >> "$TMPDIR/.play_restore_hints"
	case $_split_count in ''|*[!0-9]*) _split_count=0 ;; esac
	[[ -n $_risk_split && ${_split_count:-0} -eq 0 ]] && echo "$_show: split APK 狀態異常，若啟動失敗請確認 base + split APK 是否完整" >> "$TMPDIR/.play_restore_hints"
	[[ -n $_play_store && $_play_store != installed_enabled ]] && echo "$_show: Google Play 商店未正常啟用，建議先恢復/啟用 com.android.vending" >> "$TMPDIR/.play_restore_hints"
	[[ -n $_play_services && $_play_services != installed_enabled ]] && echo "$_show: Play services 狀態=$_play_services enabledState=$_play_services_enabled uid=$_play_services_uid version=$_play_services_ver，建議先恢復/啟用 com.google.android.gms" >> "$TMPDIR/.play_restore_hints"
	[[ -n $_play_store_runany && $_play_store_runany != null && $_play_store_runany != 0 ]] && echo "$_show: Play Store RUN_ANY_IN_BACKGROUND mode=$_play_store_runany，若商店行為異常可先恢復 Google Play 的電池/AppOps" >> "$TMPDIR/.play_restore_hints"
	[[ -n $_play_services_runany && $_play_services_runany != null && $_play_services_runany != 0 ]] && echo "$_show: Play services RUN_ANY_IN_BACKGROUND mode=$_play_services_runany，若驗證/更新異常可先恢復 GMS 的電池/AppOps" >> "$TMPDIR/.play_restore_hints"
}

_append_install_compare_batch() {
	local _pkg="$1" _json="$2"
	[[ -z $_pkg || -z $_json ]] && return
	local _tmp="$TMPDIR/.install_compare_$$" _jqerr="$TMPDIR/.install_compare_jq_$$.err"
	# install_diagnostics 非 JSON 時不要把 jq parse error 寫進 stderr.log；略過安裝完整性比對即可。
	if ! printf '%s\n' "$_json" | jq -e 'type == "object"' >/dev/null 2>"$_jqerr"; then
		{
			echo "[$(date '+%H:%M:%S' 2>/dev/null)] $_pkg install_diagnostics 非 JSON object，已略過完整性比對批次建立"
			[[ -s $_jqerr ]] && sed 's/^/[jq] /' "$_jqerr"
		} >> "${SPEED_DEBUG_CMD_LOG:-/dev/null}" 2>/dev/null
		rm -f "$_jqerr" "$_tmp" 2>/dev/null
		return 0
	fi
	rm -f "$_jqerr" 2>/dev/null
	printf '%s\n' "$_json" | jq -r '[ (.versionCode // ""), (.signingSha256 // ""), (.splitCount // "0" | tostring) ] | @tsv' 2>>${SPEED_DEBUG_CMD_LOG:-/dev/null} > "$_tmp"
	local _ver _sig _split
	IFS='	' read -r _ver _sig _split < "$_tmp"
	rm -f "$_tmp"
	[[ -z $_ver && -z $_sig && -z $_split ]] && return
	[[ -z $_ver ]] && _ver=null
	[[ -z $_sig ]] && _sig=null
	[[ -z $_split ]] && _split=0
	printf '[%s %s %s %s] ' "$_pkg" "$_ver" "$_sig" "$_split" >> "$TMPDIR/.batch_install_compare"
}

_install_compare_hints_from_output() {
	[[ -z $1 || ! -s $1 ]] && return
	awk '
		$2=="INSTALL_COMPARE" && $6=="MISMATCH" {
			if ($3=="versionCode") print $1 ": versionCode 不一致，備份=" $4 " 當前=" $5 "；若 app 跳 Play，請安裝同簽章且版本正確的 APK 或走 Play 更新"
			else if ($3=="signingSha256") print $1 ": 簽章 SHA-256 不一致，備份=" $4 " 當前=" $5 "；dex 不能修簽章，只能重裝正確簽章 APK"
			else if ($3=="splitCount") print $1 ": split APK 數量不一致，備份=" $4 " 當前=" $5 "；請確認 base.apk 與所有 split APK 都有完整恢復"
		}
		$2=="INSTALL_RISK" {
			if ($3=="VERSION_CHANGED") print $1 ": 版本已改變，建議比對 Play/備份 APK 版本"
			if ($3=="SIGNATURE_CHANGED") print $1 ": 簽章已改變，必須重裝正確簽章 APK"
			if ($3=="SPLIT_COUNT_CHANGED") print $1 ": split 結構已改變，必須完整恢復 split APK"
		}
	' "$1" >> "$TMPDIR/.install_compare_hints"
}

_install_compare_hints_report() {
	[[ ! -s $TMPDIR/.install_compare_hints ]] && return
	echoRgb "—————— 安裝完整性比對提示 ——————" "3"
	awk '!seen[$0]++' "$TMPDIR/.install_compare_hints" | while read -r _line; do [[ -n $_line ]] && echoRgb "$_line" "2"; done
	rm -f "$TMPDIR/.install_compare_hints"
}

_play_restore_hints_report() {
	[[ ! -s $TMPDIR/.play_restore_hints ]] && return
	echoRgb "—————— Play 恢復注意事項 ——————" "3"
	awk '!seen[$0]++' "$TMPDIR/.play_restore_hints" | while read -r _line; do [[ -n $_line ]] && echoRgb "$_line" "2"; done
	rm -f "$TMPDIR/.play_restore_hints"
}

# v24.20.14-3 appstate auto chunk：使用者仍可一次恢復 100+ app；內部只切 dex stdin 批次。
_appstate_chunk_size() {
	local _v="$1" _fallback="$2"
	case $_v in ''|*[!0-9]*) echo "$_fallback" ;; 0) echo "$_fallback" ;; *) echo "$_v" ;; esac
}

_appstate_collect_pkglist() {
	local _out="$1" _f
	shift
	: > "$_out"
	for _f in "$@"; do
		[[ -s $_f ]] || continue
		awk 'BEGIN{RS="]"; ORS="\n"} {gsub(/^[[:space:]\[]+/,""); gsub(/[[:space:]]+$/,""); if($0!=""){n=split($0,a,/ +/); if(a[1] ~ /\./) print a[1]}}' "$_f" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	done | awk 'NF && !seen[$0]++' > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_appstate_make_pkg_chunk() {
	local _all="$1" _offset="$2" _size="$3" _out="$4"
	awk -v off="$_offset" -v size="$_size" 'NR>off && NR<=off+size {print}' "$_all" > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_appstate_filter_by_pkgfile() {
	local _in="$1" _pkgfile="$2" _out="$3"
	: > "$_out"
	[[ -s $_in && -s $_pkgfile ]] || return 0
	awk -v pf="$_pkgfile" 'BEGIN{
		while ((getline p < pf) > 0) wanted[p]=1;
		RS="]"; ORS="";
	}
	{
		gsub(/^[[:space:]\[]+/,""); gsub(/[[:space:]]+$/,"");
		if($0!="") { n=split($0,a,/ +/); if(a[1] in wanted) printf "[%s] ",$0; }
	}' "$_in" > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_appstate_pkg_groups_by_pkgfile() {
	local _out="$1" _pkgfile="$2" _f
	shift 2
	: > "$_out"
	[[ -s $_pkgfile ]] || return 0
	for _f in "$@"; do
		[[ -s $_f ]] || continue
		awk -v pf="$_pkgfile" 'BEGIN{
			while ((getline p < pf) > 0) wanted[p]=1;
			RS="]"; ORS="";
		}
		{
			gsub(/^[[:space:]\[]+/,""); gsub(/[[:space:]]+$/,"");
			if($0!="") { n=split($0,a,/ +/); if(a[1] in wanted) printf "[%s] ",a[1]; }
		}' "$_f" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	done | awk 'BEGIN{RS="]"; ORS=""} {gsub(/^[[:space:]\[]+/,""); gsub(/[[:space:]]+$/,""); if($0!="" && !seen[$0]++) printf "[%s] ",$0}' > "$_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

_appstate_debug_reset_aggregate() {
	[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d "$SPEED_DEBUG_RUN_DIR" ]] || return 0
	: > "$SPEED_DEBUG_RUN_DIR/app_state_stdin.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	: > "$SPEED_DEBUG_RUN_DIR/app_state_output.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	: > "$SPEED_DEBUG_RUN_DIR/permission_state_stdin.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
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

_appstate_debug_append_permission_lines() {
	local _dst="$1" _src="$2" _label="$3"
	[[ -f $_src ]] || return 0
	{
		echo
		echo "===== ${_label} BEGIN ====="
		sed -n 's/^__PERMISSION__ //p' "$_src" 2>/dev/null
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
			_appstate_debug_append_permission_lines "$SPEED_DEBUG_RUN_DIR/permission_state_stdin.log" "$_in" "restore chunk ${_tag} permission"
			_appstate_debug_append_file "$SPEED_DEBUG_RUN_DIR/app_state_output.log" "$_out" "restore chunk ${_tag} output"
			;;
		verify)
			_appstate_debug_append_file "$SPEED_DEBUG_RUN_DIR/verify_app_state_stdin.log" "$_in" "verify chunk ${_tag} stdin"
			_appstate_debug_append_file "$SPEED_DEBUG_RUN_DIR/verify_app_state_output.log" "$_out" "verify chunk ${_tag} output"
			;;
	esac
}

# v24.20.14 sparse batch：整理 bracket batch 檔，移除重複項。
# 格式: [pkg payload...] [pkg payload...]
_sparse_dedupe_bracket_batch() {
	local _f="$1" _tmp
	[[ -s $_f ]] || return 0
	_tmp="$TMPDIR/.sparse_dedupe_${_f##*/}_$$"
	awk 'BEGIN{RS="]"; ORS=""} {gsub(/^[[:space:]\[]+/,""); gsub(/[[:space:]]+$/,""); if($0 != "" && !seen[$0]++) printf "[%s] ",$0}' "$_f" > "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [[ -s $_tmp ]]; then
		cat "$_tmp" > "$_f"
	else
		: > "$_f"
	fi
	rm -f "$_tmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}

# 批量沖刷: runtime / special AppOps / media / location 權限狀態交給 dex 批量 JVM。
# AppOps reset 直接使用 HiddenApiUtil.appOpsResetBatch 公開批量入口；restoreAppStateBatch 的 __RESET__ 僅保留空 marker 兼容 parser，不再承載 reset package。
# 正常權限/通知/電池仍合併 restoreAppStateBatch；AppOps reset 先獨立批量執行，避免腳本依賴舊 AppOps reset CLI、單包 reset 公開入口或隱藏區段。
flush_batch_permissions() {
	[[ $_batch_perm_mode != 1 ]] && return
	local _g="$TMPDIR/.batch_grant" _r="$TMPDIR/.batch_revoke" _o="$TMPDIR/.batch_ops" _i="$TMPDIR/.batch_installer" _ci="$TMPDIR/.batch_clear_installer" _n="$TMPDIR/.batch_notify" _nv="$TMPDIR/.batch_notify_verify" _b="$TMPDIR/.batch_battery" _m="$TMPDIR/.batch_media_access" _l="$TMPDIR/.batch_location_access" _pf="$TMPDIR/.batch_pflags" _a="$TMPDIR/.batch_ask_access" _c="$TMPDIR/.batch_install_compare" _rs="$TMPDIR/.batch_opsreset" _rspkg _sparse_f
	# v24.20.14-7.12：部分恢復場景可能沒有任何 grant/revoke；先建立空檔，避免後續 awk/cat 查缺檔污染 stderr.log。
	for _sparse_f in "$_rs" "$_g" "$_r" "$_o" "$_m" "$_l" "$_pf" "$_a" "$_n" "$_b" "$_c"; do
		[[ -f $_sparse_f ]] || : > "$_sparse_f" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	done
	_notify_filter_readonly_fields "$_n"
	# v24.14：恢復設定合併為單次 JVM；驗證讀回也合併為 verifyAppStateBatch 單次 JVM；終端驗證提示合併顯示。
	# APK 安裝/Play session 仍獨立，因為 Play UID/context 與一般狀態恢復不同。
	# v24.20.14：flush 前去重，並讓空檔保持空，避免把重複/無效項送進 dex。
	for _sparse_f in "$_rs" "$_g" "$_r" "$_o" "$_m" "$_l" "$_pf" "$_a" "$_n" "$_b"; do
		_sparse_dedupe_bracket_batch "$_sparse_f"
	done
	# v24.20.14-7.49：restore 送 dex 前濾掉尚未建立的 NotificationChannel/Group；verify 保留原始期望做分級摘要。
	cp "$_n" "$_nv" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_notify_fast_skip_missing_channel_groups "$_n"
	_sparse_dedupe_bracket_batch "$_n"
	local _appstate_all_pkgs="$TMPDIR/.appstate_all_pkgs" _appstate_pkg_chunk="$TMPDIR/.appstate_pkg_chunk"
	local _appstate_pkg_count _appstate_chunk_size _appstate_chunk_total _appstate_chunk_idx _appstate_offset
	_appstate_collect_pkglist "$_appstate_all_pkgs" "$_rs" "$_g" "$_r" "$_o" "$_m" "$_l" "$_pf" "$_a" "$_n" "$_b"
	_appstate_pkg_count="$(awk 'END{print NR+0}' "$_appstate_all_pkgs" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
	_appstate_chunk_size="$(_appstate_chunk_size "${RESTORE_APPSTATE_BATCH_CHUNK_SIZE:-30}" 30)"
	_appstate_chunk_total=$(( (_appstate_pkg_count + _appstate_chunk_size - 1) / _appstate_chunk_size ))
	if [[ $_appstate_pkg_count -gt 0 ]] && [[ -s $_rs || -s $_g || -s $_r || -s $_o || -s $_m || -s $_l || -s $_pf || -s $_a || -s $_n || -s $_b ]]; then
		_appstate_debug_reset_aggregate
		_appstate_chunk_idx=1
		_appstate_offset=0
		while [[ $_appstate_offset -lt $_appstate_pkg_count ]]; do
			_appstate_make_pkg_chunk "$_appstate_all_pkgs" "$_appstate_offset" "$_appstate_chunk_size" "$_appstate_pkg_chunk"
			local _appstate="$TMPDIR/.batch_app_state" _appstate_out="$TMPDIR/.app_state_out"
			local _crs="$TMPDIR/.appstate_filter_reset" _cg="$TMPDIR/.appstate_filter_grant" _cr="$TMPDIR/.appstate_filter_revoke" _co="$TMPDIR/.appstate_filter_ops" _cm="$TMPDIR/.appstate_filter_media" _cl="$TMPDIR/.appstate_filter_location" _cpf="$TMPDIR/.appstate_filter_pflags" _ca="$TMPDIR/.appstate_filter_ask" _cn="$TMPDIR/.appstate_filter_notify" _cb="$TMPDIR/.appstate_filter_battery"
			_appstate_filter_by_pkgfile "$_rs" "$_appstate_pkg_chunk" "$_crs"
			_appstate_filter_by_pkgfile "$_g" "$_appstate_pkg_chunk" "$_cg"
			_appstate_filter_by_pkgfile "$_r" "$_appstate_pkg_chunk" "$_cr"
			_appstate_filter_by_pkgfile "$_o" "$_appstate_pkg_chunk" "$_co"
			_appstate_filter_by_pkgfile "$_m" "$_appstate_pkg_chunk" "$_cm"
			_appstate_filter_by_pkgfile "$_l" "$_appstate_pkg_chunk" "$_cl"
			_appstate_filter_by_pkgfile "$_pf" "$_appstate_pkg_chunk" "$_cpf"
			_appstate_filter_by_pkgfile "$_a" "$_appstate_pkg_chunk" "$_ca"
			_appstate_filter_by_pkgfile "$_n" "$_appstate_pkg_chunk" "$_cn"
			_appstate_filter_by_pkgfile "$_b" "$_appstate_pkg_chunk" "$_cb"
			# v24.20.14-7.66-180：AppOps reset 只走 appOpsResetBatch 批量入口，不再把 reset package 交給 restoreAppStateBatch __RESET__。
			if [[ -s $_crs ]]; then
				local _opsreset_pkgs="$TMPDIR/.appstate_filter_reset_pkgs" _opsreset_out="$TMPDIR/.appops_reset_batch_out"
				awk 'BEGIN{RS="]"} {gsub(/\[/,""); gsub(/^[ \t\r\n]+|[ \t\r\n]+$/,""); if($0!=""){split($0,a,/ /); if(a[1]!="") print a[1]}}' "$_crs" | sort -u > "$_opsreset_pkgs" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				if [[ -s $_opsreset_pkgs ]]; then
					[[ $_dex_debug = 1 ]] && echo "FLUSH-appOpsResetBatch chunk=${_appstate_chunk_idx}/${_appstate_chunk_total}" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/dex_call.log"
					_dex_stdin appOpsResetBatch "$_opsreset_pkgs" "$_opsreset_out"
					local _opsreset_rc=$?
					_appstate_debug_save_chunk appops-reset "$_appstate_chunk_idx" "$_opsreset_pkgs" "$_opsreset_out"
					[[ $_opsreset_rc != 0 ]] && echo_log "批量重置 AppOps 狀態"
				fi
				rm -f "$_opsreset_pkgs" "$_opsreset_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			fi
			if [[ -s $_crs || -s $_cg || -s $_cr || -s $_co || -s $_cm || -s $_cl || -s $_cpf || -s $_ca || -s $_cn || -s $_cb ]]; then
				if [[ $_appstate_chunk_total -gt 1 ]]; then
					echoRgb "恢復權限/通知/電池狀態中... ${_appstate_chunk_idx}/${_appstate_chunk_total}" "3"
				else
					echoRgb "恢復權限/通知/電池狀態中..." "3"
				fi
				{
					printf '__PERMISSION__ '
					printf '__RESET__ ' # reset 已由 appOpsResetBatch 直接處理，這裡保留空 marker 供 dex parser 對齊
					printf ' __GRANT__ '
					[[ -s $_cg ]] && cat "$_cg"
					printf ' __REVOKE__ '
					[[ -s $_cr ]] && cat "$_cr"
					printf ' __OPS__ '
					[[ -s $_co ]] && cat "$_co"
					printf ' __MEDIA__ '
					[[ -s $_cm ]] && cat "$_cm"
					printf ' __LOCATION__ '
					[[ -s $_cl ]] && cat "$_cl"
					printf ' __PFLAGS__ '
					[[ -s $_cpf ]] && cat "$_cpf"
					printf ' __ASK__ '
					[[ -s $_ca ]] && cat "$_ca"
					printf ' __INSTALLER__ '
					printf ' __CLEAR_INSTALLER__ '
					printf ' __NOTIFY__ '
					[[ -s $_cn ]] && cat "$_cn"
					printf ' __BATTERY__ '
					[[ -s $_cb ]] && cat "$_cb"
					printf '\n'
				} > "$_appstate"
				[[ $_dex_debug = 1 ]] && echo "FLUSH-restoreAppStateBatch chunk=${_appstate_chunk_idx}/${_appstate_chunk_total}" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/dex_call.log"
				rm -f "$_appstate_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				_dex_stdin restoreAppStateBatch "$_appstate" "$_appstate_out"
				local _appstate_rc=$?
				_appstate_debug_save_chunk restore "$_appstate_chunk_idx" "$_appstate" "$_appstate_out"
				[[ $_appstate_rc != 0 ]] && echo_log "批量恢復 App 狀態"
				rm -f "$_appstate" "$_appstate_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			fi
			rm -f "$_crs" "$_cg" "$_cr" "$_co" "$_cm" "$_cl" "$_cpf" "$_ca" "$_cn" "$_cb" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			_appstate_offset=$((_appstate_offset + _appstate_chunk_size))
			_appstate_chunk_idx=$((_appstate_chunk_idx + 1))
		done
		echoRgb "權限/通知/電池設定完成" "1"
	fi
		# ====== v24.14 恢復後驗證讀回合併：install compare/runtime/appops/notify/battery 一次 JVM；終端只顯示一次批量驗證提示 ======
	local _verify_batch_in="$TMPDIR/.verify_app_state_stdin" _verify_batch_out="$TMPDIR/.verify_app_state_out"
	local _verify_all_pkgs="$TMPDIR/.verify_appstate_all_pkgs" _verify_pkg_chunk="$TMPDIR/.verify_appstate_pkg_chunk"
	local _verify_pkg_count _verify_chunk_size _verify_chunk_total _verify_chunk_idx _verify_offset
	rm -f "$_verify_batch_in" "$_verify_batch_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [[ $_perm_verify != 0 || -s $_c ]]; then
		_appstate_collect_pkglist "$_verify_all_pkgs" "$_c" "$_g" "$_r" "$_o" "$_m" "$_l" "$_pf" "$_a" "$_nv" "$_b"
		_verify_pkg_count="$(awk 'END{print NR+0}' "$_verify_all_pkgs" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		_verify_chunk_size="$(_appstate_chunk_size "${VERIFY_APPSTATE_BATCH_CHUNK_SIZE:-30}" 30)"
		_verify_chunk_total=$(( (_verify_pkg_count + _verify_chunk_size - 1) / _verify_chunk_size ))
		if [[ $_verify_pkg_count -gt 0 ]]; then
			: > "$_verify_batch_out"
			[[ -n ${SPEED_DEBUG_RUN_DIR:-} && -d "$SPEED_DEBUG_RUN_DIR" ]] && { : > "$SPEED_DEBUG_RUN_DIR/verify_app_state_stdin.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; : > "$SPEED_DEBUG_RUN_DIR/verify_app_state_output.log" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}; }
			_verify_chunk_idx=1
			_verify_offset=0
			while [[ $_verify_offset -lt $_verify_pkg_count ]]; do
				_appstate_make_pkg_chunk "$_verify_all_pkgs" "$_verify_offset" "$_verify_chunk_size" "$_verify_pkg_chunk"
				local _vc="$TMPDIR/.verify_appstate_chunk_install_compare" _vruntime="$TMPDIR/.verify_appstate_chunk_runtime" _vops="$TMPDIR/.verify_appstate_chunk_ops" _vn="$TMPDIR/.verify_appstate_chunk_notify" _vb="$TMPDIR/.verify_appstate_chunk_battery" _vout_chunk="$TMPDIR/.verify_app_state_out_chunk"
				_appstate_filter_by_pkgfile "$_c" "$_verify_pkg_chunk" "$_vc"
				_appstate_pkg_groups_by_pkgfile "$_vruntime" "$_verify_pkg_chunk" "$_g" "$_r" "$_m" "$_l" "$_pf" "$_a"
				_appstate_pkg_groups_by_pkgfile "$_vops" "$_verify_pkg_chunk" "$_o"
				_appstate_pkg_groups_by_pkgfile "$_vn" "$_verify_pkg_chunk" "$_nv"
				_appstate_pkg_groups_by_pkgfile "$_vb" "$_verify_pkg_chunk" "$_b"
				{
					printf '__INSTALL_COMPARE__ '
					[[ -s $_vc ]] && cat "$_vc"
					printf ' __RUNTIME__ '
					[[ -s $_vruntime ]] && cat "$_vruntime"
					printf ' __OPS__ '
					[[ -s $_vops ]] && cat "$_vops"
					printf ' __NOTIFY__ '
					[[ -s $_vn ]] && cat "$_vn"
					printf ' __BATTERY__ '
					[[ -s $_vb ]] && cat "$_vb"
					printf '\n'
				} > "$_verify_batch_in"
				if [[ -s $_verify_batch_in ]]; then
					if [[ $_verify_chunk_total -gt 1 ]]; then
						echoRgb "批量驗證安裝完整性/權限/AppOps/通知/電池狀態中... ${_verify_chunk_idx}/${_verify_chunk_total}" "3"
					else
						echoRgb "批量驗證安裝完整性/權限/AppOps/通知/電池狀態中..." "3"
					fi
					[[ $_dex_debug = 1 ]] && echo "FLUSH-verifyAppStateBatch chunk=${_verify_chunk_idx}/${_verify_chunk_total}" >> "${SPEED_DEBUG_RUN_DIR:-/data/speed_debug}/dex_call.log"
					rm -f "$_vout_chunk" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					_dex_stdin verifyAppStateBatch "$_verify_batch_in" "$_vout_chunk"
					cat "$_vout_chunk" >> "$_verify_batch_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					_appstate_debug_save_chunk verify "$_verify_chunk_idx" "$_verify_batch_in" "$_vout_chunk"
				fi
				rm -f "$_vc" "$_vruntime" "$_vops" "$_vn" "$_vb" "$_vout_chunk" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				_verify_offset=$((_verify_offset + _verify_chunk_size))
				_verify_chunk_idx=$((_verify_chunk_idx + 1))
			done
		fi
	fi
		if [[ -s $_c ]]; then
		: # v24.14：安裝完整性已併入批量驗證讀回
		local _cmp_out="$TMPDIR/.install_compare_$$"
		if [[ -s $_verify_batch_out ]]; then
			grep -E " INSTALL_(COMPARE|RISK) |INSTALL_COMPARE_FAILED_SKIP" "$_verify_batch_out" > "$_cmp_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		else
			_dex_xargs compareInstallDiagnostics "$_c" "$_cmp_out"
		fi
		_install_compare_hints_from_output "$_cmp_out"
		rm -f "$_cmp_out" "$_c"
	fi
	_install_compare_hints_report
	_play_restore_hints_report
	rm -f "$TMPDIR/.pkg_notify" "$TMPDIR/.pkg_battery" "$TMPDIR/.install_diag" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}

	# ====== 恢復後權限驗證 (只驗 grant/revoke 開關, 不驗 ops mode) ======
	# flush 後一次 getRuntimePermissions 批量讀回實際權限, 跟應設狀態比對
	if [[ $_perm_verify != 0 ]] && [[ -s $_g || -s $_r ]]; then
		: # v24.14：Runtime 權限已併入批量驗證讀回
		# 從 batch 檔解析出 期望狀態: 格式 pkg<TAB>perm<TAB>true/false
		local _expect="$TMPDIR/.perm_expect" _actual="$TMPDIR/.perm_actual"
		: > "$_expect"
		# grant 檔 → 期望 true; revoke 檔 → 期望 false. 格式 [pkg perm perm] [pkg perm]
		awk 'BEGIN{RS="]"} {
			gsub(/\[/,""); n=split($0,a," "); if(n<2)next
			for(i=2;i<=n;i++) print a[1]"\t"a[i]"\ttrue"
		}' "$_g" >> "$_expect" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		awk 'BEGIN{RS="]"} {
			gsub(/\[/,""); n=split($0,a," "); if(n<2)next
			for(i=2;i<=n;i++) print a[1]"\t"a[i]"\tfalse"
		}' "$_r" >> "$_expect" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		# 取所有涉及的包名, 一次批量讀回實際權限 (1 次 dex)
		local _vpkgs
		_vpkgs="$(awk -F'\t' '{print $1}' "$_expect" | sort -u | paste -sd' ' -)"
		if [[ -s $_verify_batch_out ]]; then
			awk 'NF>=5 && $2 ~ /^(android\.permission\.|android:)/ {pf="0"; for(i=6;i<=NF;i++){ if($i ~ /^pflags=/){pf=$i; sub(/^pflags=/,"",pf)} } print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"pf}' "$_verify_batch_out" > "$_actual"
		else
			get_Permissions $_vpkgs 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk 'NF>=5 {pf="0"; for(i=6;i<=NF;i++){ if($i ~ /^pflags=/){pf=$i; sub(/^pflags=/,"",pf)} } print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"pf}' > "$_actual"
		fi
		_runtime_semantic_report "$_expect" "$_actual" "$_m" "$_l" "$_pf" "$_a"
		_permission_policy_v2_runtime_report "$_expect" "$_actual"
		# 比對: 期望 vs 實際。除了 granted=true/false，也檢查有效 AppOps mode；
		# granted=true 但 mode=1(ignored) 或 mode=2(errored) 時，系統 UI 仍可能顯示未授予，不能算通過。
		local _mismatch
		_mismatch="$(awk -F'\t' '
			function runtime_verify_skip(p){ return (p=="android.permission.FOREGROUND_SERVICE" || p ~ /^android\.permission\.FOREGROUND_SERVICE_/) }
			NR==FNR { act[$1"\t"$2]=$3; op[$1"\t"$2]=$4; mode[$1"\t"$2]=$5; next }
			{
				if (runtime_verify_skip($2)) next
				key=$1"\t"$2
				if (key in act) {
					if (act[key] != $3) {
						print "  ✗ "$1"  "$2"  應="$3" 實際="act[key]
					} else if ($3 == "true" && (mode[key] == "1" || mode[key] == "2")) {
						print "  ✗ "$1"  "$2"  granted=true 但 AppOps op="op[key]" mode="mode[key]"，實際仍被系統阻擋"
					}
				} else {
					print "  ? "$1"  "$2"  應="$3" 實際=未讀到"
				}
			}' "$_actual" "$_expect")"
		if [[ -z $_mismatch ]]; then
			echoRgb "✅ Runtime 權限驗證通過" "1"
		else
			if echo "$_mismatch" | grep -q 'granted=true 但 AppOps'; then
				local _repair="$TMPDIR/.runtime_appops_dex_repair"
				awk -F'\t' 'NR==FNR { act[$1"\t"$2]=$3; mode[$1"\t"$2]=$5; next } $3=="true" { k=$1"\t"$2; if ((k in act) && act[k]=="true" && (mode[k]=="1" || mode[k]=="2")) print "["$1" "$2"]" }' "$_actual" "$_expect" > "$_repair" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				if [[ -s $_repair ]]; then
					echoRgb "Runtime 權限 AppOps 被阻擋，交由 dex 批量補救..." "3"
					_dex_xargs fixRuntimeAppOpsAllow "$_repair"
					get_Permissions $_vpkgs 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk 'NF>=5 {pf="0"; for(i=6;i<=NF;i++){ if($i ~ /^pflags=/){pf=$i; sub(/^pflags=/,"",pf)} } print $1"\t"$2"\t"$3"\t"$4"\t"$5"\t"pf}' > "$_actual"
					_mismatch="$(awk -F'\t' '
						function runtime_verify_skip(p){ return (p=="android.permission.FOREGROUND_SERVICE" || p ~ /^android\.permission\.FOREGROUND_SERVICE_/) }
						NR==FNR { act[$1"\t"$2]=$3; op[$1"\t"$2]=$4; mode[$1"\t"$2]=$5; next }
						{ if (runtime_verify_skip($2)) next; key=$1"\t"$2; if (key in act) { if (act[key] != $3) print "  ✗ "$1"  "$2"  應="$3" 實際="act[key]; else if ($3 == "true" && (mode[key] == "1" || mode[key] == "2")) print "  ✗ "$1"  "$2"  granted=true 但 AppOps op="op[key]" mode="mode[key]"，實際仍被系統阻擋" } else print "  ? "$1"  "$2"  應="$3" 實際=未讀到" }' "$_actual" "$_expect")"
				fi
				rm -f "$_repair"
			fi
			if [[ -z $_mismatch ]]; then
				echoRgb "✅ Runtime 權限驗證通過" "1"
			else
				_verify_mismatch_log "Runtime 權限 mismatch" "$_mismatch"
				echoRgb "⚠️ Runtime 權限驗證失敗，詳細 mismatch 已寫入 debug 包 verify_mismatch.log" "0"
			fi
		fi
		rm -f "$_expect" "$_actual"
	fi
	# ====== 恢復後 AppOps mode 驗證 ======
	# 驗證批量 AppOps 實際 mode 是否與備份值一致（op + mode）
	if [[ $_perm_verify != 0 && -s $_o ]]; then
		: # v24.14：AppOps mode 已併入批量驗證讀回
		local _ops_expect="$TMPDIR/.ops_expect" _ops_actual="$TMPDIR/.ops_actual" _ops_pkgs _ops_mismatch
		: > "$_ops_expect"
		awk 'BEGIN{RS="]"} {
			gsub(/\[/,""); n=split($0,a," "); if(n<3)next
			for(i=2;i+1<=n;i+=2) print a[1]"\t"a[i]"\t"a[i+1]
		}' "$_o" >> "$_ops_expect" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_ops_pkgs="$(awk -F'\t' '{print $1}' "$_ops_expect" | sort -u | paste -sd' ' -)"
		if [[ -n $_ops_pkgs ]]; then
			if [[ -s $_verify_batch_out ]]; then
				awk 'NF>=5 && $2 ~ /^(android\.permission\.|android:)/ {print $1"\t"$4"\t"$5}' "$_verify_batch_out" > "$_ops_actual"
			else
				get_Permissions $_ops_pkgs 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk 'NF>=5 {print $1"\t"$4"\t"$5}' > "$_ops_actual"
			fi
			_appops_scope_detail_report "$_ops_expect" "$_ops_actual"
			# v24.20.14-7.66-190: verifyAppStateBatch 有些 package-special op 不會出現在 runtime-style 輸出，
			# 但 appOpsScopeDetail 已可讀到 package/effective mode。補進實際值，避免 op=119 這類假「未讀到」。
			if [ -n "${SPEED_DEBUG_RUN_DIR:-}" ] && [ -s "$SPEED_DEBUG_RUN_DIR/appops_scope_detail.log" ]; then
				local _ops_actual_merged="$TMPDIR/.ops_actual_merged"
				cp "$_ops_actual" "$_ops_actual_merged" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				awk -F'\t' '
					NR==FNR { want[$1"\t"$2]=1; next }
					/^#/ { next }
					{
						pkg=$1; op=""; eff="";
						for(i=2;i<=NF;i++){
							if($i ~ /^op=/){ op=$i; sub(/^op=/,"",op) }
							if($i ~ /^effective_mode=/){ eff=$i; sub(/^effective_mode=/,"",eff) }
						}
						if(op!="" && eff!="" && eff!="-999" && (pkg"\t"op) in want) print pkg"\t"op"\t"eff
					}
				' "$_ops_expect" "$SPEED_DEBUG_RUN_DIR/appops_scope_detail.log" >> "$_ops_actual_merged" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				mv -f "$_ops_actual_merged" "$_ops_actual" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			fi
			_appops_semantic_report "$_ops_expect" "$_ops_actual"
			_permission_policy_v2_appops_report "$_ops_expect" "$_ops_actual"
			_ops_mismatch="$(awk -F'\t' '
				NR==FNR { act[$1"\t"$2]=$3; next }
				{
					key=$1"\t"$2
					if (key in act) {
						if (act[key] != $3) print "  ✗ "$1"  op="$2"  應mode="$3" 實際mode="act[key]
					} else {
						print "  ? "$1"  op="$2"  應mode="$3" 實際=未讀到"
					}
				}' "$_ops_actual" "$_ops_expect")"
			if [[ -z $_ops_mismatch ]]; then
				echoRgb "✅ AppOps mode 驗證通過" "1"
			else
				_verify_mismatch_log "AppOps mode mismatch" "$_ops_mismatch"
				echoRgb "⚠️ AppOps mode 驗證失敗，詳細 mismatch 已寫入 debug 包 verify_mismatch.log" "0"
			fi
		fi
		rm -f "$_ops_expect" "$_ops_actual"
	fi
	# ====== 恢復後通知設定驗證 ======
	# 驗證 notification_settings 的 key/value 是否與備份值一致
	# 注意：部分 app 的 NotificationChannel 只有在 app 第一次啟動/建立通知後才會出現。
	# 因此 NOTIFY_CHANNEL/NOTIFY_GROUP「未讀到」不直接當成恢復錯誤，而是列為「待建立分類」。
	if [[ $_perm_verify != 0 && -s $_nv ]]; then
		: # v24.14：通知設定已併入批量驗證讀回
		local _notify_expect="$TMPDIR/.notify_expect" _notify_actual="$TMPDIR/.notify_actual" _notify_pkgs
		local _notify_mismatch_file="$TMPDIR/.notify_mismatch" _notify_pending_file="$TMPDIR/.notify_pending"
		local _notify_mismatch _notify_pending
		: > "$_notify_expect"
		: > "$_notify_mismatch_file"
		: > "$_notify_pending_file"
		awk 'BEGIN{RS="]"} {
			gsub(/\[/,""); n=split($0,a," "); if(n<3)next
			for(i=2;i+1<=n;i+=2) print a[1]"\t"a[i]"\t"a[i+1]
		}' "$_nv" >> "$_notify_expect" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_notify_pkgs="$(awk -F'\t' '{print $1}' "$_notify_expect" | sort -u | paste -sd' ' -)"
		if [[ -n $_notify_pkgs ]]; then
			if [[ -s $_verify_batch_out ]]; then
				awk 'NF>=3 && $2 ~ /^NOTIFY_/ {val=$3; for(i=4;i<=NF;i++) val=val" "$i; print $1"\t"$2"\t"val}' "$_verify_batch_out" > "$_notify_actual"
			else
				get_Notifications $_notify_pkgs 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk 'NF>=3 {
					val=$3; for(i=4;i<=NF;i++) val=val" "$i
					print $1"\t"$2"\t"val
				}' > "$_notify_actual"
			fi
			_notification_deep_verify_report "$_notify_expect" "$_notify_actual"
			awk -F'\t' -v mis="$_notify_mismatch_file" -v pend="$_notify_pending_file" '
				NR==FNR { act[$1"\t"$2]=$3; next }
				{
					key=$1"\t"$2
					if (key in act) {
						if (act[key] != $3) print "  ✗ "$1"  "$2"  應="$3" 實際="act[key] >> mis
					} else if ($2 ~ /^NOTIFY_CHANNEL:/ || $2 ~ /^NOTIFY_GROUP:/) {
						# 通知分類/群組尚未建立：同一個 channel/group 只列一次，避免刷滿螢幕。
						n=split($2, parts, ":")
						if (n >= 2) print "  ? "$1"  "parts[1]":"parts[2]"  尚未建立/未讀到，啟動應用建立通知分類後再驗證" >> pend
						else print "  ? "$1"  "$2"  尚未建立/未讀到，啟動應用建立通知分類後再驗證" >> pend
					} else {
						# app-level 設定未讀到才是真正不一致
						print "  ✗ "$1"  "$2"  應="$3" 實際=未讀到" >> mis
					}
				}' "$_notify_actual" "$_notify_expect"
			_notify_mismatch="$(cat "$_notify_mismatch_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
			_notify_pending="$(sort -u "$_notify_pending_file" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
			if [[ -z $_notify_mismatch && -z $_notify_pending ]]; then
				echoRgb "✅ 通知設定驗證通過" "1"
			else
				if [[ -n $_notify_mismatch ]]; then
					_verify_mismatch_log "通知設定 mismatch" "$_notify_mismatch"
					echoRgb "⚠️ 通知設定驗證失敗，詳細 mismatch 已寫入 debug 包 verify_mismatch.log" "0"
				fi
				if [[ -n $_notify_pending ]]; then
					local _pending_cnt
		            _pending_cnt="$(awk -F'\t' '{k=$1"\t"$2} !seen[k]++ {c++} END{print c+0}' "$TMPDIR/.notify_pending" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		            echoRgb "⚠️ 有 ${_pending_cnt} 個通知分類/群組尚未建立，已略過逐條顯示；啟動 app 建立 NotificationChannel 後可再重跑通知恢復/驗證" "2"
		            echoRgb "✅ app-level 通知設定與已存在的通知分類驗證通過；缺失分類不判定為恢復錯誤" "1"
				fi
			fi
		fi
		rm -f "$_notify_expect" "$_notify_actual" "$_notify_mismatch_file" "$_notify_pending_file"
	fi
	# ====== 恢復後電池/背景設定驗證 ======
	# RUN_* 實際輸出是 pkg key op mode modeName，驗證 mode；deviceidle_whitelist 驗證 true/false
	if [[ $_perm_verify != 0 && -s $_b ]]; then
		: # v24.14：電池/背景設定已併入批量驗證讀回
		local _battery_expect="$TMPDIR/.battery_expect" _battery_actual="$TMPDIR/.battery_actual" _battery_pkgs _battery_mismatch
		: > "$_battery_expect"
		awk 'BEGIN{RS="]"} {
			gsub(/\[/,""); n=split($0,a," "); if(n<3)next
			for(i=2;i+1<=n;i+=2) {
				key=a[i]; val=a[i+1]
				if (key=="BATTERY:RUN_IN_BACKGROUND" || key=="BATTERY:RUN_ANY_IN_BACKGROUND") {
					if (val=="allow" || val=="allowed" || val=="true") val=0
					else if (val=="ignore" || val=="ignored" || val=="false") val=1
					else if (val=="deny" || val=="denied" || val=="errored") val=2
					else if (val=="default") val=3
					else if (val=="foreground") val=4
				}
				print a[1]"\t"key"\t"val
			}
		}' "$_b" >> "$_battery_expect" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		_battery_pkgs="$(awk -F'\t' '{print $1}' "$_battery_expect" | sort -u | paste -sd' ' -)"
		if [[ -n $_battery_pkgs ]]; then
			if [[ -s $_verify_batch_out ]]; then
				awk 'NF>=3 && $2 ~ /^BATTERY:/ { if ($2=="BATTERY:deviceidle_whitelist") print $1"\t"$2"\t"$3; else if ($2=="BATTERY:RUN_IN_BACKGROUND" || $2=="BATTERY:RUN_ANY_IN_BACKGROUND") print $1"\t"$2"\t"$4 }' "$_verify_batch_out" > "$_battery_actual"
			else
				get_Battery_Settings $_battery_pkgs 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | awk 'NF>=3 {
					if ($2=="BATTERY:deviceidle_whitelist") {
						print $1"\t"$2"\t"$3
					} else if ($2=="BATTERY:RUN_IN_BACKGROUND" || $2=="BATTERY:RUN_ANY_IN_BACKGROUND") {
						print $1"\t"$2"\t"$4
					}
				}' > "$_battery_actual"
			fi
			_battery_mismatch="$(awk -F'\t' '
				NR==FNR { act[$1"\t"$2]=$3; next }
				{
					key=$1"\t"$2
					if (key in act) {
						if (act[key] != $3) print "  ✗ "$1"  "$2"  應="$3" 實際="act[key]
					} else {
						print "  ? "$1"  "$2"  應="$3" 實際=未讀到"
					}
				}' "$_battery_actual" "$_battery_expect")"
			if [[ -z $_battery_mismatch ]]; then
				echoRgb "✅ 電池/背景設定驗證通過" "1"
			else
				_verify_mismatch_log "電池/背景設定 mismatch" "$_battery_mismatch"
				echoRgb "⚠️ 電池/背景設定驗證失敗，詳細 mismatch 已寫入 debug 包 verify_mismatch.log" "0"
			fi
		fi
		rm -f "$_battery_expect" "$_battery_actual"
	fi
	rm -f "$_g" "$_r" "$_o" "$_m" "$_l" "$_pf" "$_a" "$_i" "$_ci" "$_n" "$_nv" "$_b" "$_c" "$_rs" "$TMPDIR/.perm_expect" "$TMPDIR/.perm_actual" "$TMPDIR/.ops_expect" "$TMPDIR/.ops_actual" "$TMPDIR/.notify_expect" "$TMPDIR/.notify_actual" "$TMPDIR/.notify_mismatch" "$TMPDIR/.notify_pending" "$TMPDIR/.battery_expect" "$TMPDIR/.battery_actual" "$_verify_batch_in" "$_verify_batch_out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
}
# 取得當前正在後台運行的所有 app 列表
# 配合「後台應用忽略」設定, 跳過正在運行的 app 不備份
Background_application_list() {
	[[ $activity != false ]] && {
	if [[ $Background_apps_ignore = true || $1 = debug ]]; then
		unset Backstage
		#獲取後台
		Backstage="$(dumpsys activity activities | awk -v uid="$user" '/ActivityRecord\{/{split($4,a,"/"); user=$3; pkg=a[1]; if(user~/^u[0-9]+$/ && pkg!~/\//){sub(/^u/,"",user); if(uid=="" || user==uid) if(!seen[user","pkg]++) print pkg}}')"
		if [[ $Backstage = "" ]]; then
			Backstage="$(am stack list | awk -v uid="$user" '/taskId/&&!/unknown/{split($2,a,"/"); pkg=a[1]; user="unknown"; for(i=1;i<=NF;i++) if($i~/^userId=/){split($i,b,"="); user=b[2]; break} if(uid==""||user==uid) if(!seen[pkg]++) print pkg}')"
			[[ $Backstage = "" ]] && {
			echoRgb "獲取當前後台應用失敗" "0" && unset Backstage
			}
		fi
	fi
	}
}
Background_application_list debug
pkgs="$(pm list packages --user "$user" | cut -f2 -d ':' | awk -v pkg="$(echo "$Backstage" | head -1)" '$1 == pkg {print $1}')"
if [[ $pkgs != "" ]]; then
	echoRgb "後台應用獲取成功($pkgs)" "1"
	[[ $(Process_Information "$pkgs") = "" ]] && echoRgb "應用pid獲取失敗" "0" || echoRgb "應用pid獲取成功$(Process_Information "$pkgs")" "1"
else
	echoRgb "後台應用獲取失敗" "0" activity=false
fi
unset Backstage
# ======================================================
# backup() 主函數
# ======================================================
# 主備份函數 - 對 appList.txt 內所有 app 執行完整備份
# 流程: 讀清單 → 逐個 app → 備份 apk + data + user_de + obb → 備份 SSAID/權限
# 結尾備份 wifi、生成 start.sh、設置 REMOTE_TRIGGER=1 觸發遠端上傳
# ============================================================
# SpeedBackup single-file section: sb_60_backup_main_media_stats.sh
# ============================================================
backup() {
	self_test
	case $MODDIR in
	/storage/emulated/0/Android/* | /data/media/0/Android/* | /sdcard/Android/*) echoRgb "請勿在$MODDIR內備份" "0" && exit 2 ;;
	esac
	case $Compression_method in
	zstd | Zstd | ZSTD | tar | Tar | TAR) ;;
	*) echoRgb "$Compression_method為不支持的壓縮算法" "0" && exit 2 ;;
	esac
	# 流式上傳路徑快取: 在 Compression_method 還未被 Backup_data() 暫時污染前固定一次
	_BACKUP_DIRNAME_CACHED="$(get_backup_dirname)"
	prepare_pkg_uid_map
	prepare_pkg_ver_map
	load_kv_map "$TMPDIR/.pkg_uid" _pu
	load_kv_map "$TMPDIR/.pkg_ver" _pv
	: > "$TMPDIR/.backup_done"
	: > "$TMPDIR/.update_apks"
	: > "$TMPDIR/.add_apks"
	: > "$TMPDIR/.ssaid_apks"
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
	backup_path
	show_conf backup
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
			app=($REPLY $REPLY)
			if [[ ${app[1]} != "" && ${app[2]} != "" ]]; then
				if [[ $(echo "$Apk_info" | awk -v pkg="${app[1]}" '$1 == pkg {print $1}') != "" ]]; then
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
	txt2="$Backup/appList.txt"
	txt_path2="$txt2"
	[[ ! -f $txt2 ]] && echo "#不需要恢復還原的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market">"$txt2"
	txt2="$(cat "$txt2")"
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
		ssaid_info="$(get_ssaid "$(jq -r '.[] | select(.PackageName != null).PackageName' "${0%/*}/app_details.json")")"
		# 單獨備份模式: 只預掃這一個 app 的權限
		local _single_pkg
		_single_pkg="$(jq -r '.[] | select(.PackageName != null).PackageName' "${0%/*}/app_details.json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		# 單獨備份也走批量同一套預掃/解析邏輯，避免 inline jq 解析差異導致 permissions/notification_settings 漏寫。
		prepare_permissions_map "$_single_pkg"
		prepare_notifications_map "$_single_pkg"
		prepare_pkg_installer_map "$_single_pkg"
		prepare_install_diagnostics_map "$_single_pkg"
		prepare_battery_settings_map "$_single_pkg"
		prepare_battery_whitelist "$_single_pkg"
		prepare_remote_filelist
		prepare_remote_scripts_map
		prepare_remote_json_map
		load_kv_map "$TMPDIR/.pkg_perms" _pp
		load_kv_map "$TMPDIR/.pkg_notify" _pn
		load_kv_map "$TMPDIR/.pkg_installer" _pi
		load_kv_map "$TMPDIR/.install_diag" _id
		load_kv_map "$TMPDIR/.battery_wl" _bw
		load_kv_map "$TMPDIR/.pkg_battery" _bs
	else
		ssaid_info="$(get_ssaid "$(echo "$txt" | awk '{printf "%s ", $2}')")"
		prepare_permissions_map
		prepare_notifications_map
		prepare_pkg_installer_map
		prepare_install_diagnostics_map
		prepare_battery_settings_map
		prepare_battery_whitelist
		prepare_dir_size_map
		load_dir_size_map
		prepare_remote_filelist
		prepare_remote_scripts_map
		prepare_remote_json_map
		load_kv_map "$TMPDIR/.pkg_perms" _pp
		load_kv_map "$TMPDIR/.pkg_notify" _pn
		load_kv_map "$TMPDIR/.pkg_installer" _pi
		load_kv_map "$TMPDIR/.install_diag" _id
		load_kv_map "$TMPDIR/.battery_wl" _bw
		load_kv_map "$TMPDIR/.pkg_battery" _bs
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
			ChineseName="$(jq -r 'try (([.[] | objects | select(.PackageName != null)] | length) as $n | if $n > 0 then (to_entries[] | select(.value.PackageName != null).key) else (to_entries[] | select(.key != null).key) end) catch "" // ""' "${0%/*}/app_details.json" | head -n 1)"
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
			[[ $Backstage != "" && $(echo "$Backstage" | grep -Ew "^$name2$") != "" ]] && echoRgb "$name1存在後台 忽略備份" "0" && nobackup="true"
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
			# 一次讀取 app_details.json 所有欄位 (APK_VER / SSAID_OLD / PERMS_OLD / PKG_NAME / BACKUP_TIME / SIZE_*)
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
					if remote_download_single_file "$name1/app_details.json" "$_mergetmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && \
						[[ "$(head -c 1 "$_mergetmp" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})" = "{" ]]; then
						if jq -s '.[0] * .[1]' "$_mergetmp" "$app_details" > "$_mergetmp.out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} && \
							[[ -s $_mergetmp.out ]]; then
							cat "$_mergetmp.out" > "$app_details"
						fi
					fi
					rm -f "$_mergetmp" "$_mergetmp.out" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				fi
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
			echoRgb "完成$(safe_percent "$i" "$r")% $(progress_bar $(safe_percent "$i" "$r"))$([[ $remote_stream != 1 ]] && echo " $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')")" "3"
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
			if [[ -f "$TMPDIR/.ssaid_apks" ]]; then SSAID_apk2="$(cat "$TMPDIR/.ssaid_apks" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"; else SSAID_apk2=""; fi
			update_apk2="${update_apk2:=" -暫無更新"}"
			add_app2="${add_app2:=" -暫無更新"}"
			echoRgb "\n -已更新的apk=\"$osn\"\n -已新增的備份=\"$osk\"\n -apk版本號無變化=\"$osj\"\n -下列為版本號已變更的應用\n$update_apk2\n -新增的備份....\n$add_app2\n -包含SSAID的應用\n$SSAID_apk2" "3"
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
			rm -f "$TMPDIR/.backup_done" "$TMPDIR/.update_apks" "$TMPDIR/.add_apks" "$TMPDIR/.ssaid_apks" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
			if [[ $backup_media = true && ! -f ${0%/*}/app_details.json ]]; then
				A=1
				B="$(printf "%s\n" "$Custom_path" | awk '!/[#＃]/ && NF{count++} END{print count}')"
				if [[ $B != "" ]]; then
					echoRgb "備份結束，備份多媒體" "1"
					notification_progress "102" "$B" 0 "Media備份開始"
					starttime1="$(date -u "+%s")"
					Backup_folder="$Backup/Media"
					app_details="$Backup_folder/app_details.json"
					if [[ $remote_stream = 1 && -n $remote_type ]]; then
						_STREAM_DEST="Media"; Backup_folder="$TMPDIR/.stream_stage/Media"; app_details="$Backup_folder/app_details.json"; mkdir -p "$Backup_folder" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
					fi
					mediatxt="$Backup/mediaList.txt"
					# 延遲建立: 只有實際備份了至少一個資料夾才建立 (避免空殼)
					_media_created=0
					_ensure_media_dirs() {
						[[ $_media_created = 1 ]] && return
						[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
						[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
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
						echoRgb "完成$(safe_percent "$A" "$B")% $(progress_bar $(safe_percent "$A" "$B"))$([[ $remote_stream != 1 ]] && echo " $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')")" "2"
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
		unset _restore_force_play_session
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
			_has_ssaid="$(jq -r 'try ([.[] | objects | select(.Ssaid != null)] | length) catch 0' "$_jf" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
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
	_total_json="$(grep -vc '^$' "$_apps")"
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
	local _running=0 _i=0
	while read -r _ra; do
		[[ -z $_ra ]] && continue
		let _i++
		printf '\r -下載中 %d/%d' "$_i" "$_total_json" >&2
		( remote_download_single_file "$_ra/app_details.json" "$TMPDIR/.remote_stats_dl/$_ra.json" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} ) &
		let _running++
		if [[ $_running -ge 8 ]]; then wait; _running=0; fi
	done < "$_apps"
	wait
	echo >&2
	local _valid_json=0 _ssaid_cnt=0
	while read -r _ra; do
		[[ -z $_ra ]] && continue
		local _jf="$TMPDIR/.remote_stats_dl/$_ra.json"
		if [[ -s $_jf ]] && jq -e . "$_jf" >/dev/null 2>&1; then
			let _valid_json++
			local _has_ssaid
			_has_ssaid="$(jq -r 'try ([.[] | objects | select(.Ssaid != null)] | length) catch 0' "$_jf" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
			[[ ${_has_ssaid:-0} -gt 0 ]] && let _ssaid_cnt++
		fi
	done < "$_apps"
	rm -rf "$TMPDIR/.remote_stats_dl" "$_filelist" "$_apps" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	echoRgb "應用數量: $_app_cnt 個" "2"
	[[ $_media_cnt -gt 0 ]] && echoRgb "媒體/自訂資料夾: $_media_cnt 個" "2"
	echoRgb "檔案總數: ${_filecount:-0} 個" "2"
	echoRgb "備份總大小: $(size "${_totalsize:-0}")" "2"
	echoRgb "含SSAID的應用: $_ssaid_cnt 個" "2"
	if [[ $_valid_json -eq $_total_json ]]; then
		echoRgb "JSON有效率: $_valid_json/$_total_json (全數正常)" "1"
	else
		echoRgb "JSON有效率: $_valid_json/$_total_json (有 $((_total_json - _valid_json)) 個損壞或無法下載)" "0"
	fi
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
	# 遠端備份子目錄 (Backup_zstd_X)
	_RESTORE_SUBDIR="$(get_backup_dirname)"
	echoRgb "流式恢復來源: $remote_type://$REMOTE_HOST/ ($_RESTORE_SUBDIR)" "3"
	echoRgb "清單: $list" "2"
	# 設流式恢復旗標, 復用 Restore 全流程
	_RESTORE_STREAM=1
	mkdir -p "$TMPDIR/.restore_stage" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	Restore
	# 清理 staging (只有 json, 數據從未落地)
	rm -rf "$TMPDIR/.restore_stage" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	_RESTORE_STREAM=0
}
# ============================================================
# SpeedBackup single-file section: sb_70_restore_menu_entry.sh
# ============================================================
Restore() {
	self_test
	disable_verify
	[[ ! -d $path2 ]] && echoRgb "設備不存在user目錄" "0" && exit 1
	# 預掃資料 (取代主迴圈內每 app fork)
	prepare_pkg_uid_map
	prepare_pkg_ver_map
	prepare_installed_pkgs_map
	# v24.20.14-7.6：恢復主迴圈期間必須保留 session maps。
	# Release_data() 會在每個 tar 解壓後呼叫 cleanup_tmpdir_contents()；
	# 若此 flag 沒有開啟，第 1 個 app 後 .installed_pkgs/.pkg_ver/.pkg_uid 會被刪除，
	# 第 2 個 app 起就會誤判為未安裝並重跑 APK 安裝。
	_RESTORE_KEEP_SESSION_MAPS=1
	_speed_debug_log "RESTORE_SESSION_MAP_KEEP_BEGIN keep=$_RESTORE_KEEP_SESSION_MAPS installed=$(wc -l < "$TMPDIR/.installed_pkgs" 2>/dev/null) pkg_ver=$(wc -l < "$TMPDIR/.pkg_ver" 2>/dev/null) pkg_uid=$(wc -l < "$TMPDIR/.pkg_uid" 2>/dev/null)"
	# 初始化恢復 SSAID 動態批量變量 (v24.20.14-7.63：恢復舊版一次 JVM 批量參數，不依賴 TMP 清單)
	_ssaid_restore_accum_reset
	if [[ ! -f ${0%/*}/app_details.json ]]; then
		echoRgb "假設反悔了要終止腳本請儘速離開此腳本點擊$MODDIR_NAME/start.sh選擇終止腳本\n -否則腳本將繼續執行直到結束" "0"
		echoRgb "如果大量提示找不到資料夾請執行$MODDIR_NAME/start.sh選擇轉換資料夾名稱"
		txt="$MODDIR/appList.txt"
		# 流式恢復: 改用 appList_network.txt (功能8 產生), 過濾掉註解與特殊項(wifi/Media), 只留 app 行
		if [[ $_RESTORE_STREAM = 1 ]]; then
			grep -Ev '^[[:space:]]*[#＃]|^[[:space:]]*$' "$MODDIR/appList_network.txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} \
				| grep -Evx '[[:space:]]*(wifi|Media)[[:space:]]*' > "$TMPDIR/.stream_restore_list"
			txt="$TMPDIR/.stream_restore_list"
		fi
		[[ ! -f $txt ]] && echoRgb "請執行start.sh獲取應用列表再來恢復" "0" && exit 2
		sort -u "$txt" -o "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		i=1
		r="$(awk '!/[#＃]/ && NF{count++} END{print count}' "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		[[ $r = "" ]] && echoRgb "appList.txt包名為空或是被注釋了\n -請執行start.sh獲取應用列表再來恢復" "0" && exit 1
		Backup_folder2="$MODDIR/Media"
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
		if [[ -d $Backup_folder2 ]]; then
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
					case "$_reply_line" in !play[[:space:]]*|！play[[:space:]]*) _reply_line="${_reply_line#*!play}"; _reply_line="${_reply_line#*！play}"; _reply_line="${_reply_line# }" ;; esac
					app=($_reply_line $_reply_line)
					_apk_pkg="${app[1]}"
					if [[ ${app[1]} != "" && ${app[2]} != "" ]]; then
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
				if [[ $(jq -r 'try (.[] | select(.Ssaid != null).Ssaid) catch ""' "$REPLY" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}) != "" ]]; then
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
			ChineseName="$(jq -r 'try (([.[] | objects | select(.PackageName != null)] | length) as $n | if $n > 0 then (to_entries[] | select(.value.PackageName != null).key) else (to_entries[] | select(.key != null).key) end) catch "" // ""' "$app_details" | head -n 1)"
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
	# 啟用權限批量模式: 迴圈內 restore_permissions 只收集到暫存檔, 迴圈結束後 flush 一次沖刷；單 app/外部呼叫會自動臨時 batch+flush
	# 此迴圈同時服務批量恢復(N個app)與單獨恢復(1個app); 單獨恢復時收集1組→flush設1組, 等價立即執行
	_batch_perm_mode=1
	# 清空本輪批量恢復暫存，installer/通知/電池也一併清，避免同一 shell session 內殘留
	rm -f "$TMPDIR/.batch_grant" "$TMPDIR/.batch_revoke" "$TMPDIR/.batch_ops" "$TMPDIR/.batch_media_access" "$TMPDIR/.batch_location_access" "$TMPDIR/.batch_opsreset" \
		"$TMPDIR/.batch_installer" "$TMPDIR/.batch_clear_installer" "$TMPDIR/.batch_notify" "$TMPDIR/.batch_notify_verify" "$TMPDIR/.batch_battery" "$TMPDIR/.batch_install_compare" \
		"$TMPDIR/.batch_pflags" "$TMPDIR/.batch_ask_access"
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
			case "$_line" in
			!play[[:space:]]*|！play[[:space:]]*)
				_restore_force_play_session=1
				_line="${_line#*!play}"
				_line="${_line#*！play}"
				_line="${_line# }"
				;;
			esac
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
			fi
			if [[ -f "$Backup_folder/app_details.json" ]]; then
				app_details="$Backup_folder/app_details.json"
				apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
				# 流式: 列表(appList_network.txt)只有資料夾名, 包名 name2 從 json 的 PackageName 取
				if [[ $_RESTORE_STREAM = 1 ]]; then
					name2="$(jq -r '.[] | select(.PackageName != null).PackageName' "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
				fi
			else
				echoRgb "$Backup_folder/app_details.json不存在" "0"
			fi
			[[ $name2 = "" ]] && echoRgb "應用包名獲取失敗" "0" && exit 1
		fi
		# 流式恢復: Backup_folder 是 staging (只有 json), 視為存在以進入恢復流程
		if [[ -d $Backup_folder ]] || [[ $_RESTORE_STREAM = 1 ]]; then
			echoRgb "恢復$name1" "2"
			Background_application_list
			restore="true"
			[[ $Backstage != "" && $(echo "$Backstage" | grep -Ew "^$name2$") != "" ]] && echoRgb "$name1存在後台 忽略恢復" "0" && restore="false"
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
						# 流式恢復也要納入 thanox.tar(.zst)，否則 Thanox 的 /data/system/thanos* 配置只會在本地恢復時處理
						for _dt in user data obb user_de thanox; do
							# 只恢復遠端 json 有記錄的資料 (Size 存在表示有備份)
							local _has
							_has="$(jq -r --arg k "$_dt" 'try .[$k].Size catch "" // ""' "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
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
					restore_permissions
					Ssaid="$_rp_ssaid"
					if [ -n "$Ssaid" ] && [ "$Ssaid" != "null" ]; then
						_ssaid_restore_accum_append "$name1" "$name2" "$Ssaid"
						unset Ssaid
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
			if [ "${_SSAID_RESTORE_COUNT:-0}" -gt 0 ]; then
				echoRgb "開始恢復SSAID" "2"
				_restore_ssaid_report
			fi
			notification_progress "105" "$r" "$r" "app恢復完成 $(endtime 1 "應用恢復" "2")"
			[[ ! -f ${0%/*}/app_details.json ]] && {
			if [[ $media_recovery = true ]]; then
				starttime1="$(date -u "+%s")"
				app_details="$Backup_folder2/app_details.json"
				txt="$MODDIR/mediaList.txt"
				sort -u "$txt" -o "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
				A=1
				B="$(awk '!/[#＃]/ && NF{count++} END{print count}' "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
				[[ $B = "" ]] && echoRgb "mediaList.txt壓縮包名為空或是被注釋了\n -請執行start.sh獲取列表再來恢復" "0" && B=0
				notification_progress "106" "$B" 0 "Media恢復開始"
				while [[ $A -le $B ]]; do
					name1="$(awk -v n=$A '!/[#＃]/ && NF{c++} c==n{print $1; exit}' "$txt" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
					starttime2="$(date -u "+%s")"
					echoRgb "恢復第$A/$B個壓縮包 剩下$((B - A))個" "3"
					Release_data "$Backup_folder2/$name1"
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
		unset _restore_force_play_session
		let i++ en++ nskg++
	done
	# 迴圈結束: 一次批量設置所有 app 的權限 (grant/revoke/ops 各一次 JVM)
	flush_batch_permissions
	# 復位: 確保批量模式不外溢；非迴圈直接呼叫 restore_permissions 時函式內會自動臨時 batch+flush
	_batch_perm_mode=0
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
	echo_log() {
		if [[ $? = 0 ]]; then
			echoRgb "$1成功" "1" && result=0
		else
			echoRgb "$1恢復失敗，過世了" "0" && result=1
		fi
	}
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
_ssaid_restore_accum_reset() {
	# v24.20.14-7.63：恢復舊版動態變量批量 SSAID 參數。
	# 目的：保留一次 JVM 批量 set/get，同時避免 TMP 清單在 data 恢復流程中被清掉而漏 app。
	_SSAID_RESTORE_SET_ARGS=""
	_SSAID_RESTORE_GET_ARGS=""
	_SSAID_RESTORE_EXPECTED=""
	_SSAID_RESTORE_COUNT=0
	if [ -n "${SPEED_DEBUG_RUN_DIR:-}" ] && [ -d "$SPEED_DEBUG_RUN_DIR" ]; then
		: > "$SPEED_DEBUG_RUN_DIR/ssaid_restore_collect.log" 2>/dev/null
	fi
}

_ssaid_restore_accum_append() {
	# 參數：app_name package ssaid
	local _tab _line
	[ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] || return 0
	_tab="$(printf '\t')"
	_line="$1$_tab$2$_tab$3"
	if [ -z "${_SSAID_RESTORE_EXPECTED:-}" ]; then
		_SSAID_RESTORE_EXPECTED="$_line"
	else
		_SSAID_RESTORE_EXPECTED="$_SSAID_RESTORE_EXPECTED
$_line"
	fi
	if [ -z "${_SSAID_RESTORE_SET_ARGS:-}" ]; then
		_SSAID_RESTORE_SET_ARGS="$2 $3"
		_SSAID_RESTORE_GET_ARGS="$2"
	else
		_SSAID_RESTORE_SET_ARGS="$_SSAID_RESTORE_SET_ARGS $2 $3"
		_SSAID_RESTORE_GET_ARGS="$_SSAID_RESTORE_GET_ARGS $2"
	fi
	_SSAID_RESTORE_COUNT=$((${_SSAID_RESTORE_COUNT:-0}+1))
	[ -n "${SPEED_DEBUG_RUN_DIR:-}" ] && [ -d "$SPEED_DEBUG_RUN_DIR" ] && printf 'COLLECT\t%s\t%s\t%s\n' "$1" "$2" "$3" >> "$SPEED_DEBUG_RUN_DIR/ssaid_restore_collect.log" 2>/dev/null
}

_restore_ssaid_report() {
	# v24.20.14-7.63：SSAID set/get 使用動態變量批量參數，各一次 JVM。
	# 預期清單也保存在 shell 變量中；只在報告階段落地到 debug 暫存，避免恢復迴圈中被 TMP 清理影響。
	local _out _line _expect _actual _name1 _name2 _ok=0 _warn=0 _fail=0 _skip=0 _set_rc _info _tab
	local _tmp_expected _tmp_readback _count
	_tab="$(printf '\t')"
	[ -n "${SPEED_DEBUG_RUN_DIR:-}" ] && [ -d "$SPEED_DEBUG_RUN_DIR" ] && _out="$SPEED_DEBUG_RUN_DIR/ssaid_restore_verify.log" || _out=""
	[ -n "$_out" ] && {
		: > "$_out" 2>/dev/null
		printf '# SSAID restore verify\n# 狀態分級：一致 / 已寫入但讀回不同 / 寫入失敗 / 無備份值略過\n# v24.20.14-7.63：動態變量累積 batch args，set/get 各一次 JVM；不依賴 TMP 清單。\n' >> "$_out" 2>/dev/null
	}
	_count="${_SSAID_RESTORE_COUNT:-0}"
	if [ "$_count" -le 0 ] || [ -z "${_SSAID_RESTORE_SET_ARGS:-}" ] || [ -z "${_SSAID_RESTORE_GET_ARGS:-}" ] || [ -z "${_SSAID_RESTORE_EXPECTED:-}" ]; then
		echoRgb "- SSAID無備份值，已略過" "2"
		[ -n "$_out" ] && printf 'SKIP\tSSAID無備份值，已略過\nSUMMARY\tok=0\twarn=0\tfail=0\tskip=1\n' >> "$_out" 2>/dev/null
		return 0
	fi
	_tmp_expected="$TMPDIR/.ssaid_expected_$$"
	_tmp_readback="$TMPDIR/.ssaid_readback_$$"
	printf '%s\n' "$_SSAID_RESTORE_EXPECTED" > "$_tmp_expected" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	: > "$_tmp_readback" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	if [ ! -s "$_tmp_expected" ]; then
		echoRgb "- SSAID無備份值，已略過" "2"
		[ -n "$_out" ] && printf 'SUMMARY\tok=0\twarn=0\tfail=0\tskip=1\n' >> "$_out" 2>/dev/null
		rm -f "$_tmp_expected" "$_tmp_readback" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		return 0
	fi
	[ -n "$_out" ] && printf 'BATCH\tmode=dynamic_args\tset_args_packages=%s\tget_args_packages=%s\n' "$_count" "$_count" >> "$_out" 2>/dev/null
	# 一次 JVM 批量寫入；沿用舊版 SsaidUtil set 參數格式："pkg ssaid pkg ssaid ..."。
	_dex_raw /system/bin com.xayah.dex.SsaidUtil set "$USER_ID" "$_SSAID_RESTORE_SET_ARGS" >/dev/null
	_set_rc=$?
	# 一次 JVM 批量讀回；沿用舊版 SsaidUtil get 參數格式："pkg pkg ..."。
	_info="$(_dex_raw /system/bin com.xayah.dex.SsaidUtil get "$USER_ID" "$_SSAID_RESTORE_GET_ARGS")"
	printf '%s\n' "$_info" > "$_tmp_readback" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	while IFS="$_tab" read -r _name1 _name2 _expect _line; do
		[ -n "$_name2" ] || continue
		if [ -z "$_expect" ] || [ "$_expect" = "null" ]; then
			echoRgb "$_name1 SSAID: 無備份值，略過" "2"
			[ -n "$_out" ] && printf 'SKIP\t%s\t%s\tSSAID無備份值\n' "$_name1" "$_name2" >> "$_out" 2>/dev/null
			_skip=$((_skip+1))
			continue
		fi
		_actual="$(awk -v pkg="$_name2" '$1 == pkg {print $2; exit}' "$_tmp_readback" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
		[ -n "$_out" ] && printf 'APP\t%s\t%s\tbackup=%s\tactual=%s\tbatch_set_rc=%s\n' "$_name1" "$_name2" "$_expect" "$_actual" "$_set_rc" >> "$_out" 2>/dev/null
		if [ "$_actual" = "$_expect" ]; then
			echoRgb "$_name1 ✅ SSAID一致" "1"
			[ -n "$_out" ] && printf 'OK\t%s\t%s\tSSAID讀回一致\n' "$_name1" "$_name2" >> "$_out" 2>/dev/null
			_ok=$((_ok+1))
		elif [ "$_set_rc" -eq 0 ] && [ -n "$_actual" ] && [ "$_actual" != "null" ]; then
			echoRgb "$_name1 ⚠️ SSAID已寫入，但目前讀回仍不同，可能需強制停止/重開App或重啟手機後生效" "2"
			[ -n "$_out" ] && printf 'WARN\t%s\t%s\tSSAID已寫入但讀回不同，可能需重啟後生效\n' "$_name1" "$_name2" >> "$_out" 2>/dev/null
			_warn=$((_warn+1))
		else
			echoRgb "$_name1 ❌ SSAID寫入失敗或讀回失敗，詳情見speed_debug" "0"
			[ -n "$_out" ] && printf 'FAIL\t%s\t%s\tSSAID寫入失敗或讀回失敗\n' "$_name1" "$_name2" >> "$_out" 2>/dev/null
			_fail=$((_fail+1))
		fi
	done < "$_tmp_expected"
	rm -f "$_tmp_expected" "$_tmp_readback" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
	echoRgb "SSAID摘要: 一致=$_ok 需重啟確認=$_warn 失敗=$_fail 略過=$_skip" "2"
	[ -n "$_out" ] && printf 'SUMMARY\tok=%s\twarn=%s\tfail=%s\tskip=%s\tbatch_set_rc=%s\n' "$_ok" "$_warn" "$_fail" "$_skip" "$_set_rc" >> "$_out" 2>/dev/null
	if [ "$_warn" -gt 0 ]; then
		echoRgb "⚠️ SSAID已寫入但讀回不同的應用，請先強制停止/重開App；仍不一致再重啟手機" "2"
		notification "107" "SSAID已寫入但部分應用可能需重啟後生效"
	elif [ "$_ok" -gt 0 ]; then
		echoRgb "✅ SSAID讀回一致；若個別App仍讀舊值，請強制停止後重開App" "1"
	fi
}

# 僅恢復包含 SSAID 應用 (不含數據,只裝 apk + 還原 SSAID)
# 用於只想保留遊戲帳號識別、不要舊存檔的場景
Restore4() {
	if [[ $ssaid_mode_1 = true ]]; then
		_ssaid_restore_accum_reset
		_ssaid_details_list="$TMPDIR/.ssaid_details_list"
		find "$MODDIR" -maxdepth 2 -name "app_details.json" -type f 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null} | sort > "$_ssaid_details_list"
		while read -r; do
			if [[ $(jq -r '.[] | select(.Ssaid != null).Ssaid' "$REPLY") != "" ]]; then
				ChineseName="$(jq -r 'try (([.[] | objects | select(.PackageName != null)] | length) as $n | if $n > 0 then (to_entries[] | select(.value.PackageName != null).key) else (to_entries[] | select(.key != null).key) end) catch "" // ""' "$REPLY" | head -n 1)"
				PackageName="$(jq -r '.[] | select(.PackageName != null).PackageName' "$REPLY")"
				if [[ $ssaid_name = "" ]]; then
					ssaid_name="$ChineseName $PackageName"
				else
					ssaid_name="$ssaid_name\n$ChineseName $PackageName"
				fi
			fi
		done < "$_ssaid_details_list"
		rm -f "$_ssaid_details_list" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		[[ $ssaid_name != "" ]] && txt="$ssaid_name"
		i=1
		[[ $(echo "$txt") != "" ]] && txt="$(echo "$txt" | sed -e '/^$/d')"
		r="$(echo "$txt" | awk 'NF != 0 { count++ } END { print count }')"
		while [[ $i -le $r ]]; do
			_line="$(echo "$txt" | sed -n "${i}p")"
			name1="${_line%% *}"
			name2="${_line#* }"
			name2="${name2%% *}"
			unset _line
			Backup_folder="$MODDIR/$name1"
			if [[ -f "$Backup_folder/app_details.json" ]]; then
				app_details="$Backup_folder/app_details.json"
				apk_version="$(jq -r '.[] | select(.apk_version != null).apk_version' "$app_details")"
			else
				echoRgb "$Backup_folder/app_details.json不存在" "0"
			fi
			[[ $name2 = "" ]] && echoRgb "應用包名獲取失敗" "0" && exit 1
			if [[ $(pm list packages --user "$user" | awk -v pkg="$name2" -F':' '$2 == pkg {print $2}') != "" ]]; then
				[[ $name2 != *mt* ]] && {
				kill_app
				Ssaid="$(jq -r 'try ([.[] | objects | select(.Ssaid != null and .Ssaid != "" and .Ssaid != "null").Ssaid] | .[0]) catch "" // ""' "$app_details" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null})"
				if [ -n "$Ssaid" ] && [ "$Ssaid" != "null" ]; then
					_ssaid_restore_accum_append "$name1" "$name2" "$Ssaid"
					unset Ssaid
				fi
				}
			fi
			if [[ $i = $r ]]; then
				if [ "${_SSAID_RESTORE_COUNT:-0}" -gt 0 ]; then
					echoRgb "開始恢復SSAID" "2"
					_restore_ssaid_report
				fi
			fi
			let i++
		done
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
	TARGET_PACKAGES="$(echo "$system" | paste -sd'|' - | sed 's/^|//')"
	Pre_installed_apps="$(echo "$Apk_info" | awk 'index("|" $3 "|", "|system|") {print $1, $2}' | grep -Ew "$TARGET_PACKAGES")"
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
	wait
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
		if [[ $remote_stream = 1 && -n $remote_type ]]; then
			_STREAM_DEST="Media"; Backup_folder="$TMPDIR/.stream_stage/Media"; app_details="$Backup_folder/app_details.json"; mkdir -p "$Backup_folder" 2>>${SPEED_DEBUG_ERR_LOG:-/dev/null}
		fi
		mediatxt="$Backup/mediaList.txt"
		# 延遲建立: 只有實際備份了至少一個資料夾才建立 Media/txt 等 (避免空殼)
		_media_created=0
		_ensure_media_dirs() {
			[[ $_media_created = 1 ]] && return
			[[ ! -d $Backup_folder ]] && mkdir -p "$Backup_folder"
			[[ ! -f $Backup/start.sh ]] && touch_shell "2" "$Backup/start.sh"
			[[ ! -d $Backup/tools ]] && cp -r "$tools_path" "$Backup"
			[[ ! -f $Backup/restore_settings.conf ]] && update_Restore_settings_conf>"$Backup/restore_settings.conf"
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
			echoRgb "完成$(safe_percent "$A" "$B")% $(progress_bar $(safe_percent "$A" "$B"))$([[ $remote_stream != 1 ]] && echo " $hx$(echo "$Occupation_status" | awk 'END{print "剩餘:"$1"使用率:"$2}')")" "2" && echoRgb "____________________________________" && let A++
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
# 從 tools/Device_List 對照表查詢設備識別資訊 (處理器型號、RAM 規格等)
Device_List() {
	URL="https://raw.githubusercontent.com/KHwang9883/MobileModels/refs/heads/master/brands"
	rm -rf "$tools_path/Device_List"
	for i in $(echo "xiaomi\nxiaomi_en\nsamsung\nsamsung_global\nasus\nBlack_Shark\nBlack_Shark_en\ngoogle\nLenovo\nMEIZU\nMEIZU_en\nMotorola\nNokia\nnothing\nnubia\nOnePlus\nOnePlus_en\nSony\nrealme\nrealme_en\nvivo\nvivo_en\noppo\noppo_en"); do
		echoRgb "獲取品牌$i"
		case $i in
		xiaomi) Brand_URL="$URL/xiaomi.md" ;;
		xiaomi_en) Brand_URL="$URL/xiaomi_en.md" ;;
		samsung) Brand_URL="$URL/samsung_cn.md" ;;
		samsung_global) Brand_URL="$URL/samsung_global_en.md" ;;
		asus) Brand_URL="$URL/asus.md" ;;
		Black_Shark) Brand_URL="$URL/blackshark.md" ;;
		Black_Shark_en) Brand_URL="$URL/blackshark_en.md" ;;
		google) Brand_URL="$URL/google.md" ;;
		Lenovo) Brand_URL="$URL/lenovo.md" ;;
		MEIZU) Brand_URL="$URL/meizu.md" ;;
		MEIZU_en) Brand_URL="$URL/meizu_en.md" ;;
		Motorola) Brand_URL="$URL/motorola.md" ;;
		Nokia) Brand_URL="$URL/nokia.md" ;;
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
			down "$Brand_URL" | grep -oE '`[^`]+`:[^`]*' | sed -E 's/: /:/g' | sed -E 's/`([^`]+)`:(.*)/"\1" "\2"/'>"$tools_path/Device_List"
		else
			down "$Brand_URL" | grep -oE '`[^`]+`:[^`]*' | sed -E 's/: /:/g' | sed -E 's/`([^`]+)`:(.*)/"\1" "\2"/' | while read -r; do
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
	if [[ -f $MODDIR/backup_settings.conf ]]; then
		steps=(
			"生成應用列表"
			"備份應用"
			"備份已更新應用"
			"備份自定義資料夾"
			"備份WiFi"
			"測試遠端連線"
			"單獨上傳當前備份"
			"列出遠端備份(產生 appList_network.txt)"
			"從遠端下載備份"
			"從遠端流式恢復(不佔本機)"
			"目前備份統計"
			"殺死運行中腳本"
		)
		# 備份類 commands 結尾用 "; exit" 確保跑完退出主 shell, 而非回到選單
		commands=(
			"Getlist"
			"backup; exit"
			"backup_update_apk; exit"
			"backup_media; _rc=$?; _speed_debug_normal_finish_pack $_rc; exit $_rc"
			"wifi; _rc=$?; _speed_debug_normal_finish_pack $_rc; exit $_rc"
			"remote_test"
			"upload_current_backup"
			"remote_list_backups"
			"remote_download_backup"
			"remote_stream_restore; _rc=$?; _speed_debug_normal_finish_pack $_rc; exit $_rc"
			"Stats_Dispatch"
			"echoRgb '等待腳本停止中，請稍後.....' && echoRgb '腳本終止'; exit"
		)
	elif [[ -f $MODDIR/restore_settings.conf ]]; then
		steps=(
			"重新生成應用列表"
			"恢復備份"
			"僅恢復包含ssaid應用(含數據)"
			"僅恢復包含ssaid應用(不含數據)"
			"恢復自定義資料夾"
			"恢復wifi"
			"壓縮檔完整性檢查"
			"JSON結構檢查"
			"轉換文件夾名稱"
			"殺死運行中腳本"
		)
		# 恢復類 commands 結尾用 "; exit" 確保跑完退出
		commands=(
			"dumpname"
			"Restore; exit"
			"ssaid_mode=true && Restore; exit"
			"ssaid_mode_1=true && Restore4; _rc=$?; _speed_debug_normal_finish_pack $_rc; exit $_rc"
			"Restore3; _rc=$?; _speed_debug_normal_finish_pack $_rc; exit $_rc"
			"recover_wifi \"$MODDIR/wifi\"; _rc=$?; _speed_debug_normal_finish_pack $_rc; exit $_rc"
			"check_file"
			"Check_json"
			"convert"
			"echoRgb '等待腳本停止中，請稍後.....' && echoRgb '腳本終止'; exit"
		)
	fi
	echoRgb "請選擇要執行的操作："
	for i in "${!steps[@]}"; do
		printf " -%d) %s\n" "$((i+1))" "${steps[$i]}"
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
	[1-9]*)
		if (( choice >= 1 && choice <= ${#steps[@]} )); then
			index="$((choice - 1))"
			echo " -執行：${steps[$index]}"
			background="$(grep -o 'background_execution=.*' "$conf_path" | awk -F '=' '{print $2}')"
			if [[ "$background" = "1" ]]; then
				# 後台執行: 用 subshell 防 exit 殺主 shell
				(eval "${commands[$index]}") &
				bg_pid=$!
				# 不論動作類型都 wait, 確保主選單不會被子進程輸出蓋掉
				wait "$bg_pid"
				# 備份/恢復類動作 (commands 含 exit) 跑完整個腳本退出
				case ${commands[$index]} in
				*exit*) exit 0 ;;
				esac
			else
				# 前台: 不包 subshell, command 內的 exit 會真的退出整個腳本
				# (備份類 commands 結尾有 exit, 達成「跑完就退出」)
				eval "${commands[$index]}"
			fi
		else
			echoRgb "超出功能選項範圍（1-${#steps[@]}）" "0"
		fi
		;;
	*)
		echoRgb "輸入錯誤，請重新輸入有效的數字或輸入 x 離開。" "0" ;;
	esac
	done
fi
