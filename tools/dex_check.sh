#!/system/bin/sh
# SpeedBackup dex_check - current Dex surface only / Dex v2.6.97
# 只檢測目前主線 Dex 與 tools.sh 正在使用的公開能力；不再做過時殘留/舊入口刪除類回歸掃描。
PKG="${1:-${PKG:-com.tencent.mobileqq}}"
USER_ID="${2:-${USER_ID:-0}}"
CLASSPATH_PATH="${CLASSPATH_PATH:-/data/backup_tools/classes.dex}"
TOOLS_PATH="${TOOLS_PATH:-}"
TEST_LOG_DIR="${TEST_LOG_DIR:-/data/local/tmp}"
TEST_LOG_FILE="${TEST_LOG_FILE:-$TEST_LOG_DIR/dex_check.log}"
TEST_SUMMARY_FILE="${TEST_SUMMARY_FILE:-$TEST_LOG_DIR/dex_full_test.summary}"
DEX_CHECK_VERSION="v24.20.14-7.66-492-remote-orphan-delta-label-r53-202607232022"
BACKUP_WIFI_ENABLE="${BACKUP_WIFI_ENABLE:-1}"
SB_SELFTEST_LEVEL="${SB_SELFTEST_LEVEL:-quick}"
CHANGELOG_URL="${CHANGELOG_URL:-https://api.github.com/repos/XayahSuSuSu/Android-DataBackup/releases/latest}"
SELFTEST_SCRIPT_VERSION="${SELFTEST_SCRIPT_VERSION:-v24.20.14-7.66-492-remote-orphan-delta-label-r53-202607232022}"
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
check_nonempty(){
	local _label="$1" _cls="$2" _out _rc
	shift 2
	_out="$(run_class "$_cls" "$@" 2>&1)"
	_rc=$?
	_out="$(printf '%s\n' "$_out" | sed -n '1,80p')"
	if [ "$_rc" -eq 0 ] && [ -n "$_out" ]; then ok "$_label" "rc=0"; else fail "$_label" "rc=$_rc"; fi
}
check_grep_warn(){
	local _label="$1" _pattern="$2" _cls="$3" _out _rc
	shift 3
	_out="$(run_class "$_cls" "$@" 2>&1)"
	_rc=$?
	_out="$(printf '%s\n' "$_out" | sed -n '1,160p')"
	printf '%s\n' "$_out" | grep -Eq "$_pattern" && ok "$_label" "rc=$_rc" || warn "$_label" "rc=$_rc"
}
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
log "=================================================="
log "SpeedBackup dex_check current surface"
log "pkg=$PKG user=$USER_ID classpath=$CLASSPATH_PATH tools=$TOOLS_PATH level=$SB_SELFTEST_LEVEL dex_check=$DEX_CHECK_VERSION"
log "selftest_version=$SELFTEST_SCRIPT_VERSION"
log "speedbackup_patch_build=$SPEEDBACKUP_PATCH_BUILD"
log "=================================================="

if [ -f "$CLASSPATH_PATH" ]; then ok "classes.dex 存在" "$(wc -c < "$CLASSPATH_PATH" 2>/dev/null | tr -d ' ') bytes"; else critical_fail "classes.dex 存在" "$CLASSPATH_PATH"; fi
if ! get_pkg_uid "$PKG" >/dev/null 2>&1; then
	_new="$(first_user_pkg)"
	if [ -n "$_new" ]; then warn "測試包切換" "$PKG -> $_new"; PKG="$_new"; fi
fi
_uidexec="$(command -v uidexec 2>/dev/null)"; [ -n "$_uidexec" ] || _uidexec="/data/backup_tools/uidexec"
if [ -x "$_uidexec" ]; then
	_out="$(uidexec 0 0 /data "$CLASSPATH_PATH" /system/bin/id 2>&1 | head -n 1)"
	echo "$_out" | grep -q 'uid=0' && ok "uidexec root 執行環境" "rc=0" || fail "uidexec root 執行環境" "$_out"
	_play_uid="$(get_pkg_uid "$PLAY_PKG" 2>/dev/null)"
	if echo "$_play_uid" | grep -qE '^[0-9]+$'; then
		_data_dir="/data/user/$USER_ID/$PLAY_PKG"; [ -d "$_data_dir" ] || _data_dir="/data"
		_out="$(uidexec "$_play_uid" "$_play_uid" "$_data_dir" "$CLASSPATH_PATH" /system/bin/id 2>&1 | head -n 1)"
		echo "$_out" | grep -q "uid=$_play_uid" && ok "uidexec Play UID 執行環境" "rc=0" || fail "uidexec Play UID 執行環境" "$_out"
	else
		warn "uidexec Play UID 執行環境" "Play UID不可讀"
	fi
