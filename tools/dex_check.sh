#!/system/bin/sh
# SpeedBackup dex_check; script functionality and build come from versions.properties.
# 不再鎖 Dex 版本字串、build 號、tools.sh patch marker 或歷史回歸 grep；只檢查目前 tools 真正依賴的 Dex 核心能力是否可用。
PKG="${1:-${PKG:-com.tencent.mobileqq}}"
USER_ID="${2:-${USER_ID:-0}}"
CLASSPATH_PATH="${CLASSPATH_PATH:-/data/backup_tools/classes.dex}"
TOOLS_PATH="${TOOLS_PATH:-}"
TEST_LOG_DIR="${TEST_LOG_DIR:-${PWD:-.}}"
TEST_LOG_FILE="${TEST_LOG_FILE:-$TEST_LOG_DIR/dex_check.log}"
TEST_SUMMARY_FILE="${TEST_SUMMARY_FILE:-$TEST_LOG_DIR/dex_full_test.summary}"
DEX_CHECK_VERSION="v778"
DEX_CHECK_BUILD="v780"
BACKUP_WIFI_ENABLE="${BACKUP_WIFI_ENABLE:-1}"
SB_SELFTEST_LEVEL="${SB_SELFTEST_LEVEL:-quick}"
CHANGELOG_URL="${CHANGELOG_URL:-https://api.github.com/repos/XayahSuSuSu/Android-DataBackup/releases/latest}"
SELFTEST_SCRIPT_VERSION="${SELFTEST_SCRIPT_VERSION:-$DEX_CHECK_VERSION}"
SPEEDBACKUP_PATCH_BUILD="${SPEEDBACKUP_PATCH_BUILD:-$DEX_CHECK_BUILD}"
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
DEX_CHECK_TMPDIR="${DEX_CHECK_TMPDIR:-/data/local/tmp/.speedbackup_run_dexcheck_${$}}"
mkdir -p "$DEX_CHECK_TMPDIR" 2>/dev/null || DEX_CHECK_TMPDIR="${TMPDIR:-/data/local/tmp}"
case "$DEX_CHECK_TMPDIR" in /data/local/tmp/.speedbackup_run_*) DEX_CHECK_TMPDIR_OWN=1 ;; *) DEX_CHECK_TMPDIR_OWN=0 ;; esac
TMPDIR="$DEX_CHECK_TMPDIR"
SPEEDBACKUP_RUN_TMPDIR="$DEX_CHECK_TMPDIR"
SPEEDBACKUP_CGROUP_FREEZER_SOCKET="$DEX_CHECK_TMPDIR/speedbackup_cgfreezerd.sock"
SPEEDBACKUP_PROCESS_OBSERVER_BATCH_STATE_DIR="$DEX_CHECK_TMPDIR/.speedbackup_process_observer_batch_state"
SPEEDBACKUP_WAKEBLOCK_STATE_DIR="$DEX_CHECK_TMPDIR/.speedbackup_wakeblock_state"
SPEEDBACKUP_UID_NETBLOCK_STATE_DIR="$DEX_CHECK_TMPDIR/.speedbackup_uid_netblock_state"
SPEEDBACKUP_CGROUP_FREEZER_STATE_FILE="$DEX_CHECK_TMPDIR/.speedbackup_cgroup_freezer_state"
SPEEDBACKUP_NOTIFY_STATE_DIR="$DEX_CHECK_TMPDIR/.speedbackup_notify_state"
export TMPDIR SPEEDBACKUP_RUN_TMPDIR SPEEDBACKUP_CGROUP_FREEZER_SOCKET SPEEDBACKUP_PROCESS_OBSERVER_BATCH_STATE_DIR SPEEDBACKUP_WAKEBLOCK_STATE_DIR SPEEDBACKUP_UID_NETBLOCK_STATE_DIR SPEEDBACKUP_CGROUP_FREEZER_STATE_FILE SPEEDBACKUP_NOTIFY_STATE_DIR
cleanup_dexcheck_tmpdir(){ [ "${DEX_CHECK_TMPDIR_OWN:-0}" = 1 ] && rm -rf "$DEX_CHECK_TMPDIR" 2>/dev/null || true; }
trap cleanup_dexcheck_tmpdir EXIT INT TERM
mkdir -p "$TEST_LOG_DIR" 2>/dev/null
: > "$TEST_LOG_FILE" 2>/dev/null || TEST_LOG_FILE="$DEX_CHECK_TMPDIR/dex_check_$$.log"
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
	local _cls="$1" _out="${DEX_CHECK_TMPDIR:-/data/local/tmp}/sb_dex_selftest_stdout_$$" _err="${DEX_CHECK_TMPDIR:-/data/local/tmp}/sb_dex_selftest_stderr_$$" _rc
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
	local _cls="$1" _out="${DEX_CHECK_TMPDIR:-/data/local/tmp}/sb_dex_selftest_json_stdout_$$" _err="${DEX_CHECK_TMPDIR:-/data/local/tmp}/sb_dex_selftest_json_stderr_$$" _rc
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
		([
			"dex.capabilities.v1",
			"dex.machine_stdout.v1",
			"dex.label_path_segment_safe.v1",
			"dex.webdav.relpath_traversal_guard.v1",
			"dex.root_unified_daemon.v1",
			"dex.root_daemon.ready_before_appstate_init.v1",
			"dex.root_daemon.ready_before_hiddenapi_init.v1",
			"dex.root_daemon.ready_before_hardening.v1",
			"dex.root_daemon.capability_signature.compilefix.v1",
			"dex.daemon_supervisor.r8_keep.v1",
			"hiddenapi.daemon.af_unix.v1",
			"hiddenapi.force_stop_package_batch.daemon.v1",
			"dex.app_inventory.snapshot.v1",
			"dex.app_inventory.pkg_uid.single.v1",
			"dex.app_inventory.package_status.single.v1",
			"dex.app_inventory.package_filter_batch.v1",
			"dex.app_inventory.getlist_onecall.v1",
			"dex.app_inventory.display_label_facts.v1",
			"dex.cgroup.lock_metrics.v1",
			"dex.app_inventory.xposed_module_facts.v1",
			"dex.app_inventory.xposed_runtime_facts.v1",
			"dex.app_inventory.package_facts.batch.v1",
			"dex.pm.pre_restore_package_state.batch.v1",
			"dex.pm.installer_context_facts.v1",
			"dex.pm.restore_install_plan.v1",
			"dex.pm.restore_install_plan_batch.v1",
			"webdav.profile_contract.dex.v1",
			"webdav.profile_contract_full.dex.v1",
				"webdav.profile_contract_authoritative.dex.v1",
				"dex.appstate.android16_17_policy_contract.v1",
			"dex.hidden_api.bypass_softgate.v1",
			"appstate.snapshot.batch.v2",
			"appstate.snapshot.batch.parallel.v1",
			"appstate.snapshot.direct_files.v1",
			"appstate.snapshot.direct_files.single_pass.v1",
			"appstate.snapshot.direct_files.telemetry_v2.v1",
			"appstate.restore.batch.v4",
			"appstate.verify.batch.v4",
			"appstate.run_results.v1",
			"appstate.result_files.v1",
			"appstate.ssaid.typed_result.v1",
			"dex.control_results.v1",
			"webdav.stream_result.v1",
			"webdav.chunk_write_coalesced.v1",
			"dex.result_contract.v1",
			"appstate.verify.vendor_classification.dex.v1",
			"appstate.restore.vendor_classification.dex.v1",
			"appstate.restore.permission_appop_vendor_classification.dex.v1",
			"appstate.android17_runtime_permission_appop_package_fallback.v1",
			"appstate.android17_location_appop_policy_classification.v1",
			"appstate.verify.android17_platform_permission_policy.dex.v1",
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
			"dex.build_info.unified_version.v1",
			"dex.daemon.read_exactly.body_limit.v1",
			"dex.daemon.token_seed_shared.v1",
			"dex.notification.peer_credentials_uid.v1",
			"dex.notification.peer_uid_fail_closed.v1",
			"dex.ssaid.state_cache_shutdown.v1",
			"dex.ssaid.state_cache_shutdown_bounded.v1",
			"dex.daemon_supervisor.pid_starttime.v1",
			"dex.daemon_supervisor.pid_starttime_cmdline.v1",
			"dex.cchelper.table_hardening.v1",
			"dex.device_model_db.entry_count_runtime.v1",
			"dex.device_model_db.entry_count_selfcheck.v1",
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
            "dex.process_observer.batch_cleanup_stale.v1",
            "dex.tmp_state.run_tmpdir_scope.v1",
            "dex.process_observer.batch_stop_summary_tsv.v1",
			"dex.app_wake_block.persistent_restore.v1",
			"dex.app_wake_block.cleanup_restore_failed_retain_state.v1",
			"dex.app_wake_block.snapshot_unsafe_refuse_apply.v1",
			"dex.uid_net_block.persistent_restore.v1",
			"dex.uid_net_block.cleanup_restore_failed_retain_state.v1",
			"dex.cgroup_freezer.lifecycle.v1",
			"dex.cgroup_freezer.persistent_batch_session.v1",
			"dex.cgroup_freezer.native_package_atomic.v1",
			"dex.cgroup_freezer.primary_app_scope_package_freeze.v1",
			"dex.cgroup_freezer.primary_app_scope_refresh.v1",
			"dex.process_observer.primary_cgroup_refresh.v1",
			"dex.process_observer.wake_block_stop_defer_to_app_scope.v1",
			"dex.cgroup_freezer.native_package_kill_live_rescan.v1",
			"dex.cgroup_freezer.native_thaw_uid_emergency.v1",
			"dex.cgroup_freezer.daemon_parent_control.v1",
			"dex.display_power.root_daemon.v1",
			"webdav.rel_only.v1",
			"webdav.managed_put.v1",
            "webdav.putstdin.skip_parent_mkdir.v1",
			"webdav.managed_list_classify.v1",
			"webdav.classify_depth1_walk_fallback.dex.v1",
			"webdav.managed_batch_put_with_parents.v1",
			"webdav.propfind.no_cache.v1",
			"webdav.stream_heartbeat_error_kind.dex.v1",
			"webdav.daemon.read_body_limit.v1",
			"webdav.tsv_output.control_guard.v1",
			"webdav.direct_children_manifest.dex.v1",
			"webdav.prepare_dirs_created_only_progress.dex.v1",
			"webdav.prepare_dirs_full_timing.dex.v1",
			"webdav.prepare_dirs_parallel_mkcol.dex.v1",
			"webdav.classify_parallel_depth1.dex.v1",
			"webdav.profile_visible_compact.dex.v1",
			"webdav.download_manifest.dex.v1",
			"webdav.orphan_roots_manifest.dex.v1",
			"dex.daemon.common_framed_reader.v1",
			"rust.native_replacement_rc.v1",
			"webdav.stream_stall_watchdog.dex.v1",
			"webdav.stream_stall_socket_abort.dex.v1",
			"webdav.stream_post_body_response_timeout.dex.v1",
			"webdav.stream_post_body_phase_guard.dex.v1",
			"webdav.alist_new_payload_direct.dex.v1",
			"webdav.known_missing_direct_by_fact.dex.v1",
			"webdav.alist_openlist_sync_put_semantics.dex.v1",
			"webdav.pathmode_retry_http400.dex.v1",
			"webdav.backend_profile.dex.v1",
			"webdav.server_provider_profile.dex.v1",
			"webdav.redirect_auth_guard.dex.v1",
			"webdav.feature_profile.dex.v1",
			"webdav.feature_profile_complete.dex.v1",
			"webdav.backend_contract_probe.dex.v1",
			"webdav.list_strategy_by_fact.dex.v1",
			"webdav.fixed_put_chunked_fallback.dex.v1",
			"webdav.nas_identity_profile.dex.v1",
			"webdav.speedbackup_identity.dex.v1",
			"webdav.sftpgo_identity.dex.v1",
			"webdav.zspace_identity.dex.v1",
			"webdav.nas_identity_extended.dex.v1",
			"webdav.generic_nas_dav5005_identity.dex.v1",
			"webdav.replayable_put_paths_fact_driven.dex.v1",
			"webdav.atomic_policy_fact_priority.dex.v1",
			"webdav.managed_probe_chunked.dex.v1",
			"webdav.backend_support_tier.dex.v1",
			"webdav.pacer_retry_after_jitter.dex.v1",
			"webdav.move_copy_verify_after_ambiguous.dex.v1",
			"webdav.put_verify_after_ambiguous.dex.v1",
			"webdav.put_405_ambiguous_stat.dex.v1",
			"webdav.direct_put_verify_before_cleanup.dex.v1",
			"webdav.put_2xx_body_semantic_guard.dex.v1",
			"webdav.put_2xx_stat_verify.dex.v1",
			"webdav.cloudreve_identity.dex.v1",
			"webdav.alist_version_security_advisory.dex.v1",
			"webdav.quota_probe.dex.v1",
			"webdav.upload_size_verify_batch.dex.v1",
			"webdav.locked_cleanup_deferred.dex.v1",
			"webdav.jianguoyun_500m_guard.dex.v1",
			"webdav.backend_decision_log.dex.v1",
			"rust.native_primitives.convergence_source.v1",
			"dex.smb.target_probe.v1",
			"notification.daemon.af_unix.v1",
			"notification.inline_small_icon.v1"
		] | all(.[]; cap(.)))
	' "$_file" >/dev/null 2>&1 && ok "$_label" "核心能力齊全" || critical_fail "$_label" "缺少必要能力，請重編/替換 classes.dex"
}

