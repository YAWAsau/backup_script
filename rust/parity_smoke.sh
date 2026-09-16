#!/usr/bin/env sh
set -eu
# SpeedBackup r540 native Rust v21 merge-verification strict C-source parity smoke. STRICT defaults to 1; loose mode is no longer the default.
# Usage: sh rust/parity_smoke.sh /path/to/c-bin-dir /path/to/rust-bin-dir [tmpdir]
C_BIN="${1:-}"
R_BIN="${2:-}"
TMP="${3:-${TMPDIR:-/data/local/tmp}/speedbackup_rust_parity_smoke_$$}"
if [ -z "$C_BIN" ] || [ -z "$R_BIN" ]; then
  echo "usage: $0 /path/to/c-bin-dir /path/to/rust-bin-dir [tmpdir]" >&2
  exit 2
fi
mkdir -p "$TMP/root/a/b" "$TMP/root/empty" "$TMP/out"
echo hello > "$TMP/root/a/file1.txt"
echo world > "$TMP/root/a/b/file2.txt"
ln -s file1.txt "$TMP/root/a/link1" 2>/dev/null || true
: > "$TMP/list.txt"
printf '%s\n' "$TMP/root/a/file1.txt" "$TMP/root/a/b/file2.txt" "$TMP/root/a/missing" > "$TMP/abs.list"
printf 'pkg.one\tdata\t%s\npkg.two\tuser\t%s\npkg.empty\tempty\t%s\n' "$TMP/root/a" "$TMP/root/a/b" "$TMP/root/empty" > "$TMP/dir_size_map.tsv"
printf 'pkg.one\tdata\t%s\nmalformed-only-one-column\npkg.two\tuser\t%s\n' "$TMP/root/a" "$TMP/root/a/b" > "$TMP/dir_size_map_bad.tsv"
printf 'App One|com.example.one\n!No Data|com.example.nodata\n' > "$TMP/appList.txt"
: > "$TMP/blacklist.txt"

