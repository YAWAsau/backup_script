#!/system/bin/sh
# SpeedBackup dex_check - r318; core-only precheck: key tools and Dex capabilities, no historical tools regression grep.
# 不再鎖 Dex 版本字串、build 號、tools.sh patch marker 或歷史回歸 grep；只檢查目前 tools 真正依賴的 Dex 核心能力是否可用。
PKG="${1:-${PKG:-com.tencent.mobileqq}}"
USER_ID="${2:-${USER_ID:-0}}"
CLASSPATH_PATH="${CLASSPATH_PATH:-/data/backup_tools/classes.dex}"
TOOLS_PATH="${TOOLS_PATH:-}"
TEST_LOG_DIR="${TEST_LOG_DIR:-/data/local/tmp}"
TEST_LOG_FILE="${TEST_LOG_FILE:-$TEST_LOG_DIR/dex_check.log}"
TEST_SUMMARY_FILE="${TEST_SUMMARY_FILE:-$TEST_LOG_DIR/dex_full_test.summary}"
DEX_CHECK_VERSION="v24.20.14-7.66-900-dexcheck-section-log-r477-202607232022"
BACKUP_WIFI_ENABLE="${BACKUP_WIFI_ENABLE:-1}"
SB_SELFTEST_LEVEL="${SB_SELFTEST_LEVEL:-quick}"
CHANGELOG_URL="${CHANGELOG_URL:-https://api.github.com/repos/XayahSuSuSu/Android-DataBackup/releases/latest}"
SELFTEST_SCRIPT_VERSION="${SELFTEST_SCRIPT_VERSION:-v24.20.14-7.66-900-dexcheck-section-log-r477-202607232022}"
SPEEDBACKUP_PATCH_BUILD="${SPEEDBACKUP_PATCH_BUILD:-}"
PATH="/data/backup_tools:$(dirname "$CLASSPATH_PATH" 2>/dev/null):$PATH"
export PATH
HIDDEN_CLASS="com.xayah.dex.HiddenApiUtil"
HTTP_CLASS="com.xayah.dex.HttpUtil"
CC_CLASS="com.xayah.dex.CCUtil"
NETWORK_CLASS="com.xayah.dex.NetworkUtil"
NOTIFICATION_CLASS="com.xayah.dex.NotificationUtil"
WEBDAV_CLASS="com.xayah.dex.WebDavUtil"
SMB_SCAN_CLASS="com.xayah.dex.SmbScanUtil"
APPSTATE_CLASS="com.xayah.dex.AppStateUtil"
ROOT_DAEMON_CLASS="com.xayah.dex.SpeedBackupRootDaemon"
PLAY_PKG="${PLAY_PKG:-com.android.vending}"
TOTAL="${TOTAL:-dynamic}"
IDX=0
OK=0
WARN=0
FAIL=0
HAD_CMD_STDERR=0
CRITICAL_FAIL=0
mkdir -p "$TEST_LOG_DIR" 2>/dev/null
: > "$TEST_LOG_FILE" 2>/dev/null || TEST_LOG_FILE="/data/local/tmp/dex_check_$$.log"
: > "$TEST_LOG_FILE" 2>/dev/null
: > "$TEST_SUMMARY_FILE" 2>/dev/null
log(){ printf '%s\n' "$*" >> "$TEST_LOG_FILE" 2>/dev/null; }
section(){
	local _title="$1" _desc="$2"
	printf "\033[38;5;81m[%s] %s\033[0m\n" "$_title" "$_desc"
	log "[$_title] $_desc"
	printf '[SECTION] %s %s\n' "$_title" "$_desc" >> "$TEST_SUMMARY_FILE" 2>/dev/null
}
print_line(){
	local _st="$1" _label="$2" _detail="$3" _icon _color _reset
	IDX=$((IDX+1))
	_reset='\033[0m'
	case "$_st" in
		OK) _icon='✅'; _color='\033[38;5;121m'; OK=$((OK+1));;
		WARN) _icon='⚠️'; _color='\033[38;5;220m'; WARN=$((WARN+1));;
		*) _icon='❌'; _color='\033[38;5;197m'; FAIL=$((FAIL+1));;
	esac
	[ -n "$_detail" ] && _label="$_label ($_detail)"
	printf "${_color} -[dynamic] %2d %s %s${_reset}\n" "$IDX" "$_icon" "$_label"
	printf '%s %s/%s %s %s\n' "$_st" "$IDX" "$TOTAL" "$_label" "$_detail" >> "$TEST_SUMMARY_FILE" 2>/dev/null
	log "[$_st] $IDX/$TOTAL $_label $_detail"
}
ok(){ print_line OK "$1" "$2"; }
warn(){ print_line WARN "$1" "$2"; }
fail(){ print_line FAIL "$1" "$2"; }
critical_fail(){ CRITICAL_FAIL=1; print_line FAIL "$1" "$2"; }
stderr_has_unexpected(){
	local _file="$1"
	[ -s "$_file" ] || return 1
	[ "${DEX_SMOKE_EXPECT_STDERR:-0}" = "1" ] && return 1
	grep -vE '^[[:space:]]*$|(^|[[:space:]])HUMAN([[:space:]]|$)|^WARNING: linker:|^WARNING: linker64:' "$_file" 2>/dev/null | grep -q .
}
run_class(){
	local _cls="$1" _out="/data/local/tmp/sb_dex_selftest_stdout_$$" _err="/data/local/tmp/sb_dex_selftest_stderr_$$" _rc
	shift
	{
		echo ""
		echo "----- COMMAND BEGIN -----"
		printf 'CMD: CLASSPATH=%s app_process /system/bin %s' "$CLASSPATH_PATH" "$_cls"
		for _a in "$@"; do printf ' %s' "$_a"; done
		echo ""
	} >> "$TEST_LOG_FILE" 2>/dev/null
	CLASSPATH="$CLASSPATH_PATH" app_process /system/bin "$_cls" "$@" >"$_out" 2>"$_err"
	_rc=$?
	{
		echo "[stdout]"; [ -s "$_out" ] && cat "$_out" || echo "<empty>"
		echo "[stderr]"; [ -s "$_err" ] && cat "$_err" || echo "<empty>"
		echo "[exit] $_rc"
		echo "----- COMMAND END -----"
	} >> "$TEST_LOG_FILE" 2>/dev/null
	if stderr_has_unexpected "$_err"; then HAD_CMD_STDERR=1; fi
	[ -s "$_out" ] && cat "$_out"
	[ -s "$_err" ] && cat "$_err" >&2
	rm -f "$_out" "$_err" 2>/dev/null
	return "$_rc"
}
run_class_stdout(){
	local _cls="$1" _out="/data/local/tmp/sb_dex_selftest_json_stdout_$$" _err="/data/local/tmp/sb_dex_selftest_json_stderr_$$" _rc
	shift
	{
		echo ""
		echo "----- COMMAND BEGIN (stdout-only) -----"
		printf 'CMD: CLASSPATH=%s app_process /system/bin %s' "$CLASSPATH_PATH" "$_cls"
		for _a in "$@"; do printf ' %s' "$_a"; done
		echo ""
	} >> "$TEST_LOG_FILE" 2>/dev/null
	CLASSPATH="$CLASSPATH_PATH" app_process /system/bin "$_cls" "$@" >"$_out" 2>"$_err"
	_rc=$?
	{
		echo "[stdout]"; [ -s "$_out" ] && cat "$_out" || echo "<empty>"
		echo "[stderr]"; [ -s "$_err" ] && cat "$_err" || echo "<empty>"
		echo "[exit] $_rc"
		echo "----- COMMAND END (stdout-only) -----"
	} >> "$TEST_LOG_FILE" 2>/dev/null
	if stderr_has_unexpected "$_err"; then HAD_CMD_STDERR=1; fi
	[ -s "$_out" ] && cat "$_out"
	rm -f "$_out" "$_err" 2>/dev/null
	return "$_rc"
}
run_class_quiet_stdout(){
	local _cls="$1"
	shift
	CLASSPATH="$CLASSPATH_PATH" app_process /system/bin "$_cls" "$@" 2>/dev/null
}
run_dex_quiet_stdout(){ run_class_quiet_stdout "$HIDDEN_CLASS" "$@"; }