else
	fail "uidexec root 執行環境" "uidexec_not_found"
	fail "uidexec Play UID 執行環境" "uidexec_not_found"
fi

_dex_ver_now="$(run_dex --version 2>&1 | head -n 30)"
echo "$_dex_ver_now" | grep -q 'v2.6.97-app-inventory-source-path-cache-single-tools-unified-root-webdav-deep-hiddenapi-sync-webdav-eof-quiet-appops-location-verify' && ok "Dex版本 v2.6.97 AppInventory source path cache" "rc=0" || critical_fail "Dex版本 v2.6.97 AppInventory source path cache" "$_dex_ver_now"
echo "$_dex_ver_now" | grep -q 'build=v24.20.14-7.66-484-app-inventory-source-path-r45-202607232022' && ok "Dex build 484/r45 contract" "rc=0" || critical_fail "Dex build 484/r45 contract" "$_dex_ver_now"
_wdav_ver_now="$(run_class_stdout "$WEBDAV_CLASS" version)"; _wdav_ver_rc=$?
printf '%s\n' "$_wdav_ver_now" | grep -q 'v1.5.20-unified-root-webdav-deep-policy dex=v2.6.97-app-inventory-source-path-cache-single-tools-unified-root-webdav-deep-hiddenapi-sync-webdav-eof-quiet-appops-location-verify' && [ "$_wdav_ver_rc" -eq 0 ] \
	&& ok "WebDavUtil版本 v1.5.20 / Dex v2.6.97" "rc=0" || critical_fail "WebDavUtil版本 v1.5.20 / Dex v2.6.97" "rc=$_wdav_ver_rc $_wdav_ver_now"
_root_ver_now="$(run_class_stdout "$ROOT_DAEMON_CLASS" version)"; _root_ver_rc=$?
printf '%s\n' "$_root_ver_now" | grep -q 'v2.6.97-app-inventory-source-path-cache-single-tools-unified-root-webdav-deep-hiddenapi-sync-webdav-eof-quiet-appops-location-verify' && [ "$_root_ver_rc" -eq 0 ] \
	&& ok "SpeedBackupRootDaemon版本可讀" "rc=0" || critical_fail "SpeedBackupRootDaemon版本可讀" "rc=$_root_ver_rc $_root_ver_now"

_hidden_bypass_out="$(run_dex hiddenApiBypassStatus 2>&1 | head -n 5)"
echo "$_hidden_bypass_out" | grep -Eq 'HIDDEN_API_BYPASS|status=|available=' && ok "AndroidHiddenApiBypass狀態入口" "$_hidden_bypass_out" || fail "AndroidHiddenApiBypass狀態入口" "$_hidden_bypass_out"
_help_full="$(run_dex help 2>&1 | head -n 320)"
[ -n "$_help_full" ] && ok "HiddenApiUtil help可讀" "rc=0" || fail "HiddenApiUtil help可讀" "empty"
for _cmd in getPackageLabel getPackageArchiveInfo getInstalledPackagesAsUser appInventorySnapshot appOpsScopeDetail setDisplayPowerMode forceStopPackageBatch; do
	echo "$_help_full" | grep -Eq "^[[:space:]]+${_cmd}([[:space:]]|$)" && ok "HiddenApiUtil目前入口 $_cmd" "present" || fail "HiddenApiUtil目前入口 $_cmd" "missing"
done
echo "$_help_full" | grep -q 'daemon-only commands: getPackageUid / getInstallSourceInfo / installSessionCreate / installSessionCommit' \
	&& ok "HiddenApiUtil daemon-only 熱路徑說明" "present" || fail "HiddenApiUtil daemon-only 熱路徑說明" "missing"