log "=================================================="
log "SpeedBackup dex_check 使用者可讀分組檢查"
log "pkg=$PKG user=$USER_ID classpath=$CLASSPATH_PATH tools=$TOOLS_PATH level=$SB_SELFTEST_LEVEL"
log "policy=final_user_groups_logged required_core optional_facts reverted_display_timeout_direct native_pack_plan_facts webdav_stream_stall_watchdog webdav_stream_stall_socket_abort webdav_stream_post_body_response_timeout webdav_stream_post_body_phase_guard webdav_alist_new_payload_direct webdav_pathmode_retry_http400 speedscan_nonblocking_timeout speedscan_prescan_singlepass speedscan_tsv_decimal_sum payload_compression_zstd_aligned_parser payload_prescan_exact_tar_input webdav_backend_profile webdav_server_provider_profile speedscan_entryfacts_fastskip_join stream_entry_perf_child_elapsed rust_capability_only tools_runtime_capability_only eventwait_capability_only webdav_known_missing_direct_by_fact webdav_alist_openlist_sync_put_semantics stream_entry_post_body_semantics remote_stream_local_read_release webdav_compact_profile_created_only_dirs appdetails_bundle_no_shrink_guard appdetails_bundle_payload_set_cover_guard single_apk_parse_session_fallback single_apk_sdk36_session_first installer_context_facts_direct_parse single_apk_session_all_sdk_no_legacy single_apk_session_log_dedupe dex_webdav_profile_contract install_plan_diagnostic speedscan_appdetails_bundle_audit speedscan_appdetails_bundle_manifest speedscan_remote_manifest_plan speedscan_restore_payload_plan speedscan_manifest_diff_cache_index speedscan_full_convergence_stage3 speedscan_manifest_diff_cache_index_v2 speedscan_selected_apps_map speedscan_appdetails_summary_map speedscan_appstate_match_map speedscan_remote_orphan_candidates speedscan_full_convergence_stage4 speedscan_full_convergence_stage5 webdav_profile_contract_authoritative dex_appstate_android16_17_policy_contract play_installer_exact_source_hybrid shell_pm_install_restore dex_install_deadcode_clean dex_hygiene_stage2 rust_appdetails_manifest appstate_match_canonical restore_guard_safe_appstate_v3 restore_home_ime_cgroup_scope appstate_ssaid_preserve_v4 webdav_generic_nas_dav5005_identity appdetails_seedless_stage_cover appdetails_scoped_cover rust_speedscan_compilefix restore_guard_filtered_wide appdetails_seedless_taint appdetails_seed_count_fix appdetails_seed_expansion prescan_exact_batch remote_prescan_converge prepare_finish_convergence remote_stream_local_read_plan_v2 restore_finalize_terminal appdetails_audit_mode_tag appdetails_health_batch remote_bundle_health_fastpath deadcode_hygiene install_unzip_fastskip_clean dirsize_map_v2 dirsize_profiler_timeout cgfreezer_startup_nosocket_skip"
log "=================================================="

section "核心環境" "檢查 Dex / native 啟動條件"
if [ -f "$CLASSPATH_PATH" ]; then ok "Dex 檔案存在" "$(wc -c < "$CLASSPATH_PATH" 2>/dev/null | tr -d ' ') bytes"; else critical_fail "Dex 檔案存在" "$CLASSPATH_PATH"; fi
if ! get_pkg_uid "$PKG" >/dev/null 2>&1; then
	_new="$(first_user_pkg)"
	if [ -n "$_new" ]; then warn "測試包切換" "$PKG -> $_new"; PKG="$_new"; fi
fi
_multicall="$(command -v speednative 2>/dev/null)"
if [ -x "$_multicall" ] && "$_multicall" --capabilities 2>/dev/null | grep -F 'speednative.argv0_dispatch.v1' >/dev/null; then
	_multi_ok=1
	for _applet in cgfreezer eventwait filewatch netwatch procwait speedscan uidexec unixsock; do
		_link="${_multicall%/*}/$_applet"
		[ -L "$_link" ] && [ "$(readlink "$_link")" = speednative ] && [ -x "$_link" ] || _multi_ok=0
	done
	if [ "$_multi_ok" = 1 ]; then ok "Rust 單一 ELF 軟連結" "8 applets capability=argv0_dispatch"; else critical_fail "Rust 單一 ELF 軟連結" "missing_or_stale_link"; fi
else
	critical_fail "Rust 單一 ELF" "missing_multicall_capability"
fi

_unixsock="$(command -v unixsock 2>/dev/null)"
_root_caps=""
if [ -x "$_unixsock" ]; then _root_caps="$("$_unixsock" capabilities 2>/dev/null)"; fi
for _root_cap in unixsock.stream_relay.v1 unixsock.plain_response_eof.v1 unixsock.root_request_framing.v1 unixsock.root_request_snapshot.v1; do
	case " $_root_caps " in
	*" $_root_cap "*) ok "Root native 請求安全能力" "$_root_cap" ;;
	*) critical_fail "Root native 請求安全能力" "missing=$_root_cap，請一起更新 tools.sh 與 speednative" ;;
	esac
