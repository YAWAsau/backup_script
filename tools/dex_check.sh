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
DEX_CHECK_VERSION="v24.20.14-7.66-863-finalpack-timeout-cache-restore-r440-202607232022"
BACKUP_WIFI_ENABLE="${BACKUP_WIFI_ENABLE:-1}"
SB_SELFTEST_LEVEL="${SB_SELFTEST_LEVEL:-quick}"
CHANGELOG_URL="${CHANGELOG_URL:-https://api.github.com/repos/XayahSuSuSu/Android-DataBackup/releases/latest}"
SELFTEST_SCRIPT_VERSION="${SELFTEST_SCRIPT_VERSION:-v24.20.14-7.66-863-finalpack-timeout-cache-restore-r440-202607232022}"
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
first_user_pkg(){ run_dex getInstalledPackagesAsUser "$USER_ID" user pkgName 2>/dev/null | awk 'NF==1 && $1 ~ /^[A-Za-z0-9_.-]+$/ {print; exit}'; }
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
	' "$_file" >/dev/null 2>&1 && ok "$_label" "core_caps_ok" || critical_fail "$_label" "core_caps_missing"
}

log "=================================================="
log "SpeedBackup dex_check core capability smoke"
log "pkg=$PKG user=$USER_ID classpath=$CLASSPATH_PATH tools=$TOOLS_PATH level=$SB_SELFTEST_LEVEL dex_check=$DEX_CHECK_VERSION"
log "selftest_version=$SELFTEST_SCRIPT_VERSION"
log "speedbackup_patch_build=$SPEEDBACKUP_PATCH_BUILD"
log "policy=core_only key_tools dex_capabilities no_historical_tools_regression_grep"
log "=================================================="

if [ -f "$CLASSPATH_PATH" ]; then ok "classes.dex 存在" "$(wc -c < "$CLASSPATH_PATH" 2>/dev/null | tr -d ' ') bytes"; else critical_fail "classes.dex 存在" "$CLASSPATH_PATH"; fi
if ! get_pkg_uid "$PKG" >/dev/null 2>&1; then
	_new="$(first_user_pkg)"
	if [ -n "$_new" ]; then warn "測試包切換" "$PKG -> $_new"; PKG="$_new"; fi
fi
_uidexec="$(command -v uidexec 2>/dev/null)"; [ -n "$_uidexec" ] || _uidexec="/data/backup_tools/uidexec"
if [ -x "$_uidexec" ]; then
	_out="$(uidexec 0 0 /data "$CLASSPATH_PATH" /system/bin/id 2>&1 | head -n 1)"
	echo "$_out" | grep -q 'uid=0' && ok "uidexec root 執行環境" "rc=0" || warn "uidexec root 執行環境" "$_out"
	_play_uid="$(get_pkg_uid "$PLAY_PKG" 2>/dev/null)"
	if echo "$_play_uid" | grep -qE '^[0-9]+$'; then
		_data_dir="/data/user/$USER_ID/$PLAY_PKG"; [ -d "$_data_dir" ] || _data_dir="/data"
		_out="$(uidexec "$_play_uid" "$_play_uid" "$_data_dir" "$CLASSPATH_PATH" /system/bin/id 2>&1 | head -n 1)"
		echo "$_out" | grep -q "uid=$_play_uid" && ok "uidexec Play UID 執行環境" "rc=0" || warn "uidexec Play UID 執行環境" "$_out"
	else
		warn "uidexec Play UID 執行環境" "Play UID不可讀"
	fi
else
	warn "uidexec root 執行環境" "uidexec_not_found"
	warn "uidexec Play UID 執行環境" "uidexec_not_found"
fi

_dex_ver_now="$(run_dex --version 2>&1 | head -n 30)"; _dex_ver_rc=$?
if [ "$_dex_ver_rc" -eq 0 ] && printf '%s\n' "$_dex_ver_now" | grep -q '^v2\.6\.'; then
	ok "Dex version入口可讀" "rc=0"
else
	critical_fail "Dex version入口可讀" "rc=$_dex_ver_rc $_dex_ver_now"