run_dex(){ run_class "$HIDDEN_CLASS" "$@"; }
run_timeout_suppressed(){
	local _label="$1" _timeout="$2" _tmp="/data/local/tmp/sb_dex_selftest_suppressed_$$" _pid _start _now _rc _bytes
	shift 2
	"$@" >"$_tmp" 2>&1 &
	_pid=$!
	_start="$(date +%s 2>/dev/null)"; case "$_start" in ''|*[!0-9]*) _start=0;; esac
	while kill -0 "$_pid" 2>/dev/null; do
		sleep 1
		_now="$(date +%s 2>/dev/null)"; case "$_now" in ''|*[!0-9]*) _now=$((_start+_timeout+1));; esac
		if [ "$_timeout" -gt 0 ] && [ "$_start" -gt 0 ] && [ $((_now-_start)) -ge "$_timeout" ]; then
			kill -TERM "$_pid" 2>/dev/null; sleep 1; kill -KILL "$_pid" 2>/dev/null; wait "$_pid" 2>/dev/null; _rc=124; break
		fi
	done
	[ -z "${_rc:-}" ] && { wait "$_pid" 2>/dev/null; _rc=$?; }
	_bytes="$(wc -c < "$_tmp" 2>/dev/null | tr -d ' ')"; [ -z "$_bytes" ] && _bytes=0
	log "[suppressed] $_label rc=$_rc bytes=$_bytes"
	rm -f "$_tmp" 2>/dev/null
	[ "$_rc" -eq 0 ] && ok "$_label" "rc=0" || warn "$_label" "rc=$_rc bytes=$_bytes"
}
get_pkg_uid(){
	local _pkg="$1" _uid _line _cmd
	for _cmd in "cmd package list packages -U" "pm list packages -U"; do
		_line="$($_cmd 2>/dev/null | awk -v p="package:$_pkg" '$1==p { for(i=1;i<=NF;i++){ if($i ~ /^uid:/){ sub(/^uid:/,"",$i); print $i; exit } } }')"
		case "$_line" in ''|*[!0-9]*) ;; *) echo "$_line"; return 0 ;; esac
	done
	_uid="$(dumpsys package "$_pkg" 2>/dev/null | sed -n '
		s/.*userId=\([0-9][0-9]*\).*/\1/p
		s/.*appId=\([0-9][0-9]*\).*/\1/p
		s/.*uid=\([0-9][0-9]*\).*/\1/p
	' | head -n 1)"
	case "$_uid" in ''|*[!0-9]*) return 1 ;; *) echo "$_uid"; return 0 ;; esac
}
first_user_pkg(){ run_dex_quiet_stdout getInstalledPackagesAsUser "$USER_ID" user pkgName 2>/dev/null | awk 'NF==1 && $1 ~ /^[A-Za-z0-9_.-]+$/ {print; exit}'; }
find_tools_file(){
	if [ -f "$TOOLS_PATH" ]; then echo "$TOOLS_PATH"; return 0; fi
	if [ -n "$TOOLS_PATH" ] && [ -f "$TOOLS_PATH/tools.sh" ]; then echo "$TOOLS_PATH/tools.sh"; return 0; fi
	if [ -f /data/backup_tools/tools.sh ]; then echo /data/backup_tools/tools.sh; return 0; fi
	return 1
}
require_text(){
	local _label="$1" _hay="$2" _needle="$3"
	printf '%s\n' "$_hay" | grep -F "$_needle" >/dev/null 2>&1 && ok "$_label" "present" || critical_fail "$_label" "missing=$_needle"
}
require_caps_json(){
	local _file="$1" _label="$2"
	jq -e '
		. as $root |
		def cap($n): any($root.capabilities[]?; .name == $n and .enabled == true);
		($root.schemaVersion == 2) and
		((($root.daemonProtocolVersion // 0)) >= 1) and
		((($root.dexVersion // "")) | startswith("v2.6.")) and
		([
			"dex.capabilities.v1",
			"dex.machine_stdout.v1",
			"dex.label_path_segment_safe.v1",
			"dex.webdav.relpath_traversal_guard.v1",
			"dex.root_unified_daemon.v1",
			"hiddenapi.daemon.af_unix.v1",
			"hiddenapi.force_stop_package_batch.daemon.v1",
			"dex.app_inventory.snapshot.v1",
			"dex.app_inventory.pkg_uid.single.v1",
			"dex.app_inventory.package_status.single.v1",
			"dex.app_inventory.package_filter_batch.v1",
			"dex.app_inventory.getlist_onecall.v1",
			"dex.app_inventory.package_facts.batch.v1",
			"dex.hidden_api.bypass_softgate.v1",
			"appstate.snapshot.batch.v2",
			"appstate.restore.batch.v4",
			"appstate.verify.batch.v4",
			"appstate.verify.vendor_classification.dex.v1",
			"appstate.restore.vendor_classification.dex.v1",
			"appstate.restore.permission_appop_vendor_classification.dex.v1",
			"appstate.restore.special_access_vendor_classification.dex.v1",
			"appstate.verify.default_dialer_vendor_classification.dex.v1",
			"appstate.daemon.af_unix.v1",
			"appstate.structured_result_codes.v2",
			"appstate.ssaid.integrated.v1",
			"appstate.special_access.integrated.v1",
			"appstate.scoped_appops_fields.v1",
			"appstate.default_home.v1",
            "appstate.default_ime.v1",
            "appstate.default_ime.exec_settings.v1",
			"dex.settings.exec_shim.v1",
            "dex.pm.visible_after_install.v1",
            "dex.pm.visible_after_install.v1",
			"dex.framework_facts.batch.v1",
			"dex.device_facts.v1",
			"dex.device_model_name_map.v1",
			"appstate.foreground_state.batch.v1",
			"appstate.foreground_list.json.v1",
			"dex.process_observer.global_daemon.v1",
			"dex.process_observer.target_lifecycle.v1",
			"dex.process_observer.batch_watchset.v1",
			"dex.process_observer.batch_stop_safe.v1",
			"dex.process_observer.batch_persistent_safety.v1",
			"dex.process_observer.taskstack_package_guard.v1",
			"dex.process_observer.live_respawn_guard.v1",
			"dex.process_observer.cgroup_high_risk_only.v1",
            "dex.process_observer.high_risk_notop_cgroup_freeze.v1",
            "dex.process_observer.cgroup_freeze_reuse.v1",
            "dex.process_observer.cgroup_freeze_reuse_all_alive_pids.v1",
            "dex.process_observer.cgroup_stale_token_prune.v1",
            "dex.process_observer.cgroup_dead_pid_package_retry.v1",
            "dex.process_observer.high_risk_top_fast_freeze.v1",
            "dex.process_observer.restore_freeze_action.v1",
            "dex.process_observer.restore_session_direct_start.v1",
            "dex.process_observer.restore_session_facts_cache.v1",
            "dex.process_observer.restore_action_policy_builder.v1",
            "dex.process_observer.batch_stop_summary_tsv.v1",
			"dex.app_wake_block.persistent_restore.v1",
			"dex.uid_net_block.persistent_restore.v1",
			"dex.cgroup_freezer.lifecycle.v1",
			"dex.cgroup_freezer.persistent_batch_session.v1",
			"dex.cgroup_freezer.native_package_atomic.v1",
			"dex.cgroup_freezer.native_package_kill_live_rescan.v1",
			"dex.cgroup_freezer.native_thaw_uid_emergency.v1",
			"dex.cgroup_freezer.daemon_parent_control.v1",
			"dex.display_power.root_daemon.v1",
			"webdav.rel_only.v1",
			"webdav.managed_put.v1",
            "webdav.putstdin.skip_parent_mkdir.v1",
			"webdav.managed_list_classify.v1",
			"webdav.managed_batch_put_with_parents.v1",
			"webdav.propfind.no_cache.v1",
			"webdav.stream_heartbeat_error_kind.dex.v1",
			"dex.smb.target_probe.v1",
			"notification.daemon.af_unix.v1",
			"notification.inline_small_icon.v1"
		] | all(.[]; cap(.)))
	' "$_file" >/dev/null 2>&1 && ok "$_label" "核心能力齊全" || critical_fail "$_label" "缺少必要能力，請重編/替換 classes.dex"
}

log "=================================================="
log "SpeedBackup dex_check 使用者可讀分組檢查"
log "pkg=$PKG user=$USER_ID classpath=$CLASSPATH_PATH tools=$TOOLS_PATH level=$SB_SELFTEST_LEVEL dex_check=$DEX_CHECK_VERSION"
log "selftest_version=$SELFTEST_SCRIPT_VERSION"
log "speedbackup_patch_build=$SPEEDBACKUP_PATCH_BUILD"
log "policy=final_user_groups_logged required_core optional_facts reverted_display_timeout_direct"
log "=================================================="

section "核心環境" "檢查 Dex / native 啟動條件"
if [ -f "$CLASSPATH_PATH" ]; then ok "Dex 檔案存在" "$(wc -c < "$CLASSPATH_PATH" 2>/dev/null | tr -d ' ') bytes"; else critical_fail "Dex 檔案存在" "$CLASSPATH_PATH"; fi
if ! get_pkg_uid "$PKG" >/dev/null 2>&1; then
	_new="$(first_user_pkg)"
	if [ -n "$_new" ]; then warn "測試包切換" "$PKG -> $_new"; PKG="$_new"; fi
fi
_uidexec="$(command -v uidexec 2>/dev/null)"; [ -n "$_uidexec" ] || _uidexec="/data/backup_tools/uidexec"
if [ -x "$_uidexec" ]; then
	_out="$(uidexec 0 0 /data "$CLASSPATH_PATH" /system/bin/id 2>&1 | head -n 1)"
	echo "$_out" | grep -q 'uid=0' && ok "Root 權限執行環境" "rc=0" || warn "Root 權限執行環境" "$_out"
	_play_uid="$(get_pkg_uid "$PLAY_PKG" 2>/dev/null)"
	if echo "$_play_uid" | grep -qE '^[0-9]+$'; then
		_data_dir="/data/user/$USER_ID/$PLAY_PKG"; [ -d "$_data_dir" ] || _data_dir="/data"
		_out="$(uidexec "$_play_uid" "$_play_uid" "$_data_dir" "$CLASSPATH_PATH" /system/bin/id 2>&1 | head -n 1)"
		echo "$_out" | grep -q "uid=$_play_uid" && ok "Play 商店身分模擬環境" "rc=0" || warn "Play 商店身分模擬環境" "$_out"
	else
		warn "Play 商店身分模擬環境" "Play UID不可讀"
	fi
else
	warn "Root 權限執行環境" "uidexec_not_found"
	warn "Play 商店身分模擬環境" "uidexec_not_found"
fi

_dex_ver_now="$(run_dex --version 2>&1 | head -n 30)"; _dex_ver_rc=$?
if [ "$_dex_ver_rc" -eq 0 ] && printf '%s\n' "$_dex_ver_now" | grep -q '^v2\.6\.'; then
	ok "Dex 主入口可啟動" "rc=0"
else
	critical_fail "Dex 主入口可啟動" "rc=$_dex_ver_rc $_dex_ver_now"
fi
_root_ver="$(run_class_stdout "$ROOT_DAEMON_CLASS" version 2>&1 | head -n 20)"; _root_ver_rc=$?
[ "$_root_ver_rc" -eq 0 ] && [ -n "$_root_ver" ] && ok "Dex RootDaemon 可啟動" "rc=0" || critical_fail "Dex RootDaemon 可啟動" "rc=$_root_ver_rc"
_bypass="$(run_dex hiddenApiBypassStatus 2>&1 | head -n 40)"; _bypass_rc=$?
printf '%s\n' "$_bypass" > "$TEST_LOG_DIR/hiddenapi_bypass_status.txt" 2>/dev/null
if [ "$_bypass_rc" -eq 0 ] && printf '%s\n' "$_bypass" | grep -q 'HIDDEN_API_BYPASS'; then
	ok "Hidden API softgate 狀態" "rc=0 optional=1"
else
	warn "Hidden API softgate 狀態" "rc=$_bypass_rc optional=1"
fi
_probe_out="$(run_dex hiddenApiRuntimeProbe "$USER_ID" "$PKG" 2>/dev/null | head -n 120)"; _probe_rc=$?
printf '%s\n' "$_probe_out" > "$TEST_LOG_DIR/hiddenapi_runtime_probe.txt" 2>/dev/null
if [ "$_probe_rc" -eq 0 ] && printf '%s\n' "$_probe_out" | grep -q 'HIDDEN_API_PROBE_DONE'; then
	ok "Hidden API 實際功能探測" "rc=0 functional_gate=1"
else
	warn "Hidden API 實際功能探測" "rc=$_probe_rc functional_gate=1"
fi
_hidden_help="$(run_dex_quiet_stdout help 2>/dev/null)"; _hidden_help_rc=$?
[ "$_hidden_help_rc" -eq 0 ] && ok "Dex HiddenApiUtil 指令表可讀" "rc=0" || critical_fail "Dex HiddenApiUtil 指令表可讀" "rc=$_hidden_help_rc"
section "備份能力" "檢查 App 清單、媒體與設備資訊入口"
require_text "App 名稱讀取" "$_hidden_help" "getPackageLabel"
require_text "使用者 App 清單" "$_hidden_help" "getInstalledPackagesAsUser"
require_text "App 清單快照" "$_hidden_help" "appInventorySnapshot"
require_text "App UID 讀取" "$_hidden_help" "appInventoryPkgUid"
require_text "App 安裝狀態讀取" "$_hidden_help" "appInventoryPackageStatus"
require_text "App 批量安裝狀態讀取" "$_hidden_help" "appInventoryPackageStatusBatch"
require_text "App 批量資訊讀取" "$_hidden_help" "appInventoryPackageFactsBatch"
require_text "預設角色資訊" "$_hidden_help" "defaultRoleFacts"
require_text "媒體儲存資訊" "$_hidden_help" "storageMediaFacts"
require_text "設備資訊讀取" "$_hidden_help" "deviceFacts"

section "恢復能力" "檢查恢復後 Package 可見性與 AppState/SSAID 入口"
require_text "恢復後 App 可見性資訊" "$_hidden_help" "appInventoryPostInstallFactsBatch"
require_text "恢復後 Package 可見性入口" "$_hidden_help" "packageVisibleAfterInstall"

section "進程控制" "檢查 force-stop、cgroup freeze、ProcessObserver 入口"
require_text "批量停止 App" "$_hidden_help" "forceStopPackageBatch"
require_text "停止 App 後驗證" "$_hidden_help" "forceStopPackageVerify"
require_text "UID 存活狀態" "$_hidden_help" "uidLiveState"
require_text "UID observer 探測" "$_hidden_help" "uidObserverProbe"
require_text "UID observer 監控" "$_hidden_help" "uidObserverWatch"
require_text "Package 存活狀態" "$_hidden_help" "packageLiveState"
require_text "螢幕亮度/電源模式控制" "$_hidden_help" "setDisplayPowerMode"
require_text "cgroup freeze 啟動" "$_hidden_help" "cgroupFreezeStart"
require_text "cgroup freeze 停止" "$_hidden_help" "cgroupFreezeStop"
require_text "cgroup daemon 啟動" "$_hidden_help" "cgroupFreezeDaemonEnsure"
require_text "ProcessObserver 啟動" "$_hidden_help" "processObserverStart"
require_text "ProcessObserver 停止" "$_hidden_help" "processObserverStop"
require_text "ProcessObserver 批量啟動" "$_hidden_help" "processObserverBatchStart"
require_text "ProcessObserver 批量停止" "$_hidden_help" "processObserverBatchStop"
require_text "恢復 guard session" "$_hidden_help" "processObserverRestoreSessionStart"
require_text "ProcessObserver 狀態" "$_hidden_help" "processObserverStatus"
require_text "目前前台 App 判斷" "$_hidden_help" "processObserverTop"
require_text "前台狀態查詢" "$_hidden_help" "processObserverForeground"

section "可選資訊" "缺少時只略過 speed_debug 輔助 TSV，不阻斷備份/恢復"
printf '%s\n' "$_hidden_help" | grep -F "storageVolumeFacts" >/dev/null 2>&1 && ok "儲存空間詳細 TSV" "present optional=1" || warn "儲存空間詳細 TSV" "missing optional=1"
printf '%s\n' "$_hidden_help" | grep -F "homeImeLauncherFacts" >/dev/null 2>&1 && ok "桌面/鍵盤候選 TSV" "present optional=1" || warn "桌面/鍵盤候選 TSV" "missing optional=1"

section "恢復能力" "檢查 AppState / SSAID / Framework facts 契約"
_app_caps="$(run_class_stdout "$APPSTATE_CLASS" capabilities 2>/dev/null)"; _app_caps_rc=$?
printf '%s\n' "$_app_caps" > "$TEST_LOG_DIR/appstate_capabilities.json" 2>/dev/null
if [ "$_app_caps_rc" -eq 0 ] && [ -s "$TEST_LOG_DIR/appstate_capabilities.json" ]; then
	require_caps_json "$TEST_LOG_DIR/appstate_capabilities.json" "Dex 備份/恢復核心能力"
else
	critical_fail "Dex 備份/恢復核心能力" "rc=$_app_caps_rc"
fi
_appstate_help="$(run_class_quiet_stdout "$APPSTATE_CLASS" help 2>/dev/null)"; _appstate_help_rc=$?
[ "$_appstate_help_rc" -eq 0 ] && ok "Dex AppState 指令表可讀" "rc=0" || critical_fail "Dex AppState 指令表可讀" "rc=$_appstate_help_rc"
require_text "AppState capability 查詢入口" "$_appstate_help" "capabilities"
require_text "AppState 備份快照入口" "$_appstate_help" "snapshotAppStateBatch"
require_text "前台狀態批量入口" "$_appstate_help" "foregroundStateBatch"
require_text "前台執行狀態入口" "$_appstate_help" "foregroundStateRunning"
require_text "目前頂層 App 入口" "$_appstate_help" "foregroundTop"
require_text "前台清單 JSON 入口" "$_appstate_help" "foregroundListJson"
require_text "AppState 恢復入口" "$_appstate_help" "restoreAppStateBatch"
require_text "AppState 驗證入口" "$_appstate_help" "verifyAppStateBatch"
require_text "預設桌面判斷入口" "$_appstate_help" "defaultHome"
require_text "預設鍵盤判斷入口" "$_appstate_help" "defaultIme"
require_text "系統設定讀取 fallback 入口" "$_appstate_help" "settingsGet"
require_text "系統設定寫入 fallback 入口" "$_appstate_help" "settingsPut"
require_text "Framework facts 入口" "$_appstate_help" "frameworkFacts"
require_text "設備 facts 入口" "$_appstate_help" "deviceFacts"
require_text "RootDaemon unix socket 入口" "$_appstate_help" "daemonunix"

section "備份能力" "執行安全 smoke，確認不是只有入口存在"
_inv_out="$(run_class_stdout "$HIDDEN_CLASS" appInventoryPackageStatus "$USER_ID" "$PKG" refresh 2>/dev/null)"; _inv_rc=$?
printf '%s\n' "$_inv_out" > "$TEST_LOG_DIR/appinventory_package_status.json" 2>/dev/null
if [ "$_inv_rc" -eq 0 ] && printf '%s\n' "$_inv_out" | jq -e '.schema=="speedbackup.app_inventory.status.v1" or .schema=="speedbackup.app_inventory.v1" or has("packageName")' >/dev/null 2>&1; then ok "App 安裝狀態讀取" "rc=0"; else warn "App 安裝狀態讀取" "rc=$_inv_rc"; fi

_device_facts_out="$(run_class_stdout "$HIDDEN_CLASS" deviceFacts 2>/dev/null)"; _device_facts_rc=$?
printf '%s\n' "$_device_facts_out" > "$TEST_LOG_DIR/device_facts.json" 2>/dev/null
if [ "$_device_facts_rc" -eq 0 ] && printf '%s\n' "$_device_facts_out" | jq -e '.schema=="speedbackup.device_facts.v1" and (.modelNameSource|length>0) and (.marketNameZh|length>0) and (.modelDbEntryCount >= 4000) and (.modelDbSourceLines >= 4000) and ((.modelDbSourceSha256|length)==64)' >/dev/null 2>&1; then ok "Dex 內建機型資料庫" "rc=0"; else warn "Dex 內建機型資料庫" "rc=$_device_facts_rc"; fi

_facts_out="$(run_class_stdout "$HIDDEN_CLASS" appInventoryPackageFactsBatch "$USER_ID" "$PKG" refresh 2>/dev/null)"; _facts_rc=$?
printf '%s\n' "$_facts_out" > "$TEST_LOG_DIR/appinventory_package_facts.tsv" 2>/dev/null
if [ "$_facts_rc" -eq 0 ] && printf '%s\n' "$_facts_out" | grep -q '^#schema[[:space:]]speedbackup.pm_facts.v1' && printf '%s\n' "$_facts_out" | grep -q "^OK[[:space:]]$PKG[[:space:]]"; then ok "App 批量資訊讀取" "rc=0"; else warn "App 批量資訊讀取" "rc=$_facts_rc"; fi

section "恢復能力" "執行恢復相關 smoke"
_post_facts_out="$(run_class_stdout "$HIDDEN_CLASS" appInventoryPostInstallFactsBatch "$USER_ID" "$PKG" refresh 2>/dev/null)"; _post_facts_rc=$?
printf '%s\n' "$_post_facts_out" > "$TEST_LOG_DIR/appinventory_post_install_facts.tsv" 2>/dev/null
if [ "$_post_facts_rc" -eq 0 ] && printf '%s\n' "$_post_facts_out" | grep -q '^#schema[[:space:]]speedbackup.pm_facts.v1' && printf '%s\n' "$_post_facts_out" | grep -q "^OK[[:space:]]$PKG[[:space:]]"; then ok "恢復後 App 可見性資訊" "rc=0"; else warn "恢復後 App 可見性資訊" "rc=$_post_facts_rc"; fi

_role_facts_out="$(run_class_stdout "$HIDDEN_CLASS" defaultRoleFacts "$USER_ID" 2>/dev/null)"; _role_facts_rc=$?
printf '%s\n' "$_role_facts_out" > "$TEST_LOG_DIR/default_role_facts.tsv" 2>/dev/null
if [ "$_role_facts_rc" -eq 0 ] && printf '%s\n' "$_role_facts_out" | grep -q '^#schema[[:space:]]speedbackup.default_role_facts.v1'; then ok "預設角色資訊" "rc=0"; else warn "預設角色資訊" "rc=$_role_facts_rc"; fi

_storage_facts_out="$(run_class_stdout "$HIDDEN_CLASS" storageMediaFacts "$USER_ID" 2>/dev/null)"; _storage_facts_rc=$?
printf '%s\n' "$_storage_facts_out" > "$TEST_LOG_DIR/storage_media_facts.tsv" 2>/dev/null
if [ "$_storage_facts_rc" -eq 0 ] && printf '%s\n' "$_storage_facts_out" | grep -q '^#schema[[:space:]]speedbackup.storage_media_facts.v1'; then ok "媒體儲存資訊" "rc=0"; else warn "媒體儲存資訊" "rc=$_storage_facts_rc"; fi
section "已撤回" "顯示已移除的過時檢測與正式 fallback"
_settings_out="$(run_class_stdout "$APPSTATE_CLASS" settingsGet "$USER_ID" secure default_input_method 2>/dev/null)"; _settings_rc=$?
printf '%s\n' "$_settings_out" > "$TEST_LOG_DIR/appstate_settings_get_smoke.ndjson" 2>/dev/null
if [ "$_settings_rc" -eq 0 ] && printf '%s\n' "$_settings_out" | jq -s -e 'any(.[]; .recordType=="settingsGet" and .source=="exec_settings")' >/dev/null 2>&1; then ok "系統設定 shell fallback" "rc=0"; else warn "系統設定 shell fallback" "rc=$_settings_rc"; fi
	# r473: Dex display-timeout/settings direct smoke removed. Settings screen_off_timeout is intentionally handled by bounded shell in tools.
ok "Dex 直接改螢幕逾時已撤回" "正式路徑=bounded-shell"