done

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
if [ "$_dex_ver_rc" -eq 0 ] && [ -n "$_dex_ver_now" ]; then
	ok "Dex 主入口可啟動" "rc=0 diagnostic_version_only"
else
	critical_fail "Dex 主入口可啟動" "rc=$_dex_ver_rc $_dex_ver_now"
fi
_root_ver="$(run_class_stdout "$ROOT_DAEMON_CLASS" version 2>&1 | head -n 20)"; _root_ver_rc=$?
[ "$_root_ver_rc" -eq 0 ] && [ -n "$_root_ver" ] && ok "Dex RootDaemon 可啟動" "rc=0" || critical_fail "Dex RootDaemon 可啟動" "rc=$_root_ver_rc"
_dex_ver_line="$(printf '%s\n' "$_dex_ver_now" | sed -n '1p')"
_webdav_ver="$(run_class_stdout "$WEBDAV_CLASS" version 2>&1 | head -n 1)"; _webdav_ver_rc=$?
_notify_ver="$(run_class_stdout "$NOTIFICATION_CLASS" version 2>&1 | head -n 1)"; _notify_ver_rc=$?
_appstate_ver="$(run_class_stdout "$APPSTATE_CLASS" version 2>&1 | head -n 1)"; _appstate_ver_rc=$?
_supervisor_ver="$(run_class_stdout com.xayah.dex.DaemonSupervisorUtil version 2>&1 | head -n 1)"; _supervisor_ver_rc=$?
if [ "$_root_ver_rc" -eq 0 ] && [ "$_webdav_ver_rc" -eq 0 ] && [ "$_notify_ver_rc" -eq 0 ] && [ "$_appstate_ver_rc" -eq 0 ] && [ "$_supervisor_ver_rc" -eq 0 ]     && [ "$_root_ver" = "$_dex_ver_line" ] && [ "$_webdav_ver" = "$_dex_ver_line" ] && [ "$_notify_ver" = "$_dex_ver_line" ] && [ "$_appstate_ver" = "$_dex_ver_line" ] && [ "$_supervisor_ver" = "$_dex_ver_line" ]; then
	ok "Dex 全域版本資訊" "consistent diagnostic-only"
else
	warn "Dex 全域版本資訊" "diagnostic-only capability-gated HiddenApi=$_dex_ver_line RootDaemon=$_root_ver WebDav=$_webdav_ver Notification=$_notify_ver AppState=$_appstate_ver DaemonSupervisor=$_supervisor_ver"
fi
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

require_text "恢復前 Package 狀態 facts" "$_hidden_help" "preRestorePackageStateBatch"
require_text "安裝來源 context facts" "$_hidden_help" "installerContextFacts"

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
_cg_bin="$(command -v cgfreezer 2>/dev/null)"; [ -n "$_cg_bin" ] || _cg_bin="$TOOLS_PATH/cgfreezer"
if [ -x "$_cg_bin" ]; then
	_cg_caps="$("$_cg_bin" capabilities 2>/dev/null)"; _cg_caps_rc=$?
	printf '%s\n' "$_cg_caps" > "$TEST_LOG_DIR/cgfreezer_capabilities.txt" 2>/dev/null
	for _cg_need in freeze-package-refresh-v1 daemon-worker-error-detail-v1 subscribe-peer-close-v1 daemon-worker-admission-v1 daemon-stop-reaped-v1; do
		if [ "$_cg_caps_rc" -eq 0 ] && printf '%s\n' "$_cg_caps" | tr ',' '\n' | grep -Fx "$_cg_need" >/dev/null 2>&1; then
			ok "cgfreezer $_cg_need" "capability-only present"
		else
			critical_fail "cgfreezer $_cg_need" "missing_required_capability，請替換配套的 speednative"
		fi
	done
	if [ "$_cg_caps_rc" -eq 0 ] && printf '%s\n' "$_cg_caps" | tr ',' '\n' | grep -Fx "daemon-diagnostics-batch-v1" >/dev/null 2>&1; then
		ok "cgfreezer 批量診斷能力" "capability-only daemon-diagnostics-batch-v1 present"
	else
		critical_fail "cgfreezer 批量診斷能力" "missing_required_capability rc=$_cg_caps_rc，請替換本輪 native"
	fi
else
	critical_fail "cgfreezer 批量診斷能力" "missing binary $_cg_bin"
fi
_ew_bin="$(command -v eventwait 2>/dev/null)"; [ -n "$_ew_bin" ] || _ew_bin="/data/backup_tools/eventwait"
if [ -x "$_ew_bin" ]; then
	_ew_ver="$($_ew_bin --version 2>/dev/null | head -n 1)"; _ew_ver_rc=$?
	printf '%s\n' "$_ew_ver" > "$TEST_LOG_DIR/eventwait_version.txt" 2>/dev/null
	if [ "$_ew_ver_rc" -eq 0 ] && [ -n "$_ew_ver" ]; then
		ok "eventwait 版本資訊" "diagnostic-only capability-gated"
	else
		warn "eventwait 版本資訊" "diagnostic-only rc=$_ew_ver_rc version=$_ew_ver"
	fi
	_ew_caps="$($_ew_bin capabilities 2>/dev/null | head -n 3)"; _ew_caps_rc=$?
	printf '%s\n' "$_ew_caps" > "$TEST_LOG_DIR/eventwait_capabilities.txt" 2>/dev/null
	case " $_ew_caps " in
	*" eventwait.fifo_process_identity.v1 "*) ok "eventwait FIFO process identity" "present" ;;
	*) critical_fail "eventwait FIFO process identity" "missing；執行時使用 Shell FIFO 相容路徑，套件完整性檢查不通過，請同步更新配套 speednative" ;;
	esac
	case " $_ew_caps " in
	*" eventwait.fifo_emit_nonblocking.v1 "*) ok "eventwait FIFO 非阻塞通知" "present" ;;
	*) critical_fail "eventwait FIFO 非阻塞通知" "missing；執行時省略通知並以 child exit/fatal file 判斷，請同步更新配套 speednative" ;;
	esac
	case " $_ew_caps " in
	*" eventwait.tar_progress_extract_total.v1 "*)
		case " $_ew_caps " in
		*" eventwait.tty_write_retry.v2 "*) ok "tar 進度與非阻塞訊息輸出" "present" ;;
		*) critical_fail "native 終端訊息輸出" "缺少非阻塞 tty-write 能力" ;;
		esac ;;
	*) critical_fail "tar 非阻塞即時進度" "missing；備份仍可執行但無即時位元組顯示，請同步更新配套 speednative" ;;
	esac
	case " $_ew_caps " in
	*" eventwait.tty_relay.v2 "*) ok "常駐終端訊息輸出" "present" ;;
	*) critical_fail "常駐終端訊息輸出" "missing；執行時回退單次輸出，請同步更新配套 speednative" ;;
	esac
	if [ "$_ew_caps_rc" -eq 0 ] && printf '%s\n' "$_ew_caps" | grep -F "eventwait.pidfd_open.v1" >/dev/null 2>&1 && printf '%s\n' "$_ew_caps" | grep -F "eventwait.pid_exit_pidfd.v1" >/dev/null 2>&1; then ok "eventwait pidfd capability" "present"; else critical_fail "eventwait pidfd capability" "rc=$_ew_caps_rc $_ew_caps，請重編/替換 eventwait"; fi
	_ew_probe="$($_ew_bin pidfd-probe $$ 2>/dev/null | head -n 3)"; _ew_probe_rc=$?
	printf '%s\n' "$_ew_probe" > "$TEST_LOG_DIR/eventwait_pidfd_probe.txt" 2>/dev/null
	if [ "$_ew_probe_rc" -eq 0 ] && printf '%s\n' "$_ew_probe" | grep -F "pidfd-probe" >/dev/null 2>&1 && printf '%s\n' "$_ew_probe" | grep -F "backend=pidfd_open" >/dev/null 2>&1; then ok "eventwait pidfd runtime" "rc=0"; else warn "eventwait pidfd runtime" "rc=$_ew_probe_rc $_ew_probe；舊核心會回退 poll-no-block"; fi
else
	warn "eventwait 版本資訊" "diagnostic-only eventwait_not_found"
	critical_fail "eventwait pidfd capability" "eventwait_not_found"
fi