fi
_root_ver="$(run_class_stdout "$ROOT_DAEMON_CLASS" version 2>&1 | head -n 20)"; _root_ver_rc=$?
[ "$_root_ver_rc" -eq 0 ] && [ -n "$_root_ver" ] && ok "SpeedBackupRootDaemon version可讀" "rc=0" || critical_fail "SpeedBackupRootDaemon version可讀" "rc=$_root_ver_rc"
_bypass="$(run_dex hiddenApiBypassStatus 2>&1 | head -n 40)"; _bypass_rc=$?
printf '%s\n' "$_bypass" > "$TEST_LOG_DIR/hiddenapi_bypass_status.txt" 2>/dev/null
if [ "$_bypass_rc" -eq 0 ] && printf '%s\n' "$_bypass" | grep -q 'HIDDEN_API_BYPASS'; then
	ok "HiddenApiBypass softgate狀態入口" "rc=0 optional=1"
else
	warn "HiddenApiBypass softgate狀態入口" "rc=$_bypass_rc optional=1"
fi
_probe_out="$(run_dex hiddenApiRuntimeProbe "$USER_ID" "$PKG" 2>/dev/null | head -n 120)"; _probe_rc=$?
printf '%s\n' "$_probe_out" > "$TEST_LOG_DIR/hiddenapi_runtime_probe.txt" 2>/dev/null
if [ "$_probe_rc" -eq 0 ] && printf '%s\n' "$_probe_out" | grep -q 'HIDDEN_API_PROBE_DONE'; then
	ok "HiddenApi runtime功能探測" "rc=0 functional_gate=1"
else
	warn "HiddenApi runtime功能探測" "rc=$_probe_rc functional_gate=1"
fi
_hidden_help="$(run_dex help 2>&1)"; _hidden_help_rc=$?
[ "$_hidden_help_rc" -eq 0 ] && ok "HiddenApiUtil help可讀" "rc=0" || critical_fail "HiddenApiUtil help可讀" "rc=$_hidden_help_rc"
for _cmd in getPackageLabel getInstalledPackagesAsUser appInventorySnapshot appInventoryPkgUid appInventoryPackageStatus appInventoryPackageStatusBatch appInventoryPackageFactsBatch appInventoryPostInstallFactsBatch defaultRoleFacts storageMediaFacts deviceFacts forceStopPackageBatch forceStopPackageVerify uidLiveState uidObserverProbe uidObserverWatch packageLiveState setDisplayPowerMode cgroupFreezeStart cgroupFreezeStop cgroupFreezeDaemonEnsure processObserverStart processObserverStop processObserverBatchStart processObserverBatchStop processObserverRestoreSessionStart processObserverStatus processObserverTop processObserverForeground; do
	require_text "HiddenApiUtil核心入口 $_cmd" "$_hidden_help" "$_cmd"
done

_app_caps="$(run_class_stdout "$APPSTATE_CLASS" capabilities 2>/dev/null)"; _app_caps_rc=$?
printf '%s\n' "$_app_caps" > "$TEST_LOG_DIR/appstate_capabilities.json" 2>/dev/null
if [ "$_app_caps_rc" -eq 0 ] && [ -s "$TEST_LOG_DIR/appstate_capabilities.json" ]; then
	require_caps_json "$TEST_LOG_DIR/appstate_capabilities.json" "AppState capabilities核心能力"
else
	critical_fail "AppState capabilities核心能力" "rc=$_app_caps_rc"
fi
_appstate_help="$(run_class_stdout "$APPSTATE_CLASS" help 2>&1)"; _appstate_help_rc=$?
[ "$_appstate_help_rc" -eq 0 ] && ok "AppStateUtil help可讀" "rc=0" || critical_fail "AppStateUtil help可讀" "rc=$_appstate_help_rc"
for _cmd in capabilities snapshotAppStateBatch foregroundStateBatch foregroundStateRunning foregroundTop foregroundListJson restoreAppStateBatch verifyAppStateBatch defaultHome defaultIme settingsGet settingsPut frameworkFacts deviceFacts daemonunix; do
	require_text "AppStateUtil核心入口 $_cmd" "$_appstate_help" "$_cmd"
