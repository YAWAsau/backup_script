#!/system/bin/sh
# SpeedBackup native replacement RC smoke: compare installed C helpers and rebuilt Rust helpers.
# Usage: C_BIN_DIR=/data/backup_tools_c RUST_BIN_DIR=/data/backup_tools ./native_replacement_rc_smoke.sh
# This script is intentionally POSIX/mksh compatible; it does not decide product policy.
set -u
C_BIN_DIR="${C_BIN_DIR:-${1:-}}"
RUST_BIN_DIR="${RUST_BIN_DIR:-${2:-}}"
OUT_DIR="${OUT_DIR:-${TMPDIR:-/data/local/tmp}/speedbackup_native_rc_smoke_$$}"
HELPERS="cgfreezer eventwait filewatch netwatch procwait speedscan uidexec unixsock"
mkdir -p "$OUT_DIR" 2>/dev/null || exit 2
log="$OUT_DIR/native_replacement_rc_smoke.log"
: > "$log"
fail=0
say() { printf '%s\n' "$*" | tee -a "$log"; }
run_one() {
    _kind="$1"; _bin="$2"; shift 2
    _name="$(basename "$_bin")"
    _tag="$OUT_DIR/${_kind}_${_name}_$(printf '%s_' "$@" | tr '/ ' '__').out"
    if [ ! -x "$_bin" ]; then
        printf 'MISSING kind=%s bin=%s\n' "$_kind" "$_bin" >> "$log"
        return 127
    fi
    "$_bin" "$@" >"$_tag" 2>"$_tag.err"
    _rc=$?
    printf 'RUN kind=%s bin=%s args=%s rc=%s out=%s err=%s\n' "$_kind" "$_bin" "$*" "$_rc" "$_tag" "$_tag.err" >> "$log"
    return "$_rc"
}
check_cmd() {
    _h="$1"; shift
    cbin="$C_BIN_DIR/$_h"
    rbin="$RUST_BIN_DIR/$_h"
    run_one C "$cbin" "$@"; crc=$?
    run_one Rust "$rbin" "$@"; rrc=$?
    if [ "$crc" != "$rrc" ]; then
        say "MISMATCH helper=$_h args=$* c_rc=$crc rust_rc=$rrc"
        fail=1
    fi
}
if [ -z "$C_BIN_DIR" ] || [ -z "$RUST_BIN_DIR" ]; then
    say "usage: C_BIN_DIR=/path/to/c RUST_BIN_DIR=/path/to/rust $0"
    exit 2
fi
say "SpeedBackup native replacement RC smoke r577"
say "C_BIN_DIR=$C_BIN_DIR"
say "RUST_BIN_DIR=$RUST_BIN_DIR"
for h in $HELPERS; do
    check_cmd "$h" --version
    check_cmd "$h" version
    check_cmd "$h" capabilities
    check_cmd "$h" --capabilities
    check_cmd "$h" --help
    check_cmd "$h" help
    check_cmd "$h" __speedbackup_unknown_command__
done
say "RESULT rc=$fail log=$log out_dir=$OUT_DIR"
exit "$fail"