check_nonempty "取得名稱" "$HIDDEN_CLASS" getPackageLabel "$USER_ID" "$PKG"
check_nonempty "已安裝清單 label" "$HIDDEN_CLASS" getInstalledPackagesAsUser "$USER_ID" user label
check_nonempty "已安裝清單 pkgName" "$HIDDEN_CLASS" getInstalledPackagesAsUser "$USER_ID" user pkgName
check_nonempty "已安裝清單 flag" "$HIDDEN_CLASS" getInstalledPackagesAsUser "$USER_ID" user flag
check_nonempty "AppInventory jsonl" "$HIDDEN_CLASS" appInventorySnapshot "$USER_ID" jsonl all
check_nonempty "AppInventory appinfo" "$HIDDEN_CLASS" appInventorySnapshot "$USER_ID" appinfo "user|system|xposed"
check_nonempty "AppInventory pkgVerMap" "$HIDDEN_CLASS" appInventorySnapshot "$USER_ID" pkgVerMap all
check_nonempty "AppInventory pkgUidMap" "$HIDDEN_CLASS" appInventorySnapshot "$USER_ID" pkgUidMap all
check_nonempty "AppInventory pkgEnabledMap" "$HIDDEN_CLASS" appInventorySnapshot "$USER_ID" pkgEnabledMap all
check_nonempty "AppInventory sourceDirMap" "$HIDDEN_CLASS" appInventorySnapshot "$USER_ID" sourceDirMap all
check_nonempty "AppInventory pkgApkPathMap" "$HIDDEN_CLASS" appInventorySnapshot "$USER_ID" pkgApkPathMap all
run_timeout_suppressed "AppInventory splitSourceDirsMap" 20 env CLASSPATH="$CLASSPATH_PATH" app_process /system/bin "$HIDDEN_CLASS" appInventorySnapshot "$USER_ID" splitSourceDirsMap all
check_nonempty "AppOps scope detail 讀取" "$HIDDEN_CLASS" appOpsScopeDetail "$USER_ID" "[$PKG 26 27]"

_caps_out="$(run_class_stdout "$APPSTATE_CLASS" capabilities)"; _caps_rc=$?
if [ "$_caps_rc" -ne 0 ] || ! printf '%s\n' "$_caps_out" | jq -e . >/dev/null 2>&1; then
	critical_fail "Dex capabilities可讀" "rc=$_caps_rc"