_cg_bin="$(command -v cgfreezer 2>/dev/null)"; [ -n "$_cg_bin" ] || _cg_bin="/data/backup_tools/cgfreezer"
if [ -x "$_cg_bin" ]; then
	_cg_usage="$($_cg_bin 2>&1 | head -n 5)"
	printf '%s\n' "$_cg_usage" | grep -F "proc-wchan" >/dev/null 2>&1 && ok "cgroup WCHAN native 指令" "present" || critical_fail "cgroup WCHAN native 指令" "missing proc-wchan，請重編/替換 cgfreezer"
	_cg_backend_out="$($_cg_bin backend-probe 2>/dev/null | head -n 20)"; _cg_backend_rc=$?
	printf '%s\n' "$_cg_backend_out" > "$TEST_LOG_DIR/cgfreezer_backend_probe.txt" 2>/dev/null
	if [ "$_cg_backend_rc" -eq 0 ] && printf '%s\n' "$_cg_backend_out" | grep -q 'preferred='; then ok "cgroup backend selector 探測" "rc=0"; else critical_fail "cgroup backend selector 探測" "rc=$_cg_backend_rc"; fi
		# + cgfreezer keeps backend-select-cache-v1 in the CAPS payload, not in the no-arg usage line.
		# The no-arg usage is intentionally short, so fall back to checking the binary payload directly.
		if printf '%s\n' "$_cg_usage" | grep -F "backend-select-cache-v1" >/dev/null 2>&1; then
			ok "cgroup backend 快取 capability" "present usage"
		elif grep -F "backend-select-cache-v1" "$_cg_bin" >/dev/null 2>&1; then
			ok "cgroup backend 快取 capability" "present binary"
		else
			critical_fail "cgroup backend 快取 capability" "missing backend-select-cache-v1，請重編/替換 cgfreezer"
		fi
	_cg_wchan_out="$($_cg_bin proc-wchan -1 $$ any 2>/dev/null | head -n 80)"; _cg_wchan_rc=$?
	printf '%s\n' "$_cg_wchan_out" > "$TEST_LOG_DIR/cgfreezer_wchan_smoke.txt" 2>/dev/null
	if [ "$_cg_wchan_rc" -eq 0 ] && printf '%s\n' "$_cg_wchan_out" | grep -q 'CGFREEZER_WCHAN_DONE ok=true'; then ok "cgroup WCHAN 狀態確認" "rc=0"; else critical_fail "cgroup WCHAN 狀態確認" "rc=$_cg_wchan_rc"; fi
else
	critical_fail "cgroup WCHAN native 指令" "cgfreezer_not_found"
	critical_fail "cgroup WCHAN 狀態確認" "cgfreezer_not_found"
fi

_ss_bin="$(command -v speedscan 2>/dev/null)"; [ -n "$_ss_bin" ] || _ss_bin="/data/backup_tools/speedscan"
if [ -x "$_ss_bin" ]; then
		# speedscan contract is capability-only. Do not grep usage/help text or exact --version;
		# help wording and VERSION are diagnostic-only and may legitimately lag behind capabilities.
		_ss_usage="$($_ss_bin 2>&1 | head -n 120)"
		printf '%s\n' "$_ss_usage" > "$TEST_LOG_DIR/speedscan_usage.txt" 2>/dev/null
		ok "speedscan help/version contract" "diagnostic-only capability-gated"
	_ss_caps="$($_ss_bin capabilities 2>/dev/null | head -n 5)"; _ss_caps_rc=$?
	printf '%s\n' "$_ss_caps" > "$TEST_LOG_DIR/speedscan_capabilities.txt" 2>/dev/null
	if [ "$_ss_caps_rc" -eq 0 ] \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appdetails_seed_index_strict_meta.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appdetails_seed_index.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.backup_prescan_exact_input_batch.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.tar_input_hardlink_type_safe.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.dir_size_tar_input_map.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.tree_pack_plan.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.restore_tree_verify.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.payload_stats.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.restore_tree_audit_bytes.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.result_contract.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.backup_run_model.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.backup_plan_coverage.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.tree_fixup_symlink_owner.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.tar_source_manifest.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.restore_source_verify.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.debug_consolidate.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.remote_orphan_plan.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.restore_tree_manifest_bytes.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.app_media_index.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.dir_size_map_nested_singlepass.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.dir_size_map_v2.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.dir_size_map_profiler.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.dir_size_map_workers8_cap.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.dir_size_map_workers24_cap.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.tsv_decimal_sum.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.entry_size_facts.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.changed_entry_facts.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.local_fastskip_join.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.local_fastskip_join_stats_v2.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.local_fastskip_presize_plan_v3.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.local_fastskip_presize_plan_v4.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.local_fastskip_presize_bundle_v1.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.remote_fastskip_presize_bundle_v1.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.backup_entry_presence_map.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.payload_archive_set.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.dir_size_manifest.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.dir_size_worker_scanroots.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.dir_size_map_route_trie.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.dir_size_map_hint_schedule.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.remote_stream_local_read_plan.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.remote_stream_local_read_plan.v2" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.remote_stream_local_read_final_plan.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.stream_entry_perf_resolver.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.stream_entry_perf_child_elapsed.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.stream_entry_post_body_semantics.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.argv_non_utf8_clean_fail.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appdetails_bundle_audit.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appdetails_bundle_audit_seedless_stage_cover.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appdetails_bundle_audit_scoped_cover.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appdetails_bundle_audit_seedless_taint.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appdetails_bundle_audit_seed_expansion.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appdetails_bundle_manifest.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appdetails_health_batch.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.remote_manifest_plan.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.restore_payload_plan.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.restore_payload_plan_full.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.manifest_diff_cache_index.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.manifest_diff_cache_index.v2" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.selected_apps_map.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appdetails_summary_map.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appstate_match_map.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appstate_match_canonical_v2.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appstate_match_canonical_v3.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.appstate_match_canonical_v4.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.remote_orphan_candidates.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.full_convergence_stage3.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.full_convergence_stage4.v1" >/dev/null 2>&1 \
		&& printf '%s\n' "$_ss_caps" | grep -F "speedscan.full_convergence_stage5.v1" >/dev/null 2>&1; then
		ok "speedscan capabilities" "capability-only required-set-present"
	else
		critical_fail "speedscan capabilities" "missing_required_capability rc=$_ss_caps_rc $_ss_caps"
	fi

	_ss_ad_root="$DEX_CHECK_TMPDIR/appdetails_manifest_root"
	_ss_ad_prefix="$DEX_CHECK_TMPDIR/appdetails_manifest_probe"
	rm -rf "$_ss_ad_root" 2>/dev/null
	mkdir -p "$_ss_ad_root/TestApp" 2>/dev/null
	cat > "$_ss_ad_root/TestApp/app_details.json" 2>/dev/null <<'EOF_SPEEDSCAN_APPDETAILS_MANIFEST'
{"TestApp":{"PackageName":"com.speedbackup.test","apk_version":"1"}}
EOF_SPEEDSCAN_APPDETAILS_MANIFEST
	_ss_ad_msg="$($_ss_bin appdetails-bundle-manifest "$_ss_ad_root" "$_ss_ad_prefix" 2>&1 | head -n 20)"; _ss_ad_rc=$?
	printf '%s
' "$_ss_ad_msg" > "$TEST_LOG_DIR/speedscan_appdetails_bundle_manifest.summary.txt" 2>/dev/null
	if [ "$_ss_ad_rc" -eq 0 ] && [ -s "$_ss_ad_root/manifest.tsv" ] && awk -F '\t' '$1=="TestApp" && $2=="com.speedbackup.test" && $3 ~ /^[0-9]+$/ && length($4)==64 {ok=1} END{exit ok?0:1}' "$_ss_ad_root/manifest.tsv" 2>/dev/null; then
		ok "speedscan app_details manifest Rust 化" "rc=0 schema=appdetails_bundle_manifest.v1"
	else
		critical_fail "speedscan app_details manifest Rust 化" "rc=$_ss_ad_rc $_ss_ad_msg"
	fi
	# extracted app_details bundle validation/seed-list generation is Rust-owned.
	_ss_seed_root="$DEX_CHECK_TMPDIR/appdetails_seed_index_root"
	_ss_seed_out="$DEX_CHECK_TMPDIR/appdetails_seed_index.lst"
	_ss_seed_prefix="$DEX_CHECK_TMPDIR/appdetails_seed_index_probe"
	rm -rf "$_ss_seed_root" 2>/dev/null
	mkdir -p "$_ss_seed_root/TestApp" "$_ss_seed_root/BadApp" \
		"$_ss_seed_root/Truncated" "$_ss_seed_root/Nested" \
		"$_ss_seed_root/Trailing" 2>/dev/null
	cat > "$_ss_seed_root/TestApp/app_details.json" 2>/dev/null <<'EOF_SPEEDSCAN_APPDETAILS_SEED_OK'
{"TestApp":{"PackageName":"com.speedbackup.test","apk_version":"1"}}
EOF_SPEEDSCAN_APPDETAILS_SEED_OK
	cat > "$_ss_seed_root/BadApp/app_details.json" 2>/dev/null <<'EOF_SPEEDSCAN_APPDETAILS_SEED_BAD'
{"BadApp":{"PackageName":"com.speedbackup.bad"}}
EOF_SPEEDSCAN_APPDETAILS_SEED_BAD
	printf '%s\n' '{"Meta":{"PackageName":"p","apk_version":7}' > "$_ss_seed_root/Truncated/app_details.json"
	printf '%s\n' '{"Meta":{"A":{"PackageName":"p"},"B":{"apk_version":7}}}' > "$_ss_seed_root/Nested/app_details.json"
	printf '%s\n' '{"Meta":{"PackageName":"p","apk_version":7}} GARBAGE' > "$_ss_seed_root/Trailing/app_details.json"
	_ss_seed_msg="$("$_ss_bin" appdetails-seed-index "$_ss_seed_root" "$_ss_seed_out" "$_ss_seed_prefix" 2>&1)"
	_ss_seed_rc=$?
	printf '%s\n' "$_ss_seed_msg" > "$TEST_LOG_DIR/speedscan_appdetails_seed_index.summary.txt" 2>/dev/null
	if [ "$_ss_seed_rc" -eq 0 ] \
		&& grep -Fx "TestApp" "$_ss_seed_out" >/dev/null 2>&1 \
		&& [ "$(wc -l < "$_ss_seed_out")" -eq 1 ] \
		&& [ -f "$_ss_seed_root/TestApp/app_details.json" ] \
		&& [ ! -f "$_ss_seed_root/BadApp/app_details.json" ] \
		&& [ ! -f "$_ss_seed_root/Truncated/app_details.json" ] \
		&& [ ! -f "$_ss_seed_root/Nested/app_details.json" ] \
		&& [ ! -f "$_ss_seed_root/Trailing/app_details.json" ] \
		&& grep -F "speedbackup.appdetails_seed_index.v1" "$_ss_seed_prefix.stats" >/dev/null 2>&1; then
		ok "speedscan app_details seed index Rust 化" "rc=0 schema=appdetails_seed_index.v1 strict-document direct-child invalid-dropped"
	else
		critical_fail "speedscan app_details seed index Rust 化" "rc=$_ss_seed_rc $_ss_seed_msg"
	fi
	_ss_audit_root="$DEX_CHECK_TMPDIR/appdetails_audit_seedless_root"
	_ss_audit_remote="$DEX_CHECK_TMPDIR/appdetails_audit_seedless_remote.lst"
	_ss_audit_prefix="$DEX_CHECK_TMPDIR/appdetails_audit_seedless_probe"
	rm -rf "$_ss_audit_root" 2>/dev/null
	mkdir -p "$_ss_audit_root/AppA" "$_ss_audit_root/AppB" 2>/dev/null
	cat > "$_ss_audit_root/AppA/app_details.json" 2>/dev/null <<'EOF_SPEEDSCAN_AUDIT_A'
{"PackageName":"com.speedbackup.audit.a","apk_version":"1"}
EOF_SPEEDSCAN_AUDIT_A
	cat > "$_ss_audit_root/AppB/app_details.json" 2>/dev/null <<'EOF_SPEEDSCAN_AUDIT_B'
{"PackageName":"com.speedbackup.audit.b","apk_version":"1"}
EOF_SPEEDSCAN_AUDIT_B
	printf 'AppA/user.tar.zst