kv_get() {
  key="$1"; file="$2"
  tr ' ' '\n' <"$file" | sed -n "s/^${key}=//p" | head -n 1
}
num_abs_diff_ok() {
  a="$1"; b="$2"; tol="$3"
  [ -n "$a" ] || return 1
  [ -n "$b" ] || return 1
  diff=$(( a > b ? a - b : b - a ))
  [ "$diff" -le "$tol" ]
}
case_storage_summary() {
  tool=speedscan; name=storage_summary_strict; shift || true
  cout="$TMP/out/${tool}_${name}_c.out"; cerr="$TMP/out/${tool}_${name}_c.err"; crc="$TMP/out/${tool}_${name}_c.rc"
  rout="$TMP/out/${tool}_${name}_rs.out"; rerr="$TMP/out/${tool}_${name}_rs.err"; rrc="$TMP/out/${tool}_${name}_rs.rc"
  set +e
  "$C_BIN/$tool" storage-summary "$TMP/root" >"$cout" 2>"$cerr"; echo $? >"$crc"
  "$R_BIN/$tool" storage-summary "$TMP/root" >"$rout" 2>"$rerr"; echo $? >"$rrc"
  set -e
  rcok=0; cmp -s "$crc" "$rrc" && rcok=1
  total_c=$(kv_get totalBytes "$cout"); total_r=$(kv_get totalBytes "$rout")
  used_c=$(kv_get usedBytes "$cout"); used_r=$(kv_get usedBytes "$rout")
  avail_c=$(kv_get availBytes "$cout"); avail_r=$(kv_get availBytes "$rout")
  pct_c=$(kv_get usePct "$cout"); pct_r=$(kv_get usePct "$rout")
  fs_c=$(kv_get fsType "$cout"); fs_r=$(kv_get fsType "$rout")
  mp_c=$(kv_get mountPoint "$cout"); mp_r=$(kv_get mountPoint "$rout")
  src_c=$(kv_get source "$cout"); src_r=$(kv_get source "$rout")
  outok=1
  [ "$total_c" = "$total_r" ] || outok=0
  [ "$pct_c" = "$pct_r" ] || outok=0
  [ "$fs_c" = "$fs_r" ] || outok=0
  [ "$mp_c" = "$mp_r" ] || outok=0
  [ "$src_c" = "$src_r" ] || outok=0
  # Allow one 4K block drift between two calls, matching the reviewer-approved host behavior.
  num_abs_diff_ok "${used_c:-0}" "${used_r:-0}" 4096 || outok=0
  num_abs_diff_ok "${avail_c:-0}" "${avail_r:-0}" 4096 || outok=0
  if [ "$rcok" = 1 ] && [ "$outok" = 1 ]; then echo "OK speedscan storage_summary_strict"; else echo "FAIL speedscan storage_summary_strict rcok=$rcok outok=$outok" >&2; fail=1; fi
}
case_wchan_expect() {
  name="$1"; expect="$2"
  cout="$TMP/out/cgfreezer_${name}_c.out"; cerr="$TMP/out/cgfreezer_${name}_c.err"; crc="$TMP/out/cgfreezer_${name}_c.rc"
  rout="$TMP/out/cgfreezer_${name}_rs.out"; rerr="$TMP/out/cgfreezer_${name}_rs.err"; rrc="$TMP/out/cgfreezer_${name}_rs.rc"
  set +e
  "$C_BIN/cgfreezer" proc-wchan -1 "$$" "$expect" >"$cout" 2>"$cerr"; echo $? >"$crc"
  "$R_BIN/cgfreezer" proc-wchan -1 "$$" "$expect" >"$rout" 2>"$rerr"; echo $? >"$rrc"
  set -e
  rcok=0; cmp -s "$crc" "$rrc" && rcok=1
  kind_c=$(kv_get freezeKind "$cout"); kind_r=$(kv_get freezeKind "$rout")
  match_c=$(kv_get match "$cout"); match_r=$(kv_get match "$rout")
  outok=0; [ "$kind_c" = "$kind_r" ] && [ "$match_c" = "$match_r" ] && outok=1
  if [ "$rcok" = 1 ] && [ "$outok" = 1 ]; then echo "OK cgfreezer ${name}"; else echo "FAIL cgfreezer ${name} rcok=$rcok outok=$outok" >&2; fail=1; fi
}

fail=0
case_line() {
  tool="$1"; shift
  name="$1"; shift
  cout="$TMP/out/${tool}_${name}_c.out"; cerr="$TMP/out/${tool}_${name}_c.err"; crc="$TMP/out/${tool}_${name}_c.rc"
  rout="$TMP/out/${tool}_${name}_rs.out"; rerr="$TMP/out/${tool}_${name}_rs.err"; rrc="$TMP/out/${tool}_${name}_rs.rc"
  set +e
  "$C_BIN/$tool" "$@" >"$cout" 2>"$cerr"; echo $? >"$crc"
  "$R_BIN/$tool" "$@" >"$rout" 2>"$rerr"; echo $? >"$rrc"
  set -e
  if cmp -s "$crc" "$rrc"; then rcok=1; else rcok=0; fi
  strict="${STRICT:-1}"
  if [ "$strict" = 1 ]; then
    # Normalize only volatile timing/version/marker values; all data fields remain strict.
    sed -E 's/elapsedMs=[0-9]+/elapsedMs=<ms>/g; s/version=[^ \t]+/version=<version>/g; s/r[0-9]+-[A-Za-z0-9._-]+/r<ver>/g; s/rust-native-[A-Za-z0-9._-]+/rust-native-<marker>/g' "$cout" >"$cout.norm"
    sed -E 's/elapsedMs=[0-9]+/elapsedMs=<ms>/g; s/version=[^ \t]+/version=<version>/g; s/r[0-9]+-[A-Za-z0-9._-]+/r<ver>/g; s/rust-native-[A-Za-z0-9._-]+/rust-native-<marker>/g' "$rout" >"$rout.norm"
    cmp -s "$cout.norm" "$rout.norm" && outok=1 || outok=0
  else
    echo "WARN loose smoke disabled for release proof: set STRICT=1 for valid parity evidence" >&2
    [ -s "$rout" -a -s "$cout" ] && outok=1 || outok=0
  fi
  if [ "$rcok" = 1 ] && [ "$outok" = 1 ]; then
    echo "OK $tool $name"
  else
    echo "FAIL $tool $name rcok=$rcok outok=$outok" >&2
    fail=1
  fi
}