done

_inv_out="$(run_class_stdout "$HIDDEN_CLASS" appInventoryPackageStatus "$USER_ID" "$PKG" refresh 2>/dev/null)"; _inv_rc=$?
printf '%s\n' "$_inv_out" > "$TEST_LOG_DIR/appinventory_package_status.json" 2>/dev/null
if [ "$_inv_rc" -eq 0 ] && printf '%s\n' "$_inv_out" | jq -e '.schema=="speedbackup.app_inventory.status.v1" or .schema=="speedbackup.app_inventory.v1" or has("packageName")' >/dev/null 2>&1; then ok "appInventoryPackageStatus smoke" "rc=0"; else warn "appInventoryPackageStatus smoke" "rc=$_inv_rc"; fi

_device_facts_out="$(run_class_stdout "$HIDDEN_CLASS" deviceFacts 2>/dev/null)"; _device_facts_rc=$?
printf '%s\n' "$_device_facts_out" > "$TEST_LOG_DIR/device_facts.json" 2>/dev/null
if [ "$_device_facts_rc" -eq 0 ] && printf '%s\n' "$_device_facts_out" | jq -e '.schema=="speedbackup.device_facts.v1" and (.modelNameSource|length>0) and (.marketNameZh|length>0) and (.modelDbEntryCount >= 4000) and (.modelDbSourceLines >= 4000) and ((.modelDbSourceSha256|length)==64)' >/dev/null 2>&1; then ok "deviceFacts Dex全量內建機型表 smoke" "rc=0"; else warn "deviceFacts Dex全量內建機型表 smoke" "rc=$_device_facts_rc"; fi

_facts_out="$(run_class_stdout "$HIDDEN_CLASS" appInventoryPackageFactsBatch "$USER_ID" "$PKG" refresh 2>/dev/null)"; _facts_rc=$?
printf '%s\n' "$_facts_out" > "$TEST_LOG_DIR/appinventory_package_facts.tsv" 2>/dev/null
if [ "$_facts_rc" -eq 0 ] && printf '%s\n' "$_facts_out" | grep -q '^#schema[[:space:]]speedbackup.pm_facts.v1' && printf '%s\n' "$_facts_out" | grep -q "^OK[[:space:]]$PKG[[:space:]]"; then ok "appInventoryPackageFactsBatch smoke" "rc=0"; else warn "appInventoryPackageFactsBatch smoke" "rc=$_facts_rc"; fi

_post_facts_out="$(run_class_stdout "$HIDDEN_CLASS" appInventoryPostInstallFactsBatch "$USER_ID" "$PKG" refresh 2>/dev/null)"; _post_facts_rc=$?
printf '%s\n' "$_post_facts_out" > "$TEST_LOG_DIR/appinventory_post_install_facts.tsv" 2>/dev/null
if [ "$_post_facts_rc" -eq 0 ] && printf '%s\n' "$_post_facts_out" | grep -q '^#schema[[:space:]]speedbackup.pm_facts.v1' && printf '%s\n' "$_post_facts_out" | grep -q "^OK[[:space:]]$PKG[[:space:]]"; then ok "appInventoryPostInstallFactsBatch smoke" "rc=0"; else warn "appInventoryPostInstallFactsBatch smoke" "rc=$_post_facts_rc"; fi

_role_facts_out="$(run_class_stdout "$HIDDEN_CLASS" defaultRoleFacts "$USER_ID" 2>/dev/null)"; _role_facts_rc=$?
printf '%s\n' "$_role_facts_out" > "$TEST_LOG_DIR/default_role_facts.tsv" 2>/dev/null
if [ "$_role_facts_rc" -eq 0 ] && printf '%s\n' "$_role_facts_out" | grep -q '^#schema[[:space:]]speedbackup.default_role_facts.v1'; then ok "defaultRoleFacts smoke" "rc=0"; else warn "defaultRoleFacts smoke" "rc=$_role_facts_rc"; fi