AppB/apk.tar.zst
' > "$_ss_audit_remote" 2>/dev/null
	_ss_audit_msg="$($_ss_bin appdetails-bundle-audit "$_ss_audit_root" "$_ss_audit_remote" - missing 0 "$_ss_audit_prefix" 0 2>&1 | head -n 20)"; _ss_audit_rc=$?
	printf '%s
' "$_ss_audit_msg" > "$TEST_LOG_DIR/speedscan_appdetails_audit_seedless.summary.txt" 2>/dev/null
	if [ "$_ss_audit_rc" -eq 0 ] && printf '%s
' "$_ss_audit_msg" | grep -F 'APPDETAILS_BUNDLE_AUDIT' >/dev/null 2>&1 && printf '%s
' "$_ss_audit_msg" | grep -F 'seedlessRepair=1' >/dev/null 2>&1 && printf '%s
' "$_ss_audit_msg" | grep -F 'missingStage=0' >/dev/null 2>&1; then
		ok "speedscan app_details seedless stage-cover 修復" "rc=0 seedlessRepair=1"
	else
		critical_fail "speedscan app_details seedless stage-cover 修復" "rc=$_ss_audit_rc $_ss_audit_msg"
	fi
	# old bundle seed may safely expand only when stage exactly covers scoped remote payload.
	_ss_audit_seed="$DEX_CHECK_TMPDIR/appdetails_audit_seed_expansion_seed.lst"
	printf 'AppA\n' > "$_ss_audit_seed" 2>/dev/null
	_ss_audit_expand_prefix="$DEX_CHECK_TMPDIR/appdetails_audit_seed_expansion_probe"
	_ss_audit_expand_msg="$("$_ss_bin" appdetails-bundle-audit "$_ss_audit_root" "$_ss_audit_remote" "$_ss_audit_seed" ok 1 "$_ss_audit_expand_prefix" 0 2>&1 | head -n 20)"; _ss_audit_expand_rc=$?
	printf '%s\n' "$_ss_audit_expand_msg" > "$TEST_LOG_DIR/speedscan_appdetails_audit_seed_expansion.summary.txt" 2>/dev/null
	if [ "$_ss_audit_expand_rc" -eq 0 ] && printf '%s\n' "$_ss_audit_expand_msg" | grep -F 'APPDETAILS_BUNDLE_AUDIT' >/dev/null 2>&1 && printf '%s\n' "$_ss_audit_expand_msg" | grep -F 'seedExpansion=1' >/dev/null 2>&1 && printf '%s\n' "$_ss_audit_expand_msg" | grep -F 'missingSeed=1' >/dev/null 2>&1 && printf '%s\n' "$_ss_audit_expand_msg" | grep -F 'missingStage=0' >/dev/null 2>&1 && printf '%s\n' "$_ss_audit_expand_msg" | grep -F 'bad=0' >/dev/null 2>&1 && printf '%s\n' "$_ss_audit_expand_msg" | grep -F 'ignoredRemotePayloadApps=0' >/dev/null 2>&1; then
		ok "speedscan app_details 合法 seed expansion" "rc=0 seedExpansion=1 missingSeed=1"
	else
		critical_fail "speedscan app_details 合法 seed expansion" "rc=$_ss_audit_expand_rc $_ss_audit_expand_msg"
	fi
	_ss_lr_sel="$DEX_CHECK_TMPDIR/speedscan_lr_selected.tsv"
	_ss_lr_dirs="$DEX_CHECK_TMPDIR/speedscan_lr_dirs.tsv"
	_ss_lr_out="$DEX_CHECK_TMPDIR/speedscan_lr_plan.tsv"
	_ss_lr_android="$DEX_CHECK_TMPDIR/speedscan_lr_android"
	_ss_lr_user="$DEX_CHECK_TMPDIR/speedscan_lr_user"
	_ss_lr_userde="$DEX_CHECK_TMPDIR/speedscan_lr_userde"
	mkdir -p "$_ss_lr_android/data/com.speedbackup.test" "$_ss_lr_userde/com.speedbackup.test" 2>/dev/null
	printf 'TestApp\tcom.speedbackup.test\t0\t1\n' > "$_ss_lr_sel" 2>/dev/null
	printf 'com.speedbackup.test\tdata\t1234\ncom.speedbackup.test\tuser_de\t999\n' > "$_ss_lr_dirs" 2>/dev/null
	_ss_lr_msg="$($_ss_bin remote-stream-local-read-plan "$_ss_lr_sel" "$_ss_lr_dirs" "$_ss_lr_out" true true true "$_ss_lr_android" "$_ss_lr_user" "$_ss_lr_userde" 2>&1 | head -n 20)"; _ss_lr_rc=$?
	printf '%s\n' "$_ss_lr_msg" > "$TEST_LOG_DIR/speedscan_local_read_plan.summary.txt" 2>/dev/null
	if [ "$_ss_lr_rc" -eq 0 ] && [ "$(awk -F '\t' '$2=="com.speedbackup.test" && $3=="data"{n++} END{print n+0}' "$_ss_lr_out" 2>/dev/null)" -eq 1 ] && [ "$(awk -F '\t' '$2=="com.speedbackup.test" && $3=="user_de"{n++} END{print n+0}' "$_ss_lr_out" 2>/dev/null)" -eq 0 ]; then
		ok "speedscan local-read release plan" "rc=0 conservative-small-skip"
	else
		critical_fail "speedscan local-read release plan" "rc=$_ss_lr_rc $_ss_lr_msg"
	fi
	# exact-input must resolve DIR map + all requested APK packages in one native process.
	_ss_exact_dir="$DEX_CHECK_TMPDIR/speedscan_exact_batch"
	mkdir -p "$_ss_exact_dir" 2>/dev/null
	dd if=/dev/zero of="$_ss_exact_dir/base.apk" bs=513 count=1 2>/dev/null
	_ss_exact_rows="$_ss_exact_dir/rows.tsv"
	_ss_exact_dirmap="$_ss_exact_dir/dir_tar.tsv"
	_ss_exact_apkmap="$_ss_exact_dir/apk_paths.tsv"
	_ss_exact_details="$_ss_exact_dir/details.tsv"
	_ss_exact_stats="$_ss_exact_dir/stats.tsv"
	printf 'APK\tTestApp\tcom.speedbackup.test\tapk\t0\nDIR\tTestApp\tcom.speedbackup.test\tuser\t123\n' > "$_ss_exact_rows" 2>/dev/null
	printf 'com.speedbackup.test\tuser\t/data/user/0/com.speedbackup.test\t20480\n' > "$_ss_exact_dirmap" 2>/dev/null
	printf 'com.speedbackup.test\t%s\n' "$_ss_exact_dir/base.apk" > "$_ss_exact_apkmap" 2>/dev/null
	_ss_exact_msg="$("$_ss_bin" backup-prescan-exact-input "$_ss_exact_rows" "$_ss_exact_dirmap" "$_ss_exact_apkmap" "$_ss_exact_details" "$_ss_exact_stats" 2>&1 | head -n 20)"; _ss_exact_rc=$?
	printf '%s\n' "$_ss_exact_msg" > "$TEST_LOG_DIR/speedscan_exact_batch.summary.txt" 2>/dev/null
	_ss_exact_bytes="$(awk -F '\t' '$1=="bytes"{print $2;exit}' "$_ss_exact_stats" 2>/dev/null)"
	_ss_exact_archives="$(awk -F '\t' '$1=="archives"{print $2;exit}' "$_ss_exact_stats" 2>/dev/null)"
	_ss_exact_cache="$(awk -F '\t' '$1=="cacheKeys"{print $2;exit}' "$_ss_exact_stats" 2>/dev/null)"
	if [ "$_ss_exact_rc" -eq 0 ] && [ "$_ss_exact_bytes" = 30720 ] && [ "$_ss_exact_archives" = 2 ] && [ "$(wc -l < "$_ss_exact_details" 2>/dev/null | tr -d ' ')" = 2 ] && printf '%s\n' "$_ss_exact_cache" | grep -F '|com.speedbackup.test:apk|' >/dev/null 2>&1 && printf '%s\n' "$_ss_exact_cache" | grep -F '|com.speedbackup.test:user|' >/dev/null 2>&1; then
		ok "speedscan prescan exact batch" "bytes=30720 archives=2 cacheKeys=apk+user single-process"
	else
		critical_fail "speedscan prescan exact batch" "rc=$_ss_exact_rc bytes=$_ss_exact_bytes archives=$_ss_exact_archives $_ss_exact_msg"
	fi
	_ss_plan="$TEST_LOG_DIR/speedscan_tree_pack_plan.tsv"
	_ss_plan_summary="$($_ss_bin tree-pack-plan "$TEST_LOG_DIR" "$_ss_plan" - 256 2>&1 | head -n 20)"; _ss_plan_rc=$?
	printf '%s\n' "$_ss_plan_summary" > "$TEST_LOG_DIR/speedscan_tree_pack_plan.summary.txt" 2>/dev/null
	if [ "$_ss_plan_rc" -eq 0 ] && [ -s "$_ss_plan" ] && grep -F "speedbackup.tree_pack_plan.v1" "$_ss_plan" >/dev/null 2>&1; then
		ok "speedscan tree pack-plan facts" "rc=0"
	else
		critical_fail "speedscan tree pack-plan facts" "rc=$_ss_plan_rc $_ss_plan_summary"
	fi
	_ss_media="$TEST_LOG_DIR/speedscan_app_media_index.tsv"
	_ss_media_summary="$($_ss_bin app-media-index "$TEST_LOG_DIR" "$_ss_media" 4 256 - 2>&1 | head -n 20)"; _ss_media_rc=$?
	printf '%s\n' "$_ss_media_summary" > "$TEST_LOG_DIR/speedscan_app_media_index.summary.txt" 2>/dev/null
	if [ "$_ss_media_rc" -eq 0 ] && [ -s "$_ss_media" ] && grep -F "speedbackup.app_media_index.v1" "$_ss_media" >/dev/null 2>&1; then
		ok "speedscan app media index facts" "rc=0"
	else
		critical_fail "speedscan app media index facts" "rc=$_ss_media_rc $_ss_media_summary"
	fi
	_ss_orphan_root="$DEX_CHECK_TMPDIR/orphan_fixture"
	mkdir -p "$_ss_orphan_root/HideThanox" "$_ss_orphan_root/Installed"
	printf '%s\n' '{"Meta":{"PackageName":"com.speedbackup.absent","apk_version":1}}' > "$_ss_orphan_root/HideThanox/app_details.json"
	printf '%s\n' '{"Meta":{"PackageName":"com.speedbackup.present","apk_version":1}}' > "$_ss_orphan_root/Installed/app_details.json"
	printf 'DIR\tHideThanox\tBackup/HideThanox\nDIR\tInstalled\tBackup/Installed\n' > "$_ss_orphan_root/roots.tsv"
	printf '%s\n' 'com.speedbackup.present' > "$_ss_orphan_root/installed.txt"
	_ss_orphan_prefix="$TEST_LOG_DIR/speedscan_orphan_plan"
	"$_ss_bin" remote-orphan-plan "$_ss_orphan_root/roots.tsv" webdav Backup "$_ss_orphan_root" "$_ss_orphan_root/installed.txt" "$_ss_orphan_prefix" > "${_ss_orphan_prefix}.summary.txt" 2>&1
	_ss_orphan_rc=$?
	if [ "$_ss_orphan_rc" -eq 0 ] && [ "$(wc -l < "${_ss_orphan_prefix}.candidates.tsv" 2>/dev/null | tr -d ' ')" = 2 ] && grep -F "$(printf 'HideThanox\tcom.speedbackup.absent\tpackage_not_installed')" "${_ss_orphan_prefix}.candidates.tsv" >/dev/null 2>&1; then
		ok "speedscan remote orphan plan" "rc=0 explicit-roots fixture-only no-delete"
	else
		critical_fail "speedscan remote orphan plan" "rc=$_ss_orphan_rc"
	fi
	_ss_stats_fixture="$DEX_CHECK_TMPDIR/payload_stats.tsv"
	printf 'App/user.tar.zst\t10240\t100\twebdav\tzstd\tuser\n' > "$_ss_stats_fixture"
	"$_ss_bin" payload-stats "$_ss_stats_fixture" "$DEX_CHECK_TMPDIR/no_size_map" 10240 10240 1 > "$TEST_LOG_DIR/payload_stats_result.tsv" 2> "$TEST_LOG_DIR/payload_stats_error.log"
	_ss_stats_rc=$?
	if [ "$_ss_stats_rc" -eq 0 ] && awk -F '\t' '$1=="SBRESULT" && $2==1 && $3=="payload-stats" && $4=="ok" && $10==10240 && $11==100 && $15=="99.02" && $18==1 {ok=1} END{exit !ok}' "$TEST_LOG_DIR/payload_stats_result.tsv"; then
		ok "speedscan unified payload stats" "fixture exact bytes and reconcile"
	else
		critical_fail "speedscan unified payload stats" "rc=$_ss_stats_rc"
	fi
	# exercise the run state machine using only isolated fixture files.
	_ss_run="$TEST_LOG_DIR/backup_run_fixture"
	printf 'DIR\tFixture\tpkg\tuser\t10240\n' > "$_ss_run.plan"
	printf 'Fixture/user\tFixture\tuser\t1\tbegin\t-\t-\tzstd\tlocal\t10\t-\tpacking\nFixture/user\tFixture\tuser\t1\tsuccess\t10240\t100\tzstd\tlocal\t20\t0\tvalidated\nFixture/apk\tFixture\tapk\t0\tskipped\t-\t-\tzstd\tlocal\t20\t0\tunchanged\n' > "$_ss_run.events"
	if "$_ss_bin" backup-run-summary "$_ss_run.plan" "$_ss_run.events" "$DEX_CHECK_TMPDIR/no_size_map" "$_ss_run" 10240 10240 > "$_ss_run.receipt" 2>&1 && awk -F '\t' '$3=="backup-run" && $4=="ok" && $18==1 && $23==2 && $24==1 && $25==0 {ok=1} END{exit !ok}' "$_ss_run.receipt"; then
		ok "speedscan run statistics" "actual-only APK, skipped entry, exact reconciliation"
	else
		critical_fail "speedscan run statistics" "fixture failed"
	fi
	_ss_restore_root="$TEST_LOG_DIR/restore_verify_fixture"
	mkdir -p "$_ss_restore_root"
	_ss_odd_name="$(printf 'odd\n\tname')"
	printf '%s' 'fixture' > "$_ss_restore_root/$_ss_odd_name"
	_ss_source="$TEST_LOG_DIR/restore_source_fixture"
	mkdir -p "$_ss_restore_root/empty"
	ln -s "$_ss_odd_name" "$_ss_restore_root/link" 2>/dev/null
	ln "$_ss_restore_root/$_ss_odd_name" "$_ss_restore_root/hard" 2>/dev/null
	if tar -cf "$_ss_source.tar" -C "$_ss_restore_root" . && "$_ss_bin" tar-source-manifest "$_ss_source" < "$_ss_source.tar" > "$_ss_source.forward.tar" && cmp -s "$_ss_source.tar" "$_ss_source.forward.tar" && "$_ss_bin" restore-source-verify "$_ss_restore_root" "$_ss_source" keep ignore keep > "$_ss_source.receipt"; then
		ok "speedscan archive source verify" "persisted headers, raw names, links and empty directory"
		printf 'changed' >> "$_ss_restore_root/$_ss_odd_name"
		"$_ss_bin" restore-source-verify "$_ss_restore_root" "$_ss_source" keep ignore keep > "$_ss_source.changed.receipt"
		if [ "$?" = 1 ]; then ok "speedscan archive source mismatch" "changed file rejected"; else critical_fail "speedscan archive source mismatch" "mutation was not detected"; fi
	else
		critical_fail "speedscan archive source verify" "capture or verification failed"
	fi
	_ss_restore_manifest="$TEST_LOG_DIR/speedscan_restore_verify_manifest.tsv"
	"$_ss_bin" restore-tree-manifest-bytes "$_ss_restore_root" "$_ss_restore_manifest" > "$TEST_LOG_DIR/speedscan_restore_manifest.log" 2>&1
	_ss_restore_manifest_rc=$?
	"$_ss_bin" restore-tree-verify-bytes "$_ss_restore_root" "$_ss_restore_manifest" > "$TEST_LOG_DIR/speedscan_restore_tree_verify.summary.txt" 2>&1
	_ss_restore_rc=$?
	"$_ss_bin" restore-tree-audit-bytes "$_ss_restore_root" "$_ss_restore_manifest" > "$TEST_LOG_DIR/speedscan_restore_audit.summary.txt" 2>&1
	_ss_audit_rc=$?
	if [ "$_ss_audit_rc" -eq 0 ] && grep -F "$(printf 'SBRESULT\t1\trestore-tree-audit\tok\t0\t0')" "$TEST_LOG_DIR/speedscan_restore_audit.summary.txt" >/dev/null 2>&1; then
		ok "speedscan single-process restore audit" "independent snapshot and verify passes"
	else
		critical_fail "speedscan single-process restore audit" "rc=$_ss_audit_rc"
	fi
	if [ "$_ss_restore_manifest_rc" -eq 0 ] && [ "$_ss_restore_rc" -eq 0 ] && grep -F "pathEncoding=hex" "$TEST_LOG_DIR/speedscan_restore_tree_verify.summary.txt" >/dev/null 2>&1; then
		ok "speedscan restore tree verify facts" "rc=0 pathEncoding=hex"
	else
		critical_fail "speedscan restore tree verify facts" "manifest_rc=$_ss_restore_manifest_rc rc=$_ss_restore_rc"
	fi
