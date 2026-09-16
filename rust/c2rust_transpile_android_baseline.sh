#!/usr/bin/env sh
set -eu
# Transpile C helpers to unsafe Rust baselines with C2Rust.
# Usage: sh rust/c2rust_transpile_android_baseline.sh [compile_commands.json] [out_dir]
ROOT_DIR="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
COMPILE_DB="${1:-$ROOT_DIR/rust/parity/c2rust_android_compile_db/compile_commands.json}"
OUT_DIR="${2:-$ROOT_DIR/rust/parity/c2rust_baseline}"
TOOLS="${TOOLS:-eventwait filewatch netwatch procwait speedscan uidexec unixsock cgfreezer}"
FAIL_ON_ERROR="${FAIL_ON_ERROR:-1}"
BUILD_AFTER_TRANSPILE="${BUILD_AFTER_TRANSPILE:-0}"
CARGO_BUILD_ARGS="${CARGO_BUILD_ARGS:-}"

if [ ! -f "$COMPILE_DB" ]; then
  echo "compile_commands.json not found: $COMPILE_DB" >&2
  echo "Run: sh rust/c2rust_make_android_compile_commands.sh /path/to/android-ndk-r28c" >&2
  exit 2
fi
command -v c2rust >/dev/null 2>&1 || { echo "c2rust not found in PATH" >&2; exit 127; }

HELP="$(c2rust transpile --help 2>&1 || true)"
case "$HELP" in *--binary*) MAIN_OPT="--binary" ;; *) MAIN_OPT="--main" ;; esac
case "$HELP" in *--output-dir*) HAS_OUTPUT_DIR=1 ;; *) HAS_OUTPUT_DIR=0 ;; esac
if [ "$HAS_OUTPUT_DIR" != 1 ]; then
  echo "This harness requires a c2rust build exposing --output-dir, to avoid writing generated files beside c/." >&2
  echo "Update c2rust or run manual transpile in a throwaway tree." >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
for tool in $TOOLS; do
  work="$OUT_DIR/$tool"
  rm -rf "$work"
  mkdir -p "$work"
  regex="(^|.*/)$tool[.]c$"
  echo "[c2rust] transpile $tool -> $work"
  if [ "$FAIL_ON_ERROR" = 1 ]; then
    if ! c2rust transpile --fail-on-error --emit-build-files "$MAIN_OPT" "$tool" --filter "$regex" --output-dir "$work" "$COMPILE_DB" >"$work/transpile.log" 2>&1; then
      cat "$work/transpile.log" >&2
      echo "c2rust transpile failed for $tool; log=$work/transpile.log" >&2
      exit 1
    fi
  else
    if ! c2rust transpile --emit-build-files "$MAIN_OPT" "$tool" --filter "$regex" --output-dir "$work" "$COMPILE_DB" >"$work/transpile.log" 2>&1; then
      cat "$work/transpile.log" >&2
      echo "c2rust transpile failed for $tool; log=$work/transpile.log" >&2
      exit 1
    fi
  fi
  if [ "$BUILD_AFTER_TRANSPILE" = 1 ]; then
    echo "[cargo] build $tool"
    if ! (cd "$work" && cargo build --release $CARGO_BUILD_ARGS) >"$work/cargo_build.log" 2>&1; then
      cat "$work/cargo_build.log" >&2
      echo "cargo build failed for $tool; log=$work/cargo_build.log" >&2
      exit 1
    fi
  fi
done

echo "c2rust baselines: $OUT_DIR"
echo "Note: c2rust output is a verification oracle only; do not install it as runtime helpers."