_storage_facts_out="$(run_class_stdout "$HIDDEN_CLASS" storageMediaFacts "$USER_ID" 2>/dev/null)"; _storage_facts_rc=$?
printf '%s\n' "$_storage_facts_out" > "$TEST_LOG_DIR/storage_media_facts.tsv" 2>/dev/null
if [ "$_storage_facts_rc" -eq 0 ] && printf '%s\n' "$_storage_facts_out" | grep -q '^#schema[[:space:]]speedbackup.storage_media_facts.v1'; then ok "storageMediaFacts smoke" "rc=0"; else warn "storageMediaFacts smoke" "rc=$_storage_facts_rc"; fi
_settings_out="$(run_class_stdout "$APPSTATE_CLASS" settingsGet "$USER_ID" secure default_input_method 2>/dev/null)"; _settings_rc=$?
printf '%s\n' "$_settings_out" > "$TEST_LOG_DIR/appstate_settings_get_smoke.ndjson" 2>/dev/null
if [ "$_settings_rc" -eq 0 ] && printf '%s\n' "$_settings_out" | jq -s -e 'any(.[]; .recordType=="settingsGet" and .source=="exec_settings")' >/dev/null 2>&1; then ok "settingsGet exec shim smoke" "rc=0"; else warn "settingsGet exec shim smoke" "rc=$_settings_rc"; fi
_framework_out="$(run_class_stdout "$APPSTATE_CLASS" frameworkFacts "$USER_ID" "$PKG" 2>/dev/null)"; _framework_rc=$?
printf '%s\n' "$_framework_out" > "$TEST_LOG_DIR/appstate_framework_facts_smoke.ndjson" 2>/dev/null
if [ "$_framework_rc" -eq 0 ] && printf '%s\n' "$_framework_out" | jq -s -e --arg p "$PKG" 'any(.[]; .recordType=="frameworkFacts" and .packageName==$p) and any(.[]; .recordType=="summary" and .command=="frameworkFacts")' >/dev/null 2>&1; then ok "frameworkFacts smoke" "rc=0"; else warn "frameworkFacts smoke" "rc=$_framework_rc"; fi
_snap_out="$(run_class_stdout "$APPSTATE_CLASS" snapshotAppStateBatch "$USER_ID" "$PKG")"; _snap_rc=$?
printf '%s\n' "$_snap_out" > "$TEST_LOG_DIR/appstate_snapshot_probe.ndjson" 2>/dev/null
if [ "$_snap_rc" -eq 0 ] && printf '%s\n' "$_snap_out" | jq -s -e --arg p "$PKG" 'any(.[]; .recordType=="snapshot" and .packageName==$p and (.result.name=="OK" or .result.name=="PARTIAL")) and any(.[]; .recordType=="summary" and .command=="snapshotAppStateBatch")' >/dev/null 2>&1; then ok "snapshotAppStateBatch smoke" "rc=0"; else critical_fail "snapshotAppStateBatch smoke" "rc=$_snap_rc"; fi
_fg_out="$(run_class_stdout "$APPSTATE_CLASS" foregroundStateBatch "$USER_ID" "$PKG")"; _fg_rc=$?
printf '%s\n' "$_fg_out" > "$TEST_LOG_DIR/appstate_foreground_state_smoke.ndjson" 2>/dev/null
if [ "$_fg_rc" -eq 0 ] && printf '%s\n' "$_fg_out" | jq -s -e --arg p "$PKG" 'any(.[]; .recordType=="foregroundState" and .packageName==$p and (.active|type)=="boolean") and any(.[]; .recordType=="summary" and .command=="foregroundStateBatch")' >/dev/null 2>&1; then ok "foregroundStateBatch smoke" "rc=0"; else critical_fail "foregroundStateBatch smoke" "rc=$_fg_rc"; fi
_home_out="$(run_class_stdout "$APPSTATE_CLASS" defaultHome "$USER_ID")"; _home_rc=$?
printf '%s\n' "$_home_out" > "$TEST_LOG_DIR/appstate_default_home_smoke.ndjson" 2>/dev/null
if [ "$_home_rc" -eq 0 ] && printf '%s\n' "$_home_out" | jq -s -e 'any(.[]; .recordType=="defaultHome") and any(.[]; .recordType=="summary" and .command=="defaultHome")' >/dev/null 2>&1; then ok "defaultHome smoke" "rc=0"; else critical_fail "defaultHome smoke" "rc=$_home_rc"; fi