else
	ok "Dex capabilities可讀" "rc=0"
	printf '%s\n' "$_caps_out" > "$TEST_LOG_DIR/appstate_capabilities.json" 2>/dev/null
	_caps_check='def cap($n): any(.capabilities[]?; .name==$n and .enabled==true);
		(.schemaVersion==2) and (.daemonProtocolVersion==1) and
		((.engineVersion//"")|startswith("v1.3.35-ssaid-metadata-restore")) and
		((.dexVersion//"")|startswith("v2.6.97-app-inventory-source-path-cache-single-tools-unified-root-webdav-deep-hiddenapi-sync-webdav-eof-quiet-appops-location-verify")) and
		cap("dex.capabilities.v1") and cap("dex.root_unified_daemon.v1") and cap("dex.app_inventory.snapshot.v1") and cap("dex.app_inventory.daemon_cache.v1") and cap("dex.app_inventory.source_paths.v1") and
		cap("appstate.snapshot.batch.v2") and cap("appstate.snapshot.compact_persist.v1") and
		cap("appstate.foreground_state.batch.v1") and cap("appstate.foreground_state.simple_batch.v1") and cap("appstate.foreground_state.robust.v1") and
		cap("appstate.foreground_running.v1") and cap("appstate.foreground_top.v1") and cap("appstate.foreground_list.json.v1") and cap("appstate.foreground_list.simple_json.v1") and
		cap("appstate.shared_payload.v1") and cap("appstate.special_access.integrated.v1") and
		cap("appstate.restore.batch.v4") and cap("appstate.verify.batch.v4") and
		cap("appstate.appops_reset.integrated.v1") and cap("appstate.ssaid.integrated.v1") and cap("appstate.ssaid.hardening.v1") and cap("appstate.ssaid.metadata_restore.v1") and
		cap("appstate.appops.effective_scope_drift.v2") and
		cap("appstate.structured_result_codes.v2") and cap("appstate.scoped_appops_fields.v1") and cap("appstate.explicit_package_mode_snapshot.v1") and
		cap("appstate.default_appop_missing_equivalent.v1") and cap("appstate.permission_denied_item_partial.v1") and
		cap("appstate.non_ok_structured_body.v1") and cap("appstate.legacy_permission_normalize.v1") and cap("appstate.runtime_permission_uid_restore.v1") and cap("appstate.permission_flags.stable_mask.v1") and cap("appstate.special_access.deduplicated.v1") and
		cap("appstate.localization.dex.v1") and cap("appstate.localization.raw_plus_cn.v1") and
		cap("appstate.batch_preflight_validation.v1") and cap("dex.machine_stdout.v1") and
		cap("dex.cchelper.glossary.v1") and cap("dex.cchelper.table_refresh.v1") and cap("dex.cchelper.zh_tw_polish.v1") and cap("dex.cchelper.repeat_merge_fix.v1") and
		cap("appstate.daemon.af_unix.v1") and cap("appstate.daemon.runtime_preinit.v1") and cap("dex.daemon_bootstrap.shared.v1") and cap("dex.daemon_bootstrap.sequential_guard.v1") and cap("dex.google_package_snapshot.shared.v1") and
		cap("webdav.rel_only.v1") and cap("webdav.base_preflight.dex.v1") and cap("webdav.directory_ensure.dex.v1") and cap("webdav.options_preflight.dex.v1") and cap("dex.source.libsardine_removed.v1") and
		cap("webdav.daemon.af_unix") and cap("webdav.daemon.mkcol_cache.v1") and cap("webdav.daemon.list_cache.v1") and cap("webdav.putbatchrel.v1") and cap("webdav.managed_put.v1") and cap("webdav.managed_probe.v1") and cap("webdav.cjk_put_replay_probe.v1") and cap("webdav.managed_probe.nodot_temp.v1") and cap("webdav.stream_probe.subdir.v1") and cap("webdav.daemon.normal_diagnostics_log.v1") and
		cap("webdav.rclone_json_direct_put.dex.v1") and cap("webdav.rclone_direct_all.dex.v1") and cap("webdav.pan123_managed_direct.dex.v1") and cap("dex.daemon_hardening.oom_protect.v1") and cap("dex.daemon_supervisor.watchdog.v1") and cap("dex.http_util.get.v1") and
		cap("webdav.compat_probe.v1") and cap("webdav.atomic_probe.v2") and cap("webdav.vendor_quirks.v1") and cap("webdav.vendor_auto_detect.v1") and cap("webdav.pacer_retry_backoff.v1") and cap("webdav.directory_cache.v1") and cap("webdav.propfind_xml_tolerant.v2") and cap("webdav.error_policy_table.v1") and cap("webdav.regression_suite.v1") and cap("webdav.buffer.autotune.v3") and cap("webdav.socket.read_idle_timeout.v1") and cap("webdav.socket.write_idle_watchdog.v1") and cap("webdav.empty_body_retry_before_payload") and
		cap("hiddenapi.lsposed_hiddenapibypass.v1") and cap("hiddenapi.daemon.af_unix.v1") and cap("hiddenapi.force_stop_package_batch.daemon.v1") and cap("hiddenapi.daemon.response_body.capture.fix.v1") and cap("hiddenapi.install_session.hybrid_write.v1") and cap("hiddenapi.hot_cli_removed.v1") and
		cap("notification.daemon.af_unix.v1") and cap("notification.hot_cli_removed.v1")'
	printf '%s\n' "$_caps_out" | jq -e "$_caps_check" >/dev/null 2>&1 && ok "current critical capabilities完整" "rc=0" || critical_fail "current critical capabilities完整" "contract_mismatch"
	for _rcode in 'OK=0' 'PARTIAL=10' 'BAD_REQUEST=20' 'PACKAGE_NOT_FOUND=30' 'UNSUPPORTED=40' 'PERMISSION_DENIED=50' 'VERIFY_MISMATCH=60' 'INTERNAL_ERROR=70'; do
		_rname="${_rcode%%=*}"; _rnum="${_rcode#*=}"
		printf '%s\n' "$_caps_out" | jq -e --arg n "$_rname" --argjson c "$_rnum" 'any(.resultCodes[]?; .name==$n and .code==$c)' >/dev/null 2>&1 \
			&& ok "結構化錯誤碼 $_rcode" "present" || critical_fail "結構化錯誤碼 $_rcode" "missing"
	done
fi

_appstate_ver="$(run_class_stdout "$APPSTATE_CLASS" --version)"; _appstate_ver_rc=$?
printf '%s\n' "$_appstate_ver" | grep -q 'v1.3.35-ssaid-metadata-restore' && [ "$_appstate_ver_rc" -eq 0 ] && ok "AppStateUtil版本" "rc=0" || critical_fail "AppStateUtil版本" "rc=$_appstate_ver_rc"
_appstate_help="$(run_class_stdout "$APPSTATE_CLASS" help)"; _appstate_help_rc=$?
[ "$_appstate_help_rc" -eq 0 ] && ok "AppStateUtil help可讀" "rc=0" || critical_fail "AppStateUtil help可讀" "rc=$_appstate_help_rc"
for _cmd in capabilities snapshotAppStateBatch foregroundStateBatch foregroundStateRunning foregroundTop foregroundListJson restoreAppStateBatch verifyAppStateBatch daemonunix; do
	printf '%s\n' "$_appstate_help" | grep -q "$_cmd" && ok "AppStateUtil目前入口 $_cmd" "present" || critical_fail "AppStateUtil目前入口 $_cmd" "missing"
done
_snap_out="$(run_class_stdout "$APPSTATE_CLASS" snapshotAppStateBatch "$USER_ID" "$PKG")"; _snap_rc=$?
printf '%s\n' "$_snap_out" > "$TEST_LOG_DIR/appstate_snapshot_probe.ndjson" 2>/dev/null
if [ "$_snap_rc" -eq 0 ] && printf '%s\n' "$_snap_out" | jq -s -e --arg p "$PKG" '
	def scoped: (has("scope") and ((.scope)=="package" or (.scope)=="uid" or (.scope)=="default" or (.scope)=="unsupported")) and (has("mode") or has("appOpMode"));
	(any(.[]; .recordType=="snapshot" and .schemaVersion==2 and .packageName==$p and (.result.name=="OK" or .result.name=="PARTIAL")
		and (.permissions|type)=="array" and (.specialAccess|type)=="object" and (.otherAppOps|type)=="array" and (.batterySettings|type)=="object" and has("ssaid") and (.installDiagnostics|type)=="object"
		and all(.permissions[]?; ((.appOp // -1) == -1) or scoped) and all(.specialAccess[]?; scoped) and all(.otherAppOps[]?; scoped))) and
	(any(.[]; .recordType=="summary" and .command=="snapshotAppStateBatch" and (.result.name=="OK" or .result.name=="PARTIAL")))
' >/dev/null 2>&1; then
	ok "snapshotAppStateBatch canonical schema2" "rc=0"
else
	critical_fail "snapshotAppStateBatch canonical schema2" "rc=$_snap_rc"
fi
_fg_out="$(run_class_stdout "$APPSTATE_CLASS" foregroundStateBatch "$USER_ID" "$PKG")"; _fg_rc=$?
printf '%s\n' "$_fg_out" > "$TEST_LOG_DIR/appstate_foreground_state_smoke.ndjson" 2>/dev/null
if [ "$_fg_rc" -eq 0 ] && printf '%s\n' "$_fg_out" | jq -s -e --arg p "$PKG" '
	any(.[]; .recordType=="foregroundState" and .packageName==$p and (.label|type)=="string" and (.active|type)=="boolean") and any(.[]; .recordType=="summary" and .command=="foregroundStateBatch")
' >/dev/null 2>&1; then ok "foregroundStateBatch schema" "rc=0"; else critical_fail "foregroundStateBatch schema" "rc=$_fg_rc"; fi
_run_out="$(run_class_stdout "$APPSTATE_CLASS" foregroundStateRunning "$USER_ID")"; _run_rc=$?
printf '%s\n' "$_run_out" > "$TEST_LOG_DIR/appstate_foreground_running_smoke.ndjson" 2>/dev/null
if [ "$_run_rc" -eq 0 ] && printf '%s\n' "$_run_out" | jq -s -e 'any(.[]; .recordType=="summary" and .command=="foregroundStateRunning")' >/dev/null 2>&1; then ok "foregroundStateRunning schema" "rc=0"; else critical_fail "foregroundStateRunning schema" "rc=$_run_rc"; fi
_list_out="$(run_class_stdout "$APPSTATE_CLASS" foregroundListJson "$USER_ID")"; _list_rc=$?
printf '%s\n' "$_list_out" > "$TEST_LOG_DIR/appstate_foreground_list_json_smoke.json" 2>/dev/null
if [ "$_list_rc" -eq 0 ] && printf '%s\n' "$_list_out" | jq -e '.recordType=="foregroundList" and (.result.name=="OK") and (.counts|type)=="object"' >/dev/null 2>&1; then ok "foregroundListJson schema" "rc=0"; else critical_fail "foregroundListJson schema" "rc=$_list_rc"; fi
_top_out="$(run_class_stdout "$APPSTATE_CLASS" foregroundTop "$USER_ID")"; _top_rc=$?
printf '%s\n' "$_top_out" > "$TEST_LOG_DIR/appstate_foreground_top_smoke.ndjson" 2>/dev/null
if [ "$_top_rc" -eq 0 ] && printf '%s\n' "$_top_out" | jq -s -e 'any(.[]; .recordType=="foregroundTop") and any(.[]; .recordType=="summary" and .command=="foregroundTop")' >/dev/null 2>&1; then ok "foregroundTop schema" "rc=0"; else critical_fail "foregroundTop schema" "rc=$_top_rc"; fi

check_grep_warn "HttpUtil說明" 'http|get|usage|用法|參數|command|指令|unknown|未知' "$HTTP_CLASS" help
run_timeout_suppressed "網路GET自動更新地址" 25 env CLASSPATH="$CLASSPATH_PATH" app_process /system/bin "$HTTP_CLASS" get "$CHANGELOG_URL"
check_grep_warn "NetworkUtil說明" 'wifi|network|usage|用法|參數|command|指令|unknown|未知' "$NETWORK_CLASS" help
if [ "$BACKUP_WIFI_ENABLE" = "1" ]; then
	run_timeout_suppressed "WiFi清單讀取" 20 env CLASSPATH="$CLASSPATH_PATH" app_process /system/bin "$NETWORK_CLASS" getNetworks
	run_timeout_suppressed "WiFi JSON備份" 20 env CLASSPATH="$CLASSPATH_PATH" app_process /system/bin "$NETWORK_CLASS" saveNetworks
	_network_help="$(run_class "$NETWORK_CLASS" help 2>&1)"
	printf '%s\n' "$_network_help" | grep -Eq '^[[:space:]]*restoreNetworks([[:space:]]|$)' && ok "WiFi restoreNetworks入口" "present" || fail "WiFi restoreNetworks入口" "missing"
else
	warn "WiFi清單讀取" "backup_wifi_enable=0"
	warn "WiFi JSON備份" "backup_wifi_enable=0"
	warn "WiFi restoreNetworks入口" "backup_wifi_enable=0"
fi
_cc_help="$(run_class "$CC_CLASS" help 2>&1 | head -n 120)"
echo "$_cc_help" | grep -q 's2t' && echo "$_cc_help" | grep -q 't2s' && ok "CCUtil s2t/t2s入口" "present" || fail "CCUtil s2t/t2s入口" "missing"
check_nonempty "繁簡轉換s2t" "$CC_CLASS" s2t 后台服务
check_nonempty "繁簡轉換t2s" "$CC_CLASS" t2s 後台服務

_wdav_help="$(run_class "$WEBDAV_CLASS" help 2>&1)"
for _cmd in daemon daemonunix mkdirrel mkdirsrel ensurebaserel ensuredirrel optionspreflightrel putrel putbatchrel putstdinmanagedrel putmanagedrel managedproberel compatProbeRel deleterel moverel copyrel statrel listrel optionsrel propfindrel encodepath decodepath; do
	printf '%s\n' "$_wdav_help" | grep -Eq "^[[:space:]]+${_cmd}([[:space:]]|$)" && ok "WebDavUtil目前rel入口 $_cmd" "present" || critical_fail "WebDavUtil目前rel入口 $_cmd" "missing"
done
printf '%s\n' "$_wdav_help" | grep -q 'webdav.rel_only.v1' && ok "WebDavUtil rel-only契約說明" "present" || critical_fail "WebDavUtil rel-only契約說明" "missing"
_smb_help="$(run_class "$SMB_SCAN_CLASS" help 2>&1 | head -n 120)"
echo "$_smb_help" | grep -q 'scanSmb' && ok "SmbScanUtil scanSmb入口" "present" || fail "SmbScanUtil scanSmb入口" "missing"
_notify_ver="$(run_class_stdout "$NOTIFICATION_CLASS" version)"; _notify_ver_rc=$?
printf '%s\n' "$_notify_ver" | grep -q 'v1.1.5-capability-text-fix' && [ "$_notify_ver_rc" -eq 0 ] && ok "NotificationUtil版本 v1.1.5" "rc=0" || critical_fail "NotificationUtil版本 v1.1.5" "rc=$_notify_ver_rc $_notify_ver"
_nhelp="$(CLASSPATH="$CLASSPATH_PATH" app_process /system/bin "$NOTIFICATION_CLASS" help 2>&1 | head -n 160)"
for _term in notifyBatch THROTTLE_MS ITEMS INBOX; do
	echo "$_nhelp" | grep -q "$_term" && ok "NotificationUtil目前說明 $_term" "present" || fail "NotificationUtil目前說明 $_term" "missing"
done

_TOOLS_FILE="$(find_tools_file 2>/dev/null)"
if [ -n "$_TOOLS_FILE" ] && [ -f "$_TOOLS_FILE" ]; then
	_shn_out="$(sh -n "$_TOOLS_FILE" 2>&1)"; _shn_rc=$?
	[ "$_shn_rc" -eq 0 ] && ok "tools.sh sh -n" "rc=0" || critical_fail "tools.sh sh -n" "rc=$_shn_rc $_shn_out"
	grep -q 'SPEEDBACKUP_EXPECT_DEX_PREFIX="v2.6.97-app-inventory-source-path-cache-single-tools-unified-root-webdav-deep-hiddenapi-sync-webdav-eof-quiet-appops-location-verify"' "$_TOOLS_FILE" && ok "tools.sh Dex prefix contract" "present" || critical_fail "tools.sh Dex prefix contract" "missing"
	grep -q 'com.xayah.dex.SpeedBackupRootDaemon' "$_TOOLS_FILE" && grep -q '_root_daemon_call_appstate' "$_TOOLS_FILE" && ok "tools.sh RootDaemon AppState路線" "present" || critical_fail "tools.sh RootDaemon AppState路線" "missing"
	grep -q '_root_daemon_call_args_hot hiddenapi' "$_TOOLS_FILE" && grep -q '_install_daemon_call_args' "$_TOOLS_FILE" && ok "tools.sh HiddenApi/Install daemon路線" "present" || critical_fail "tools.sh HiddenApi/Install daemon路線" "missing"
	grep -q 'appinventory()' "$_TOOLS_FILE" && grep -q 'appInventorySnapshot' "$_TOOLS_FILE" && grep -q 'APP_INVENTORY_VER_MAP_OK' "$_TOOLS_FILE" && grep -q 'APP_INVENTORY_APK_PATH_MAP_OK' "$_TOOLS_FILE" && ok "tools.sh AppInventory共用map路線" "present" || critical_fail "tools.sh AppInventory共用map路線" "missing"

	! grep -q 'dex_hiddenapi getInstalledPackagesAsUser "$USER_ID" "$@"' "$_TOOLS_FILE" && ok "tools.sh appinfo舊generic fallback已清理" "absent" || critical_fail "tools.sh appinfo舊generic fallback已清理" "present"
	! grep -q 'pm list packages --show-versioncode --user' "$_TOOLS_FILE" && ok "tools.sh versionCode pm fallback已清理" "absent" || critical_fail "tools.sh versionCode pm fallback已清理" "present"
	! grep -q 'dumpsys package "$_pkg"' "$_TOOLS_FILE" && ok "tools.sh dumpsys package version fallback已清理" "absent" || critical_fail "tools.sh dumpsys package version fallback已清理" "present"
	! grep -q 'pm list packages -U --user "${user:-0}"' "$_TOOLS_FILE" && ok "tools.sh uid pm fallback已清理" "absent" || critical_fail "tools.sh uid pm fallback已清理" "present"
	grep -q 'ORPHAN_BACKUP_CLEANUP_SKIP context=.*installed_map_unavailable' "$_TOOLS_FILE" && ok "tools.sh orphan cleanup嚴格installed map" "present" || critical_fail "tools.sh orphan cleanup嚴格installed map" "missing"
	! grep -q 'cmd package list packages' "$_TOOLS_FILE" && ok "tools.sh cmd package fallback已清理" "absent" || critical_fail "tools.sh cmd package fallback已清理" "present"
	! grep -q 'pm path --user.*\$name2' "$_TOOLS_FILE" && ok "tools.sh app備份/恢復 pm path name2 fallback已清理" "absent" || critical_fail "tools.sh app備份/恢復 pm path name2 fallback已清理" "present"
	! grep -q 'pm list packages -d --user.*com.android.vending' "$_TOOLS_FILE" && ok "tools.sh Play disabled pm fallback已清理" "absent" || critical_fail "tools.sh Play disabled pm fallback已清理" "present"
	grep -q 'pkgApkPathMap' "$_TOOLS_FILE" && grep -q 'get_current_apk_paths' "$_TOOLS_FILE" && ok "tools.sh APK path AppInventory路線" "present" || critical_fail "tools.sh APK path AppInventory路線" "missing"
	grep -q 'REMOTE_TOTAL_DELTA_LABEL mode=infra_only_all_apps_fast_skip' "$_TOOLS_FILE" && grep -q '.stream_all_apps_fast_skipped' "$_TOOLS_FILE" && ok "tools.sh 遠端全fast-skip總量提示" "present" || critical_fail "tools.sh 遠端全fast-skip總量提示" "missing"
	grep -q 'REMOTE_TOTAL_DELTA_LABEL mode=remote_orphan_cleanup' "$_TOOLS_FILE" && grep -q '.remote_orphan_cleanup_removed' "$_TOOLS_FILE" && ok "tools.sh 遠端孤兒清理總量提示" "present" || critical_fail "tools.sh 遠端孤兒清理總量提示" "missing"
	grep -q '_root_daemon_prewarm_bg' "$_TOOLS_FILE" && grep -q 'ROOT_DAEMON_PREWARM_SPAWN' "$_TOOLS_FILE" && grep -q '_root_daemon_prewarm_before_feature' "$_TOOLS_FILE" && grep -q '_root_daemon_prewarm_early_start' "$_TOOLS_FILE" && grep -q 'ROOT_DAEMON_PREWARM_EARLY_REQUEST' "$_TOOLS_FILE" && ok "tools.sh RootDaemon提前背景預熱" "present" || critical_fail "tools.sh RootDaemon提前背景預熱" "missing"
	grep -q '_root_notify_call_file' "$_TOOLS_FILE" && grep -q '_root_daemon_call_file_hot notify' "$_TOOLS_FILE" && ok "tools.sh Notification RootDaemon路線" "present" || critical_fail "tools.sh Notification RootDaemon路線" "missing"
	grep -q 'snapshotAppStateBatch' "$_TOOLS_FILE" && grep -q '_appstate_snapshot_to_maps' "$_TOOLS_FILE" && grep -q '.pkg_appstate' "$_TOOLS_FILE" && ok "tools.sh AppState canonical map路線" "present" || critical_fail "tools.sh AppState canonical map路線" "missing"
	grep -q '.batch_appstate_ndjson' "$_TOOLS_FILE" && grep -Eq '_root_appstate_call[[:space:]]+restoreAppStateBatch' "$_TOOLS_FILE" && grep -Eq '_root_appstate_call[[:space:]]+verifyAppStateBatch' "$_TOOLS_FILE" && ok "tools.sh AppState restore/verify payload路線" "present" || critical_fail "tools.sh AppState restore/verify payload路線" "missing"
	grep -q 'com.xayah.dex.WebDavUtil' "$_TOOLS_FILE" && grep -q 'daemonunix' "$_TOOLS_FILE" && grep -q 'relay-unix' "$_TOOLS_FILE" && ok "tools.sh WebDAV AF_UNIX daemon路線" "present" || critical_fail "tools.sh WebDAV AF_UNIX daemon路線" "missing"
	grep -q 'putstdinmanagedrel' "$_TOOLS_FILE" && grep -q 'getrel' "$_TOOLS_FILE" && grep -q 'listrel' "$_TOOLS_FILE" && ok "tools.sh WebDAV rel串流路線" "present" || critical_fail "tools.sh WebDAV rel串流路線" "missing"
	grep -q 'com.xayah.dex.SmbScanUtil' "$_TOOLS_FILE" && grep -q 'scanSmb' "$_TOOLS_FILE" && ok "tools.sh SMB預掃Dex路線" "present" || fail "tools.sh SMB預掃Dex路線" "missing"
else
	warn "tools.sh目前Dex路線檢查" "TOOLS_PATH不存在"
fi

case "$TOTAL" in
	''|dynamic|DYNAMIC) TOTAL="$IDX" ;;
	*[!0-9]*) log "測試項數量提示非數字: TOTAL=$TOTAL IDX=$IDX" ;;
	*) if [ "$IDX" -ne "$TOTAL" ]; then warn "測試項數量不一致" "IDX=$IDX TOTAL=$TOTAL"; fi ;;
esac
printf '\033[38;5;51m -dex current surface測試完成: ✅%s ❌%s ⚠️%s，詳情會打包在 speed_debug tar 內: dex_full_test.log\033[0m\n' "$OK" "$FAIL" "$WARN"
log "dex current surface測試完成: OK=$OK FAIL=$FAIL WARN=$WARN IDX=$IDX TOTAL=$TOTAL"
[ "$HAD_CMD_STDERR" = "1" ] && log "WARN unexpected stderr seen"
[ "$CRITICAL_FAIL" -gt 0 ] && exit 2
[ "$FAIL" -gt 0 ] && exit 1
exit 0