case_line eventwait version --version
case_line eventwait caps capabilities
case_line eventwait file_created file-created "$TMP/root/a/file1.txt" 100 smoke_file_created
case_line eventwait file_nonempty file-nonempty "$TMP/root/a/file1.txt" 100 smoke_file_nonempty
case_line eventwait file_contains file-contains "$TMP/root/a/file1.txt" hello 100 smoke_file_contains
case_line eventwait file_stable file-size-stable "$TMP/root/a/file1.txt" 20 200 smoke_file_stable
case_line procwait version --version
case_line procwait pkg_gone pkg-gone 0 com.this.package.should.not.exist 300 50
case_line procwait uid_gone uid-gone 999999 300 50
case_line speedscan version --version
case_line speedscan caps capabilities
case_line speedscan dir_size dir-size "$TMP/root"
# r577: strict C-vs-Rust proof for ordered parallel dir-size-map output and malformed-row rc=4.
case_line speedscan dir_size_map dir-size-map "$TMP/dir_size_map.tsv"
case_line speedscan dir_size_map_bad dir-size-map "$TMP/dir_size_map_bad.tsv"
case_line speedscan file_list file-list "$TMP/root"
case_line speedscan list_total list-total-size "$TMP/abs.list"
case_line speedscan batch_stat batch-stat "$TMP/abs.list"
case_line speedscan batch_exists batch-exists "$TMP/abs.list"
case_line speedscan has_files has-files "$TMP/root"
case_line speedscan manifest manifest "$TMP/root" "$TMP/manifest.tsv"
case_line speedscan scan_summary scan-summary "$TMP/root" "$TMP/scan_manifest.tsv"
case_line speedscan appdetails_index appdetails-index "$TMP/root" "$TMP/appdetails.tsv" 3 0
case_line speedscan file_abs_filter file-list-abs-filter "$TMP/root" "$TMP/abs_filter.tsv" 1 -
case_line speedscan selected_list selected-list "$TMP/appList.txt" "$TMP/blacklist.txt" "$TMP/selected.tsv" 0
case_line speedscan apk_map apk-size-map "$TMP/abs.list" "$TMP/apkmap.tsv"
case_line speedscan backup_root_index backup-root-index "$TMP/root" "$TMP/root_index.tsv" 3
case_storage_summary
case_line speedscan checksum_list checksum-list "$TMP/root" "$TMP/checksum.tsv"
case_line speedscan manifest_verify manifest-verify "$TMP/root" "$TMP/manifest.tsv"
case_line speedscan run_tmpdir run-tmpdir-facts "$TMP" "$TMP/runfacts.tsv" speedbackup_rust_parity_smoke_
case_line speedscan zst_facts zst-file-facts "$TMP/root/a/file1.txt"
case_line speedscan tree_pack tree-pack-plan "$TMP/root" "$TMP/pack.tsv" - -
case_line speedscan restore_verify restore-tree-verify "$TMP/root" "$TMP/manifest.tsv"
case_line speedscan app_media app-media-index "$TMP/root" "$TMP/media.tsv" 3 200 -
case_line uidexec version --version
case_line unixsock version --version
case_line filewatch version --version
case_line netwatch version --version
case_line cgfreezer version --version
case_line cgfreezer version_alias version
case_line cgfreezer no_args
case_line cgfreezer unknown __speedbackup_unknown_command__
case_line cgfreezer freeze_pid_missing freeze-pid
case_line cgfreezer daemon_missing daemon
case_line cgfreezer root check-root
case_line cgfreezer backend backend-probe
case_wchan_expect wchan_any any
case_wchan_expect wchan_frozen_mismatch frozen
case_line cgfreezer scan scan-package com.this.package.should.not.exist 0