_top_out="$(run_dex processObserverTop "$USER_ID" 2>/dev/null)"; _top_rc=$?
printf '%s\n' "$_top_out" > "$TEST_LOG_DIR/process_observer_top_smoke.txt" 2>/dev/null
if [ "$_top_rc" -eq 0 ] && printf '%s\n' "$_top_out" | grep -q 'PROCESS_OBSERVER_TOP'; then ok "processObserverTop direct smoke" "rc=0"; else warn "processObserverTop direct smoke" "rc=$_top_rc"; fi
_pof_out="$(run_dex processObserverForeground "$USER_ID" "$PKG" 2>/dev/null)"; _pof_rc=$?
printf '%s\n' "$_pof_out" > "$TEST_LOG_DIR/process_observer_foreground_smoke.txt" 2>/dev/null
if [ "$_pof_rc" -eq 0 ] && printf '%s\n' "$_pof_out" | grep -q 'PROCESS_OBSERVER_FOREGROUND'; then ok "processObserverForeground direct smoke" "rc=0"; else warn "processObserverForeground direct smoke" "rc=$_pof_rc"; fi
_pls_out="$(run_dex packageLiveState "$USER_ID" "$PKG" 2>/dev/null)"; _pls_rc=$?
printf '%s\n' "$_pls_out" > "$TEST_LOG_DIR/package_live_state_smoke.txt" 2>/dev/null
if [ "$_pls_rc" -eq 0 ] && printf '%s\n' "$_pls_out" | grep -q 'PACKAGE_LIVE_STATE'; then ok "packageLiveState direct smoke" "rc=0 hash=0"; else warn "packageLiveState direct smoke" "rc=$_pls_rc"; fi
_pis_out="$(run_dex packageInstallSnapshot "$USER_ID" "$PKG" 2>/dev/null)"; _pis_rc=$?
printf '%s\n' "$_pis_out" > "$TEST_LOG_DIR/package_install_snapshot_smoke.txt" 2>/dev/null
if [ "$_pis_rc" -eq 0 ] && printf '%s\n' "$_pis_out" | grep -q 'PACKAGE_INSTALL_SNAPSHOT' && printf '%s\n' "$_pis_out" | grep -q 'hash=0'; then ok "packageInstallSnapshot direct smoke" "rc=0 hash=0"; else warn "packageInstallSnapshot direct smoke" "rc=$_pis_rc"; fi
_prs_out="$(run_dex packageRestrictionSnapshot "$USER_ID" "$PKG" 2>/dev/null)"; _prs_rc=$?
printf '%s\n' "$_prs_out" > "$TEST_LOG_DIR/package_restriction_snapshot_smoke.txt" 2>/dev/null
if [ "$_prs_rc" -eq 0 ] && printf '%s\n' "$_prs_out" | grep -q 'PACKAGE_RESTRICTION_SNAPSHOT' && printf '%s\n' "$_prs_out" | grep -q 'hash=0'; then ok "packageRestrictionSnapshot direct smoke" "rc=0 hash=0"; else warn "packageRestrictionSnapshot direct smoke" "rc=$_prs_rc"; fi
_uid_probe_out="$(run_dex uidObserverProbe 2>/dev/null)"; _uid_probe_rc=$?
printf '%s\n' "$_uid_probe_out" > "$TEST_LOG_DIR/uid_observer_probe_smoke.txt" 2>/dev/null
if [ "$_uid_probe_rc" -eq 0 ] && printf '%s\n' "$_uid_probe_out" | grep -q 'UID_OBSERVER_PROBE'; then ok "uidObserverProbe direct smoke" "rc=0"; else warn "uidObserverProbe direct smoke" "rc=$_uid_probe_rc"; fi
_uid_out="$(run_dex uidLiveState "$USER_ID" "$PKG" 2>/dev/null)"; _uid_rc=$?
printf '%s\n' "$_uid_out" > "$TEST_LOG_DIR/uid_live_state_smoke.txt" 2>/dev/null
if [ "$_uid_rc" -eq 0 ] && printf '%s\n' "$_uid_out" | grep -q 'UID_LIVE_STATE'; then ok "uidLiveState direct smoke" "rc=0 hash=0"; else warn "uidLiveState direct smoke" "rc=$_uid_rc"; fi
_uid_watch_out="$(run_dex uidObserverWatch "$USER_ID" "$PKG" 120 2>/dev/null)"; _uid_watch_rc=$?
printf '%s\n' "$_uid_watch_out" > "$TEST_LOG_DIR/uid_observer_watch_smoke.txt" 2>/dev/null
if [ "$_uid_watch_rc" -eq 0 ] && printf '%s\n' "$_uid_watch_out" | grep -q 'UID_OBSERVER_WATCH_DONE'; then ok "uidObserverWatch direct smoke" "rc=0"; else warn "uidObserverWatch direct smoke" "rc=$_uid_watch_rc"; fi
_fsv_out="$(run_dex forceStopPackageVerify "$USER_ID" "$PKG" 100 2>/dev/null)"; _fsv_rc=$?
printf '%s\n' "$_fsv_out" > "$TEST_LOG_DIR/force_stop_verify_smoke.txt" 2>/dev/null
if [ "$_fsv_rc" -eq 0 ] && printf '%s\n' "$_fsv_out" | grep -q 'FORCE_STOP_VERIFY'; then ok "forceStopPackageVerify direct smoke" "rc=0"; else warn "forceStopPackageVerify direct smoke" "rc=$_fsv_rc"; fi