else
	critical_fail "speedscan pack-plan 指令" "speedscan_not_found"
	critical_fail "speedscan local-read release plan" "speedscan_not_found"
	critical_fail "speedscan tree pack-plan facts" "speedscan_not_found"
	critical_fail "speedscan app media index facts" "speedscan_not_found"
	critical_fail "speedscan restore tree verify facts" "speedscan_not_found"
fi
_tools_self="${TOOLS_PATH%/}/tools.sh"
[ -f "$_tools_self" ] || _tools_self="$(dirname "$0" 2>/dev/null)/tools.sh"
if [ -f "$_tools_self" ] && grep -F "_cgroup_freezer_wchan_corrective_pkg" "$_tools_self" >/dev/null 2>&1 && grep -F "CGROUP_WCHAN_CORRECTIVE_BEGIN" "$_tools_self" >/dev/null 2>&1; then
	ok "cgroup WCHAN bounded 修正接入" "tools=present"
else
	critical_fail "cgroup WCHAN bounded 修正接入" "tools_missing"
fi
if [ -f "$_tools_self" ] \
	&& grep -F '[[ $_ROOT_DAEMON_READY = 1 ]] && [[ -S $_ROOT_DAEMON_SOCKET ]]' "$_tools_self" >/dev/null 2>&1 \
	&& grep -F 'APPSTATE_ROOT_PROTOCOL_TIMING' "$_tools_self" >/dev/null 2>&1 \
	&& grep -F 'requestBodyBytes=$_snapshot_body_len' "$_tools_self" >/dev/null 2>&1 \
	&& grep -F 'speedbackup.appstate_root_protocol_timing.v1' "$_tools_self" >/dev/null 2>&1 \
	&& ! grep -F 'if [[ $_ROOT_DAEMON_READY = 1 ]] && _root_daemon_probe' "$_tools_self" >/dev/null 2>&1; then
	ok "RootDaemon healthy hot-path no-preprobe" "trusted-ready+protocol-telemetry"
