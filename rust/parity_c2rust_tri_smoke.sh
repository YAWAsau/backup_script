#!/usr/bin/env sh
set -eu
# Run C reference vs handwritten Rust parity smoke, then optionally C reference vs C2Rust baseline smoke.
# Usage: STRICT=1 sh rust/parity_c2rust_tri_smoke.sh /path/to/c-bin /path/to/manual-rust-bin [/path/to/c2rust-bin] [tmpdir]
C_BIN="${1:-}"
RUST_BIN="${2:-}"
C2RUST_BIN="${3:-}"
TMP="${4:-${TMPDIR:-/data/local/tmp}/speedbackup_c2rust_tri_smoke_$$}"
ROOT_DIR="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
SMOKE="$ROOT_DIR/rust/parity_smoke.sh"
STRICT="${STRICT:-1}"
export STRICT

if [ -z "$C_BIN" ] || [ -z "$RUST_BIN" ]; then
  echo "usage: $0 /path/to/c-bin /path/to/manual-rust-bin [/path/to/c2rust-bin] [tmpdir]" >&2
  exit 2
fi
if [ ! -x "$SMOKE" ]; then
  echo "missing parity smoke: $SMOKE" >&2
  exit 2
fi
mkdir -p "$TMP"
fail=0

echo "=== C reference vs handwritten Rust ==="
if sh "$SMOKE" "$C_BIN" "$RUST_BIN" "$TMP/manual_rust" >"$TMP/manual_rust.log" 2>&1; then
  cat "$TMP/manual_rust.log"
  echo "RESULT manual_rust ok=true log=$TMP/manual_rust.log"
else
  cat "$TMP/manual_rust.log"
  echo "RESULT manual_rust ok=false log=$TMP/manual_rust.log" >&2
  fail=1
fi

if [ -n "$C2RUST_BIN" ] && [ "$C2RUST_BIN" != "-" ]; then
  echo "=== C reference vs c2rust baseline ==="
  if sh "$SMOKE" "$C_BIN" "$C2RUST_BIN" "$TMP/c2rust_baseline" >"$TMP/c2rust_baseline.log" 2>&1; then
    cat "$TMP/c2rust_baseline.log"
    echo "RESULT c2rust_baseline ok=true log=$TMP/c2rust_baseline.log"
  else
    cat "$TMP/c2rust_baseline.log"
    echo "RESULT c2rust_baseline ok=false log=$TMP/c2rust_baseline.log" >&2
    fail=1
  fi
else
  echo "SKIP c2rust_baseline no_c2rust_bin_dir"
fi

echo "logs: $TMP"
exit "$fail"