_wdav_help="$(run_class "$WEBDAV_CLASS" help 2>&1)"; _wdav_help_rc=$?
# r208: WebDavUtil help may print complete usage then exit 2 on older command dispatchers.
# Treat stdout content as the smoke criterion; exit code alone is not a core capability failure.
if printf '%s\n' "$_wdav_help" | grep -q 'WebDavUtil' && 	printf '%s\n' "$_wdav_help" | grep -q 'daemonunix' && 	printf '%s\n' "$_wdav_help" | grep -q 'putstdinmanagedrel'; then
	if [ "$_wdav_help_rc" -eq 0 ]; then
		ok "WebDavUtil help可讀" "rc=0"
	else
		ok "WebDavUtil help可讀" "stdout-ok rc=$_wdav_help_rc"
	fi
	for _cmd in daemonunix putstdinmanagedrel putmanagedrel managedbatchputrelwithparents managedlistclassifyrel listrel classifylistrel preparedirsplanrel statrel optionspreflightrel ensurebaserel ensuredirsbatchrel; do require_text "WebDavUtil核心入口 $_cmd" "$_wdav_help" "$_cmd"; done
	# getrel 是 WebDAV 下載路徑使用的 legacy/alias command；部分 Dex help 不再列出，但命令可能仍存在。
	# dex_check 只做核心 smoke，不再因 help usage 少列 alias 而中止工具。
	if printf '%s\n' "$_wdav_help" | grep -q 'getrel'; then
		ok "WebDavUtil可選入口 getrel" "present"
	else
		warn "WebDavUtil可選入口 getrel" "not-listed-in-help"
	fi
else
	critical_fail "WebDavUtil help可讀" "missing-core-output rc=$_wdav_help_rc"