else
	critical_fail "RootDaemon healthy hot-path no-preprobe" "tools integration missing"
fi
if [ -f "$_tools_self" ] \
	&& grep -F 'SPEEDSCAN_DIRSIZE_HINTS_FILE=' "$_tools_self" >/dev/null 2>&1 \
	&& grep -F 'DIRSIZE_MAP_STATS_SINGLEPASS' "$_tools_self" >/dev/null 2>&1 \
	&& grep -F 'speedscan.dir_size_map_route_trie.v1' "$_tools_self" >/dev/null 2>&1 \
	&& grep -F 'speedscan.dir_size_map_hint_schedule.v1' "$_tools_self" >/dev/null 2>&1 \
	&& ! grep -F 'dirsize_map_ready 80 1500' "$_tools_self" >/dev/null 2>&1; then
	ok "dir-size route/schedule hot-path" "trie+hints+singlepass-stats"
	if grep -q "speedscan.remote_fastskip_presize_bundle_v1.v1" "$_tools_self" 2>/dev/null && grep -q "remote-fastskip-presize-bundle-v1" "$_tools_self" 2>/dev/null; then
		ok "remote presize convergence" "bundle+tiny+singlepass"
	else
		critical_fail "remote presize convergence" "tools integration missing"
	fi
	if grep -q "REMOTE_FIRST_FULL_PRESIZE_PLAN_OK" "$_tools_self" 2>/dev/null && grep -q "rust-local-firstfull-bundle-v1" "$_tools_self" 2>/dev/null && grep -q "REMOTE_FIRST_FULL_PRESIZE_FACTS_REUSE_DISABLED" "$_tools_self" 2>/dev/null; then
		ok "remote first-full presize" "local-existence-prune no-remote-facts"
	else
		critical_fail "remote first-full presize" "tools integration missing"
	fi
	if grep -q "XPOSED_RUNTIME_FACTS" "$_tools_self" 2>/dev/null \
		&& grep -q "XPOSED_MODULE_SUMMARY" "$_tools_self" 2>/dev/null \
		&& grep -q "xposed_runtime_facts_last.tsv" "$_tools_self" 2>/dev/null \
		&& grep -q "dex.app_inventory.xposed_module_facts.v1" "$_tools_self" 2>/dev/null \
		&& grep -q "dex.app_inventory.xposed_runtime_facts.v1" "$_tools_self" 2>/dev/null; then
		ok "Xposed facts integration" "module-format+runtime-positive-evidence"
	else
		critical_fail "Xposed facts integration" "tools integration missing"
	fi
	if grep -q "BACKUP_PAYLOAD_STATS_SUMMARY" "$_tools_self" 2>/dev/null \
		&& grep -q "_backup_payload_stats_record_success" "$_tools_self" 2>/dev/null \
		&& grep -q "BACKUP_PAYLOAD_STATS_SMB_POST_MAP_CAPTURE" "$_tools_self" 2>/dev/null \
		&& grep -q "reuse=remote-dir-size" "$_tools_self" 2>/dev/null \
		&& grep -q "_zstd_input_bytes_from_raw_log" "$_tools_self" 2>/dev/null \
		&& grep -q "tools.zstd_input_log_aligned_space.v1" "$_tools_self" 2>/dev/null \
		&& grep -q "SPEEDBACKUP_LAST_LOCAL_ARCHIVE_INPUT_BYTES" "$_tools_self" 2>/dev/null \
		&& grep -q "tools.payload_prescan_exact_tar_input.v1" "$_tools_self" 2>/dev/null \
		&& grep -q "_backup_prescan_exact_payload_plan" "$_tools_self" 2>/dev/null \
		&& grep -q "_backup_prescan_exact_remote_rows" "$_tools_self" 2>/dev/null \
		&& grep -q "backup-prescan-exact-input" "$_tools_self" 2>/dev/null \
		&& grep -q "perEntryForks=0" "$_tools_self" 2>/dev/null \
		&& grep -q "BACKUP_PRESCAN_EXACT_INPUT_READY" "$_tools_self" 2>/dev/null \
		&& grep -q "BACKUP_PAYLOAD_STATS_PLAN_RECONCILE" "$_tools_self" 2>/dev/null \
		&& grep -q -- "-實際處理：" "$_tools_self" 2>/dev/null \
		&& grep -q -- "-q -vvv --priority=rt" "$_tools_self" 2>/dev/null; then
		ok "payload compression stats" "prescan-exact single Rust batch + zstd exact final reconcile"
	else
		critical_fail "payload compression stats" "exact-input batch integration missing"
	fi
	if grep -q "WEBDAV_REMOTE_SETUP_COLLAPSED" "$_tools_self" 2>/dev/null \
		&& grep -q "WEBDAV_BASE_PATH_PREFLIGHT_SKIP" "$_tools_self" 2>/dev/null \
		&& grep -q "backendProfileRelay=0" "$_tools_self" 2>/dev/null \
		&& grep -q "appdetails-seed-index" "$_tools_self" 2>/dev/null; then
		ok "remote prescan convergence" "root-url ensure skip + compat JSON parse + Rust seed index"
	else
		critical_fail "remote prescan convergence" "tools integration missing"
	fi
	if grep -F '_webdav_feature_support_tier' "$_tools_self" >/dev/null 2>&1 \
		&& grep -F 'speedscan.appdetails_seed_index_strict_meta.v1' "$_tools_self" >/dev/null 2>&1 \
		&& grep -F '[[ $_depth1 = 1 && $_walk = 1 ]]' "$_tools_self" >/dev/null 2>&1 \
		&& ! grep -F '_WEBDAV_PROFILE_SUPPORT_TIER="VERIFIED"' "$_tools_self" >/dev/null 2>&1; then
		ok "strict metadata and measured WebDAV tier" "capability gate + depth1/walk + measured support tier"
	else
		critical_fail "strict metadata and measured WebDAV tier" "tools integration missing"
	fi
else
	critical_fail "dir-size route/schedule hot-path" "tools integration missing"
fi
if [ -f "$_tools_self" ] && grep -F "_speedscan_cmd_bounded_to_file" "$_tools_self" >/dev/null 2>&1 && grep -F "SPEEDBACKUP_NATIVE_PACK_PLAN_TIMEOUT_MS" "$_tools_self" >/dev/null 2>&1 && grep -F "SPEEDBACKUP_NATIVE_APP_MEDIA_INDEX_TIMEOUT_MS" "$_tools_self" >/dev/null 2>&1; then
	ok "speedscan native facts timeout bound" "scope=pack-plan+app-media-index tools=present source-check-only"
else
	critical_fail "speedscan native facts timeout bound" "tools_missing"