send_unix_line() {
  sock="$1"; line="$2"
  python3 - "$sock" "$line" <<'PYCLIENT'
import socket, sys
sock, line = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock)
s.sendall((line + "\n").encode())
s.shutdown(socket.SHUT_WR)
out = bytearray()
while True:
    chunk = s.recv(65536)
    if not chunk:
        break
    out.extend(chunk)
s.close()
sys.stdout.buffer.write(out)
PYCLIENT
}
wait_for_socket() {
  sock="$1"; i=0
  while [ "$i" -lt 100 ]; do
    [ -S "$sock" ] && return 0
    i=$((i+1))
    sleep 0.05
  done
  return 1
}
norm_daemon_out() {
  sed -E 's/elapsedMs=[0-9]+/elapsedMs=<ms>/g; s/waitMs=[0-9]+/waitMs=<ms>/g; s/pid=[0-9]+/pid=<pid>/g; s/version=[^ 	]+/version=<version>/g; s/rust-native-[A-Za-z0-9._-]+/rust-native-<marker>/g; s/r[0-9]+-[A-Za-z0-9._-]+/r<ver>/g'
}
case_daemon_line() {
  name="$1"; line="$2"
  cout="$TMP/out/cgfreezer_daemon_${name}_c.out"
  rout="$TMP/out/cgfreezer_daemon_${name}_rs.out"
  set +e
  send_unix_line "$CGSOCK" "$line" >"$cout" 2>"$cout.err"; csend=$?
  send_unix_line "$RSSOCK" "$line" >"$rout" 2>"$rout.err"; rsend=$?
  set -e
  rcok=0; [ "$csend" = 0 ] && [ "$rsend" = 0 ] && rcok=1
  norm_daemon_out <"$cout" >"$cout.norm"
  norm_daemon_out <"$rout" >"$rout.norm"
  cmp -s "$cout.norm" "$rout.norm" && outok=1 || outok=0
  if [ "$rcok" = 1 ] && [ "$outok" = 1 ]; then
    echo "OK cgfreezer daemon_$name"
  else
    echo "FAIL cgfreezer daemon_$name rcok=$rcok outok=$outok" >&2
    fail=1
  fi
}
case_daemon_shared_logic() {
  command -v python3 >/dev/null 2>&1 || { echo "SKIP cgfreezer daemon_shared_logic no_python3"; return 0; }
  CGSOCK="$TMP/cgfreezer_c.sock"; RSSOCK="$TMP/cgfreezer_rs.sock"
  rm -f "$CGSOCK" "$RSSOCK"
  set +e
  "$C_BIN/cgfreezer" daemon "$CGSOCK" >"$TMP/out/cgfreezer_daemon_c.log" 2>"$TMP/out/cgfreezer_daemon_c.err" & CPID=$!
  "$R_BIN/cgfreezer" daemon "$RSSOCK" >"$TMP/out/cgfreezer_daemon_rs.log" 2>"$TMP/out/cgfreezer_daemon_rs.err" & RPID=$!
  set -e
  if ! wait_for_socket "$CGSOCK" || ! wait_for_socket "$RSSOCK"; then
    echo "FAIL cgfreezer daemon_start" >&2
    fail=1
  else
    case_daemon_line check_root "CHECK_ROOT"
    case_daemon_line scan_empty "SCAN com.this.package.should.not.exist 0"
    case_daemon_line freeze_badpid "FREEZE 0 1500"
    case_daemon_line thaw_badpid "THAW_PID 0 - 0 1500"
    case_daemon_line freeze_pid_zero "FREEZE_PID_LIST 0 0 1500"
    case_daemon_line kill_pid_zero "KILL_PID_LIST 0 0 9"
  fi
  send_unix_line "$CGSOCK" "STOP" >/dev/null 2>&1 || true
  send_unix_line "$RSSOCK" "STOP" >/dev/null 2>&1 || true
  wait "$CPID" >/dev/null 2>&1 || true
  wait "$RPID" >/dev/null 2>&1 || true
}
case_daemon_shared_logic

exit "$fail"