fi
_smb_help="$(run_class "$SMB_SCAN_CLASS" help 2>&1 | head -n 160)"; _smb_help_rc=$?
[ "$_smb_help_rc" -eq 0 ] && printf '%s\n' "$_smb_help" | grep -q 'probeTarget' && ok "SmbScanUtil probeTarget入口" "present" || critical_fail "SmbScanUtil probeTarget入口" "rc=$_smb_help_rc"
_notify_help="$(run_class "$NOTIFICATION_CLASS" help 2>&1 | head -n 160)"; _notify_rc=$?
[ "$_notify_rc" -eq 0 ] && printf '%s\n' "$_notify_help" | grep -q 'notifyBatch' && ok "NotificationUtil notifyBatch入口" "present" || warn "NotificationUtil notifyBatch入口" "rc=$_notify_rc"
_cc_help="$(run_class "$CC_CLASS" help 2>&1 | head -n 120)"; _cc_rc=$?
[ "$_cc_rc" -eq 0 ] && printf '%s\n' "$_cc_help" | grep -q 's2t' && printf '%s\n' "$_cc_help" | grep -q 't2s' && ok "CCUtil s2t/t2s入口" "present" || warn "CCUtil s2t/t2s入口" "rc=$_cc_rc"
if [ "$BACKUP_WIFI_ENABLE" = "1" ]; then
	run_timeout_suppressed "NetworkUtil getNetworks smoke" 20 env CLASSPATH="$CLASSPATH_PATH" app_process /system/bin "$NETWORK_CLASS" getNetworks
else
	warn "NetworkUtil getNetworks smoke" "backup_wifi_enable=0"
fi


_TOOLS_FILE="$(find_tools_file 2>/dev/null)"
if [ -n "$_TOOLS_FILE" ] && [ -f "$_TOOLS_FILE" ]; then
	_shn_out="$(sh -n "$_TOOLS_FILE" 2>&1)"; _shn_rc=$?
	[ "$_shn_rc" -eq 0 ] && ok "tools.sh 語法檢查" "rc=0" || critical_fail "tools.sh 語法檢查" "rc=$_shn_rc $_shn_out"
else
	warn "tools.sh 語法檢查" "TOOLS_PATH不存在"
fi

key_tool_path(){
	local _name="$1" _p
	_p="$(command -v "$_name" 2>/dev/null)"
	[ -n "$_p" ] && { echo "$_p"; return 0; }
	[ -x "/data/backup_tools/$_name" ] && { echo "/data/backup_tools/$_name"; return 0; }
	return 1
}
check_key_tool(){
	local _name="$1" _level="$2" _p
	_p="$(key_tool_path "$_name" 2>/dev/null)"
	if [ -n "$_p" ] && [ -x "$_p" ]; then
		ok "關鍵工具 $_name" "$_p"
	else
		case "$_level" in
			critical) critical_fail "關鍵工具 $_name" "missing" ;;
			*) warn "關鍵工具 $_name" "missing" ;;
		esac
	fi
}
check_key_tool app_process critical
check_key_tool uidexec critical
check_key_tool jq critical
check_key_tool tar critical
check_key_tool zstd critical
check_key_tool busybox warn
check_key_tool smbclient warn
check_key_tool keycheck warn
check_key_tool procwait warn
check_key_tool eventwait warn
check_key_tool speedscan warn
check_key_tool unixsock warn
check_key_tool cgfreezerd warn
ok "dex_check 範圍" "core-only-r299: key tools + Dex capabilities only; live-safe observer default; split-awk WebDAV size fastmap with decimal integer sums"

case "$TOTAL" in
	''|dynamic|DYNAMIC) TOTAL="$IDX" ;;
	*[!0-9]*) log "測試項數量提示非數字: TOTAL=$TOTAL IDX=$IDX" ;;
	*) if [ "$IDX" -ne "$TOTAL" ]; then warn "測試項數量不一致" "IDX=$IDX TOTAL=$TOTAL"; fi ;;
esac
printf '\033[38;5;51m -dex core capability測試完成: ✅%s ❌%s ⚠️%s，詳情會打包在 speed_debug tar 內: dex_full_test.log\033[0m\n' "$OK" "$FAIL" "$WARN"
log "dex core capability測試完成: OK=$OK FAIL=$FAIL WARN=$WARN IDX=$IDX TOTAL=$TOTAL"
[ "$HAD_CMD_STDERR" = "1" ] && log "WARN unexpected stderr seen"
[ "$CRITICAL_FAIL" -gt 0 ] && exit 2
exit 0