fi
if [ -f "$_tools_self" ] \
	&& grep -F "SPEEDBACKUP_SPEEDSCAN_REQUIRED_CAPS" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F "_speedscan_require_main_capabilities" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F "SPEEDSCAN_CAPABILITIES_OK stage=runtime_contract" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F 'no_exact_version=1' "$_tools_self" >/dev/null 2>&1 \
	&& ! grep -F 'startswith("v2.6.")' "$_tools_self" >/dev/null 2>&1; then
	ok "tools runtime Rust capability gate" "capability-only version-debug-only"
else
	critical_fail "tools runtime Rust capability gate" "tools_missing_or_version_gate_present"
fi
if [ -f "$_tools_self" ] \
	&& grep -F "speedscan.remote_stream_local_read_plan.v1" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F "speedscan.remote_stream_local_read_plan.v2" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F "speedscan.remote_stream_local_read_final_plan.v1" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F "speedscan.argv_non_utf8_clean_fail.v1" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F "remote-stream-local-read-plan-v2" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F "APP_LOCAL_READ_RELEASE_ARM" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F "APP_LOCAL_READ_RELEASE_DONE" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F "APP_LOCAL_READ_RELEASE_PARENT_SYNC" "$_tools_self" >/dev/null 2>&1; then
	ok "WebDAV 最後本地讀取提前釋放" "plan+producer+parent-sync"
else
	critical_fail "WebDAV 最後本地讀取提前釋放" "missing local-read release integration"
fi
if [ -f "$_tools_self" ] \
	&& grep -F "_sb_println()" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F "print -r --" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F 'timelineMode=builtin-print' "$_tools_self" >/dev/null 2>&1 \
	&& grep -F "printMode=\${SPEEDBACKUP_PRINT_MODE:-unresolved}" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F 'SPEEDBACKUP_PRINT_MODE="print-builtin"' "$_tools_self" >/dev/null 2>&1 \
	&& ! grep -F "printMode=\${SPEEDBACKUP_PRINT_MODE:-auto}" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F '_sb_println "[${SPEEDBACKUP_NOW_HMS:-unknown}] $*"' "$_tools_self" >/dev/null 2>&1 \
	&& grep -F '_sb_println "${_ts}${SB_TAB}${_phase}' "$_tools_self" >/dev/null 2>&1 \
	&& grep -F "_sb_file_has_exact_line()" "$_tools_self" >/dev/null 2>&1 \
	&& ! grep -F "grep -Fqx" "$_tools_self" >/dev/null 2>&1 \
	&& grep -F "RESTORE_STREAM_PERF_STAGES" "$_tools_self" >/dev/null 2>&1; then
	ok "speed_debug print builtin/resolved 熱路徑 + cleanup" "timelineMode=builtin-print"
else
	critical_fail "speed_debug print builtin/resolved 熱路徑 + cleanup" "tools_missing_or_hotpath_regression"
fi
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
require_text "AppState direct-file 備份快照入口" "$_appstate_help" "snapshotAppStateBatchFiles"
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

_xposed_getlist_out="$(run_class_stdout "$HIDDEN_CLASS" appInventoryGetlist "$USER_ID" "$PKG" refresh 2>/dev/null)"; _xposed_getlist_rc=$?
printf '%s\n' "$_xposed_getlist_out" > "$TEST_LOG_DIR/appinventory_xposed_facts.tsv" 2>/dev/null
if [ "$_xposed_getlist_rc" -eq 0 ] \
    && printf '%s\n' "$_xposed_getlist_out" | grep -q '^#META[[:space:]]xposedFramework[[:space:]]' \
    && printf '%s\n' "$_xposed_getlist_out" | grep -q '^#META[[:space:]]xposedModules[[:space:]]'; then
    ok "Xposed 模組/框架 facts" "rc=0 positive-evidence-only=1"
else
    critical_fail "Xposed 模組/框架 facts" "rc=$_xposed_getlist_rc"
fi

_device_facts_out="$(run_class_stdout "$HIDDEN_CLASS" deviceFacts 2>/dev/null)"; _device_facts_rc=$?
printf '%s\n' "$_device_facts_out" > "$TEST_LOG_DIR/device_facts.json" 2>/dev/null
if [ "$_device_facts_rc" -eq 0 ] && printf '%s\n' "$_device_facts_out" | jq -e '.schema=="speedbackup.device_facts.v1" and (.modelNameSource|length>0) and (.marketNameZh|length>0) and (.modelDbEntryCount >= 4000) and (.modelDbSourceLines >= 4000) and ((.modelDbSourceSha256|length)==64)' >/dev/null 2>&1; then ok "Dex 內建機型資料庫" "rc=0"; else warn "Dex 內建機型資料庫" "rc=$_device_facts_rc"; fi

_facts_out="$(run_class_stdout "$HIDDEN_CLASS" appInventoryPackageFactsBatch "$USER_ID" "$PKG" refresh 2>/dev/null)"; _facts_rc=$?
printf '%s\n' "$_facts_out" > "$TEST_LOG_DIR/appinventory_package_facts.tsv" 2>/dev/null
if [ "$_facts_rc" -eq 0 ] && printf '%s\n' "$_facts_out" | grep -q '^#schema[[:space:]]speedbackup.pm_facts.v1' && printf '%s\n' "$_facts_out" | grep -q "^OK[[:space:]]$PKG[[:space:]]"; then ok "App 批量資訊讀取" "rc=0"; else warn "App 批量資訊讀取" "rc=$_facts_rc"; fi

_pre_state_out="$(run_class_stdout "$HIDDEN_CLASS" preRestorePackageStateBatch "$USER_ID" "$PKG" refresh 2>/dev/null)"; _pre_state_rc=$?
printf '%s\n' "$_pre_state_out" > "$TEST_LOG_DIR/pre_restore_package_state.tsv" 2>/dev/null
if [ "$_pre_state_rc" -eq 0 ] && printf '%s\n' "$_pre_state_out" | grep -q '^#schema[[:space:]]speedbackup.pre_restore_package_state.v1' && printf '%s\n' "$_pre_state_out" | grep -Eq "^(OK|MISSING)[[:space:]]$PKG[[:space:]]"; then ok "恢復前 Package 狀態 facts" "rc=0"; else warn "恢復前 Package 狀態 facts" "rc=$_pre_state_rc"; fi

_inst_ctx_out="$(run_class_stdout "$HIDDEN_CLASS" installerContextFacts "$USER_ID" "$PKG" com.android.vending refresh 2>/dev/null)"; _inst_ctx_rc=$?
printf '%s\n' "$_inst_ctx_out" > "$TEST_LOG_DIR/installer_context_facts.tsv" 2>/dev/null
if [ "$_inst_ctx_rc" -eq 0 ] && printf '%s\n' "$_inst_ctx_out" | grep -q '^#schema[[:space:]]speedbackup.installer_context_facts.v1'; then ok "安裝來源 context facts" "rc=0"; else warn "安裝來源 context facts" "rc=$_inst_ctx_rc"; fi

_install_plan_out="$(run_class_stdout "$HIDDEN_CLASS" restoreInstallPlan "$USER_ID" "$PKG" single com.android.vending auto refresh 2>/dev/null)"; _install_plan_rc=$?
printf '%s\n' "$_install_plan_out" > "$TEST_LOG_DIR/restore_install_plan.tsv" 2>/dev/null
if [ "$_install_plan_rc" -eq 0 ] && printf '%s\n' "$_install_plan_out" | grep -q '^#schema[[:space:]]speedbackup.restore_install_plan.v1'; then ok "Dex install plan facts" "rc=0 route=session"; else warn "Dex install plan facts" "rc=$_install_plan_rc"; fi

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
	# Dex display-timeout/settings direct smoke removed. Settings screen_off_timeout is intentionally handled by bounded shell in tools.
ok "Dex 直接改螢幕逾時已撤回" "正式路徑=bounded-shell"

# a later successful probe must not erase an earlier critical failure.
_dex_check_finish() {
	local _rc=0 _state=ok
	if [ "${CRITICAL_FAIL:-0}" != 0 ]; then
		_rc=2; _state=failed
	elif [ "${FAIL:-0}" != 0 ]; then
		_rc=1; _state=failed
	elif [ "${WARN:-0}" != 0 ]; then
		_state=partial
	fi
	printf 'SBRESULT\t1\tdex-check\t%s\trc=%s\tchecks=%s\tok=%s\twarn=%s\tfailed=%s\tcritical=%s\n' \
		"$_state" "$_rc" "${IDX:-0}" "${OK:-0}" "${WARN:-0}" "${FAIL:-0}" "${CRITICAL_FAIL:-0}" >> "$TEST_SUMMARY_FILE"
	log "DEX_CHECK_DONE state=$_state rc=$_rc checks=${IDX:-0} ok=${OK:-0} warn=${WARN:-0} failed=${FAIL:-0} critical=${CRITICAL_FAIL:-0}"
	exit "$_rc"
}
_discovery_caps="$(run_class_stdout com.xayah.dex.WebDavDiscoveryUtil capabilities 2>/dev/null)"
if [ "$_discovery_caps" = "webdav.lan_discovery.v1" ]; then
    ok "WebDAV內網探測" "anonymous/read-only/deadline"
else
    critical_fail "WebDAV內網探測" "配套Dex缺少webdav.lan_discovery.v1"
fi
_dex_check_finish
